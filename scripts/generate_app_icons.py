#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path

SIZE = 1024
IOS_DIR = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset")
WATCH_DIR = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset")
SOURCE = IOS_DIR / "AppIcon.png"


def validate_png(path: Path) -> bytes:
    payload = path.read_bytes()

    if payload[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: invalid PNG signature")

    offset = 8
    saw_idat = False
    saw_iend = False

    while offset + 12 <= len(payload):
        length = struct.unpack(">I", payload[offset:offset + 4])[0]
        kind = payload[offset + 4:offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        crc_end = data_end + 4

        if crc_end > len(payload):
            raise SystemExit(f"{path}: truncated PNG chunk {kind!r}")

        data = payload[data_start:data_end]
        expected_crc = struct.unpack(">I", payload[data_end:crc_end])[0]

        if (zlib.crc32(kind + data) & 0xFFFFFFFF) != expected_crc:
            raise SystemExit(f"{path}: CRC mismatch in {kind!r}")

        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, _ = struct.unpack(
                ">IIBBBBB",
                data,
            )
            if (width, height, bit_depth, color_type) != (SIZE, SIZE, 8, 2):
                raise SystemExit(
                    f"{path}: expected {SIZE}x{SIZE} 8-bit RGB, got "
                    f"{width}x{height}, bit_depth={bit_depth}, "
                    f"color_type={color_type}"
                )
        elif kind == b"IDAT":
            saw_idat = True
        elif kind == b"IEND":
            saw_iend = True
            break

        offset = crc_end

    if not (saw_idat and saw_iend):
        raise SystemExit(f"{path}: incomplete PNG structure")

    return payload


def write_icon(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def main() -> None:
    # AppIcon.png is the approved source of truth. Keeping the source PNG
    # directly in the asset catalog avoids a second embedded raster source
    # drifting away from the logo selected for ATHLTH.
    payload = validate_png(SOURCE)

    write_icon(IOS_DIR / "AppIcon-dark.png", payload)
    write_icon(IOS_DIR / "AppIcon-tinted.png", payload)
    write_icon(WATCH_DIR / "AppIcon.png", payload)

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
