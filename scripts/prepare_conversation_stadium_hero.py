#!/usr/bin/env python3
"""Bundle a high-resolution, standalone stadium photograph for ATHLTH DM.

A photo is bundled in Assets.xcassets (never the entire conversation mockup).
The image source below is CC0; no on-device download or account data needed.

Preferred source: https://commons.wikimedia.org/wiki/File:Sunset_at_Lake_Fairway_Athletics_Track.JPG
License: Creative Commons Attribution 3.0 Unported (CC BY 3.0), Editor5807.
Credit and crop disclosure: docs/conversation-stadium-artwork.md
Alternate source: https://pxhere.com/en/photo/1038422 (CC0 Public Domain).
"""

from __future__ import annotations

from io import BytesIO
from pathlib import Path
from urllib.request import Request, urlopen

from PIL import Image, ImageEnhance, ImageOps, ImageStat, UnidentifiedImageError

SOURCE = (
    "https://c.pxhere.com/photos/33/7b/"
    "athletic_field_stadium_playground_sunset-1038422.jpg"
)
SOURCES = [
    # Full 4592 x 3056 photograph, credited under CC BY 3.0.
    "https://upload.wikimedia.org/wikipedia/commons/c/c8/"
    "Sunset_at_Lake_Fairway_Athletics_Track.JPG",
    # Full-size PxHere original (CC0), if its upstream permits access.
    SOURCE,
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
