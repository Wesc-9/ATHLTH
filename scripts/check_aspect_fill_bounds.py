#!/usr/bin/env python3
"""Cheap SwiftUI image-layout regression check (not a visual-device test).

The screenshots from Strength details and ATHLTH Coach demonstrated that an
unbounded aspect-fill image can expand a vertical ScrollView sideways.
Coach now uses an image-free compact header; guard its responsive chat layout
and the remaining artwork surfaces instead.
Legitimate GeometryReader-based or bounded-fill images are deliberately allowed.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "ATHLTH"

# Required source-level invariants for the two real-world iPhone regressions.
# These checks intentionally avoid matching asset names or changing artwork.
REQUIRED = {
    # Coach now uses a compact, image-free header. The old 164 pt
    # aspect-fill photo guard is intentionally obsolete.
    "ATHLTH/Recovery/RecoveryAIViews.swift": (
        r"private struct RecoveryCoachCompactHeader",
        r"\.containerRelativeFrame\(\.horizontal\)",
    ),
    "ATHLTH/Social/HomeActivityStrengthDetailView.swift": (
        r"GeometryReader\s*\{\s*viewport\s+in",
        r"\.frame\(width:\s*viewport\.size\.width,\s*height:\s*196\)",
        r"\.containerRelativeFrame\(\.horizontal\)",
    ),
    "ATHLTH/Community/CommunityV4.swift": (
        r"Image\(assetName\).*?\.scaledToFill\(\)\s*\.athlthBoundedFill\(\)",
    ),
    "ATHLTH/Social/SocialViews.swift": (
        r"Image\(\"CommunityHero\"\)\s*\.resizable\(\)\s*\.scaledToFill\(\)\s*\.athlthBoundedFill\(\)",
    ),
    "ATHLTH/Profile/ProfilePerformanceViews.swift": (
        r"Image\(\"GoalSprint\"\).*?\.scaleEffect\(1\.10\)\s*\.athlthBoundedFill\(\)",
        r"Image\(\"StrengthPostWorkoutHero\"\).*?\.scaleEffect\(1\.08\)\s*\.athlthBoundedFill\(\)",
    ),
    "ATHLTH/Goals/GoalViews.swift": (
        r"private struct GoalPreviewCard.*?\.athlthBoundedFill\(\)",
    ),
    "ATHLTH/Challenges/ChallengeViews.swift": (
        r"private struct ChallengeReviewCard.*?\.athlthBoundedFill\(\)",
    ),
}

def main() -> int:
    errors: list[str] = []
    for relative, patterns in REQUIRED.items():
        path = ROOT / relative
        source = path.read_text(encoding="utf-8")
        for pattern in patterns:
            if not re.search(pattern, source, re.DOTALL):
                errors.append(f"{relative}: lost responsive artwork guard: {pattern}")

    # Informational project-wide scan. An image can be safely bounded by
    # an enclosing GeometryReader, so simplistic grep matches aren't build
    # failures; source-specific regressions above *are* failures.
    candidates = []
    scanned = 0
    total_fills = 0
    for path in APP.rglob("*.swift"):
        scanned += 1
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if ".scaledToFill()" not in line:
                continue
            total_fills += 1
            ahead = "\n".join(lines[index + 1:index + 22])
            max_width = re.search(
                r"\.frame\(\s*(?:(?:height|minHeight|maxHeight)\s*:"
                r"[^)]*\)\s*)?maxWidth\s*:\s*\.infinity",
                ahead,
            )
            if max_width and not (
                ".athlthBoundedFill()" in ahead[:max_width.end()]
                or re.search(r"\.frame\(\s*width\s*:", ahead[:max_width.end()])
                or ".containerRelativeFrame(.horizontal)" in ahead[:max_width.end()]
            ):
                candidates.append(f"{path.relative_to(ROOT)}:{index+1}")

    print(
        f"Aspect-fill layout audit: {scanned} Swift files, "
        f"{total_fills} aspect-fill images, "
        f"{len(candidates)} potential width risks for manual review."
    )
    for location in candidates[:35]:
        print(f"  REVIEW {location}")
    if len(candidates) > 35:
        print(f"  ... and {len(candidates)-35} other potential review locations")

    for message in errors:
        print(f"ERROR {message}")
    if errors:
        return 1
    print("All known responsive hero and preview guards are present.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
