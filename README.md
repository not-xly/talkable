<img src="assets/icon-1024.png" width="128" alt="Talkable">

# Talkable

> Talk. It types. **Free, private, local voice dictation for your desktop.**

*Versión en español: [README.es.md](README.es.md)*

[![build](https://github.com/not-xly/talkable/actions/workflows/build.yml/badge.svg)](https://github.com/not-xly/talkable/actions) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[Downloads](#install) · [Usage](#usage) · [Building](#building) · [Structure](#structure) · [Roadmap](docs/ROADMAP.md) · [Licenses](THIRD_PARTY_LICENSES.md)

Talkable turns your voice into typed text in **any app**, using **only your computer** — no cloud, no accounts, no subscriptions, no word limits.

I started it because I didn't want to send my voice to a server or pay a monthly fee just to dictate. It works like this:

1. Hold a key, speak, release it.
2. The transcription lands wherever your cursor is, in whatever app you're using.
3. Nothing is stored or sent anywhere: when you release the key, the audio is gone.

- **macOS** — native app (Swift) with on-device system speech recognition.
- **Windows & Linux** — Tauri app with whisper.cpp (transcription) + llama.cpp (AI polish), all local. Installers (`.exe` / `.AppImage` / `.deb`) are built by CI on every push to `main`, under the Actions tab.

## Why local

| | Cloud dictation | Talkable |
|---|---|---|
| Price | Monthly subscription | **Free, MIT** |
| Word limits | Usually capped | **Unlimited** |
| Your audio leaves your machine | Yes | **No** |
| Works offline | No | **Yes** (after a one-time model download) |
| Account required | Yes | **No** |

## Install

Pick the path that matches you.

### I just want to use it

Grab the files from the [latest release](https://github.com/not-xly/talkable/releases/latest) (public, no login needed):

| Platform | File |
|---|---|
| Windows (x64) | `Talkable_0.3.0_x64-setup.exe` (NSIS installer) |
| Linux (x86_64) | `Talkable_0.3.0_amd64.AppImage` (portable, ~84 MB) or `Talkable_0.3.0_amd64.deb` (~7 MB + system packages) |
| macOS | `Talkable-macOS.zip` (contains `Talkable.app`) |

Bleeding-edge builds from every push are also in [Actions](https://github.com/not-xly/talkable/actions) artifacts (login required, they expire).

Notes per system:

- **Windows**: on first launch the app downloads the transcription model (~145 MB, required — setup can't finish without it) and, if you want AI polish, the polish model (~400 MB, optional). Afterwards it works offline. A small floating indicator shows what's happening while you dictate. If SmartScreen warns you: More info → Run anyway (unsigned build for now).
- **Linux**: an **X11** session is required to type into other apps, plus the `libwebkit2gtk-4.1` package. On Wayland, dictate with the Dictate button and copy the text by hand.
- **macOS**: being an unsigned build for now, right-click → Open on first launch (or allow it in Settings › Privacy & Security). Then grant what it asks for:

| Permission | Why |
|---|---|
| **Microphone** | To hear you. Audio stays on your machine. |
| **Speech Recognition** | The system's on-device transcriber. |
| **Input Monitoring** | To catch the dictation key system-wide. |
| **Accessibility** | To type the text into the app you're using. |

### I want to build it

You need git and, depending on the platform:

- **macOS**: Xcode Command Line Tools (`xcode-select --install`), macOS 14+, Swift 5.9+.
- **Windows/Linux**: stable Rust + Node (for the Tauri CLI). On Linux also: `libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev libasound2-dev libxtst-dev libxi-dev pkg-config cmake`.

```bash
git clone https://github.com/not-xly/talkable.git && cd talkable
```

#### Build (macOS)

```bash
cd macos
./scripts/make_app.sh
open build/Talkable.app
```

#### Build (Windows/Linux)

```bash
cd desktop/src-tauri
cargo check          # quick check
npm install -g @tauri-apps/cli
tauri build          # produces .exe / .AppImage / .deb under target/release/bundle
```

## Usage

**macOS:** hold **right ⌘** to dictate, release to paste. A quick tap starts, another tap pastes.

**Windows & Linux:** **right Ctrl** (or **F6** as a fallback). Same gestures: hold to dictate, release to paste, quick tap to toggle. A small floating indicator near the bottom of the screen shows what's happening (recording, transcribing, the final text) without stealing focus. If the global hotkey doesn't respond, the window has a Dictate button; and if auto-typing fails, the text stays in the window so you can copy it by hand.

## Status (v0.3)

Already working:

- Global hotkey on all three systems, hold and tap modes.
- macOS: on-device transcription (Apple Speech), live floating panel, auto-typing with clipboard fallback, preferences and first-run guide. Languages: en-US, es-AR, es-ES, es-MX, es-CO, es-CL, pt-BR, fr-FR, it-IT.
- Windows & Linux: local transcription with whisper.cpp, optional polish with Qwen3-0.6B, a floating dictation indicator above the desktop, and a first-run guide that requires the transcription model (AI polish stays optional).
- AI polish (optional): a small model running on your machine fixes punctuation, accents, capitalization and filler words.

On the way: configurable hotkey, spoken commands, auto-updates. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Structure

```
talkable/
├── macos/                    native macOS app (Swift)
│   ├── Sources/Talkable/     TalkableApp, AppState, HotkeyManager,
│   │                         SpeechTranscriber, AudioCapture, HUDController,
│   │                         TextTyper, AIPolisher, PreferencesView,
│   │                         OnboardingView, XlyTheme
│   ├── scripts/make_app.sh   builds and bundles Talkable.app (ad-hoc signed)
│   └── Package.swift         Swift dependencies (MLX, Hugging Face)
├── desktop/                  Windows & Linux app (Tauri v2)
│   ├── src-tauri/src/        main.rs, audio.rs, stt.rs, polish.rs,
│   │                         models.rs, typer.rs, hud.rs
│   ├── src-tauri/Cargo.toml  Rust dependencies
│   └── ui/                   index.html (status, models, setup) and
│                             hud.html (floating indicator)
├── assets/                   icon (icns, png, svg, source)
├── scripts/make_icon.sh      regenerates every icon with rounded corners
│                             (needs Pillow: pip install Pillow)
├── docs/ROADMAP.md           what's done and what's missing, per version
├── .github/workflows/        CI: Windows, Linux and macOS builds on every push
├── LICENSE                   MIT
└── THIRD_PARTY_LICENSES.md   license of every dependency and model
```

## How it's built

**macOS:** the right ⌘ key is watched with a `CGEventTap`, audio is captured with `AVAudioEngine`, Apple Speech transcribes on-device, and text is typed with `CGEvent` Unicode events (or goes to the clipboard).

**Windows/Linux:** right Ctrl is watched with a low-level hook (`rdev`, F6 fallback via the global-shortcut plugin), audio is recorded with `cpal`, transcribed by `whisper.cpp`, polished by `candle` (pure Rust, no C++) with Qwen3-0.6B, typed with `enigo`.

```
key ─▶ global hook ─▶ microphone ─▶ local STT ─▶ local AI polish ─▶ typing
macOS:    CGEventTap   AVAudioEngine  Apple Speech   MLX/Qwen3      CGEvent
win/lin:  rdev (+F6)   cpal           whisper.cpp    candle/Qwen3   enigo
```

## Models

| Model | Source | Approx. size | License |
|---|---|---|---|
| Whisper base (transcription, Win/Linux) | `ggerganov/whisper.cpp` | 145 MB | MIT |
| Qwen3-0.6B Q4_K_M (polish, Win/Linux) | `unsloth/Qwen3-0.6B-GGUF` | 400 MB | Apache 2.0 |
| Qwen3-0.6B 4-bit (polish, macOS via MLX) | `mlx-community/Qwen3-0.6B-4bit` | 335 MB | Apache 2.0 |

Downloaded once from Hugging Face. On macOS transcription needs no model: it uses the one already in the system.

## Handy commands

```bash
cd macos && ./scripts/make_app.sh   # macOS build
cd desktop/src-tauri && cargo check  # quick desktop check
./scripts/make_icon.sh               # regenerate icon (from repo root)
```

## Privacy

- No telemetry, no analytics, no crash reports, no accounts.
- Outside the one-time model download, the app never opens a network connection. You can verify that with a firewall (Little Snitch) or `nettop`.
- Audio is processed in memory and discarded when you release the key.

## License

Talkable is **MIT**: use it, change it, sell it if you want ([LICENSE](LICENSE)).

Everything it uses — libraries, models, packagers — allows commercial use and redistribution. The full breakdown is in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
