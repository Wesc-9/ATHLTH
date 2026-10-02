#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import struct
import zlib
from pathlib import Path

SIZE = 1024
SOURCE = Path("ATHLTH/Brand/AppIconSource/ATHLTH-AppIcon-Source-1024.png")
EXPECTED_SOURCE_SHA256 = "0e76317bfdd07c525378453bc94f5ba7e05f3fea5e5765154691dd2c96f9748d"

IOS_DIR = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset")
WATCH_DIR = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset")


def validate_png(payload: bytes) -> None:
    if payload[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("ATHLTH app icon source is not a PNG.")

    offset = 8
    idat = bytearray()
    saw_ihdr = False
    saw_iend = False

    while offset + 12 <= len(payload):
        length = struct.unpack(">I", payload[offset:offset + 4])[0]
        kind = payload[offset + 4:offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        crc_end = data_end + 4

        if crc_end > len(payload):
            raise SystemExit(f"ATHLTH app icon has truncated {kind!r} chunk.")

        data = payload[data_start:data_end]
        expected_crc = struct.unpack(">I", payload[data_end:crc_end])[0]
        actual_crc = zlib.crc32(kind + data) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise SystemExit(f"ATHLTH app icon has invalid CRC in {kind!r}.")

        if kind == b"IHDR":
            if length != 13:
                raise SystemExit("ATHLTH app icon has invalid IHDR.")
            width, height, bit_depth, color_type, _, _, _ = struct.unpack(
                ">IIBBBBB", data
            )
            if (width, height) != (SIZE, SIZE):
                raise SystemExit(
                    f"ATHLTH app icon is {width}x{height}; expected {SIZE}x{SIZE}."
                )
            if bit_depth != 8 or color_type != 2:
                raise SystemExit(
                    "ATHLTH app icon must be 8-bit RGB with no alpha channel."
                )
            saw_ihdr = True
        elif kind == b"IDAT":
            idat.extend(data)
        elif kind == b"IEND":
            saw_iend = True
            offset = crc_end
            break

        offset = crc_end

    if not saw_ihdr or not saw_iend:
        raise SystemExit("ATHLTH app icon is missing required PNG chunks.")
    if offset != len(payload):
        raise SystemExit("ATHLTH app icon contains unexpected trailing bytes.")

    # A complete decode catches damaged/truncated IDAT payloads before Xcode.
    zlib.decompress(bytes(idat))


def write_icon(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def main() -> None:
    payload = SOURCE.read_bytes()

    digest = hashlib.sha256(payload).hexdigest()
    if digest != EXPECTED_SOURCE_SHA256:
        raise SystemExit(
            "ATHLTH app icon source checksum mismatch: "
            f"expected {EXPECTED_SOURCE_SHA256}, got {digest}"
        )

    validate_png(payload)

    # The exact user-provided ATHLTH logo is the single source of truth.
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

    print(
        "Validated and installed canonical ATHLTH app icon "
        f"({len(payload)} bytes, SHA256 {digest})."
    )


if __name__ == "__main__":
    main()
