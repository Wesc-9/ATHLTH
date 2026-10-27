#!/usr/bin/env python3
"""Ensure the approved Train > Plan experience is actually wired to live data.

This guards against the earlier mistake where revised mockup/detail code was
committed but the tab continued rendering a different old Plan workspace.
"""
from pathlib import Path

root = Path("ATHLTH/Views/ProductRootTabView.swift").read_text(encoding="utf-8")
plan = Path("ATHLTH/Training/ATHLTHTrainPlanPremiumView.swift").read_text(encoding="utf-8")

checks = {
    "Train Plan tab renders the real premium workspace":
        "if selectedSection == .plan {" in root
        and "ATHLTHTrainPlanPremiumView(" in root,
    "Workspace shows a persisted active plan":
        "return session.activePlan" in plan
        and "referencePlanSummary(active, isActive: true)" in plan,
    "One selected week, with all seven days visible as rows":
        "let week = plan.weeks[weekIndex]" in plan
        and "ForEach(week.days.sorted(by:" in plan
        and "planReferenceDayRow(day, plan: plan)" in plan,
    "Opening a day shows details in the actual schedule":
        "if selectedDayID == day.id {" in plan
        and "referenceDayWorkspace(day, plan: plan)" in plan,
    "The day has both scheduled workouts and real day-details modes":
        'tr("Scheduled workouts", "Planlagte økter")' in plan
        and 'tr("Day details", "Dagdetaljer")' in plan
        and "premiumSelectedDayPanel(day, plan: plan)" in plan,
    "Workout phase data comes from unified recorded structure":
        "ATHLTHUnifiedWorkout.editorBlocks(from: workout)" in plan
        and "referenceWorkoutPhase(" in plan,
    "Days can directly add, edit and copy workouts":
        'Label(tr("Add workout", "Legg til økt"), systemImage: "plus")' in plan
        and 'Label(tr("Edit workout", "Rediger økt"), systemImage: "pencil")' in plan
        and 'Label(tr("Copy day", "Kopier dag"), systemImage: "doc.on.doc")' in plan,
    "Editing uses versioned plan/day records, not sample content":
        "ATHLTHTrainWorkoutBuilderView(" in plan
        and "expectedPlanVersion: destination.version" in plan,
    "The Plan header is part of the same Train navigation":
        "premiumTrainBrandHeader" in root
        and "progressHeaderTab(\"Plan\", section: .plan)" in root,
    "Week copy is wired to the real safe copy service":
        'tr("Copy week", "Kopier uke")' in plan
        and "ATHLTHTrainPlanWeekCopyPolicy.copy(" in plan
        and "ATHLTHTrainPlanWeekCopyPolicy.preview(" in plan,
    "Full week editor opens the selected persisted week":
        "ATHLTHTrainWeekBuilderView(" in plan
        and "initialWeekIndex: selectedWeekIndex" in plan,
}

for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
if not all(checks.values()):
    raise SystemExit("Train > Plan reference implementation is disconnected or incomplete")
