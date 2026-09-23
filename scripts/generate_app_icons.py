#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import struct
import zlib
from pathlib import Path

SIZE = 1024
SOURCE_SIZE = 128
SOURCE_PATH = Path("ATHLTH/Brand/AppIconSource/raw256.b64")
EXPECTED_SOURCE_SHA256 = "cd33202075ce3606d9197bb6fd83dfc2856084423436045d2f240884af39a846"

IOS_DIR = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset")
WATCH_DIR = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset")


def load_source_rgb() -> bytes:
    encoded = SOURCE_PATH.read_text(encoding="utf-8").strip()
    compressed = base64.b64decode(encoded, validate=True)
    raw = zlib.decompress(compressed)

    expected_bytes = SOURCE_SIZE * SOURCE_SIZE * 3
    if len(raw) != expected_bytes:
        raise SystemExit(
            f"ATHLTH icon source has {len(raw)} bytes; expected {expected_bytes}."
        )

    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SOURCE_SHA256:
        raise SystemExit(
            "ATHLTH icon source checksum mismatch: "
            f"expected {EXPECTED_SOURCE_SHA256}, got {digest}"
        )

    return raw


def resize_bilinear(source: bytes) -> list[bytes]:
    src = memoryview(source)

    x_lookup: list[tuple[int, int, int]] = []
    for x in range(SIZE):
        source_x = (x + 0.5) * SOURCE_SIZE / SIZE - 0.5
        x0 = max(0, min(SOURCE_SIZE - 1, int(source_x)))
        x1 = min(SOURCE_SIZE - 1, x0 + 1)
        fraction = max(0.0, min(1.0, source_x - x0))
        x_lookup.append((x0, x1, int(round(fraction * 256))))

    rows: list[bytes] = []
    for y in range(SIZE):
        source_y = (y + 0.5) * SOURCE_SIZE / SIZE - 0.5
        y0 = max(0, min(SOURCE_SIZE - 1, int(source_y)))
        y1 = min(SOURCE_SIZE - 1, y0 + 1)
        fy = int(round(max(0.0, min(1.0, source_y - y0)) * 256))

        base0 = y0 * SOURCE_SIZE * 3
        base1 = y1 * SOURCE_SIZE * 3
        row = bytearray(SIZE * 3)

        for x, (x0, x1, fx) in enumerate(x_lookup):
            i00 = base0 + x0 * 3
            i01 = base0 + x1 * 3
            i10 = base1 + x0 * 3
            i11 = base1 + x1 * 3
            output = x * 3

            for channel in range(3):
                upper = (
                    src[i00 + channel] * (256 - fx)
                    + src[i01 + channel] * fx
                    + 128
                ) >> 8
                lower = (
                    src[i10 + channel] * (256 - fx)
                    + src[i11 + channel] * fx
                    + 128
                ) >> 8
                row[output + channel] = (
                    upper * (256 - fy) + lower * fy + 128
                ) >> 8

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


def write_icon(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def main() -> None:
    source = load_source_rgb()
    rows = resize_bilinear(source)
    payload = png_payload(rows)

    # The approved approved ATHLTH pulse-A mark is intentionally identical across
    # normal, dark, tinted, and Apple Watch appearances so ATHLTH keeps one
    # recognizable identity everywhere.
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
