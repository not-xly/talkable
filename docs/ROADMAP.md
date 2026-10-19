# Roadmap

## Unreleased

- Live text preview while you speak on Windows/Linux (previews every ~1.5 s, last 30 s of audio), matching macOS
- HUD moved to the top right on Windows/Linux; Liquid Glass style (native on macOS 26+, translucent card elsewhere)
- Dictations over 2 minutes paste the captured part with a note instead of failing
- Fixes from a code review: AI polish no longer carries history between dictations, a dictation released during the permission prompt no longer leaves the mic open, the tokenizer download is atomic, the AI model loads once, and Tauri commands no longer block the main thread

## v0.4.0

New in v0.4.0 (bug fixes + features):

- Fixed download state race, added size verification, real timeouts, resume + cancel
- Fixed tokenizer hang, input truncation (OOM guard), 2-minute dictation cap, Esc cancels
- Fixed Right Ctrl combos, hotkey tap leaks, typing races, Accessibility prompt, AI prewarm
- Added offline translation (needs the AI model), polish on/off in Settings, offline indicator
- Hardened HUD (correct monitor), CSP, CI tests, version script

Carried from v0.3.0:

macOS (native Swift app):

- [x] Global hotkey: hold right ⌘ to dictate, release to paste; quick-tap toggle
- [x] On-device transcription (Apple Speech, offline) with live floating panel
- [x] Auto-typing into any app (CGEvent Unicode) + clipboard fallback
- [x] Menu-bar app with preferences (language, on-device only, sounds, punctuation, AI polish)
- [x] Optional local AI polish (Qwen3-0.6B via MLX), prewarmed at launch
- [x] First-run setup guide with the shared design language; microphone and speech
      recognition are required to finish it, AI polish is optional
- [x] First-run window now opens reliably on launch (was only built while the menu was open)
- [x] Languages: en-US, es-AR, es-ES, es-MX, es-CO, es-CL, pt-BR, fr-FR, it-IT
- [x] Unit tests for text processing and locale fallback

Windows & Linux (Tauri v2 app):

- [x] Right Ctrl hotkey (rdev hook) + F6 fallback; hold-to-talk and tap-to-toggle
- [x] Local transcription + optional AI polish; both models prewarmed at startup
- [x] Floating dictation panel with live text (transparent, always-on-top, non-focus-stealing)
- [x] Audio capture supports every sample format the OS may report
- [x] Transcription uses all CPU cores; no more truncation of long dictations
- [x] Click-to-dictate button (Wayland fallback) with manual-copy fallback
- [x] First-run setup: transcription model REQUIRED to finish, AI polish OPTIONAL
      (enforced in the UI and re-validated by the backend)
- [x] Setup UI redesigned with the shared design language
- [x] App icon with properly rounded corners on every platform
- [x] Unit tests for audio resampling and polish sanity checks
- [x] CI builds: Windows `.exe` (NSIS) + Linux `.AppImage`/`.deb` + macOS `.app` zip on every push

## Next

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
