# Roadmap

## v0.1.0 — current

macOS (native Swift app):

- [x] Global hotkey: hold right ⌘ to dictate, release to paste; quick-tap toggle
- [x] On-device transcription (Apple Speech, offline) with live floating panel
- [x] Auto-typing into any app (CGEvent Unicode) + clipboard fallback
- [x] Menu-bar app with preferences (language, on-device only, sounds, punctuation, AI polish)
- [x] Optional local AI polish (Qwen3-0.6B via MLX) with first-run download
- [x] First-run onboarding guide
- [x] Languages: en-US, es-AR, es-ES, es-MX, es-CO, es-CL, pt-BR

Windows & Linux (Tauri v2 app):

- [x] Right Ctrl hotkey (rdev hook) + F6 fallback; hold-to-talk and tap-to-toggle
- [x] Local transcription (whisper.cpp) + optional Qwen3-0.6B polish (candle, pure Rust)
- [x] Click-to-dictate button (Wayland fallback) with manual-copy fallback
- [x] First-run onboarding with model downloads and progress
- [x] CI builds: Windows `.exe` (NSIS) + Linux `.AppImage`/`.deb` + macOS `.app` zip on every tag

## v0.2.0 — next

- [x] Transcription languages: English, Spanish, French, Portuguese, Italian (all three platforms)
- [ ] Configurable hotkey (UI picker)
- [ ] Spoken commands ("new line", "delete that")
- [ ] App exclusion list (never type into banking apps, etc.)
- [ ] Personal dictionary / custom words
- [ ] Auto-updates (Sparkle on macOS)
- [ ] UI localization (English / Spanish)

## Ideas parking lot

- Streaming partial-polish (polish as you speak)
- Per-app style profiles (casual chat vs. formal email)
- Multilingual auto-detection (es ↔ en code-switching)
- Landing page (GitHub Pages) with demo GIF
