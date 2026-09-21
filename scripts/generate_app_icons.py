#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import struct
from pathlib import Path

IOS_DIR = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset")
WATCH_DIR = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset")
SOURCE_DIR = Path("ATHLTH/Brand/AppIconSource")
EXPECTED_SHA256 = "fa63dc29de29939d50d45da6ea740b2c9dce9649ec0d9bb8c3d8954b606839c4"


def load_master_icon() -> bytes:
    parts = sorted(SOURCE_DIR.glob("part*.txt"))
    if not parts:
        raise SystemExit(f"No app-icon source parts found in {SOURCE_DIR}")

    encoded = "".join(part.read_text(encoding="utf-8").strip() for part in parts)
    payload = base64.b64decode(encoded, validate=True)

    if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit("ATHLTH master app icon is not a PNG.")

    width, height = struct.unpack(">II", payload[16:24])
    if (width, height) != (1024, 1024):
        raise SystemExit(f"ATHLTH master app icon must be 1024x1024, got {width}x{height}.")

    digest = hashlib.sha256(payload).hexdigest()
    if digest != EXPECTED_SHA256:
        raise SystemExit(
            "ATHLTH master app icon checksum mismatch: "
            f"expected {EXPECTED_SHA256}, got {digest}"
        )

    return payload


def write_icon(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def main() -> None:
    payload = load_master_icon()

    # Keep the approved premium ATHLTH mark consistent across iPhone/iPad,
    # dark/tinted Home Screen appearances and Apple Watch.
    write_icon(IOS_DIR / "AppIcon.png", payload)
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
