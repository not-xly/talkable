use std::fs::File;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use candle_core::{DType, Device, Tensor};
use candle_transformers::generation::LogitsProcessor;
use candle_transformers::models::quantized_qwen3::ModelWeights;
use tokenizers::Tokenizer;

use crate::models;

const SYSTEM_PROMPT: &str = "You are a voice-dictation proofreader. Only fix the user's text: \
punctuation, capitalization, accents and filler words, keeping the original language. \
Don't change the meaning or add content. Reply with ONLY the corrected text, \
no explanations or quotes. /no_think";

/// Candle is pure Rust (no C++ or linked ggml): it can live with the
/// transcription engine in the same binary without symbol clashes. The model
/// loads once and is reused on every dictation.
struct Loaded {
    model: ModelWeights,
    tokenizer: Tokenizer,
    eos: Vec<u32>,
}

static CACHED: Mutex<Option<(PathBuf, PathBuf, Loaded)>> = Mutex::new(None);

/// The tokenizer is tiny (~MB) and downloads itself if missing.
fn ensure_tokenizer(path: &Path) -> Result<(), String> {
    if path.exists() {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let bytes = reqwest::blocking::get(models::TOKENIZER_URL)
        .and_then(|r| r.error_for_status())
        .map_err(|e| format!("Couldn't download the tokenizer: {e}"))?
        .bytes()
        .map_err(|e| e.to_string())?;
    std::fs::write(path, &bytes).map_err(|e| e.to_string())?;
    Ok(())
}

fn load(model_path: &Path, tok_path: &Path) -> Result<Loaded, String> {
    let device = Device::Cpu;
    let mut f = File::open(model_path).map_err(|e| format!("Couldn't open the AI model: {e}"))?;
    let content = candle_core::quantized::gguf_file::Content::read(&mut f)
        .map_err(|e| format!("Invalid model file: {e}"))?;
    let model = ModelWeights::from_gguf(content, &mut f, &device)
        .map_err(|e| format!("Couldn't load the AI model: {e}"))?;
    let tokenizer = Tokenizer::from_file(tok_path).map_err(|e| format!("Tokenizer: {e}"))?;
    let eos = ["<|im_end|>", "<|endoftext|>"]
        .iter()
        .filter_map(|t| tokenizer.token_to_id(t))
        .collect();
    Ok(Loaded {
        model,
        tokenizer,
        eos,
    })
}

fn cache_contains(model_path: &Path, tok_path: &Path) -> bool {
    CACHED
        .lock()
        .map(|g| {
            g.as_ref()
                .map(|(m, t, _)| m == model_path && *t == tok_path)
                .unwrap_or(false)
        })
        .unwrap_or(false)
}

/// If both files are already on disk, loads the model in the background so
/// the first polished dictation doesn't stall for seconds. Never touches the
/// network: if the tokenizer is missing we just wait for the first use.
pub fn prewarm(model_path: &Path) {
    if !model_path.exists() {
        return;
    }
    let tok_path = models::qwen_tokenizer_path();
    if !tok_path.exists() || cache_contains(model_path, &tok_path) {
        return;
    }
    let model = model_path.to_path_buf();
    std::thread::spawn(move || {
        let mut guard = match CACHED.lock() {
            Ok(g) => g,
            Err(_) => return,
        };
        let fresh = guard
            .as_ref()
            .map(|(m, t, _)| m != &model || *t != tok_path)
            .unwrap_or(true);
        if fresh {
            match load(&model, &tok_path) {
                Ok(loaded) => *guard = Some((model, tok_path, loaded)),
                Err(e) => eprintln!("talkable: AI polish warm-up failed: {e}"),
            }
        }
    });
}

/// Polishes raw text locally (greedy, no network). The model loads once and
/// is reused on every dictation.
pub fn polish(raw: &str, model_path: &Path) -> Result<String, String> {
    let tok_path = models::qwen_tokenizer_path();
    ensure_tokenizer(&tok_path)?;

    let mut guard = CACHED.lock().map_err(|_| "AI model lock".to_string())?;
    let stale = guard
        .as_ref()
        .map(|(m, t, _)| m != model_path || *t != tok_path)
        .unwrap_or(true);
    if stale {
        let loaded = load(model_path, &tok_path)?;
        *guard = Some((model_path.to_path_buf(), tok_path, loaded));
    }
    let loaded = &mut guard.as_mut().expect("freshly cached model").2;

    let prompt = format!(
        "<|im_start|>system\n{SYSTEM_PROMPT}<|im_end|>\n\
         <|im_start|>user\n{raw}<|im_end|>\n\
         <|im_start|>assistant\n"
    );
    let toks = loaded
        .tokenizer
        .encode(prompt, true)
        .map_err(|e| format!("Tokenizing: {e}"))?;
    let mut all: Vec<u32> = toks.get_ids().to_vec();
    let start_len = all.len();
    if start_len == 0 {
        return Err("Empty prompt".to_string());
    }

    // A proofreader never needs more tokens than roughly the raw text it is
    // fixing. The old fixed 256-token budget was the single biggest cause of
    // slow dictations: the model kept generating long after the text was done.
    let raw_tokens = loaded
        .tokenizer
        .encode(raw, false)
        .map(|t| t.get_ids().len())
        .unwrap_or(raw.len() / 3);
    let max_new_tokens = (raw_tokens + raw_tokens / 2 + 16).clamp(32, 256);

    let device = Device::Cpu;
    let mut sampler = LogitsProcessor::new(299792458, None, None);
    let mut wrote_content = false;
    for _ in 0..max_new_tokens {
        let context = if all.len() > start_len { 1 } else { all.len() };
        let start_pos = all.len().saturating_sub(context);
        let input = Tensor::new(&all[start_pos..], &device)
            .and_then(|t| t.unsqueeze(0))
            .map_err(|e| format!("Decode: {e}"))?;
        let logits = loaded
            .model
            .forward(&input, start_pos)
            .and_then(|t| t.squeeze(0))
            .and_then(|t| t.squeeze(0))
            .and_then(|t| t.to_dtype(DType::F32))
            .map_err(|e| format!("Decode: {e}"))?;
        let next = sampler
            .sample(&logits)
            .map_err(|e| format!("Sampling: {e}"))?;
        all.push(next);
        if loaded.eos.contains(&next) {
            break;
        }
        // The corrected text is single-line: stop at the first newline after
        // real content instead of letting the model ramble.
        let piece = loaded.tokenizer.decode(&[next], false).unwrap_or_default();
        if piece.chars().any(|c| !c.is_whitespace()) {
            wrote_content = true;
        } else if piece.contains('\n') && wrote_content {
            all.pop();
            break;
        }
    }

    // Decoding everything at the end keeps multibyte chars (á, ñ, …) intact.
    let out = loaded
        .tokenizer
        .decode(&all[start_len..], true)
        .map_err(|e| format!("Decode: {e}"))?;
    Ok(out
        .trim()
        .trim_matches('"')
        .trim_end_matches("<|im_end|>")
        .trim()
        .to_string())
}

/// Sanity check: if the model went off the rails, return the raw text.
pub fn sane(polished: &str, raw: &str) -> Option<String> {
    let p = polished.trim();
    let r = raw.trim();
    if p.is_empty() || r.is_empty() {
        return None;
    }
    let pr = p.chars().count() as f64;
    let rr = r.chars().count() as f64;
    if pr < rr * 0.4 || pr > rr * 2.5 {
        return None;
    }
    Some(p.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sane_accepts_minor_edits() {
        assert_eq!(
            sane("Hello, world!", "hello world").as_deref(),
            Some("Hello, world!")
        );
    }

    #[test]
    fn sane_rejects_empty_output() {
        assert_eq!(sane("   ", "hello"), None);
        assert_eq!(sane("hello", "   "), None);
    }

    #[test]
    fn sane_rejects_runaway_output() {
        let long = "yes ".repeat(50);
        assert_eq!(sane(&long, "hello"), None);
    }

    #[test]
    fn sane_rejects_truncated_output() {
        assert_eq!(sane("ok", "one two three four five six seven eight"), None);
    }
}
