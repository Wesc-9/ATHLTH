import SwiftUI

/// Coordinates for editing an AI proposal. The draft is not persisted until
/// the athlete explicitly accepts the final result in AIProgramBuilderView.
struct ATHLTHPlanDraftWorkoutSelection: Identifiable, Equatable {
    let weekNumber: Int
    let dayIndex: Int
    let sessionIndex: Int

    var id: String { "\(weekNumber):\(dayIndex):\(sessionIndex)" }
}

enum ATHLTHPlanDraftEditing {
    static func workout(
        in draft: AIProgramDraft,
        selection: ATHLTHPlanDraftWorkoutSelection
    ) -> AIProgramDraftSession? {
        draft.weeks.first(where: { $0.weekNumber == selection.weekNumber })?
            .days.first(where: { $0.dayIndex == selection.dayIndex })?
            .sessions[safe: selection.sessionIndex]
    }

    static func replacing(
        in draft: AIProgramDraft,
        selection: ATHLTHPlanDraftWorkoutSelection,
        with updated: AIProgramDraftSession
    ) -> AIProgramDraft? {
        guard workout(in: draft, selection: selection) != nil else {
            return nil
        }
        let weeks = draft.weeks.map { week -> AIProgramDraftWeek in
            guard week.weekNumber == selection.weekNumber else { return week }
            let days = week.days.map { day -> AIProgramDraftDay in
                guard day.dayIndex == selection.dayIndex else { return day }
                var sessions = day.sessions
                sessions[selection.sessionIndex] = updated
                return AIProgramDraftDay(
                    dayIndex: day.dayIndex,
                    title: day.title,
                    sessions: sessions
                )
            }
            return AIProgramDraftWeek(
                weekNumber: week.weekNumber,
                title: week.title,
                days: days
            )
        }
        return AIProgramDraft(
            title: draft.title,
            summary: draft.summary,
            weeks: weeks
        )
    }
    /// Move a draft workout inside the same week without touching a real plan.
    /// The target day must be empty to preserve one planned workout per day.
    static func moving(
        in draft: AIProgramDraft,
        selection: ATHLTHPlanDraftWorkoutSelection,
        toDayIndex: Int,
        allowedDayIndexes: Set<Int>? = nil
    ) -> AIProgramDraft? {
        guard (1...7).contains(toDayIndex),
              allowedDayIndexes.map({ $0.contains(toDayIndex) }) ?? true,
              selection.dayIndex != toDayIndex,
              let sourceWorkout = workout(in: draft, selection: selection),
              let week = draft.weeks.first(where: { $0.weekNumber == selection.weekNumber }),
              let destination = week.days.first(where: { $0.dayIndex == toDayIndex }),
              destination.sessions.isEmpty else {
            return nil
        }

        let updatedWeeks = draft.weeks.map { week -> AIProgramDraftWeek in
            guard week.weekNumber == selection.weekNumber else { return week }
            let days = week.days.map { day -> AIProgramDraftDay in
                var sessions = day.sessions
                if day.dayIndex == selection.dayIndex {
                    sessions.remove(at: selection.sessionIndex)
                } else if day.dayIndex == toDayIndex {
                    sessions.append(sourceWorkout)
                }
                return AIProgramDraftDay(
                    dayIndex: day.dayIndex,
                    title: day.title,
                    sessions: sessions
                )
            }
            return AIProgramDraftWeek(
                weekNumber: week.weekNumber,
                title: week.title,
                days: days
            )
        }
        return AIProgramDraft(
            title: draft.title,
            summary: draft.summary,
            weeks: updatedWeeks
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Coach proposal editing uses the exact same Basic/Advanced ATHLTH
/// workout planner as Plan Studio and Quick Train. This is not a second
/// editor with a parallel exercise or interval model.
struct ATHLTHPlanDraftWorkoutEditor: View {
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    let workout: AIProgramDraftSession
    let selection: ATHLTHPlanDraftWorkoutSelection
    /// Return false to keep the shared planner open if the proposed change
    /// fails validation. Only the in-memory Coach draft is modified.
    let onSave: (AIProgramDraftSession) -> Bool

    var body: some View {
        let original = workout.makePlannedSession(
            exerciseLibrary: exerciseLibrary.selectableExercises
        )
        let sourceBlocks = ATHLTHUnifiedWorkout.editorBlocks(from: original)
        let activity = ATHLTHPlannedWorkoutType(rawValue: workout.kind) ?? .custom

        WorkoutTemplateBuilderView(
            initialTitle: original.title,
            initialBlocks: sourceBlocks,
            initialRouteID: original.routeID,
            initialDurationOverrideMinutes: original.durationMinutes,
            draftContext: "coach-proposal-" + selection.id,
            initialActivity: activity,
            initialStudioAdvanced: false,
            onSaveToPlan: { name, blocks, routeID, minutes, _, extras in
                let cleanTitle = name.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !cleanTitle.isEmpty,
                      blocks.contains(where: {
                          $0.kind == .run || $0.kind == .exercise
                      }),
                      let duration = minutes ?? original.durationMinutes,
                      (1...240).contains(duration) else {
                    return false
                }

                // Preserve the original in-memory proposal (including its
                // exercises and privacy), then replace ONLY its editable
                // workout recipe. The shared engine assigns real categories,
                // chronological phases, set pauses and execution metadata.
                var edited = original
                ATHLTHUnifiedWorkout.apply(
                    blocks: blocks, title: cleanTitle, routeID: routeID,
                    estimatedMinutes: duration, to: &edited
                )
                edited.gearIDs = extras.gearIDs
                edited.spotifyPlaylist = extras.spotifyPlaylist
                edited.spotifyAutoplayOnStart = extras.spotifyAutoplayOnStart
                edited.spotifyIntervalTrack = extras.spotifyIntervalTrack
                edited.audioCoachConfiguration = extras.audioCoachConfiguration
                edited.routeAlertConfiguration = extras.routeAlertConfiguration
                edited.ghostTargetDurationSeconds = extras.ghostTargetDurationSeconds
                edited.ghostUpdates = extras.ghostUpdates

                var updated = AIProgramDraftSession(
                    title: edited.title, kind: edited.kind.rawValue,
                    durationMinutes: edited.durationMinutes,
                    targetDistanceKilometers: edited.targetDistanceKilometers,
                    targetPaceSecondsPerKilometer:
                        edited.targetPaceSecondsPerKilometer,
                    notes: edited.notes, exercises: []
                )
                updated.authoredWorkout = edited
                return onSave(updated)
            },
            saveButtonTitle: ATHLTHLocalization.choose(
                english: "Save to Coach draft", norwegian: "Lagre i Coach-utkast"
            )
        )
        .preferredColorScheme(.light)
    }
}
