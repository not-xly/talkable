/// Types text into the focused app.
/// Linux: requires X11 (Wayland isn't supported by enigo yet).
pub fn type_text(text: &str) -> Result<(), String> {
    use enigo::{Enigo, Keyboard, Settings};
    let mut enigo = Enigo::new(&Settings::default())
        .map_err(|e| format!("Enigo: {e}"))?;
    enigo.text(text).map_err(|e| format!("While typing: {e}"))
}
