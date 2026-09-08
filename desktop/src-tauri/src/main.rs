#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod hud;
mod models;
mod polish;
mod stt;
mod typer;

use models::Config;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
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
    pub cancelled: AtomicBool,
    pub other_key_down: AtomicBool,
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
    hud::update(app, stage, text, detail);
}

fn on_press(app: &AppHandle) {
    let state = app.state::<DictState>();

    // Ignore Right Ctrl when it is part of a combo (e.g. Ctrl+C).
    if state.other_key_down.load(Ordering::SeqCst) {
        return;
    }

    if state.recording.load(Ordering::SeqCst) {
        // Recording: if the quick tap armed toggle mode, stop and paste.
        if state.tap_armed.load(Ordering::SeqCst) {
            state.tap_armed.store(false, Ordering::SeqCst);
            send_stop(app);
        }
        return;
    }

    // Debounce: ignore repeats right after releasing.
    if let Some(t) = *state.last_stop.lock().unwrap_or_else(|e| e.into_inner()) {
        if t.elapsed() < Duration::from_millis(400) {
            return;
        }
    }

    *state
        .press_start
        .lock()
        .unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
    state.tap_armed.store(false, Ordering::SeqCst);
    state.cancelled.store(false, Ordering::SeqCst);

    let (tx, rx) = mpsc::channel::<()>();
    *state.stop_tx.lock().unwrap_or_else(|e| e.into_inner()) = Some(tx);
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
        .unwrap_or_else(|e| e.into_inner())
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
    let tx = state
        .stop_tx
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .take();
    if let Some(tx) = tx {
        let _ = tx.send(());
    }
    *state.last_stop.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
}

/// Cancels dictation without typing (Esc key / Cancel button).
fn send_cancel(app: &AppHandle) {
    let state = app.state::<DictState>();
    state.cancelled.store(true, Ordering::SeqCst);
    state.tap_armed.store(false, Ordering::SeqCst);
    send_stop(app);
}

