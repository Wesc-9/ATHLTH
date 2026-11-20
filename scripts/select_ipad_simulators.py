#!/usr/bin/env python3
"""Select an already-registered, available iPad CoreSimulator device.

Selection is read-only. Newly created simulator lifecycle is owned by the
caller; pre-existing devices must never be deleted from shared runner images.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any


def matches_size(name: str, size: int) -> bool:
    if not name.startswith("iPad"):
        return False
    if size == 13:
        return bool(re.search(r"13[- ]inch", name))
    if size == 11:
        return bool(re.search(r"11[- ]inch", name)) or name in {
            "iPad (A16)", "iPad (10th generation)"
        }
    raise ValueError(f"Unsupported iPad size: {size}")


def runtime_version(identifier: str) -> tuple[int, ...] | None:
    match = re.search(r"\.SimRuntime\.iOS-(\d+(?:-\d+)*)$", identifier)
    if not match:
        return None
    return tuple(map(int, match.group(1).split("-")))


def select_registered_device(payload: dict[str, Any], size: int) -> dict[str, str] | None:
    candidates: list[tuple[tuple[Any, ...], dict[str, str]]] = []
    for runtime, devices in payload.get("devices", {}).items():
        version = runtime_version(runtime)
        if version is None:
            continue
        for device in devices:
            name = str(device.get("name", ""))
            udid = str(device.get("udid", ""))
            state = str(device.get("state", ""))
            if device.get("isAvailable") is False or not udid or not matches_size(name, size):
                continue
            if state not in {"Booted", "Shutdown"}:
                continue
            # A booted simulator may avoid expensive fresh CoreSimulator boot.
            # Actual readiness is always verified by simctl launchctl probing.
            order = (state == "Booted", version, "Pro" in name, name)
            candidates.append((order, {"udid": udid, "name": name, "state": state, "runtime": runtime}))
    if not candidates:
        return None
    return max(candidates, key=lambda pair: pair[0])[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, choices=(11, 13), required=True)
    args = parser.parse_args()
    device = select_registered_device(json.load(sys.stdin), args.size)
    if device is None:
        print(f"::notice::No registered compatible {args.size}-inch iPad; will create a temporary simulator", file=sys.stderr)
        return 1
    print(f"::notice::Reuse registered {device['name']} ({device['state']}) on {device['runtime']}", file=sys.stderr)
    print(device["udid"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
