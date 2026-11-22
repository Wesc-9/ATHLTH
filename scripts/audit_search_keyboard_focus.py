#!/usr/bin/env python3
"""Reject SwiftUI search-driven identity resets that dismiss the iOS keyboard.

TextField and .searchable must stay mounted while filtering changes. A
ScrollView/List .id(revision) is allowed for deliberate alphabet-index jumps,
but its revision must not change from an onChange handler in the same view.
This is a conservative source-level guard, not a substitute for UI testing.
"""

from __future__ import annotations

import pathlib
import re
import sys

ID_PATTERN = re.compile(r"\.id\(\s*([a-zA-Z_]\w*)\s*\)")
CHANGE_PATTERN = re.compile(
    r"\.onChange\s*\(\s*of:\s*([\w.]+)\s*\)\s*\{",
    re.MULTILINE,
)


def change_body(source: str, opening_brace: int) -> str:
    """Read one balanced onChange closure (sufficient for state writes)."""
    depth = 1
    for index in range(opening_brace + 1, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening_brace + 1 : index]
    return source[opening_brace + 1 :]


def violations(path: pathlib.Path, source: str) -> list[str]:
    if "TextField(" not in source and ".searchable(" not in source:
        return []
    remount_ids = set(ID_PATTERN.findall(source))
    problems: list[str] = []
    for remount_id in remount_ids:
        if re.search(r"(?:search|query|filter)", remount_id, re.I):
            for match in ID_PATTERN.finditer(source):
                if match.group(1) == remount_id:
                    problems.append(
                        f"{path}:{source.count(chr(10), 0, match.start()) + 1}: "
                        f".id({remount_id}) is coupled to a search/filter value"
                    )
        assignment = re.compile(
            rf"\b{re.escape(remount_id)}\s*(?:\+=|-=|(?<![=!<>])=(?!=)|\.toggle\s*\()"
        )
        for match in CHANGE_PATTERN.finditer(source):
            body = change_body(source, match.end() - 1)
            if assignment.search(body):
                line = source.count("\n", 0, match.start()) + 1
                problems.append(
                    f"{path}:{line}: .onChange(of: {match.group(1)}) "
                    f"mutates .id({remount_id}); keep TextField identity stable"
                )
    return problems


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    failures: list[str] = []
    scanned = 0
    for subdir in ("ATHLTH", "ATHLTHWatchApp", "ATHLTHWatchExtension"):
        for path in (root / subdir).rglob("*.swift"):
            scanned += 1
            failures.extend(violations(path.relative_to(root), path.read_text(encoding="utf-8")))
    if failures:
        print("Search keyboard focus risks:")
        print("\n".join(sorted(failures)))
        print("Fix search/filter remounts before merging or uploading.")
        return 1
    print(f"Search keyboard focus guard passed ({scanned} Swift files scanned).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
