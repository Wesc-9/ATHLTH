#!/usr/bin/env python3
"""Verify the final app's offline catalog and original artwork, not just source."""
from __future__ import annotations

import json
import pathlib
import sys

from prepare_repdb_offline import ORIGINALS, _has_original_pair, _safe_image_path


def verify(app: pathlib.Path, source: pathlib.Path = ORIGINALS) -> tuple[int, int, int]:
    root = app / "RepDBOffline.bundle"
    original_root = app / "ATHLTHExerciseArtwork.bundle"
    exercises = json.loads((root / "exercises.json").read_text())["exercises"]
    if not isinstance(exercises, list) or len(exercises) < 400:
        raise ValueError("Insufficient offline exercises")
    ids = [ex["id"] for ex in exercises]
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate offline exercise identifiers")

    covered = set()
    required = set()
    for ex in exercises:
        source_id = ex["id"]
        has_original = _has_original_pair(source_id, source)
        if has_original:
            if not _has_original_pair(source_id, original_root):
                raise ValueError(f"Missing archived original artwork pair: {source_id}")
            for position in ("start", "peak"):
                name = f"{source_id}-{position}.webp"
                if (source / name).read_bytes() != (original_root / name).read_bytes():
                    raise ValueError(f"Archived original artwork differs from source: {name}")
            covered.add(source_id)
        else:
            flat = (ex.get("images") or {}).get("flat") or {}
            for value in flat.values():
                if isinstance(value, str) and value.startswith("images/flat/"):
                    image = _safe_image_path(value)
                    if image is None:
                        raise ValueError(f"Invalid offline image path: {value}")
                    required.add(image)

    # A shared legacy path is still required if even one uncovered exercise
    # uses it. An original pair for another exercise cannot satisfy that need.
    missing = sorted(x for x in required if not (root / x).is_file())
    if missing:
        raise ValueError(f"Missing offline exercise art: {missing[:5]}")
    return len(exercises), len(required), len(covered)


if __name__ == "__main__":
    count, fallback, originals = verify(pathlib.Path(sys.argv[1]))
    print(f"Verified {count} offline exercises, {fallback} required RepDB assets, "
          f"and {originals} complete archived ATHLTH artwork pairs")
