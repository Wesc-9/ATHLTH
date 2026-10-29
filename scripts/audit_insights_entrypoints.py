#!/usr/bin/env python3
"""Guard the real ATHLTH Insights root, preview routes and reference content.

Regression prevented: production tab 2 once displayed ATHLTHRecoveryView while
the replacement ATHLTHInsightsView existed but was not mounted. The compatibility
preview had Train and Insights in the wrong order, masking the issue in smoke
screenshots. Retire the old Recovery screen; Readiness explanations stay in a modern sheet.
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

# Both image-led sections must paint from the very top of the device.
# Regression: the root ScrollView began below the Dynamic Island while the
# cover still rounded its upper corners, leaving a pale horizontal strip.
train_cover = Path("ATHLTH/Training/ATHLTHTrainTodayCoverView.swift").read_text()
if "edges: section == .today ? .top : []" not in root or (
    ".ignoresSafeArea(.container, edges: section == .today ? .top : [])"
    not in root
):
    fail("Train Today ScrollView must ignore the top safe area")
if "ATHLTHCoverSafeArea.statusBarTop" not in train_cover:
    fail("Train cover must reserve safe space for the Dynamic Island controls")
if "topLeading: 0" not in train_cover:
    fail("Train cover cannot clip the artwork with rounded top corners")
if "ATHLTHPinnedHeroLayout(" in insights:
    fail("Insights must share Train's single scrolling cover/card layout")
if ".ignoresSafeArea(.container, edges: .top)" not in insights:
    fail("Insights ScrollView must paint artwork through the status bar")
if "ATHLTHCoverSafeArea.statusBarTop" not in insights:
    fail("Insights cover must keep tab controls below status bar")
if "selection: $selectedSection" not in insights:
    fail("Insights hero must own the three-option segmented navigation")

# Audit the active editorial layout, rather than requiring all of the
# previous redundant charts. Each tab must have a distinct purpose.
for token in (
    "ATHLTHInsightsNavigation(",
    "ATHLTHInsightsCoverHero(",
    "readinessOverviewCard",
    "signalPerspectiveCard",
    "ATHLTHInsightsDailyCheckInCard(",
    "ATHLTHInsightsMuscleCard(summary: muscleSummary)",
    "trainingRhythmCard",
    "ATHLTHInsightsReferenceDistributionCard(",
    "whatChangedCard",
    "whatIfCard",
    "ATHLTHInsightsWhatIfView(",
    "recoveryTrendSnapshot(days: 7)",
    "ATHLTHReadinessExplanationSheet(",
):
    if token not in insights:
        fail(f"Required Insights element or data route is missing: {token}")
# Guard against duplicate cards across tabs: health measurements remain
# available through readiness details rather than a redundant fourth section.
development = between(insights,
    "private var developmentSection: some View {", "@MainActor")
if "ATHLTHInsightsReferenceSignalCard(" in development:
    fail("Development cannot duplicate health signal charts")
training = between(insights,
    "private var trainingSection: some View {",
    "private var developmentSection: some View {")
if training.find("ATHLTHInsightsMuscleCard(") > training.find("trainingRhythmCard"):
    fail("Muscle balance must be the first training insight")
if "case overview, training, development" not in sections:
    fail("Insights must contain Overview, Training and Development")
if "case overview, health, training, development" in sections:
    fail("The redundant Body & Health top-level section has returned")
if "ATHLTHInsightReferenceMetric" not in cards:
    fail("Underlying health reference metrics must remain available")
for token in (
    "RecoveryTrendSnapshot", "ATHLTHInsightsTrainingDay",
    "RecoveryTrainingLoadSummary", "RecoverySorenessStore",
):
    if token not in insights + cards:
        fail(f"Required real-data dependency missing: {token}")

print("PASS: production and preview tab 2 both use the reference Insights view.")
if "struct ATHLTHRecoveryView: View" in root or "ATHLTHRecoveryView(" in insights:
    fail("The obsolete Recovery/Insights view or route must stay removed")
if "regionTints: atlasTints" not in sections or "ForEach(allMuscles)" not in sections:
    fail("Muscle map and expanded list must cover every recorded region")
if "ATHLTHInsightsMuscleRanking.all(summary)" not in sections:
    fail("All-muscle 100% reference ranking missing")
print("PASS: obsolete Recovery screen removed; readiness opens a local factor explanation.")
print("PASS: three editorial sections preserve readiness, training and trends without a duplicate health tab.")
