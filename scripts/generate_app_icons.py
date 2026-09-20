#!/usr/bin/env python3
"""Generate ATHLTH app icons using only the Python standard library.

The generated PNG is fully opaque (no alpha channel), 1024x1024, and shared
between the iOS and watchOS AppIcon asset catalogs.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
IOS_ICON = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
WATCH_ICON = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = clamp(t)
    return tuple(round(a[i] * (1.0 - t) + b[i] * t) for i in range(3))


def blend(base: tuple[int, int, int], over: tuple[int, int, int], alpha: float) -> tuple[int, int, int]:
    return mix(base, over, clamp(alpha))


def segment_distance(
    px: float,
    py: float,
    ax: float,
    ay: float,
    bx: float,
    by: float,
) -> float:
    abx = bx - ax
    aby = by - ay
    length_sq = abx * abx + aby * aby
    if length_sq == 0:
        return math.hypot(px - ax, py - ay)

    t = clamp(((px - ax) * abx + (py - ay) * aby) / length_sq)
    cx = ax + t * abx
    cy = ay + t * aby
    return math.hypot(px - cx, py - cy)


def smooth_edge(distance: float, radius: float, feather: float = 1.5) -> float:
    return clamp((radius + feather - distance) / (2.0 * feather))


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def png_bytes() -> bytes:
    top = (250, 249, 242)
    bottom = (231, 244, 233)
    deep_green = (22, 112, 62)
    highlight_green = (47, 164, 92)
    shadow_green = (5, 73, 39)

    left_a = (250.0, 700.0)
    apex = (512.0, 270.0)
    right_b = (774.0, 700.0)

    mark_radius = 50.0
    highlight_radius = 12.5

    rows: list[bytes] = []

    for y in range(SIZE):
        vertical_t = y / (SIZE - 1)
        base_row = mix(top, bottom, vertical_t)
        row = bytearray()

        for x in range(SIZE):
            color = base_row

            # Soft white glow from the top-right.
            white_d = math.hypot((x - 795) / 315.0, (y - 145) / 290.0)
            if white_d < 1.0:
                color = blend(color, (255, 255, 255), (1.0 - white_d) * 0.34)

            # Subtle green atmosphere at the lower-left.
            green_d = math.hypot((x - 130) / 430.0, (y - 880) / 430.0)
            if green_d < 1.0:
                color = blend(color, (184, 232, 197), (1.0 - green_d) * 0.19)

            # Soft shadow behind the ATHLTH mark.
            shadow_y = y - 14.0
            shadow_distance = min(
                segment_distance(x, shadow_y, *left_a, *apex),
                segment_distance(x, shadow_y, *apex, *right_b),
            )
            if shadow_distance < mark_radius + 18.0:
                shadow_alpha = smooth_edge(shadow_distance, mark_radius + 13.0, 8.0) * 0.13
                color = blend(color, shadow_green, shadow_alpha)

            # Brand chevron.
            distance = min(
                segment_distance(x, y, *left_a, *apex),
                segment_distance(x, y, *apex, *right_b),
            )
            mark_alpha = smooth_edge(distance, mark_radius, 1.4)
            if mark_alpha > 0:
                color = blend(color, deep_green, mark_alpha)

            # Narrow brighter centre line gives the mark depth without changing
            # its silhouette.
            highlight_alpha = smooth_edge(distance, highlight_radius, 1.2)
            if highlight_alpha > 0:
                color = blend(color, highlight_green, highlight_alpha * 0.82)

            row.extend(color)

        # PNG filter byte: 0 (None)
        rows.append(b"\x00" + bytes(row))

    raw = b"".join(rows)

    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return (
        signature
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, level=9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    payload = png_bytes()

    for path in (IOS_ICON, WATCH_ICON):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        print(f"Generated {path} ({len(payload)} bytes)")


if __name__ == "__main__":
    main()
