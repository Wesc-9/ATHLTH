#!/usr/bin/env python3
"""Static, deterministic regression gate for ATHLTH Watch visual/power rules.

This is NOT a battery benchmark or screenshot inspection. A real Apple Watch
is required for display-power and runtime validation.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
AOD = ROOT / "ATHLTHWatchExtension/WatchTrainingAlwaysOnDashboard.swift"
RUN = ROOT / "ATHLTHWatchExtension/WatchRunWorkoutExperienceView.swift"
WATCH = ROOT / "ATHLTHWatchExtension/WatchWorkoutViews.swift"
POLICY = ROOT / "Shared/ATHLTHAlwaysOnRefreshPolicy.swift"
SPORT = ROOT / "ATHLTHWatchExtension/WatchOtherSportFocusPages.swift"
INTERVAL = ROOT / "ATHLTHWatchExtension/WatchRunIntervalGhostPages.swift"


def check(condition: bool, message: str, failures: list[str]) -> None:
    if condition:
        print(f"PASS  {message}")
    else:
        print(f"FAIL  {message}")
        failures.append(message)


def luminance_channel(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def white_text_on_black_contrast(alpha: float) -> float:
    # Alpha-composited sRGB white over black; relative luminance.
    lum = luminance_channel(alpha)
    return (lum + 0.05) / 0.05


def main() -> int:
    failures: list[str] = []
    aod = AOD.read_text(encoding="utf8")
    run = RUN.read_text(encoding="utf8")
    watch = WATCH.read_text(encoding="utf8")
    policy = POLICY.read_text(encoding="utf8")
    sport = SPORT.read_text(encoding="utf8")
    interval = INTERVAL.read_text(encoding="utf8")

    match = re.search(
        r"loweredWristInterval:\s*TimeInterval\s*=\s*(\d+(?:\.\d+)?)",
        policy,
    )
    interval_seconds = float(match.group(1)) if match else 0
    check(interval_seconds >= 60, "AOD timeline interval >= 60s", failures)

    timeline_occurrences = re.findall(r"TimelineView\s*\(\s*\.periodic\s*\(", aod)
    policy_occurrences = aod.count(
        "ATHLTHAlwaysOnRefreshPolicy.loweredWristInterval"
    )
    check(
        len(timeline_occurrences) == 3 and policy_occurrences == 3,
        "All three AOD countdown/ghost timeline requests use low-power policy",
        failures,
    )

    check(
        not re.search(
            r"Timer\.scheduledTimer|Timer\.publish|withAnimation\s*\(|"
            r"\.animation\s*\(|\.repeatForever\s*\(|"
            r"CADisplayLink|onReceive\s*\(",
            aod,
        ),
        "No AOD-owned timer, animation loop or per-second publisher",
        failures,
    )

    check(
        "GeometryReader" in aod
        and "geometry.size.width < 190" in aod
        and "geometry.size.height < 205" in aod
        and aod.count(".minimumScaleFactor(") >= 4,
        "Compact Watch geometry and shrinking main numbers",
        failures,
    )

    check(
        ".background(Color.black)" in aod
        and ".allowsHitTesting(false)" in aod,
        "Dark, noninteractive lowered-wrist surface",
        failures,
    )

    private_start = aod.find("private func privateWorkoutDashboard(")
    private_end = aod.find("private func strengthDashboard(", private_start)
    private_src = aod[private_start:private_end]
    check(
        private_start >= 0
        and private_end > private_start
        and "workout.kind.title" in private_src
        and "workout.elapsedTime" in private_src
        and not re.search(
            r"heartRate|ghost|routeTitle|exerciseName|currentStructuredStep",
            private_src,
            flags=re.IGNORECASE,
        ),
        "Private AOD reveals category and elapsed time, no sensitive metrics",
        failures,
    )

    check(
        "isLuminanceReduced" in run
        and "WatchTrainingAlwaysOnDashboard()" in run
        and "isLuminanceReduced" in watch
        and "WatchTrainingAlwaysOnDashboard()" in watch,
        "Run and other sports use AOD dashboard when wrist is lowered",
        failures,
    )

    check(
        "@ScaledMetric" in sport and "@ScaledMetric" in interval
        and ".accessibilityValue(" in sport
        and ".accessibilityValue(" in interval,
        "Watch sport and interval pages support large type and VoiceOver",
        failures,
    )

    # White @ 0.47 on black is the least-contrasted plain AOD text.
    # Verify it remains >= WCAG AA (4.5:1); not a claim about brightness,
    # screen reflections or font legibility on a real watch.
    match = re.search(
        r"Color\.white\.opacity\(strongContrast \? 0\.80 : ([\d.]+)\)",
        aod,
    )
    minimum_alpha = float(match.group(1)) if match else -1
    check(
        minimum_alpha > 0
        and white_text_on_black_contrast(minimum_alpha) >= 4.5,
        "Lowest static white-on-black AOD label passes 4.5:1 contrast",
        failures,
    )

    print(
        "\nSTATIC WATCH VISUAL/POWER AUDIT:",
        "FAILED" if failures else "PASS",
    )
    print(
        "Device screenshots, actual timer presentation, real battery drain, "
        "GPU utilization and Always-On refresh behavior still need hardware."
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
