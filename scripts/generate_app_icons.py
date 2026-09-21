#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path

SIZE = 1024

IOS_DIR = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset")
WATCH_DIR = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset")


def write_png(path: Path, background: tuple[int, int, int], foreground: tuple[int, int, int]) -> None:
    width = height = SIZE
    cx = width / 2
    top = height * 0.235
    bottom = height * 0.735
    outer_half = width * 0.255
    inner_half_bottom = width * 0.135
    inner_half_top = width * 0.032

    rows = []
    for y in range(height):
        row = bytearray()
        if y < top or y > bottom:
            row.extend(background * width)
        else:
            progress = (y - top) / (bottom - top)
            outer = outer_half * progress
            inner = inner_half_top + (inner_half_bottom - inner_half_top) * progress

            for x in range(width):
                dx = abs(x - cx)
                is_mark = inner <= dx <= outer
                row.extend(foreground if is_mark else background)

        rows.append(b"\x00" + bytes(row))

    raw = b"".join(rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    payload = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, level=9))
        + chunk(b"IEND", b"")
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def main() -> None:
    # iPhone/iPad: explicit default, dark and grayscale tinted variants.
    # The mark is intentionally bright with enough contrast that it can't
    # disappear into dark/tinted Home Screen icon appearances.
    write_png(IOS_DIR / "AppIcon.png", (24, 22, 20), (250, 250, 248))
    write_png(IOS_DIR / "AppIcon-dark.png", (46, 43, 39), (255, 255, 255))
    write_png(IOS_DIR / "AppIcon-tinted.png", (96, 96, 96), (248, 248, 248))

    ios_contents = {
        "images": [
            {
                "filename": "AppIcon.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "filename": "AppIcon-dark.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "tinted"}],
                "filename": "AppIcon-tinted.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (IOS_DIR / "Contents.json").write_text(
        json.dumps(ios_contents, indent=2) + "\n",
        encoding="utf-8",
    )

    # watchOS guidance recommends avoiding a pure-black background because
    # the circular icon can visually disappear into the Watch UI.
    write_png(WATCH_DIR / "AppIcon.png", (47, 56, 50), (252, 252, 250))

    watch_contents = {
        "images": [
            {
                "filename": "AppIcon.png",
                "idiom": "universal",
                "platform": "watchos",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (WATCH_DIR / "Contents.json").write_text(
        json.dumps(watch_contents, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
