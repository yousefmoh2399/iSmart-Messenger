#!/usr/bin/env python3
"""
Builds side-by-side contact sheets comparing Android (OpenCV) and iOS (CoreImage)
outputs across all 6 native scanner filters:
  original | lighten | enhance | gray | eco | no_handwriting

Usage:
  python3 scripts/build_parity_contact_sheet.py \
      --android-dir /path/to/android_outputs \
      --ios-dir /path/to/ios_outputs \
      --out-dir /path/to/contact_sheets
"""

import argparse
import os
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Pillow is required: pip install Pillow")

FILTERS = [
    "original",
    "lighten",
    "enhance",
    "gray",
    "eco",
    "no_handwriting",
]


def load_thumb(path: Path, cell_w: int, cell_h: int) -> Image.Image:
    canvas = Image.new("RGB", (cell_w, cell_h), (28, 28, 30))
    if not path.exists():
        draw = ImageDraw.Draw(canvas)
        draw.text((16, cell_h // 2), f"MISSING: {path.name}", fill=(255, 90, 90))
        return canvas
    img = Image.open(path).convert("RGB")
    img.thumbnail((cell_w - 16, cell_h - 40), Image.Resampling.LANCZOS)
    x = (cell_w - img.width) // 2
    y = 32 + (cell_h - 40 - img.height) // 2
    canvas.paste(img, (x, y))
    return canvas


def build_sheet(sample_name: str, android_dir: Path, ios_dir: Path, out_dir: Path) -> Path:
    cell_w, cell_h = 420, 560
    cols = len(FILTERS)
    rows = 2  # Row 0: Android, Row 1: iOS
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (18, 18, 20))
    draw = ImageDraw.Draw(sheet)

    for col_idx, flt in enumerate(FILTERS):
        android_file = android_dir / f"{sample_name}_{flt}.jpg"
        ios_file = ios_dir / f"{sample_name}_{flt}.jpg"

        a_thumb = load_thumb(android_file, cell_w, cell_h)
        i_thumb = load_thumb(ios_file, cell_w, cell_h)

        sheet.paste(a_thumb, (col_idx * cell_w, 0))
        sheet.paste(i_thumb, (col_idx * cell_w, cell_h))

        draw.text((col_idx * cell_w + 12, 8), f"Android: {flt}", fill=(0, 230, 118))
        draw.text((col_idx * cell_w + 12, cell_h + 8), f"iOS: {flt}", fill=(100, 181, 246))

    out_path = out_dir / f"{sample_name}_contact_sheet.jpg"
    sheet.save(out_path, quality=92)
    return out_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android-dir", required=True, type=Path)
    parser.add_argument("--ios-dir", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    samples = set()
    for p in list(args.android_dir.glob("*_original.jpg")) + list(args.ios_dir.glob("*_original.jpg")):
        samples.add(p.name[: -len("_original.jpg")])

    for sample in sorted(samples):
        out = build_sheet(sample, args.android_dir, args.ios_dir, args.out_dir)
        print(f"[Parity] Wrote contact sheet: {out}")


if __name__ == "__main__":
    main()
