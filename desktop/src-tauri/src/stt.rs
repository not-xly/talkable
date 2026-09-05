use std::path::Path;
use std::sync::Mutex;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

static CTX: Mutex<Option<WhisperContext>> = Mutex::new(None);

/// Transcribes mono 16 kHz PCM samples with whisper.cpp.
pub fn transcribe(samples: &[f32], language: &str, model_path: &Path) -> Result<String, String> {
    let mut guard = CTX.lock().map_err(|_| "Context lock")?;
    if guard.is_none() {
        let ctx = WhisperContext::new_with_params(
            model_path,
            WhisperContextParameters::default(),
        )
        .map_err(|e| format!("Couldn't load the whisper model: {e}"))?;
        *guard = Some(ctx);
    }
    let ctx = guard.as_ref().unwrap();

    let mut state = ctx.create_state().map_err(|e| e.to_string())?;

    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_language(Some(language));
    params.set_print_progress(false);
    params.set_print_special(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_single_segment(true);

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
