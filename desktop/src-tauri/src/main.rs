#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod models;
mod polish;
mod stt;
mod typer;

use models::Config;
use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_global_shortcut::{Builder as ShortcutBuilder, ShortcutState};

pub struct DictState {
    pub recording: AtomicBool,
    pub tap_armed: AtomicBool,
    pub press_start: Mutex<Option<Instant>>,
    pub last_stop: Mutex<Option<Instant>>,
    pub stop_tx: Mutex<Option<mpsc::Sender<()>>>,
    pub config: Mutex<Config>,
    pub hotkey: Mutex<String>,
}

#[derive(Clone, serde::Serialize)]
struct Status {
    stage: String,
    text: Option<String>,
    detail: Option<String>,
}

fn emit(app: &AppHandle, stage: &str, text: Option<&str>, detail: Option<&str>) {
    let _ = app.emit(
        "talkable-status",
        Status {
            stage: stage.into(),
            text: text.map(|s| s.into()),
            detail: detail.map(|s| s.into()),
        },
    );
}

fn on_press(app: &AppHandle) {
    let state = app.state::<DictState>();

    if state.recording.load(Ordering::SeqCst) {
        // Recording: if the quick tap armed toggle mode, stop and paste.
        if state.tap_armed.load(Ordering::SeqCst) {
            state.tap_armed.store(false, Ordering::SeqCst);
            send_stop(app);
        }
        return;
    }

    // Debounce: ignore repeats right after releasing.
    if let Some(t) = *state.last_stop.lock().unwrap() {
        if t.elapsed() < Duration::from_millis(400) {
            return;
        }
    }

    *state.press_start.lock().unwrap() = Some(Instant::now());
    state.tap_armed.store(false, Ordering::SeqCst);

    let (tx, rx) = mpsc::channel::<()>();
    *state.stop_tx.lock().unwrap() = Some(tx);
    state.recording.store(true, Ordering::SeqCst);
    let app2 = app.clone();
    std::thread::spawn(move || run_dictation(app2, rx));
}

fn on_release(app: &AppHandle) {
    let state = app.state::<DictState>();
    if !state.recording.load(Ordering::SeqCst) {
        return;
    }
    let held_for = state
        .press_start
        .lock()
        .unwrap()
        .take()
        .map(|t| t.elapsed())
        .unwrap_or(Duration::from_secs(10));

    if held_for < Duration::from_millis(300) {
        // Quick tap: toggle mode (the next press stops and pastes).
        state.tap_armed.store(true, Ordering::SeqCst);
        return;
    }
    send_stop(app);
}

fn send_stop(app: &AppHandle) {
    let state = app.state::<DictState>();
    let tx = state.stop_tx.lock().unwrap().take();
    if let Some(tx) = tx {
        let _ = tx.send(());
    }
    *state.last_stop.lock().unwrap() = Some(Instant::now());
}

