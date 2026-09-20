#!/usr/bin/env python3
"""Generate the locked ATHLTH Option 4 app icon.

Direction:
- warm off-white / cream background
- near-black ATHLTH wordmark only
- no decorative colour, no transparency, no pre-rounded corners
- identical visual identity for iOS and watchOS

The PNG is generated deterministically using only the Python standard library.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
IOS_ICON = Path("ATHLTH/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
WATCH_ICON = Path("ATHLTHWatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

TOP = (253, 251, 246)
BOTTOM = (245, 241, 233)
INK = (19, 20, 19)


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def mix(
    first: tuple[int, int, int],
    second: tuple[int, int, int],
    amount: float,
) -> tuple[int, int, int]:
    amount = clamp(amount)
    return tuple(
        round(first[index] * (1.0 - amount) + second[index] * amount)
        for index in range(3)
    )


def blend(
    base: tuple[int, int, int],
    overlay: tuple[int, int, int],
    alpha: float,
) -> tuple[int, int, int]:
    return mix(base, overlay, clamp(alpha))


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
    length_squared = abx * abx + aby * aby

    if length_squared == 0:
        return math.hypot(px - ax, py - ay)

    projection = clamp(
        ((px - ax) * abx + (py - ay) * aby) / length_squared
    )
    closest_x = ax + projection * abx
    closest_y = ay + projection * aby
    return math.hypot(px - closest_x, py - closest_y)


def smooth_edge(
    distance: float,
    radius: float,
    feather: float = 1.25,
) -> float:
    return clamp((radius + feather - distance) / (2.0 * feather))


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def background_rows() -> list[bytearray]:
    rows: list[bytearray] = []

    for y in range(SIZE):
        vertical_amount = y / (SIZE - 1)
        base_row = mix(TOP, BOTTOM, vertical_amount)
        row = bytearray()

        for x in range(SIZE):
            color = base_row

            # Very soft highlight keeps the cream from looking flat while
            # remaining effectively monochrome.
            highlight_distance = math.hypot(
                (x - 760) / 390.0,
                (y - 180) / 360.0,
            )
            if highlight_distance < 1.0:
                color = blend(
                    color,
                    (255, 255, 255),
                    (1.0 - highlight_distance) * 0.22,
                )

            # A faint warm shadow at the opposite corner adds depth without
            # introducing another brand colour.
            warmth_distance = math.hypot(
                (x - 160) / 500.0,
                (y - 880) / 500.0,
            )
            if warmth_distance < 1.0:
                color = blend(
                    color,
                    (235, 229, 217),
                    (1.0 - warmth_distance) * 0.12,
                )

            row.extend(color)

        rows.append(row)

    return rows


def set_pixel(
    rows: list[bytearray],
    x: int,
    y: int,
    color: tuple[int, int, int],
    alpha: float = 1.0,
) -> None:
    if not (0 <= x < SIZE and 0 <= y < SIZE):
        return

    offset = x * 3
    base = tuple(rows[y][offset : offset + 3])
    result = blend(base, color, alpha)
    rows[y][offset : offset + 3] = bytes(result)


def draw_rectangle(
    rows: list[bytearray],
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    color: tuple[int, int, int],
) -> None:
    for y in range(max(0, int(y0)), min(SIZE, int(y1))):
        for x in range(max(0, int(x0)), min(SIZE, int(x1))):
            set_pixel(rows, x, y, color)


def draw_segment(
    rows: list[bytearray],
    ax: float,
    ay: float,
    bx: float,
    by: float,
    radius: float,
    color: tuple[int, int, int],
) -> None:
    min_x = max(0, int(min(ax, bx) - radius - 2))
    max_x = min(SIZE, int(max(ax, bx) + radius + 3))
    min_y = max(0, int(min(ay, by) - radius - 2))
    max_y = min(SIZE, int(max(ay, by) + radius + 3))

    for y in range(min_y, max_y):
        for x in range(min_x, max_x):
            distance = segment_distance(
                x + 0.5,
                y + 0.5,
                ax,
                ay,
                bx,
                by,
            )
            alpha = smooth_edge(distance, radius)
            if alpha > 0:
                set_pixel(rows, x, y, color, alpha)


def draw_wordmark(rows: list[bytearray]) -> None:
    top = 430.0
    height = 166.0
    bar = 24.0
    spacing = 30.0
    widths = [112.0, 100.0, 106.0, 90.0, 100.0, 106.0]

    total_width = sum(widths) + spacing * (len(widths) - 1)
    x = (SIZE - total_width) / 2.0

    # Stylised ATHLTH A: the same open-chevron language as the in-app mark,
    # simplified for legibility at small icon sizes.
    width = widths[0]
    draw_segment(
        rows,
        x + 12,
        top + height,
        x + width / 2,
        top + 2,
        bar / 2,
        INK,
    )
    draw_segment(
        rows,
        x + width - 12,
        top + height,
        x + width / 2,
        top + 2,
        bar / 2,
        INK,
    )
    x += width + spacing

    # T
    width = widths[1]
    draw_rectangle(rows, x, top, x + width, top + bar, INK)
    draw_rectangle(
        rows,
        x + width / 2 - bar / 2,
        top,
        x + width / 2 + bar / 2,
        top + height,
        INK,
    )
    x += width + spacing

    # H
    width = widths[2]
    draw_rectangle(rows, x, top, x + bar, top + height, INK)
    draw_rectangle(rows, x + width - bar, top, x + width, top + height, INK)
    draw_rectangle(
        rows,
        x,
        top + height / 2 - bar / 2,
        x + width,
        top + height / 2 + bar / 2,
        INK,
    )
    x += width + spacing

    # L
    width = widths[3]
    draw_rectangle(rows, x, top, x + bar, top + height, INK)
    draw_rectangle(
        rows,
        x,
        top + height - bar,
        x + width,
        top + height,
        INK,
    )
    x += width + spacing

    # T
    width = widths[4]
    draw_rectangle(rows, x, top, x + width, top + bar, INK)
    draw_rectangle(
        rows,
        x + width / 2 - bar / 2,
        top,
        x + width / 2 + bar / 2,
        top + height,
        INK,
    )
    x += width + spacing

    # H
    width = widths[5]
    draw_rectangle(rows, x, top, x + bar, top + height, INK)
    draw_rectangle(rows, x + width - bar, top, x + width, top + height, INK)
    draw_rectangle(
        rows,
        x,
        top + height / 2 - bar / 2,
        x + width,
        top + height / 2 + bar / 2,
        INK,
    )


def png_bytes() -> bytes:
    rows = background_rows()
    draw_wordmark(rows)

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    signature = b"\x89PNG\r\n\x1a\n"
    header = struct.pack(
        ">IIBBBBB",
        SIZE,
        SIZE,
        8,
        2,  # true-colour RGB, deliberately no alpha
        0,
        0,
        0,
    )

    return (
        signature
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, level=9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    payload = png_bytes()

    for path in (IOS_ICON, WATCH_ICON):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        print(f"Generated Option 4 ATHLTH icon: {path} ({len(payload)} bytes)")


if __name__ == "__main__":
    main()
