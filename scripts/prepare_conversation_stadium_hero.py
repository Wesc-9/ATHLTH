#!/usr/bin/env python3
"""Bundle a high-resolution, standalone stadium photograph for ATHLTH DM.

A photo is bundled in Assets.xcassets (never the entire conversation mockup).
The image source below is CC0; no on-device download or account data needed.

Source: https://www.pexels.com/photo/stands-by-running-track-at-stadium-19753619/
License: Free under the Pexels License (https://www.pexels.com/license/).
Original high-res media is downloaded as a standalone image (no personal data).
"""

from __future__ import annotations

from io import BytesIO
from pathlib import Path
from urllib.request import Request, urlopen

from PIL import Image, ImageEnhance, ImageOps, ImageStat, UnidentifiedImageError

SOURCE = (
    "https://images.pexels.com/photos/19753619/"
    "pexels-photo-19753619.jpeg?auto=compress&cs=tinysrgb&w=3000"
)
SOURCES = [
    SOURCE,
    "https://images.pexels.com/photos/28943346/"
    "pexels-photo-28943346.jpeg?auto=compress&cs=tinysrgb&w=3000",
]
DEST = (
    Path(__file__).resolve().parent.parent /
    "ATHLTH/Assets.xcassets/ConversationStadiumHero.imageset/stadium.jpg"
)
TARGET_WIDTH = 2880
TARGET_HEIGHT = 1620


def main() -> None:
    img = None
    for url in SOURCES:
        try:
            request = Request(url, headers={
                "User-Agent": "ATHLTH-iOS-Asset-Bundler/1.0",
                "Accept": "image/jpeg,image/*",
            })
            with urlopen(request, timeout=40) as response:
                data = response.read(18 * 1024 * 1024 + 1)
            if len(data) > 18 * 1024 * 1024:
                raise ValueError("Stadium source is unexpectedly large")
            if not data.startswith(b"\xff\xd8\xff"):
                raise ValueError("Stadium source did not return a JPEG")
            with Image.open(BytesIO(data)) as source:
                candidate = ImageOps.exif_transpose(source).convert("RGB")
            print(f"Photo candidate: {candidate.size} from {url}", flush=True)
            if candidate.width >= 2000 and candidate.height >= 1000:
                img = candidate
                break
        except (OSError, ValueError, UnidentifiedImageError) as exc:
            print(f"Source unavailable: {url}: {exc}", flush=True)
    if img is None:
        raise ValueError("None of the photo URLs provides full-resolution media")

    # A wide scenic stadium header matches ATHLTH's original layout.
    # Retain the real pixels; do not artificially upscale to claim more detail.
    target_ratio = TARGET_WIDTH / TARGET_HEIGHT
    aspect = img.width / img.height
    if aspect > target_ratio:
        crop_width = round(img.height * target_ratio)
        left = max(0, (img.width - crop_width) // 2)
        img = img.crop((left, 0, left + crop_width, img.height))
    else:
        crop_height = round(img.width / target_ratio)
        # Favour sky/horizon and upper stadium seating over foreground track.
        top = max(0, int((img.height - crop_height) * 0.29))
        img = img.crop((0, top, img.width, top + crop_height))

    # Never enlarge an image: Retina quality must come from real source pixels.
    if img.width > TARGET_WIDTH:
        img = img.resize((TARGET_WIDTH, TARGET_HEIGHT), Image.Resampling.LANCZOS)

    if img.width < 1800:
        raise ValueError("Processed stadium artwork too small for a Retina header")

    # Conservative processing to preserve a naturally bright image.
    img = ImageEnhance.Contrast(img).enhance(1.04)
    DEST.parent.mkdir(parents=True, exist_ok=True)
    img.save(
        DEST, format="JPEG", quality=90, optimize=True,
        progressive=True, subsampling=0,
    )
    with Image.open(DEST) as check:
        check.verify()
    print(f"Bundled stadium hero: {img.width}x{img.height}, {DEST.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