fn run_dictation(app: AppHandle, stop_rx: mpsc::Receiver<()>) {
    let state = app.state::<DictState>();
    emit(&app, "recording", None, None);

    let recorder = match audio::Recorder::start() {
        Ok(r) => r,
        Err(e) => {
            state.recording.store(false, Ordering::SeqCst);
            emit(&app, "error", None, Some(&e));
            return;
        }
    };

    // Record until the key-release order arrives.
    loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        if !recorder.keep_going().load(Ordering::SeqCst) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(25));
    }

    let samples = recorder.stop();
    emit(&app, "transcribing", None, None);

    if samples.len() < 1_600 {
        state.recording.store(false, Ordering::SeqCst);
        emit(&app, "error", None, Some("Didn't hear anything."));
        return;
    }

    let (language, polish_on) = {
        let cfg = state.config.lock().unwrap();
        (cfg.language.clone(), cfg.polish)
    };

    // 1) Local transcription
    let wpath = models::whisper_model_path();
    if !wpath.exists() {
        state.recording.store(false, Ordering::SeqCst);
        emit(
            &app,
            "error",
            None,
            Some("Missing whisper model: download it from the Talkable window."),
        );
        return;
    }
    let raw = match stt::transcribe(&samples, &language, &wpath) {
        Ok(t) => t,
        Err(e) => {
            state.recording.store(false, Ordering::SeqCst);
            emit(&app, "error", None, Some(&e));
            return;
        }
    };
    if raw.trim().is_empty() {
        state.recording.store(false, Ordering::SeqCst);
        emit(&app, "error", None, Some("Couldn't understand anything."));
        return;
    }

    // 2) Optional local polish with Qwen3
    let final_text = if polish_on {
        let qpath = models::qwen_model_path();
        if qpath.exists() {
            emit(&app, "polishing", None, None);
            match polish::polish(&raw, &qpath) {
                Ok(out) => polish::sane(&out, &raw).unwrap_or_else(|| raw.clone()),
                Err(_) => raw.clone(),
            }
        } else {
            raw.clone()
        }
    } else {
        raw.clone()
    };

    // 3) Type into the focused app. If that's not possible (Wayland,
    // permissions), the text still lands in the window for manual copy.
    if let Err(e) = typer::type_text(&final_text) {
        state.recording.store(false, Ordering::SeqCst);
        emit(
            &app,
            "done",
            Some(&final_text),
            Some(&format!(
                "Couldn't type automatically ({e}). Copy the text from here."
            )),
        );
        return;
    }

    state.recording.store(false, Ordering::SeqCst);
    emit(&app, "done", Some(&final_text), None);
}

/// Toggles dictation from the UI (click). It's the fallback for Wayland,
/// where there's no global hotkey or auto-typing: if recording, stop and
/// paste; otherwise start recording.
#[tauri::command]
fn toggle_dictation(app: AppHandle) {
    let state = app.state::<DictState>();
    if state.recording.load(Ordering::SeqCst) {
        state.tap_armed.store(false, Ordering::SeqCst);
        send_stop(&app);
    } else {
        on_press(&app);
    }
}

#[tauri::command]
fn get_state(app: AppHandle) -> serde_json::Value {
    let hotkey = app
        .try_state::<DictState>()
        .map(|s| s.hotkey.lock().unwrap().clone())
        .unwrap_or_default();
    serde_json::json!({
        "whisperReady": models::whisper_model_path().exists(),
        "qwenReady": models::qwen_model_path().exists(),
        "config": models::load_config(),
        "hotkey": hotkey,
    })
}

#[tauri::command]
fn set_config(app: AppHandle, language: String, polish: bool) {
    let mut cfg = models::load_config();
    cfg.language = language;
    cfg.polish = polish;
    models::save_config(&cfg);
    // Dictation reads the in-memory config: update it here, otherwise the
    // change doesn't take effect until the app restarts.
    if let Some(state) = app.try_state::<DictState>() {
        *state.config.lock().unwrap() = cfg;
    }
}

#[tauri::command]
fn set_onboarding_done() {
    let mut cfg = models::load_config();
    cfg.onboarding_done = true;
    models::save_config(&cfg);
}

/// Models currently downloading (prevents double-clicks and .tmp corruption).
static DOWNLOADING: std::sync::LazyLock<Mutex<HashSet<String>>> =
    std::sync::LazyLock::new(|| Mutex::new(HashSet::new()));