fn run_dictation(app: AppHandle, stop_rx: mpsc::Receiver<()>) {
    let state = app.state::<DictState>();
    let wanted_mic = state
        .config
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .microphone
        .clone();
    emit(&app, "recording", None, None);

    let recorder = match audio::Recorder::start_with(&wanted_mic) {
        Ok(r) => r,
        Err(e) => {
            state.recording.store(false, Ordering::SeqCst);
            emit(&app, "error", None, Some(&e));
            return;
        }
    };

    // Record until the key-release order arrives, with a 2-minute safety cap.
    let record_start = Instant::now();
    const MAX_RECORDING: Duration = Duration::from_secs(120);
    let mut hit_duration_limit = false;
    loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        if !recorder.keep_going().load(Ordering::SeqCst) {
            break;
        }
        if record_start.elapsed() > MAX_RECORDING {
            hit_duration_limit = true;
            break;
        }
        std::thread::sleep(Duration::from_millis(25));
    }

    let samples = recorder.stop();

    // Esc / Cancel pressed while recording: discard silently.
    if state.cancelled.load(Ordering::SeqCst) {
        state.cancelled.store(false, Ordering::SeqCst);
        state.recording.store(false, Ordering::SeqCst);
        emit(&app, "cancelled", None, None);
        return;
    }

    if hit_duration_limit {
        state.recording.store(false, Ordering::SeqCst);
        emit(
            &app,
            "error",
            None,
            Some("Dictation stopped at the 2-minute limit. Dictate in shorter chunks."),
        );
        return;
    }
    // Hard cap in samples as well (in case of odd sample rates).
    if samples.len() > models::MAX_SAMPLES_16K + 16_000 {
        state.recording.store(false, Ordering::SeqCst);
        emit(
            &app,
            "error",
            None,
            Some("Dictation too long (2-minute limit). Dictate in shorter chunks."),
        );
        return;
    }

    if samples.len() < 1_600 {
        state.recording.store(false, Ordering::SeqCst);
        emit(&app, "error", None, Some("Didn't hear anything."));
        return;
    }
    emit(&app, "transcribing", None, None);

    let (language, polish_on, translate_on, target_language) = {
        let cfg = state.config.lock().unwrap_or_else(|e| e.into_inner());
        (
            cfg.language.clone(),
            cfg.polish,
            cfg.translate,
            cfg.target_language.clone(),
        )
    };

    // 1) Local transcription
    let wpath = models::whisper_model_path();
    if !wpath.exists() {
        state.recording.store(false, Ordering::SeqCst);
        emit(
            &app,
            "error",
            None,
            Some("Missing transcription model: install it from the Talkable window."),
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

    // 2) Optional local polish with a small language model.
    let mut polish_note: Option<String> = None;
    let polished = if polish_on {
        let qpath = models::qwen_model_path();
        if qpath.exists() {
            emit(&app, "polishing", None, None);
            match polish::polish(&raw, &qpath) {
                Ok(out) => polish::sane(&out, &raw).unwrap_or_else(|| raw.clone()),
                Err(_) => raw.clone(),
            }
        } else {
            polish_note = Some(
                "AI polish is on but its model isn't downloaded — pasted the raw text.".to_string(),
            );
            raw.clone()
        }
    } else {
        raw.clone()
    };

    // 2b) Optional offline translation with the same local model.
    // Enabled only when the AI model is installed.
    let mut final_text = polished.clone();
    if translate_on {
        let qpath = models::qwen_model_path();
        if qpath.exists() {
            emit(&app, "translating", None, None);
            match polish::translate(&polished, &target_language, &qpath) {
                Ok(out) => {
                    final_text = polish::sane(&out, &polished).unwrap_or(polished.clone());
                }
                Err(_) => {
                    let note = "Translation failed — pasted the polished text.";
                    polish_note = Some(
                        polish_note
                            .map(|n| format!("{n} {note}"))
                            .unwrap_or_else(|| note.to_string()),
                    );
                }
            }
        } else {
            let note = "Translation is on but its model isn't downloaded — pasted untranslated.";
            polish_note = Some(
                polish_note
                    .map(|n| format!("{n} {note}"))
                    .unwrap_or_else(|| note.to_string()),
            );
        }
    }

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
    emit(&app, "done", Some(&final_text), polish_note.as_deref());
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

/// Cancels dictation without typing anything (Esc key).
#[tauri::command]
fn cancel_dictation(app: AppHandle) {
    let state = app.state::<DictState>();
    if state.recording.load(Ordering::SeqCst) {
        send_cancel(&app);
    }
}

#[tauri::command]
fn get_state(app: AppHandle) -> serde_json::Value {
    let hotkey = app
        .try_state::<DictState>()
        .map(|s| {
            s.hotkey
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone()
        })
        .unwrap_or_default();
    let downloading: Vec<String> = DOWNLOADING
        .lock()
        .map(|s| s.iter().cloned().collect())
        .unwrap_or_default();
    let config = models::load_config();
    let whisper_ready = models::whisper_model_path().exists();
    serde_json::json!({
        "whisperReady": whisper_ready,
        "qwenReady": models::qwen_model_path().exists(),
        "config": config,
        "hotkey": hotkey,
        "downloading": downloading,
        "whisperSize": models::WHISPER_SIZE_LABEL,
        "qwenSize": models::QWEN_SIZE_LABEL,
        "offlineReady": whisper_ready,
        "networkActive": !downloading.is_empty(),
        "microphones": audio::Recorder::list_input_devices(),
        "version": "0.4.2",
    })
}

#[tauri::command]
fn list_microphones() -> Vec<String> {
    audio::Recorder::list_input_devices()
}

#[tauri::command]
fn set_config(
    app: AppHandle,
    language: String,
    polish: bool,
    translate: bool,
    target_language: String,
    microphone: String,
) {
    let mut cfg = models::load_config();
    cfg.language = language;
    cfg.polish = polish;
    // Translation requires the AI model: force it off when missing so the UI
    // can't leave the app in a broken state.
    let qwen_ready = models::qwen_model_path().exists();
    cfg.translate = translate && qwen_ready;
    cfg.target_language = target_language;
    // Unknown microphone names fall back to the system default at record time.
    cfg.microphone = if microphone.trim().is_empty() {
        "default".to_string()
    } else {
        microphone
    };
    models::save_config(&cfg);
    // Dictation reads the in-memory config: update it here, otherwise the
    // change doesn't take effect until the app restarts.
    if let Some(state) = app.try_state::<DictState>() {
        *state.config.lock().unwrap_or_else(|e| e.into_inner()) = cfg.clone();
    }
    // Turning polish or translation on is the moment to have the model ready.
    if polish || cfg.translate {
        polish::prewarm(&models::qwen_model_path());
    }
}

/// Setup can only be marked complete with the transcription model actually
/// installed on disk (AI polish is optional and not checked here).
#[tauri::command]
fn set_onboarding_done() -> Result<(), String> {
    if !models::whisper_model_path().exists() {
        return Err(
            "The transcription model is required: download it before finishing setup.".into(),
        );
    }
    let mut cfg = models::load_config();
    cfg.onboarding_done = true;
    models::save_config(&cfg);
    Ok(())
}

/// Models currently downloading (prevents double-clicks and corruption).
static DOWNLOADING: std::sync::LazyLock<Mutex<HashSet<String>>> =
    std::sync::LazyLock::new(|| Mutex::new(HashSet::new()));

/// Cancel flags per model (set by cancel_download).
static CANCEL_FLAGS: std::sync::LazyLock<Mutex<HashMap<String, Arc<AtomicBool>>>> =
    std::sync::LazyLock::new(|| Mutex::new(HashMap::new()));

static DOWNLOAD_CLIENT: std::sync::LazyLock<reqwest::blocking::Client> =
    std::sync::LazyLock::new(|| {
        reqwest::blocking::Client::builder()
            .connect_timeout(Duration::from_secs(15))
            // Total cap for large models; per-read stalls surface as
            // read errors from reqwest and are kept as resumable partials.
            .timeout(Duration::from_secs(600))
            .build()
            .expect("download client")
    });

fn download_target(which: &str) -> Result<(&'static str, std::path::PathBuf, &'static str, u64), String> {
    match which {
        "whisper" => Ok((
            models::WHISPER_URL,
            models::whisper_model_path(),
            "transcription model",
            models::WHISPER_MIN_BYTES,
        )),
        "qwen" => Ok((
            models::QWEN_URL,
            models::qwen_model_path(),
            "AI polish model",
            models::QWEN_MIN_BYTES,
        )),
        _ => Err("Unknown model".into()),
    }
}

/// Starts the download on a detached thread and returns right away (never
/// blocks Tauri's async runtime). Progress and results arrive as events:
/// `download-start` / `download-progress` / `download-done` / `download-error`.
/// Supports resume via HTTP Range and cancellation via cancel_download.
#[tauri::command]
fn download_model(app: AppHandle, which: String) -> Result<(), String> {
    let (url, dest, label, min_bytes) = download_target(&which)?;

    {
        let mut set = DOWNLOADING.lock().map_err(|_| "Download lock")?;
        if !set.insert(which.clone()) {
            return Err("That download is already running".into());
        }
    }
    let cancel = Arc::new(AtomicBool::new(false));
    CANCEL_FLAGS
        .lock()
        .map(|mut m| m.insert(which.clone(), cancel.clone()))
        .ok();

    std::thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            emit(&app, "download-start", None, Some(label));
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            // Resume: keep a ".downloading" partial file and ask for the rest.
            let tmp = dest.with_extension("downloading");
            let existing: u64 = std::fs::metadata(&tmp).map(|m| m.len()).unwrap_or(0);
            let mut req = DOWNLOAD_CLIENT.get(url);
            if existing > 0 {
                req = req.header("Range", format!("bytes={existing}-"));
            }
            let resp = req.send().map_err(|e| e.to_string())?;
            let status = resp.status();
            // 206 = resume accepted; 200 = server restarts from zero; 416 = already complete.
            let (mut file, mut bytes, total, resumed) = if status.as_u16() == 206 {
                let remaining = resp.content_length().unwrap_or(0);
                let f = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&tmp)
                    .map_err(|e| e.to_string())?;
                (f, existing, existing + remaining, true)
            } else if status.is_success() {
                if existing > 0 {
                    let _ = std::fs::remove_file(&tmp);
                }
                let total = resp.content_length().unwrap_or(0);
                let f = std::fs::File::create(&tmp).map_err(|e| e.to_string())?;
                (f, 0u64, total, false)
            } else if status.as_u16() == 416 {
                // Range beyond EOF: the partial file is actually complete.
                std::fs::rename(&tmp, &dest).map_err(|e| e.to_string())?;
                emit(&app, "download-done", None, Some(label));
                return Ok(());
            } else {
                return Err(format!("Download failed: {status}"));
            };
            let _ = resumed;
            use std::io::Write;
            let mut reader = resp;
            // Unknown total (no content-length): show indeterminate progress.
            let unknown_total = total == 0;
            if unknown_total {
                emit(&app, "download-progress", None, Some(&format!("{label}|-1")));
            }
            let mut last_pct = 101u64;
            loop {
                if cancel.load(Ordering::SeqCst) {
                    return Err("cancelled".into());
                }
                use std::io::Read;
                let mut buf = [0u8; 256 * 1024];
                let n = reader.read(&mut buf).map_err(|e| e.to_string())?;
                if n == 0 {
                    break;
                }
                file.write_all(&buf[..n]).map_err(|e| e.to_string())?;
                bytes += n as u64;
                if !unknown_total {
                    if let Some(pct) = bytes.checked_mul(100).and_then(|v| v.checked_div(total)) {
                        let pct = pct.min(100);
                        if pct != last_pct {
                            last_pct = pct;
                            emit(
                                &app,
                                "download-progress",
                                None,
                                Some(&format!("{label}|{pct}")),
                            );
                        }
                    }
                }
            }
            file.flush().ok();
            drop(file);
            // Verify: size must match the announced total (when known) and
            // pass a minimum sanity size (catches truncated transfers).
            if !unknown_total && bytes != total {
                let _ = std::fs::remove_file(&tmp);
                return Err(format!("Incomplete download ({bytes}/{total} bytes)"));
            }
            if bytes < min_bytes {
                let _ = std::fs::remove_file(&tmp);
                return Err(format!("Incomplete download ({bytes} bytes)"));
            }
            std::fs::rename(&tmp, &dest).map_err(|e| e.to_string())?;
            emit(&app, "download-done", None, Some(label));
            Ok(())
        })();

        DOWNLOADING.lock().ok().map(|mut set| set.remove(&which));
        CANCEL_FLAGS.lock().ok().map(|mut m| m.remove(&which));
        if let Err(e) = result {
            if e == "cancelled" {
                // Keep the partial file so the next attempt resumes.
                emit(&app, "download-error", None, Some(&format!("{label}|cancelled")));
            } else {
                // Keep partials for resume on network errors; the next
                // attempt sends Range. Only the verify path above deletes.
                emit(&app, "download-error", None, Some(&format!("{label}|{e}")));
            }
        }
    });

    Ok(())
}

