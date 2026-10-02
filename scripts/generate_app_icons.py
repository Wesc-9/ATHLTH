#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import struct
import zlib
from pathlib import Path

SIZE = 1024
LEVELS = 16
SOURCE_PARTS = [
    Path("ATHLTH/Brand/AppIconSource/v134-logo-part00.b64"),
    Path("ATHLTH/Brand/AppIconSource/v134-logo-part01.b64"),
    Path("ATHLTH/Brand/AppIconSource/v134-logo-part02.b64"),
    Path("ATHLTH/Brand/AppIconSource/v134-logo-part03.b64"),
]
EXPECTED_SOURCE_SHA256 = "9242193c420763c2db2f36fe12aa4d762995786588d7050c38afcd6b39621c6e"

IOS_DIR = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset")
WATCH_DIR = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset")


def load_source_levels() -> bytes:
    encoded = "".join(
        path.read_text(encoding="utf-8").strip()
        for path in SOURCE_PARTS
    )
    if not encoded:
        raise SystemExit("ATHLTH app icon source is empty.")

    compressed = base64.b64decode(encoded, validate=True)
    raw = zlib.decompress(compressed)

    expected_bytes = SIZE * SIZE
    if len(raw) != expected_bytes:
        raise SystemExit(
            f"ATHLTH icon source has {len(raw)} bytes; expected {expected_bytes}."
        )

    if any(value >= LEVELS for value in raw):
        raise SystemExit("ATHLTH icon source contains an invalid grayscale level.")

    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SOURCE_SHA256:
        raise SystemExit(
            "ATHLTH icon source checksum mismatch: "
            f"expected {EXPECTED_SOURCE_SHA256}, got {digest}"
        )

    return raw


def source_rows(source: bytes) -> list[bytes]:
    rows: list[bytes] = []
    for y in range(SIZE):
        start = y * SIZE
        end = start + SIZE
        row = bytearray(SIZE * 3)

        for x, level in enumerate(source[start:end]):
            value = round(level * 255 / (LEVELS - 1))
            offset = x * 3
            row[offset] = value
            row[offset + 1] = value
            row[offset + 2] = value

        rows.append(bytes(row))

    return rows


def png_payload(rows: list[bytes]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    scanlines = b"".join(b"\x00" + row for row in rows)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(
            b"IHDR",
            struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0),
        )
        + chunk(b"IDAT", zlib.compress(scanlines, level=9))
        + chunk(b"IEND", b"")
    )


def validate_png(payload: bytes) -> None:
    if payload[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("Generated ATHLTH icon is not a PNG.")

    ihdr_length = struct.unpack(">I", payload[8:12])[0]
    if ihdr_length != 13 or payload[12:16] != b"IHDR":
        raise SystemExit("Generated ATHLTH icon has an invalid IHDR chunk.")

    width, height, bit_depth, color_type, _, _, _ = struct.unpack(
        ">IIBBBBB", payload[16:29]
    )
    if (width, height) != (SIZE, SIZE):
        raise SystemExit(
            f"Generated ATHLTH icon is {width}x{height}; expected {SIZE}x{SIZE}."
        )
    if bit_depth != 8 or color_type != 2:
        raise SystemExit(
            "Generated ATHLTH icon must be 8-bit RGB with no alpha channel."
        )

    # Force a full zlib decode of all IDAT data before the file is accepted.
    offset = 8
    idat = bytearray()
    saw_iend = False
    while offset + 12 <= len(payload):
        length = struct.unpack(">I", payload[offset:offset + 4])[0]
        kind = payload[offset + 4:offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        chunk_end = data_end + 4
        if chunk_end > len(payload):
            raise SystemExit(f"Generated ATHLTH icon has truncated {kind!r} chunk.")
        if kind == b"IDAT":
            idat.extend(payload[data_start:data_end])
        if kind == b"IEND":
            saw_iend = True
            break
        offset = chunk_end

    if not saw_iend:
        raise SystemExit("Generated ATHLTH icon is missing IEND.")
    zlib.decompress(bytes(idat))


def write_icon(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def main() -> None:
    source = load_source_levels()
    payload = png_payload(source_rows(source))
    validate_png(payload)

    # One approved user-provided ATHLTH logo is the single source of truth for
    # iPhone, dark, tinted and Apple Watch app icons.
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
        "Generated ATHLTH app icons from the user-provided logo "
        f"({len(payload)} bytes, SHA256 {hashlib.sha256(payload).hexdigest()})."
    )


if __name__ == "__main__":
    main()
