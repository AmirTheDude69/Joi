#!/usr/bin/env python3
"""Build a macOS .icns from Joi's canonical first sprite frame."""

from __future__ import annotations

import argparse
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def build_icon(sprite_path: Path, output_path: Path, work_dir: Path) -> None:
    sheet = Image.open(sprite_path).convert("RGBA")
    frame = sheet.crop((0, 0, 192, 208))

    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    background = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = background.load()
    for y in range(size):
        for x in range(size):
            distance = math.dist((x, y), (size / 2, size / 2)) / (size * 0.68)
            alpha = int(255 * max(0.0, min(1.0, 1.12 - distance)))
            pixels[x, y] = (255, 226, 203, alpha)
    canvas.alpha_composite(background)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((42, 42, 982, 982), radius=230, outline=(255, 255, 255, 190), width=14)

    avatar = frame.resize((730, 790), Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", avatar.size, (0, 0, 0, 0))
    shadow.paste((50, 24, 12, 115), (0, 0), avatar.getchannel("A"))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    origin = ((size - avatar.width) // 2, 118)
    canvas.alpha_composite(shadow, (origin[0], origin[1] + 30))
    canvas.alpha_composite(avatar, origin)

    work_dir.mkdir(parents=True, exist_ok=True)
    source = work_dir / "Joi-1024.png"
    canvas.save(source)

    iconset = work_dir / "Joi.iconset"
    iconset.mkdir(exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, pixel_size in sizes.items():
        canvas.resize((pixel_size, pixel_size), Image.Resampling.LANCZOS).save(iconset / name)

    subprocess.run(
        ["/usr/bin/iconutil", "--convert", "icns", "--output", str(output_path), str(iconset)],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sprite", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("work_dir", type=Path)
    args = parser.parse_args()
    build_icon(args.sprite, args.output, args.work_dir)


if __name__ == "__main__":
    main()
