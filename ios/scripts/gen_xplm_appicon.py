#!/usr/bin/env python3
"""Generate ios/Runner/Assets.xcassets/AppIcon-Xplm.appiconset from Android X-Plm launcher."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "android/app/src/xplm/res/mipmap-xxxhdpi/ic_launcher.png"
OUT = ROOT / "ios/Runner/Assets.xcassets/AppIcon-Xplm.appiconset"

SIZES = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

CONTENTS = {
    "images": [
        {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@2x.png", "scale": "2x"},
        {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@3x.png", "scale": "3x"},
        {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@1x.png", "scale": "1x"},
        {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@2x.png", "scale": "2x"},
        {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@3x.png", "scale": "3x"},
        {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@2x.png", "scale": "2x"},
        {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@3x.png", "scale": "3x"},
        {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@2x.png", "scale": "2x"},
        {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@3x.png", "scale": "3x"},
        {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@1x.png", "scale": "1x"},
        {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@2x.png", "scale": "2x"},
        {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@1x.png", "scale": "1x"},
        {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@2x.png", "scale": "2x"},
        {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@1x.png", "scale": "1x"},
        {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@2x.png", "scale": "2x"},
        {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@1x.png", "scale": "1x"},
        {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@2x.png", "scale": "2x"},
        {"size": "83.5x83.5", "idiom": "ipad", "filename": "Icon-App-83.5x83.5@2x.png", "scale": "2x"},
        {
            "size": "1024x1024",
            "idiom": "ios-marketing",
            "filename": "Icon-App-1024x1024@1x.png",
            "scale": "1x",
        },
    ],
    "info": {"version": 1, "author": "xcode"},
}


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"missing source icon: {SRC}")
    OUT.mkdir(parents=True, exist_ok=True)
    base = Image.open(SRC).convert("RGBA")
    w, h = base.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (1, 13, 30, 255))
    canvas.paste(base, ((side - w) // 2, (side - h) // 2), base)
    for name, px in SIZES:
        img = canvas.resize((px, px), Image.Resampling.LANCZOS)
        path = OUT / name
        if px == 1024:
            bg = Image.new("RGB", (px, px), (1, 13, 30))
            bg.paste(img, mask=img.split()[-1])
            bg.save(path, "PNG")
        else:
            img.save(path, "PNG")
    (OUT / "Contents.json").write_text(
        json.dumps(CONTENTS, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {len(SIZES)} icons -> {OUT}")


if __name__ == "__main__":
    main()
