#!/usr/bin/env python3
"""Generate Android launcher icon assets from a transparent foreground PNG.

Requires Pillow:
  python3 -m pip install pillow
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FOREGROUND = PROJECT_ROOT / "assets/branding/app_icon_turtle_book_foreground.png"
DEFAULT_RES_DIR = PROJECT_ROOT / "android/app/src/main/res"

LEGACY_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

ADAPTIVE_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

BACKGROUND_TOP = (248, 243, 232, 255)
BACKGROUND_CENTER = (243, 234, 214, 255)
BACKGROUND_BOTTOM = (232, 241, 228, 255)
HIGHLIGHT = (255, 255, 255, 62)
BORDER = (216, 195, 160, 255)
SHADOW = (74, 51, 31, 72)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--foreground",
        type=Path,
        default=DEFAULT_FOREGROUND,
        help="Transparent foreground PNG to place on top of the icon background.",
    )
    parser.add_argument(
        "--res-dir",
        type=Path,
        default=DEFAULT_RES_DIR,
        help="Android res directory to receive generated launcher assets.",
    )
    return parser.parse_args()


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def write_text(path: Path, content: str) -> None:
    ensure_parent(path)
    path.write_text(content, encoding="utf-8")


def create_vertical_gradient(size: int) -> Image.Image:
    gradient = Image.new("RGBA", (size, size))
    pixels = gradient.load()
    last = size - 1 or 1
    for y in range(size):
        position = y / last
        if position < 0.55:
            local = position / 0.55
            color = interpolate(BACKGROUND_TOP, BACKGROUND_CENTER, local)
        else:
            local = (position - 0.55) / 0.45
            color = interpolate(BACKGROUND_CENTER, BACKGROUND_BOTTOM, local)
        for x in range(size):
            pixels[x, y] = color
    return gradient


def interpolate(start: tuple[int, int, int, int], end: tuple[int, int, int, int], ratio: float) -> tuple[int, int, int, int]:
    ratio = max(0.0, min(1.0, ratio))
    return tuple(int(start[i] + (end[i] - start[i]) * ratio) for i in range(4))


def create_highlight(size: int, shape: str) -> Image.Image:
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    if shape == "round":
        bbox = (
            int(size * 0.16),
            int(size * 0.08),
            int(size * 0.84),
            int(size * 0.56),
        )
    else:
        bbox = (
            int(size * 0.14),
            int(size * 0.08),
            int(size * 0.86),
            int(size * 0.54),
        )
    draw.ellipse(bbox, fill=HIGHLIGHT)
    return overlay.filter(ImageFilter.GaussianBlur(radius=max(1, size // 18)))


def create_shape_mask(size: int, shape: str, margin: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    if shape == "round":
        draw.ellipse((margin, margin, size - margin, size - margin), fill=255)
    else:
        radius = max(1, int(size * 0.19))
        draw.rounded_rectangle(
            (margin, margin, size - margin, size - margin),
            radius=radius,
            fill=255,
        )
    return mask


def create_background_tile(size: int, shape: str) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    margin = max(1, int(size * 0.05))
    mask = create_shape_mask(size, shape, margin)

    shadow_mask = create_shape_mask(size, shape, margin)
    shadow = Image.new("RGBA", (size, size), SHADOW)
    shadow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset_y = max(1, int(size * 0.035))
    shadow_layer.paste(shadow, (0, offset_y), shadow_mask)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=max(1, size // 14)))
    canvas.alpha_composite(shadow_layer)

    gradient = create_vertical_gradient(size)
    gradient.alpha_composite(create_highlight(size, shape))
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile.paste(gradient, (0, 0), mask)
    canvas.alpha_composite(tile)

    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(border)
    stroke = max(1, size // 48)
    inset = margin + stroke // 2
    if shape == "round":
        draw.ellipse((inset, inset, size - inset, size - inset), outline=BORDER, width=stroke)
    else:
        radius = max(1, int(size * 0.19))
        draw.rounded_rectangle(
            (inset, inset, size - inset, size - inset),
            radius=radius,
            outline=BORDER,
            width=stroke,
        )
    canvas.alpha_composite(border)
    return canvas


def trim_alpha(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("Foreground image has no visible pixels.")
    return image.crop(bbox)


def fit_foreground(image: Image.Image, canvas_size: int, scale: float, y_shift: float = 0.0) -> Image.Image:
    trimmed = trim_alpha(image)
    max_w = int(canvas_size * scale)
    max_h = int(canvas_size * scale)
    ratio = min(max_w / trimmed.width, max_h / trimmed.height)
    resized = trimmed.resize(
        (max(1, int(trimmed.width * ratio)), max(1, int(trimmed.height * ratio))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    x = (canvas_size - resized.width) // 2
    y = (canvas_size - resized.height) // 2 + int(canvas_size * y_shift)
    canvas.alpha_composite(resized, (x, y))
    return canvas


def create_soft_shadow(size: int, subject_mask: Image.Image) -> Image.Image:
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    color = Image.new("RGBA", (size, size), (77, 58, 39, 42))
    offset = (0, max(1, int(size * 0.025)))
    shadow.paste(color, offset, subject_mask)
    return shadow.filter(ImageFilter.GaussianBlur(radius=max(1, size // 22)))


def compose_legacy_icon(foreground: Image.Image, size: int, shape: str) -> Image.Image:
    background = create_background_tile(size, shape)
    subject = fit_foreground(foreground, size, 0.76 if shape == "square" else 0.7, y_shift=0.01)
    shadow = create_soft_shadow(size, subject.getchannel("A"))
    background.alpha_composite(shadow)
    background.alpha_composite(subject)
    return background


def compose_adaptive_foreground(foreground: Image.Image, size: int) -> Image.Image:
    return fit_foreground(foreground, size, 0.78, y_shift=0.02)


def save_png(path: Path, image: Image.Image) -> None:
    ensure_parent(path)
    image.save(path, format="PNG")


def generate_assets(foreground_path: Path, res_dir: Path) -> None:
    foreground = Image.open(foreground_path).convert("RGBA")

    for density, size in LEGACY_SIZES.items():
        mipmap_dir = res_dir / f"mipmap-{density}"
        save_png(mipmap_dir / "ic_launcher.png", compose_legacy_icon(foreground, size, "square"))
        save_png(mipmap_dir / "ic_launcher_round.png", compose_legacy_icon(foreground, size, "round"))

    for density, size in ADAPTIVE_SIZES.items():
        mipmap_dir = res_dir / f"mipmap-{density}"
        save_png(mipmap_dir / "ic_launcher_foreground.png", compose_adaptive_foreground(foreground, size))

    write_text(
        res_dir / "mipmap-anydpi-v26/ic_launcher.xml",
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""",
    )
    write_text(
        res_dir / "mipmap-anydpi-v26/ic_launcher_round.xml",
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""",
    )
    write_text(
        res_dir / "drawable/ic_launcher_background.xml",
        """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="#F8F3E8"
        android:centerColor="#F3EAD6"
        android:endColor="#E8F1E4" />
</shape>
""",
    )


def main() -> None:
    args = parse_args()
    generate_assets(args.foreground.resolve(), args.res_dir.resolve())
    print(f"Generated launcher icons in {args.res_dir.resolve()}")


if __name__ == "__main__":
    main()
