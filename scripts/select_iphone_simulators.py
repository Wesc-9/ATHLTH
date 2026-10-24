#!/usr/bin/env python3
"""Select *installed, runtime-compatible* iPhone simulators.

The Xcode device-type catalog includes retired models that cannot be created
with the latest iOS runtime. A device already registered under a runtime is
proof that CoreSimulator supports that pair. Do not create synthetic pairs.
"""
from __future__ import annotations

import json
import re
import sys


def version(runtime: str) -> tuple[int, ...]:
    match = re.search(r"iOS-(\d+(?:-\d+)*)$", runtime)
    return tuple(int(piece) for piece in match.group(1).split("-")) if match else (0,)


def category(name: str) -> str:
    lower = name.lower()
    if "se (" in lower:
        return "compact"
    if "mini" in lower:
        return "mini"
    if "pro max" in lower or "plus" in lower:
        return "large"
    return "standard"


def choose(data: dict) -> list[tuple[str, str, str]]:
    by_runtime: list[tuple[tuple[int, ...], str, dict[str, list[dict]]]] = []
    for runtime, devices in data.get("devices", {}).items():
        if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        groups: dict[str, list[dict]] = {k: [] for k in ("compact", "mini", "standard", "large")}
        seen: set[str] = set()
        for device in devices:
            name = device.get("name", "")
            udid = device.get("udid", "")
            if not name.startswith("iPhone") or not udid or udid in seen:
                continue
            if device.get("isAvailable") is False:
                continue
            seen.add(udid)
            groups[category(name)].append(device)
        by_runtime.append((version(runtime), runtime, groups))

    # Prefer the newest runtime with a real standard and large model.
    valid = [entry for entry in by_runtime
             if entry[2]["standard"] and entry[2]["large"]]
    if not valid:
        raise ValueError(
            "No installed iOS simulator runtime with both standard and large "
            "iPhone devices. Check xcrun simctl list devices available."
        )
    _, runtime, groups = max(valid, key=lambda item: item[0])
    print(f"::notice::Using registered compatible iPhone simulators for {runtime}", file=sys.stderr)

    result: list[tuple[str, str, str]] = []
    for name in ("compact", "mini", "standard", "large"):
        candidates = groups[name]
        if not candidates:
            # No SE/mini device for modern runtimes: do not invent coverage.
            print(f"::notice::No compatible {name} iPhone in {runtime}; skipping that size.",
                  file=sys.stderr)
            continue
        # Prefer more recent models inside each size class.
        picked = max(candidates, key=lambda d: (
            int((re.search(r"iPhone (\d+)", d["name"]) or [None, "0"])[1]),
            d["name"]
        ))
        result.append((name, picked["udid"], picked["name"]))
    return result


def main() -> int:
    try:
        chosen = choose(json.load(sys.stdin))
    except (ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 1
    for name, udid, label in chosen:
        print(f"{name}|{udid}|{label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
