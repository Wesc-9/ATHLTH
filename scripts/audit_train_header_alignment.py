#!/usr/bin/env python3
"""Ensure Train's three sections use one scrolling header and never a sticky tab."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
train = (root / "ATHLTH/Views/ProductRootTabView.swift").read_text()
cover = (root / "ATHLTH/Training/ATHLTHTrainTodayCoverView.swift").read_text()
progress = (root / "ATHLTH/Training/ATHLTHTrainProgressReferenceView.swift").read_text()
style = (root / "ATHLTH/DesignSystem/ATHLTHTrainDesign.swift").read_text()

checks = {
    "one canonical navigation row": "struct ATHLTHTrainHeaderRow: View" in style,
    "Today uses canonical selector": "ATHLTHTrainHeaderRow(selection: $selection)" in cover,
    "Plan/Progress use canonical selector": "ATHLTHTrainHeaderRow(selection: $selectedSection)" in train,
    "no pinned duplicate tabs": "floatingTrainTabsVisible" not in train and "premiumTrainTabs" not in train,
    "no directional sticky on scroll": "updateTrainCapsuleVisibility" not in train,
    "separate scroll positions for every tab": all(
        needle in train for needle in (
            "todayScrollPosition", "planScrollPosition", "progressScrollPosition")),
    "progress restores its independent scroll": ".scrollPosition($scrollPosition)" in progress,
    "Today retains full-bleed artwork": "edges: section == .today ? .top : []" in train,
    "animated tab crossfade": ".transition(.opacity)" in train,
    "shared selection accessible": ".accessibilityAddTraits(active ? .isSelected : [])" in style,
}
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + " — " + name)
if not all(checks.values()):
    raise SystemExit("Train tab navigation must stay visually identical and scroll away.")
