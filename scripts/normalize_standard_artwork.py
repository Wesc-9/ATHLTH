from __future__ import annotations

from pathlib import Path
from PIL import Image

ASSETS = [
    "GoalSprint",
    "GoalWalking",
    "GoalMountain",
    "GoalProgress",
    "GoalRelax",
    "GoalRunning",
    "GoalStrength",
    "GoalEndurance",
    "GoalRecovery",
    "GoalConsistency",
    "GoalEvent",
    "GoalAdventure",
]

ROOT = Path("ATHLTH/Assets.xcassets")


def near_white(pixel: tuple[int, int, int]) -> bool:
    r, g, b = pixel
    return min(r, g, b) >= 242 and (max(r, g, b) - min(r, g, b)) <= 18


def first_nonwhite_on_row(img: Image.Image, y: int) -> tuple[int, int] | None:
    px = img.load()
    w, _ = img.size
    left = None
    right = None
    for x in range(w):
        if not near_white(px[x, y]):
            left = x
            break
    if left is None:
        return None
    for x in range(w - 1, -1, -1):
        if not near_white(px[x, y]):
            right = x
            break
    return left, right


def first_nonwhite_on_col(img: Image.Image, x: int) -> tuple[int, int] | None:
    px = img.load()
    _, h = img.size
    top = None
    bottom = None
    for y in range(h):
        if not near_white(px[x, y]):
            top = y
            break
    if top is None:
        return None
    for y in range(h - 1, -1, -1):
        if not near_white(px[x, y]):
            bottom = y
            break
    return top, bottom


def clean_frame(path: Path) -> bool:
    original = Image.open(path).convert("RGB")
    w, h = original.size

    row_span = first_nonwhite_on_row(original, h // 2)
    col_span = first_nonwhite_on_col(original, w // 2)
    if row_span is None or col_span is None:
        return False

    x0, x1 = row_span
    y0, y1 = col_span

    # Full-bleed artwork should be left untouched. This also avoids treating
    # naturally bright skies/walls as an artificial frame.
    margin_x = max(x0, w - 1 - x1)
    margin_y = max(y0, h - 1 - y1)
    if margin_x < max(4, int(w * 0.008)) and margin_y < max(4, int(h * 0.008)):
        return False

    # Require a clear white background at the actual canvas corners before
    # considering the image framed.
    px = original.load()
    corner_points = [
        (0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
        (min(8, w - 1), min(8, h - 1)),
        (max(w - 9, 0), min(8, h - 1)),
        (min(8, w - 1), max(h - 9, 0)),
        (max(w - 9, 0), max(h - 9, 0)),
    ]
    white_corners = sum(near_white(px[x, y]) for x, y in corner_points)
    if white_corners < 6:
        return False

    # The old generated assets contain a rounded image inside a white canvas.
    # Find the first/last row where the image reaches the full horizontal
    # content span. Cropping there removes both the outer margin and the
    # baked-in rounded corners, leaving a true full-bleed photo.
    tolerance = max(3, int(w * 0.003))
    top_full = y0
    for y in range(y0, min(y1 + 1, y0 + max(12, h // 3))):
        span = first_nonwhite_on_row(original, y)
        if span and span[0] <= x0 + tolerance and span[1] >= x1 - tolerance:
            top_full = y
            break

    bottom_full = y1
    for y in range(y1, max(y0 - 1, y1 - max(12, h // 3)), -1):
        span = first_nonwhite_on_row(original, y)
        if span and span[0] <= x0 + tolerance and span[1] >= x1 - tolerance:
            bottom_full = y
            break

    # Defensive minimum size.
    if x1 - x0 < w * 0.55 or bottom_full - top_full < h * 0.35:
        return False

    cleaned = original.crop((x0, top_full, x1 + 1, bottom_full + 1))
    cleaned.save(path, "JPEG", quality=94, subsampling=0, optimize=True)
    print(f"CLEANED {path}: {w}x{h} -> {cleaned.width}x{cleaned.height}")
    return True


def main() -> None:
    changed = []
    for name in ASSETS:
        runtime = ROOT / f"{name}.imageset" / "runtime.jpg"
        thumb = ROOT / f"{name}Thumbnail.imageset" / "thumbnail.jpg"
        for path in (runtime, thumb):
            if not path.exists():
                raise FileNotFoundError(path)
            if clean_frame(path):
                changed.append(str(path))

    print(f"Changed {len(changed)} files")
    for path in changed:
        print(path)


if __name__ == "__main__":
    main()
