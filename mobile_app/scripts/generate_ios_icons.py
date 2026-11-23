#!/usr/bin/env python3
"""Generate Apple App Store & iOS icon assets and launch splash images."""

from __future__ import annotations

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_LOGO = REPO_ROOT / "desktop_app" / "assets" / "images" / "logo.png"
APPICON_DIR = (
    REPO_ROOT
    / "mobile_app"
    / "ios"
    / "Runner"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
)
LAUNCH_IMAGE_DIR = (
    REPO_ROOT
    / "mobile_app"
    / "ios"
    / "Runner"
    / "Assets.xcassets"
    / "LaunchImage.imageset"
)
SPLASH_RESOURCES_DIR = REPO_ROOT / "mobile_app" / "ios" / "Runner" / "Resources"
MARKETING_ICONS_DIR = REPO_ROOT / "app_store_assets" / "icons"

APP_ICON_FILES: dict[str, int] = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def build_squircle_mask(size: int, corner_ratio: float = 0.2237) -> Image.Image:
    """Create a smooth anti-aliased rounded-rect mask at 4x resolution."""
    scale = 4
    hi = size * scale
    mask_hi = Image.new("L", (hi, hi), 0)
    draw = ImageDraw.Draw(mask_hi)
    radius = int(round(hi * corner_ratio))
    draw.rounded_rectangle([(0, 0), (hi - 1, hi - 1)], radius=radius, fill=255)
    return mask_hi.resize((size, size), Image.Resampling.LANCZOS)


def prepare_master_app_icon() -> Image.Image:
    """Crop inside the pre-rounded squircle rim and bleed dark navy cleanly to 1024x1024 RGB."""
    raw = Image.open(SOURCE_LOGO).convert("RGBA")
    # Crop box (52, 48, 784, 780) removes outer straight rim cleanly while preserving centering
    cropped = raw.crop((52, 48, 784, 780)).resize(
        (1024, 1024), Image.Resampling.LANCZOS
    )

    # Create a soft, rich dark-navy full-bleed base directly from a heavily blurred inner crop
    # so the top-to-bottom lighting gradient matches seamlessly without any outer rim line.
    bg_source = cropped.crop((96, 96, 928, 928)).resize(
        (1024, 1024), Image.Resampling.BICUBIC
    )
    bg_bleed = bg_source.filter(ImageFilter.GaussianBlur(radius=48)).convert("RGBA")

    # Mask the foreground slightly tighter than the faint diagonal corner line (corner_ratio=0.25)
    # and feather the mask edge so the interior blends seamlessly into the full-bleed square.
    inner_mask = build_squircle_mask(1024, corner_ratio=0.255).filter(
        ImageFilter.GaussianBlur(radius=6)
    )
    composited = Image.composite(cropped, bg_bleed, inner_mask).convert("RGB")

    master = ImageEnhance.Sharpness(composited).enhance(1.08)
    assert master.mode == "RGB"
    return master


def prepare_splash_logo(size: int = 512) -> Image.Image:
    """Prepare a clean RGBA rounded-squircle logo for LaunchScreen and EasySplash."""
    master_rgb = prepare_master_app_icon()
    resized = master_rgb.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    mask = build_squircle_mask(size)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(resized, (0, 0), mask)
    return out


def main() -> None:
    if not SOURCE_LOGO.exists():
        raise FileNotFoundError(f"Source logo missing: {SOURCE_LOGO}")

    APPICON_DIR.mkdir(parents=True, exist_ok=True)
    MARKETING_ICONS_DIR.mkdir(parents=True, exist_ok=True)
    LAUNCH_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    SPLASH_RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

    master_rgb = prepare_master_app_icon()

    # Verify Contents.json filenames match our dictionary
    contents_path = APPICON_DIR / "Contents.json"
    if contents_path.exists():
        contents = json.loads(contents_path.read_text(encoding="utf-8"))
        json_files = {img["filename"] for img in contents.get("images", [])}
        missing = json_files - set(APP_ICON_FILES.keys())
        if missing:
            raise ValueError(f"Missing sizes in script for Contents.json: {missing}")

    # 1. Generate all AppIcon.appiconset icons (opaque RGB, no alpha)
    for filename, px in APP_ICON_FILES.items():
        resized = (
            master_rgb
            if px == 1024
            else master_rgb.resize((px, px), Image.Resampling.LANCZOS)
        )
        resized = resized.convert("RGB")
        resized.save(APPICON_DIR / filename, format="PNG", optimize=True)

    # 2. Export App Store / Marketing icons
    master_rgb.save(
        MARKETING_ICONS_DIR / "AppIcon-1024x1024-AppStore.png",
        format="PNG",
        optimize=True,
    )
    master_512 = master_rgb.resize((512, 512), Image.Resampling.LANCZOS).convert("RGB")
    master_512.save(
        MARKETING_ICONS_DIR / "AppIcon-512x512.png", format="PNG", optimize=True
    )

    # 3. Update LaunchImage.imageset (120, 240, 360) and EasySplash resources (512)
    for name, px in [
        ("LaunchImage.png", 120),
        ("LaunchImage@2x.png", 240),
        ("LaunchImage@3x.png", 360),
    ]:
        splash = prepare_splash_logo(px)
        splash.save(LAUNCH_IMAGE_DIR / name, format="PNG", optimize=True)

    splash_512 = prepare_splash_logo(512)
    splash_512.save(
        SPLASH_RESOURCES_DIR / "simple_splash_view_image_light.png",
        format="PNG",
        optimize=True,
    )
    splash_512.save(
        SPLASH_RESOURCES_DIR / "simple_splash_view_image_dark.png",
        format="PNG",
        optimize=True,
    )

    print(
        f"Generated {len(APP_ICON_FILES)} AppIcon PNGs, 2 marketing icons, "
        "3 LaunchImages, and 2 Splash images."
    )


if __name__ == "__main__":
    main()
