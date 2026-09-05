use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

pub const WHISPER_URL: &str =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin";
pub const QWEN_URL: &str =
    "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf";
pub const TOKENIZER_URL: &str =
    "https://huggingface.co/Qwen/Qwen3-0.6B/resolve/main/tokenizer.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub language: String,
    pub polish: bool,
    pub onboarding_done: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self { language: "en".into(), polish: true, onboarding_done: false }
    }
}

pub fn data_dir() -> PathBuf {
    let base = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
    let dir = base.join("talkable");
    fs::create_dir_all(&dir).ok();
    dir
}

pub fn models_dir() -> PathBuf {
    let dir = data_dir().join("models");
    fs::create_dir_all(&dir).ok();
    dir
}

pub fn whisper_model_path() -> PathBuf {
    models_dir().join("ggml-base.bin")
}

pub fn qwen_model_path() -> PathBuf {
    models_dir().join("Qwen3-0.6B-Q4_K_M.gguf")
}

pub fn qwen_tokenizer_path() -> PathBuf {
    models_dir().join("Qwen3-tokenizer.json")
}

pub fn config_path() -> PathBuf {
    data_dir().join("config.json")
}

pub fn load_config() -> Config {
    fs::read_to_string(config_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save_config(cfg: &Config) {
    if let Ok(json) = serde_json::to_string_pretty(cfg) {
        fs::write(config_path(), json).ok();
    }
}
