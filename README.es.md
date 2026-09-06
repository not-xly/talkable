<img src="assets/icon-1024.png" width="128" alt="Talkable">

# Talkable

> Hablá y se escribe. Dictado por voz gratis, privado y local para tu escritorio.

*English version: [README.md](README.md)*

[![build](https://github.com/not-xly/talkable/actions/workflows/build.yml/badge.svg)](https://github.com/not-xly/talkable/actions) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[Descargas](#instalar) · [Cómo se usa](#uso) · [Compilar](#compilar) · [Estructura](#estructura) · [Roadmap](docs/ROADMAP.md) · [Licencias](THIRD_PARTY_LICENSES.md)

Talkable convierte tu voz en texto en **cualquier aplicación**, usando **solo tu computadora**: sin nube, sin cuentas, sin suscripciones y sin límite de palabras.

Lo empecé porque no quería mandar mi voz a un servidor ni pagar una mensualidad por dictar. Funciona así:

1. Mantenés una tecla, hablás, la soltás.
2. La transcripción aparece donde esté tu cursor, en la app que estés usando.
3. Nada se guarda ni se envía a ningún lado: al soltar la tecla, el audio se descarta.

- **macOS** — app nativa (Swift) con el reconocimiento de voz del sistema, en el dispositivo.
- **Windows y Linux** — app Tauri con whisper.cpp (transcripción) + llama.cpp (pulido con IA), todo local. Los instaladores (`.exe` / `.AppImage` / `.deb`) los genera CI en cada push a `main`, en la pestaña Actions.

## Por qué local

| | Dictado en la nube | Talkable |
|---|---|---|
| Precio | Suscripción mensual | **Gratis, MIT** |
| Límite de palabras | Suele haber tope | **Sin límite** |
| Tu audio sale de tu máquina | Sí | **No** |
| Funciona sin internet | No | **Sí** (después de descargar los modelos una vez) |
| Cuenta obligatoria | Sí | **No** |

## Instalar

Elegí tu camino según lo que quieras hacer.

### Solo quiero usarlo

Descargá los archivos del [último release](https://github.com/not-xly/talkable/releases/latest) (público, sin login):

| Plataforma | Archivo |
|---|---|
| Windows (x64) | `Talkable_0.3.0_x64-setup.exe` (instalador NSIS) |
| Linux (x86_64) | `Talkable_0.3.0_amd64.AppImage` (portable, ~84 MB) o `Talkable_0.3.0_amd64.deb` (~7 MB + paquetes del sistema) |
| macOS | `Talkable-macOS.zip` (contiene `Talkable.app`) |

También hay builds de cada push en los artefactos de [Actions](https://github.com/not-xly/talkable/actions) (piden login y caducan).

Detalles por sistema:

- **Windows**: la primera vez, la app descarga el modelo de transcripción (~145 MB, obligatorio: la configuración no se puede completar sin él) y, si querés pulido con IA, el modelo de pulido (~400 MB, opcional). Después funciona offline. Un indicador flotante pequeño muestra qué está pasando mientras dictás. Si SmartScreen avisa al instalar: Más información → Ejecutar de todas formas (build sin firmar de momento).
- **Linux**: hace falta sesión **X11** para escribir en otras apps, más el paquete `libwebkit2gtk-4.1`. En Wayland se dicta con el botón Dictar y el texto se copia a mano.
- **macOS**: al ser una build sin firmar, la primera vez hacé clic derecho → Abrir (o permitirla en Ajustes › Privacidad y seguridad). Después dale los permisos que pide:

| Permiso | Para qué |
|---|---|
| **Micrófono** | Escucharte. El audio queda en tu máquina. |
| **Reconocimiento de voz** | El transcriptor local del sistema. |
| **Monitorización de entrada** | Detectar la tecla de dictado en todo el sistema. |
| **Accesibilidad** | Escribir el texto en la app que estés usando. |

### Quiero compilarlo

Necesitás git y, según la plataforma:

- **macOS**: Command Line Tools de Xcode (`xcode-select --install`), macOS 14+, Swift 5.9+.
- **Windows/Linux**: Rust estable + Node (para el CLI de Tauri). En Linux además: `libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev libasound2-dev libxtst-dev libxi-dev pkg-config cmake`.

```bash
git clone https://github.com/not-xly/talkable.git && cd talkable
```

#### Compilar (macOS)

```bash
cd macos
./scripts/make_app.sh
open build/Talkable.app
```

#### Compilar (Windows/Linux)

```bash
cd desktop/src-tauri
cargo check          # chequeo rápido
npm install -g @tauri-apps/cli
tauri build          # genera .exe / .AppImage / .deb en target/release/bundle
```

## Uso

**macOS:** mantené **⌘ derecho** para dictar y soltá para pegar. Un toque rápido empieza, otro toque pega.

**Windows y Linux:** **Ctrl derecho** (o **F6** como alternativa). Mismo gesto: mantener para dictar, soltar para pegar, toque rápido para alternar. Un indicador flotante cerca de la parte inferior de la pantalla muestra qué está pasando (grabando, transcribiendo, el texto final) sin robar el foco. Si el atajo global no responde, la ventana trae un botón Dictar; y si el tecleo automático falla, el texto queda en la ventana para copiarlo a mano.

## Estado (v0.3)

Ya funciona:

- Atajo global en los tres sistemas, con modo mantener y modo toque.
- macOS: transcripción en el dispositivo (Apple Speech), panel flotante en vivo, auto-escritura con fallback al portapapeles, preferencias y guía inicial. Idiomas: en-US, es-AR, es-ES, es-MX, es-CO, es-CL, pt-BR, fr-FR, it-IT.
- Windows y Linux: transcripción local con whisper.cpp, pulido opcional con Qwen3-0.6B, un indicador flotante de dictado sobre el escritorio y una guía inicial que exige el modelo de transcripción (el pulido con IA queda opcional).
- Pulido con IA (opcional): un modelo chico corriendo en tu máquina arregla puntuación, tildes, mayúsculas y muletillas.

En camino: atajo configurable, comandos de voz, auto-actualizaciones. Detalle en [docs/ROADMAP.md](docs/ROADMAP.md).

## Estructura

```
talkable/
├── macos/                    app nativa de macOS (Swift)
│   ├── Sources/Talkable/     TalkableApp, AppState, HotkeyManager,
│   │                         SpeechTranscriber, AudioCapture, HUDController,
│   │                         TextTyper, AIPolisher, PreferencesView,
│   │                         OnboardingView, XlyTheme
│   ├── scripts/make_app.sh   compila y arma Talkable.app (firmado ad-hoc)
│   └── Package.swift         dependencias Swift (MLX, Hugging Face)
├── desktop/                  app de Windows y Linux (Tauri v2)
│   ├── src-tauri/src/        main.rs, audio.rs, stt.rs, polish.rs,
│   │                         models.rs, typer.rs, hud.rs
│   ├── src-tauri/Cargo.toml  dependencias Rust
│   └── ui/                   index.html (estado, modelos, configuración)
│                             y hud.html (indicador flotante)
├── assets/                   icono (icns, png, svg, fuente)
├── scripts/make_icon.sh      regenera todos los iconos con esquinas
│                             redondeadas (necesita Pillow)
├── docs/ROADMAP.md           qué hay y qué falta, por versión
├── .github/workflows/        CI: builds de Windows, Linux y macOS en cada push
├── LICENSE                   MIT
└── THIRD_PARTY_LICENSES.md   licencias de cada dependencia y modelo
```

## Cómo está armado

**macOS:** la tecla ⌘ derecha se escucha con un `CGEventTap`, el audio se captura con `AVAudioEngine`, transcribe Apple Speech en el dispositivo y el texto se escribe con eventos `CGEvent` Unicode (o va al portapapeles).

**Windows/Linux:** el Ctrl derecho se escucha con un hook de bajo nivel (`rdev`, F6 de respaldo vía el plugin global-shortcut), el audio se graba con `cpal`, transcribe `whisper.cpp`, pule `candle` (Rust puro, sin C++) con Qwen3-0.6B y escribe con `enigo`.

```
tecla ─▶ hook global ─▶ micrófono ─▶ STT local ─▶ pulido IA local ─▶ tecleo
macOS:    CGEventTap    AVAudioEngine  Apple Speech   MLX/Qwen3      CGEvent
win/lin:  rdev (+F6)    cpal           whisper.cpp    candle/Qwen3   enigo
```

## Modelos

| Modelo | Origen | Tamaño aprox. | Licencia |
|---|---|---|---|
| Whisper base (transcripción, Win/Linux) | `ggerganov/whisper.cpp` | 145 MB | MIT |
| Qwen3-0.6B Q4_K_M (pulido, Win/Linux) | `unsloth/Qwen3-0.6B-GGUF` | 400 MB | Apache 2.0 |
| Qwen3-0.6B 4-bit (pulido, macOS vía MLX) | `mlx-community/Qwen3-0.6B-4bit` | 335 MB | Apache 2.0 |

Se descargan una sola vez desde Hugging Face. En macOS la transcripción no necesita modelo: usa el que ya trae el sistema.

## Comandos útiles

```bash
cd macos && ./scripts/make_app.sh   # build macOS
cd desktop/src-tauri && cargo check  # chequeo rápido desktop
./scripts/make_icon.sh               # regenerar icono (desde la raíz)
```

## Privacidad

- Sin telemetría, sin analytics, sin reportes de fallos, sin cuentas.
- Fuera de la descarga inicial de modelos, la app no abre conexiones de red. Podés comprobarlo con un firewall (Little Snitch) o con `nettop`.
- El audio se procesa en memoria y se descarta al soltar la tecla.

## Licencia

Talkable es **MIT**: usalo, modificalo y vendelo si querés ([LICENSE](LICENSE)).

Todo lo que usa —librerías, modelos, empaquetadores— permite uso comercial y redistribución. El detalle, componente por componente, está en [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
