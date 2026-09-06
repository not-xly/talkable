use std::path::Path;
use std::sync::Mutex;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

static CTX: Mutex<Option<WhisperContext>> = Mutex::new(None);

/// Loads the model once; later calls reuse it. Dictation and warm-up both go
/// through here, so the model is loaded exactly once per process.
pub fn load_model(model_path: &Path) -> Result<(), String> {
    let mut guard = CTX.lock().map_err(|_| "Context lock".to_string())?;
    if guard.is_none() {
        let ctx = WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
            .map_err(|e| format!("Couldn't load the transcription model: {e}"))?;
        *guard = Some(ctx);
    }
    Ok(())
}

/// Loads the model in the background so the first dictation doesn't pay the
/// load time (several seconds for a cold start).
pub fn warm_up(model_path: &Path) {
    if model_path.exists() {
        let model_path = model_path.to_path_buf();
        std::thread::spawn(move || {
            if let Err(e) = load_model(&model_path) {
                eprintln!("talkable: model warm-up failed: {e}");
            }
        });
    }
}

fn thread_count() -> i32 {
    std::thread::available_parallelism()
        .map(|n| n.get() as i32)
        .unwrap_or(4)
}

/// Transcribes mono 16 kHz PCM samples. The context lock is held for the
/// whole call: dictations are serialized and warm-up can't race a load.
pub fn transcribe(samples: &[f32], language: &str, model_path: &Path) -> Result<String, String> {
    load_model(model_path)?;
    let guard = CTX.lock().map_err(|_| "Context lock".to_string())?;
    let ctx = guard
        .as_ref()
        .ok_or_else(|| "Transcription model not loaded".to_string())?;

    let mut state = ctx.create_state().map_err(|e| e.to_string())?;

    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    // Use every available core: the built-in default is a fixed low thread
    // count, which made transcription several times slower than necessary.
    params.set_n_threads(thread_count());
    params.set_language(Some(language));
    params.set_translate(false);
    // Don't condition on previous decodes: prevents repetition loops on
    // silence and stray text bleeding between dictations.
    params.set_no_context(true);
    params.set_suppress_blank(true);
    params.set_print_progress(false);
    params.set_print_special(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    // No single-segment mode: it truncated dictations past the first segment.

    state
        .full(params, samples)
        .map_err(|e| format!("Transcription: {e}"))?;

    let n = state.full_n_segments();
    let mut text = String::new();
    for i in 0..n {
        if let Some(seg) = state.get_segment(i) {
            if let Ok(s) = seg.to_str() {
                text.push_str(s);
            }
        }
    }
    Ok(text.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thread_count_is_positive() {
        assert!(thread_count() >= 1);
    }
}
