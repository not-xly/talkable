# Third-party licenses

Everything Talkable uses or downloads allows **commercial use, modification and
redistribution**. There are no GPL/AGPL components and no non-commercial
licenses anywhere in the dependency tree: audited over `Cargo.lock` and over
Swift's `Package.resolved`, zero GPL/AGPL hits.

This repo's own code is MIT (see `LICENSE`).

## Models (downloaded on first use, never shipped with the app)

### Whisper base — transcription (Windows/Linux)

- Source: https://huggingface.co/ggerganov/whisper.cpp (`ggml-base.bin`)
- Original OpenAI Whisper weights, **MIT** license (Copyright © 2022 OpenAI)
- Commercial use: allowed.

### Qwen3-0.6B Q4_K_M — AI polish (Windows/Linux)

- Source: https://huggingface.co/unsloth/Qwen3-0.6B-GGUF
- **Apache License 2.0** (Qwen Team / Alibaba Cloud)
- Commercial use: allowed.

### Qwen3-0.6B 4-bit — AI polish (macOS, via MLX)

- Source: https://huggingface.co/mlx-community/Qwen3-0.6B-4bit
- **Apache License 2.0**
- Commercial use: allowed.

### Speech recognition (macOS)

- Apple's Speech framework, part of the OS and subject to its terms.
  Transcription uses the models macOS already ships; the app distributes no
  voice models of its own.

## Libraries (compiled into the app)

### whisper.cpp (via whisper-rs) — MIT / Unlicense

- Engine: https://github.com/ggerganov/whisper.cpp (**MIT**)
- `whisper-rs` binding: Unlicense (public-domain dedication)

### candle (desktop AI inference) — MIT / Apache-2.0

- `candle-core`, `candle-nn`, `candle-transformers` + `tokenizers`
  (https://github.com/huggingface/candle)
- Pure Rust, no C++ or linked ggml: that's what lets it live with whisper.cpp
  in the same binary (both used to bring their own ggml copy and the linker
  rejected the mix). Technical note, not a legal one.

### Tauri v2 + global-shortcut plugin — MIT / Apache-2.0

- https://github.com/tauri-apps/tauri

### Audio, typing and hotkeys (desktop) — Apache-2.0 / MIT

- `cpal` (microphone): Apache-2.0
- `enigo` (typing): MIT
- `rdev` (Right Ctrl detection): MIT

### Rust utilities — MIT / Apache-2.0

- `reqwest`, `dirs`, `serde`, `serde_json` and the rest of the tree: MIT,
  Apache-2.0, BSD (2/3-clause), ISC, Zlib, Unlicense and Unicode-3.0. Edge
  cases: the `cssparser` family (MPL-2.0, file-level weak copyleft,
  compatible with commercial apps) and `webpki-roots` (CDLA-Permissive-2.0).
  On Linux the bundle dynamically links system libraries (WebKitGTK and
  family, LGPL), which is that license's intended use.

### Swift (macOS) — MIT / Apache-2.0

- `mlx-swift`, `mlx-swift-lm` (local inference): **MIT** (© ml-explore)
- `swift-huggingface`, `swift-transformers` and transitive deps (`swift-jinja`,
  `swift-syntax`, `swift-crypto`, etc.): **Apache-2.0** (© Hugging Face,
  Apple, Swift)

## Packaging

- Windows installer (NSIS): zlib/libpng license for the core (explicitly
  allows commercial applications) plus permissive licenses for its
  compression modules.
- Linux AppImage / `.deb`: MIT tooling.
- Legal notices ship with every release: `Talkable.app/Contents/Resources`
  (macOS) and the bundle resources (Windows/Linux).
