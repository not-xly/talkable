#!/usr/bin/env python3
"""Generates every app icon from assets/icon-source.jpeg with rounded corners.

macOS expects the artwork inside a rounded square with transparent margins
(1024 canvas, 824 artwork, ~185px corner radius). Windows and Linux show the
PNG/ICO as-is, so those get a full-bleed rounded square instead.

Requires Pillow (pip install Pillow). Run from the repo root:
    python3 scripts/make_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "icon-source.jpeg"
TAURI_ICONS = ROOT / "desktop" / "src-tauri" / "icons"

SS = 4  # supersampling factor for smooth edges

# macOS grid: 1024 canvas, artwork 824x824 centered, corner radius 185.
MACOS_CANVAS = 1024
MACOS_ART = 824
MACOS_RADIUS = 185

# Full-bleed rounded square for Windows/Linux.
DESKTOP_RADIUS_RATIO = 0.225


def rounded_mask(size: int, radius: int) -> Image.Image:
    big = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, size * SS - 1, size * SS - 1), radius=radius * SS, fill=255
    )
    return big.resize((size, size), Image.LANCZOS)


def load_artwork(size: int) -> Image.Image:
    """Center-cropped square artwork (the source has outer margins)."""
    img = Image.open(SOURCE).convert("RGBA")
    short = min(img.size)
    left = (img.width - short) // 2
    top = (img.height - short) // 2
    inner = short * 1150 // 2048  # trim the outer margins of the source
    left = (img.width - inner) // 2
    top = (img.height - inner) // 2
    return img.crop((left, top, left + inner, top + inner)).resize(
        (size, size), Image.LANCZOS
    )


def macos_icon() -> Image.Image:
    canvas = Image.new("RGBA", (MACOS_CANVAS, MACOS_CANVAS), (0, 0, 0, 0))
    art = load_artwork(MACOS_ART)
    mask = rounded_mask(MACOS_ART, MACOS_RADIUS)
    canvas.paste(art, ((MACOS_CANVAS - MACOS_ART) // 2,) * 2, mask)
    return canvas


def desktop_icon(size: int) -> Image.Image:
    art = load_artwork(size)
    mask = rounded_mask(size, round(size * DESKTOP_RADIUS_RATIO))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(art, (0, 0), mask)
    return out


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Missing {SOURCE}")

    macos = macos_icon()
    macos.save(ROOT / "assets" / "icon-1024.png")

    TAURI_ICONS.mkdir(parents=True, exist_ok=True)
    for name, size in [("32x32.png", 32), ("128x128.png", 128), ("128x128@2x.png", 256), ("icon.png", 512)]:
        desktop_icon(size).save(TAURI_ICONS / name)

    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    desktop_icon(1024).save(TAURI_ICONS / "icon.ico", sizes=ico_sizes)

    print(f"OK: {ROOT / 'assets' / 'icon-1024.png'} + {TAURI_ICONS}")


if __name__ == "__main__":
    main()
