#!/usr/bin/env python3
"""Prevent the planner from discarding an existing workout when inviting friends.

The Community entry point may ask for a workout source, but the Settings
menu inside the workout builder must always pass its current draft, including
a new workout whose timeline is still empty.
"""
from pathlib import Path
import re

builder = Path("ATHLTH/Planning/WorkoutTemplateCatalog.swift").read_text()
composer = Path("ATHLTH/Social/TrainTogetherMarketplaceViews.swift").read_text()

start = builder.find("case .planWithFriend:")
end = builder.find("case .spotify:", start)
assert start >= 0 and end > start, "Missing Train Together settings action"
action = builder[start:end]
assert re.search(
    r"TrainTogetherPostCreateView\s*\(\s*"
    r"(?:\/\/[^\n]*\n\s*)*"
    r"initialWorkout:\s*workoutSnapshot\(\)",
    action,
), "Planner must pass the current workout regardless of empty blocks"
assert not re.search(
    r"initialWorkout:\s*blocks\.isEmpty\s*\?\s*nil",
    action,
), "Planner must never reopen workout selection for an existing draft"
assert "workout.workoutBlocks = blocks" in builder, "Snapshot lost workout steps"
assert "workout.spotifyPlaylist = selectedSpotifyPlaylist" in builder, "Snapshot lost Spotify"
assert "workout.gearIDs = Array(selectedWorkoutGearIDs)" in builder, "Snapshot lost gear"

start = composer.find("struct TrainTogetherPostCreateView:")
end = composer.find("struct TrainTogetherMapPlace:", start)
assert start >= 0 and end > start, "Missing Train Together invitation composer"
view = composer[start:end]
assert "_preparedWorkout = State(initialValue: initialWorkout)" in view, (
    "Existing workout must populate invitation composer"
)
assert "if preparedWorkout == nil {" in view and "sourceCard" in view, (
    "Source selection must be restricted to entry without an existing workout"
)
assert "preparedWorkoutSummary(preparedWorkout)" in view, (
    "Existing workout must be visible in invitation settings"
)
assert "guard var workout = preparedWorkout else { return }" in view, (
    "Publishing must use the full original workout payload"
)
print("PASS: Train Together from workout Settings reuses the live draft.")