/// Starts the download on a detached thread and returns right away (never
/// blocks Tauri's async runtime). Progress and results arrive as events:
/// `download-start` / `download-progress` / `download-done` / `download-error`.
#[tauri::command]
fn download_model(app: AppHandle, which: String) -> Result<(), String> {
    let (url, dest, label): (&'static str, std::path::PathBuf, &'static str) =
        match which.as_str() {
            "whisper" => (
                models::WHISPER_URL,
                models::whisper_model_path(),
                "whisper (base)",
            ),
            "qwen" => (models::QWEN_URL, models::qwen_model_path(), "Qwen3-0.6B"),
            _ => return Err("Unknown model".into()),
        };

    {
        let mut set = DOWNLOADING.lock().map_err(|_| "Download lock")?;
        if !set.insert(which.clone()) {
            return Err("That download is already running".into());
        }
    }

    std::thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            emit(&app, "download-start", None, Some(label));
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            let tmp = dest.with_extension("downloading");
            let resp = reqwest::blocking::get(url).map_err(|e| e.to_string())?;
            if !resp.status().is_success() {
                return Err(format!("Download failed: {}", resp.status()));
            }
            let total = resp.content_length().unwrap_or(0);
            let mut file = std::fs::File::create(&tmp).map_err(|e| e.to_string())?;
            use std::io::Write;
            let mut bytes: u64 = 0;
            let mut reader = resp;
            // chunked read
            let mut last_pct = 100u64;
            loop {
                use std::io::Read;
                let mut buf = [0u8; 256 * 1024];
                let n = reader.read(&mut buf).map_err(|e| e.to_string())?;
                if n == 0 {
                    break;
                }
                file.write_all(&buf[..n]).map_err(|e| e.to_string())?;
                bytes += n as u64;
                if total > 0 {
                    let pct = bytes * 100 / total;
                    if pct != last_pct {
                        last_pct = pct;
                        emit(&app, "download-progress", None, Some(&format!("{label}|{pct}")));
                    }
                }
            }
            file.flush().ok();
            drop(file);
            std::fs::rename(&tmp, &dest).map_err(|e| e.to_string())?;
            emit(&app, "download-done", None, Some(label));
            Ok(())
        })();

        DOWNLOADING
            .lock()
            .ok()
            .map(|mut set| set.remove(&which));
        if let Err(e) = result {
            let _ = std::fs::remove_file(dest.with_extension("downloading"));
            emit(&app, "download-error", None, Some(&format!("{label}|{e}")));
        }
    });

    Ok(())
}

fn main() {
    let config = models::load_config();

    tauri::Builder::default()
        .manage(DictState {
            recording: AtomicBool::new(false),
            tap_armed: AtomicBool::new(false),
            press_start: Mutex::new(None),
            last_stop: Mutex::new(None),
            stop_tx: Mutex::new(None),
            config: Mutex::new(config),
            hotkey: Mutex::new(String::new()),
        })
        .plugin(
            ShortcutBuilder::new()
                .with_handler(|app, _shortcut, event| match event.state() {
                    ShortcutState::Pressed => on_press(app),
                    ShortcutState::Released => on_release(app),
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            get_state,
            set_config,
            set_onboarding_done,
            download_model,
            toggle_dictation
        ])
        .setup(|app| {
            // F6 as a fallback: works on X11, Wayland and Windows.
            use tauri_plugin_global_shortcut::GlobalShortcutExt;
            let f6_ok = app.global_shortcut().register("f6").is_ok();
            // Right Ctrl by default, via a low-level hook (rdev): the
            // global-shortcut plugin doesn't accept lone modifiers as a
            // single key ("ControlRight" doesn't parse), so F6 is only the
            // plan B. rdev only observes, it never intercepts the key.
            let hotkey_label = if f6_ok {
                "Right Ctrl + F6"
            } else {
                "Right Ctrl"
            };
            *app.state::<DictState>()
                .hotkey
                .lock()
                .unwrap() = hotkey_label.to_string();
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                let hkeys = handle.clone();
                let herr = handle.clone();
                let res = rdev::listen(move |event| match event.event_type {
                    rdev::EventType::KeyPress(rdev::Key::ControlRight) => on_press(&hkeys),
                    rdev::EventType::KeyRelease(rdev::Key::ControlRight) => {
                        on_release(&hkeys)
                    }
                    _ => {}
                });
                if let Err(e) = res {
                    // No hook (e.g. Wayland): F6 or the UI button remain.
                    eprintln!("talkable: Right Ctrl hook unavailable ({e:?})");
                    if let Some(state) = herr.try_state::<DictState>() {
                        *state.hotkey.lock().unwrap() = if f6_ok {
                            "F6".to_string()
                        } else {
                            String::new()
                        };
                    }
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("failed to run Talkable");
}
