use std::sync::Mutex;

/// Reused keyboard handle: creating it connects to X11 every time (~50-100ms).
static ENIGO: Mutex<Option<enigo::Enigo>> = Mutex::new(None);

/// Types text into the focused app.
/// Linux: requires X11 (Wayland isn't supported by enigo yet).
pub fn type_text(text: &str) -> Result<(), String> {
    use enigo::{Enigo, Keyboard, Settings};
    // Fast path: reuse the existing connection.
    let reused = ENIGO
        .lock()
        .map(|mut g| g.as_mut().and_then(|e| e.text(text).ok()).is_some())
        .unwrap_or(false);
    if reused {
        return Ok(());
    }
    let mut enigo = Enigo::new(&Settings::default()).map_err(|e| format!("Enigo: {e}"))?;
    let res = enigo.text(text).map_err(|e| format!("While typing: {e}"));
    if res.is_ok() {
        if let Ok(mut g) = ENIGO.lock() {
            *g = Some(enigo);
        }
    }
    res
}
