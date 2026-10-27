#!/usr/bin/env python3
"""Guard the real ATHLTH Insights root, preview routes and reference content.

Regression prevented: production tab 2 once displayed ATHLTHRecoveryView while
the replacement ATHLTHInsightsView existed but was not mounted. The compatibility
preview had Train and Insights in the wrong order, masking the issue in smoke
screenshots. Keep Recovery as a detail destination, not a second root.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    raise SystemExit(f"INSIGHTS ROUTING ERROR: {message}")


def between(source: str, left: str, right: str) -> str:
    if source.count(left) != 1:
        fail(f"Expected exactly one opening marker: {left!r}")
    _, remainder = source.split(left, 1)
    if right not in remainder:
        fail(f"Missing closing marker after {left!r}: {right!r}")
    return remainder.split(right, 1)[0]


def section_for_case(source: str, case: int, next_case: int | None = None) -> str:
    pattern = rf"(?m)^\s*case {case}:\s*$"
    locations = list(re.finditer(pattern, source))
    if len(locations) != 1:
        fail(f"Expected one case {case} in preview routing, found {len(locations)}")
    start = locations[0].end()
    next_match = (
        re.search(rf"(?m)^\s*case {next_case}:\s*$", source[start:])
        if next_case is not None
        else re.search(r"(?m)^\s*default:\s*$", source[start:])
    )
    if not next_match:
        fail(f"Cannot find the end of compatibility case {case}")
    return source[start : start + next_match.start()]


root = Path("ATHLTH/Views/ProductRootTabView.swift").read_text()
preview = Path("ATHLTH/App/ATHLTHApp.swift").read_text()
insights = Path("ATHLTH/Insights/ATHLTHInsightsView.swift").read_text()
sections = Path("ATHLTH/Insights/ATHLTHInsightsPremiumSections.swift").read_text()
cards = Path("ATHLTH/Insights/ATHLTHInsightsReferenceCards.swift").read_text()

# Inspect only the real root TabView: a Recovery destination inside a detail
# sheet must not be misclassified as a legacy main route.
production = between(root, "struct ProductRootTabView: View {", "struct ATHLTHHomeView: View {")
if "TabView(selection: $selectedTab)" not in production:
    fail("Production TabView not found")
tab_body = between(production, "TabView(selection: $selectedTab) {", ".tag(2)")
if "ATHLTHInsightsView(" not in tab_body:
    fail("Production tab 2 must mount ATHLTHInsightsView")
if "ATHLTHRecoveryView(" in tab_body:
    fail("Legacy Recovery view has returned as a root tab")
if "isActive: selectedTab == 2" not in tab_body:
    fail("Insights must load Health data only while active")

# Previews are used to generate screenshots on different iPhones/iPads.
# These were previously swapped and could pass checks for the wrong UI.
preview_body = between(
    preview, "private struct ATHLTHCompatibilityPreviewRootView: View {",
    "private struct ATHLTHLaunchGateView: View {",
)
if "ATHLTHRecoveryView(" in preview_body:
    fail("Preview still opens legacy Recovery as a root tab")
one = section_for_case(preview_body, 1, 2)
two = section_for_case(preview_body, 2, 3)
if "ATHLTHTrainView(" not in one or "ATHLTHInsightsView(" in one:
    fail("Preview tab 1 must be Train")
if "ATHLTHInsightsView(" not in two or "ATHLTHTrainView(" in two:
    fail("Preview tab 2 must be Insights")
if "AnyView(ProductRootTabView())" not in preview:
    fail("Authenticated production root no longer uses ProductRootTabView")

# Reference layout must actually be present and use real data.
for token in (
    "ATHLTHInsightsNavigation(",
    "readinessOverviewCard",
    "dailyRecommendationCard",
    "ATHLTHInsightsDailyCheckInCard(",
    "ATHLTHInsightsReferenceSignalCard(",
    "ATHLTHInsightsReferenceLoadCard(",
    "ATHLTHInsightsReferenceTimeCard(",
    "ATHLTHInsightsReferenceDistributionCard(",
    "recoveryTrendSnapshot(days: 7)",
    "ATHLTHRecoveryView(onSelectTab: onSelectTab)",
):
    if token not in insights:
        fail(f"Required new Insights element or detail path is missing: {token}")
for case in ("case overview, health, training, development",):
    if case not in sections:
        fail("Reference's four sections were removed or changed")
for token in (
    "RecoveryTrendSnapshot", "ATHLTHInsightsTrainingDay",
    "RecoveryTrainingLoadSummary", "RecoverySorenessStore",
):
    if token not in insights + cards:
        fail(f"Required real-data dependency missing: {token}")

print("PASS: production and preview tab 2 both use the reference Insights view.")
print("PASS: legacy Recovery remains a detail page only.")
print("PASS: reference cards consume recorded Health and check-in data.")