/// Cancels an in-flight model download. The partial file is kept for resume.
#[tauri::command]
fn cancel_download(which: String) -> Result<(), String> {
    let flag = CANCEL_FLAGS
        .lock()
        .map(|m| m.get(&which).cloned())
        .map_err(|_| "Download lock")?;
    match flag {
        Some(f) => {
            f.store(true, Ordering::SeqCst);
            Ok(())
        }
        None => Err("No such download".into()),
    }
}

fn main() {
    let config = models::load_config();
    let polish_at_start = config.polish || config.translate;

    tauri::Builder::default()
        .manage(DictState {
            recording: AtomicBool::new(false),
            tap_armed: AtomicBool::new(false),
            press_start: Mutex::new(None),
            last_stop: Mutex::new(None),
            stop_tx: Mutex::new(None),
            config: Mutex::new(config.clone()),
            hotkey: Mutex::new(String::new()),
            cancelled: AtomicBool::new(false),
            other_key_down: AtomicBool::new(false),
        })
        .manage(hud::HudState::new())
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
            cancel_download,
            toggle_dictation,
            cancel_dictation,
            list_microphones
        ])
        .setup(move |app| {
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
            *app.state::<DictState>().hotkey.lock().unwrap_or_else(|e| e.into_inner()) =
                hotkey_label.to_string();
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                let hkeys = handle.clone();
                let herr = handle.clone();
                let res = rdev::listen(move |event| match event.event_type {
                    rdev::EventType::KeyPress(rdev::Key::ControlRight) => on_press(&hkeys),
                    rdev::EventType::KeyRelease(rdev::Key::ControlRight) => {
                        on_release(&hkeys);
                    }
                    rdev::EventType::KeyPress(key) => {
                        // Any other key down marks a combo: Right Ctrl alone
                        // must not start dictation (e.g. Ctrl+C), and pressing
                        // another key mid-dictation cancels it.
                        if !matches!(key, rdev::Key::ControlRight) {
                            if let Some(st) = hkeys.try_state::<DictState>() {
                                st.other_key_down.store(true, Ordering::SeqCst);
                                if st.recording.load(Ordering::SeqCst) {
                                    send_cancel(&hkeys);
                                }
                            }
                        }
                    }
                    rdev::EventType::KeyRelease(key) => {
                        if !matches!(key, rdev::Key::ControlRight) {
                            if let Some(st) = hkeys.try_state::<DictState>() {
                                st.other_key_down.store(false, Ordering::SeqCst);
                            }
                        }
                    }
                    _ => {}
                });
                if let Err(e) = res {
                    // No hook (e.g. Wayland): F6 or the UI button remain.
                    eprintln!("talkable: Right Ctrl hook unavailable ({e:?})");
                    if let Some(state) = herr.try_state::<DictState>() {
                        *state.hotkey.lock().unwrap_or_else(|e| e.into_inner()) = if f6_ok {
                            "F6".to_string()
                        } else {
                            String::new()
                        };
                    }
                }
            });

            // Have both models ready before the user dictates: without this
            // the first dictation pays the full model-load wait.
            stt::warm_up(&models::whisper_model_path());
            if polish_at_start {
                polish::prewarm(&models::qwen_model_path());
            }
            hud::init(app.handle());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("failed to run Talkable");
}
