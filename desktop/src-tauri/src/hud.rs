//! Floating dictation overlay: a small, non-focus-stealing glass card in the
//! top-right corner that shows what's happening (recording with live preview
//! text, transcribing, polishing) and the final text, like the macOS HUD.
//!
//! It's a separate transparent, always-on-top, skip-taskbar window. It never
//! takes keyboard focus (the text must land in the app the user was using),
//! and it auto-hides a few seconds after dictation ends.

use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, LogicalPosition, Manager, WebviewUrl, WebviewWindowBuilder};

/// Window size, including a transparent margin for the card's soft shadow.
/// Fits two lines of preview text.
const HUD_WIDTH: f64 = 380.0;
const HUD_HEIGHT: f64 = 96.0;
/// Distance from the work-area's top-right corner (which already excludes
/// e.g. a top panel or the taskbar).
const RIGHT_MARGIN: f64 = 8.0;
const TOP_MARGIN: f64 = 4.0;

const DONE_VISIBLE: Duration = Duration::from_secs(3);
const ERROR_VISIBLE: Duration = Duration::from_secs(6);
const POLL: Duration = Duration::from_millis(200);

pub struct HudState {
    window: Mutex<Option<tauri::WebviewWindow>>,
    hide_at: Mutex<Option<Instant>>,
}

impl HudState {
    pub fn new() -> Self {
        Self {
            window: Mutex::new(None),
            hide_at: Mutex::new(None),
        }
    }
}

/// Creates the hidden HUD window and starts the auto-hide watcher.
pub fn init(app: &AppHandle) {
    let app = app.clone();
    let window = WebviewWindowBuilder::new(&app, "hud", WebviewUrl::App("hud.html".into()))
        .title("Talkable")
        .inner_size(HUD_WIDTH, HUD_HEIGHT)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .maximizable(false)
        .minimizable(false)
        .closable(false)
        // Never take focus: dictation types into the app the user was using.
        .focused(false)
        .focusable(false)
        // Transparent windows must not draw their own shadow (Windows draws
        // an opaque square around them otherwise).
        .shadow(false)
        .visible(false)
        .build();

    match window {
        Ok(w) => {
            app.state::<HudState>().window.lock().unwrap().replace(w);
        }
        Err(e) => {
            // The HUD is a nicety; dictation still works through the main
            // window if the platform refuses a transparent overlay.
            eprintln!("talkable: floating window unavailable ({e})");
        }
    }

    std::thread::spawn(move || loop {
        std::thread::sleep(POLL);
        let due = {
            let state = app.state::<HudState>();
            let mut hide_at = state.hide_at.lock().unwrap();
            match *hide_at {
                Some(at) if Instant::now() >= at => {
                    *hide_at = None;
                    true
                }
                _ => false,
            }
        };
        if due {
            if let Some(w) = app.state::<HudState>().window.lock().unwrap().as_ref() {
                let _ = w.hide();
            }
        }
    });
}

fn position(window: &tauri::WebviewWindow) {
    // Prefer the monitor with the cursor; fall back to the primary monitor.
    let monitor = window
        .cursor_position()
        .ok()
        .and_then(|p| window.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| window.primary_monitor().ok().flatten());
    let Some(monitor) = monitor else {
        return;
    };
    let scale = monitor.scale_factor();
    let work = monitor.work_area();
    let pos = work.position.to_logical::<f64>(scale);
    let size = work.size.to_logical::<f64>(scale);
    let x = pos.x + size.width - HUD_WIDTH - RIGHT_MARGIN;
    let y = pos.y + TOP_MARGIN;
    let _ = window.set_position(LogicalPosition::new(x.max(pos.x), y));
}

/// Shows the pill and cancels any pending auto-hide.
fn show(app: &AppHandle) {
    let state = app.state::<HudState>();
    *state.hide_at.lock().unwrap() = None;
    let guard = state.window.lock().unwrap();
    if let Some(w) = guard.as_ref() {
        position(w);
        let _ = w.show();
    }
}

/// Hides the pill after `delay`, unless something new shows up first.
fn hide_later(app: &AppHandle, delay: Duration) {
    let state = app.state::<HudState>();
    *state.hide_at.lock().unwrap() = Some(Instant::now() + delay);
}

/// Drives the HUD from the dictation stages. Called from `emit`, so the
/// overlay always mirrors what the main window shows.
pub fn update(app: &AppHandle, stage: &str, text: Option<&str>, detail: Option<&str>) {
    let (kind, message) = match stage {
        "recording" => ("recording", "Recording… (Esc cancels)".to_string()),
        "transcribing" => ("busy", "Transcribing…".to_string()),
        "polishing" => ("busy", "Polishing with AI…".to_string()),
        "translating" => ("busy", "Translating…".to_string()),
        "cancelled" => ("done", "Cancelled".to_string()),
        "done" => ("done", text.unwrap_or("Done").to_string()),
        "error" => (
            "error",
            detail.unwrap_or("Something went wrong").to_string(),
        ),
        // Downloads are driven from the main window; keep the pill out of it.
        _ => return,
    };
    let _ = app.emit(
        "hud-update",
        serde_json::json!({ "kind": kind, "text": message }),
    );
    show(app);
    match kind {
        "done" => hide_later(app, DONE_VISIBLE),
        "error" => hide_later(app, ERROR_VISIBLE),
        _ => {}
    }
}

/// Shows live preview text while recording. The page ignores it once the
/// stage has moved on, so a late preview can't overwrite the result.
pub fn partial(app: &AppHandle, text: &str) {
    let _ = app.emit("hud-partial", serde_json::json!({ "text": text }));
}
