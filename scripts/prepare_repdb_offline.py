#!/usr/bin/env python3
"""Embed RepDB's free-tier snapshot in the iOS app at build time.

Only the official in-app licensed files are included. The generated catalog
must never be committed or published as a standalone dataset/API. Free tier
requires visible RepDB attribution. Paid preview assets are excluded.
"""
from __future__ import annotations

import hashlib
import io
import json
import pathlib
import posixpath
import shutil
import sys
import tempfile
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEST = ROOT / "ATHLTH" / "Resources" / "RepDBOffline.bundle"
URLS = (
    "https://cdn.repdb.co/repdb-assets/site/repdb-free.zip",
    "https://codeload.github.com/RepDB/exercise-dataset/zip/refs/heads/main",
)
MAX_ARCHIVE = 300 * 1024 * 1024
MAX_EXTRACTED = 550 * 1024 * 1024


def _fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ATHLTH-Offline-Builder/1.0"})
    with urllib.request.urlopen(request, timeout=100) as response:
        data = response.read(MAX_ARCHIVE + 1)
    if not data or len(data) > MAX_ARCHIVE:
        raise ValueError("RepDB archive is empty or unexpectedly large")
    return data


def _safe_image_path(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    path = posixpath.normpath(value.lstrip("/"))
    if not path.startswith("images/flat/") or not path.endswith(".webp"):
        return None
    if ".." in path.split("/") or "\\" in path:
        return None
    return path


def _prepare_archive(data: bytes) -> tuple[bytes, dict[str, bytes], int]:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = set(archive.namelist())
        json_candidates = sorted(
            (x for x in names if x == "exercises.json" or x.endswith("/exercises.json")),
            key=len,
        )
        errors = []
        for json_name in json_candidates:
            try:
                raw_json = archive.read(json_name)
                document = json.loads(raw_json)
                exercises = document["exercises"]
                if not isinstance(exercises, list) or not (400 <= len(exercises) <= 2000):
                    raise ValueError("unexpected exercise count")
                ids = [e["id"] for e in exercises]
                if len(set(ids)) != len(ids):
                    raise ValueError("duplicate exercise identifiers")
                prefix = json_name[:-len("exercises.json")]
                assets = set()
                for exercise in exercises:
                    flat = (exercise.get("images") or {}).get("flat") or {}
                    for key in ("start", "peak", "main"):
                        image_path = _safe_image_path(flat.get(key))
                        if image_path:
                            assets.add(image_path)
                if len(assets) < len(exercises) // 2:
                    raise ValueError("missing expected exercise art")
                absent = [asset for asset in assets if prefix + asset not in names]
                if absent:
                    raise ValueError(f"missing {len(absent)} referenced WebP images")
                extracted = {}
                total_bytes = len(raw_json)
                for asset in sorted(assets):
                    file_info = archive.getinfo(prefix + asset)
                    total_bytes += file_info.file_size
                    if total_bytes > MAX_EXTRACTED or file_info.file_size > 5 * 1024 * 1024:
                        raise ValueError("RepDB assets exceed offline size limits")
                    extracted[asset] = archive.read(prefix + asset)
                return raw_json, extracted, len(exercises)
            except (ValueError, KeyError, TypeError, OSError) as exc:
                errors.append(str(exc))
        raise ValueError("no valid RepDB catalog: " + "; ".join(errors))


def main() -> None:
    DEST.parent.mkdir(parents=True, exist_ok=True)
    failures = []
    for url in URLS:
        try:
            blob = _fetch(url)
            payload, assets, count = _prepare_archive(blob)
            with tempfile.TemporaryDirectory(prefix="athlth-repdb-") as temp:
                root = pathlib.Path(temp) / "RepDBOffline.bundle"
                root.mkdir(parents=True, exist_ok=True)
                (root / "exercises.json").write_bytes(payload)
                for path, data in assets.items():
                    target = root.joinpath(*path.split("/"))
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
                manifest = {
                    "source": "RepDB free tier — licensed for in-app use",
                    "exercises": count,
                    "images": len(assets),
                    "json_sha256": hashlib.sha256(payload).hexdigest(),
                }
                (root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
                if DEST.exists():
                    shutil.rmtree(DEST)
                shutil.copytree(root, DEST)
            print(f"Embedded {count} RepDB exercises and {len(assets)} offline images")
            return
        except (OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
            failures.append(f"{url}: {exc}")
    sys.exit("RepDB offline bundle failed: " + " | ".join(failures))


if __name__ == "__main__":
    main()
