import Foundation

/// The generator may only consider exercises present in this athlete's
/// loaded ATHLTH exercise library. "Mine øvelser" is the account-local custom
/// section; the full library also includes bundled ATHLTH/RepDB exercises.
enum StrengthAIExerciseSourceFilter: String, CaseIterable, Identifiable {
    case library
    case mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            ATHLTHLocalization.choose(
                english: "Full library", norwegian: "Hele biblioteket"
            )
        case .mine:
            ATHLTHLocalization.choose(
                english: "My exercises", norwegian: "Mine øvelser"
            )
        }
    }
}

/// Pure, testable allow-list policy used at request, preview and apply time.
/// The service also validates model IDs against the submitted candidates.
/// A renamed exercise never acquires identity by matching its display name.
enum StrengthAIExerciseSelectionPolicy {
    static func available(
        from library: [ExerciseLibraryEntry],
        excluding existingIDs: Set<UUID>,
        source: StrengthAIExerciseSourceFilter,
        focus: String?,
        equipment: String?
    ) -> [ExerciseLibraryEntry] {
        library.filter { entry in
            guard !existingIDs.contains(entry.id),
                  entry.exercise.snapshot.defaultStrengthTargetKind == .reps
            else { return false }

            if source == .mine && entry.source != .custom { return false }

            if let equipment, !equipment.isEmpty,
               !entry.exercise.equipment.contains(where: {
                   $0.localizedCaseInsensitiveCompare(equipment) == .orderedSame
               }) {
                return false
            }

            if let focus, !focus.isEmpty {
                let target = ExerciseLibraryStore.canonicalMuscleFilter(focus)
                let groups = [entry.bodyPart].compactMap { $0 } +
                    entry.exercise.primaryMuscles +
                    entry.exercise.secondaryMuscles
                guard groups.contains(where: {
                    ExerciseLibraryStore.canonicalMuscleFilter($0) == target
                }) else { return false }
            }

            return true
        }
        .sorted { left, right in
            if left.source != right.source {
                if left.source == .custom { return true }
                if right.source == .custom { return false }
                if left.source == .athlthCatalog { return true }
                if right.source == .athlthCatalog { return false }
            }
            return left.canonicalName.localizedCaseInsensitiveCompare(
                right.canonicalName
            ) == .orderedAscending
        }
    }

    static func verified(
        _ exercises: [StrengthAIExerciseSuggestion],
        allowedIDs: Set<UUID>,
        existingIDs: Set<UUID>,
        requiredCount: Int
    ) -> Bool {
        guard requiredCount > 0, exercises.count == requiredCount else {
            return false
        }
        let ids = exercises.map(\.exerciseID)
        return Set(ids).count == ids.count &&
            ids.allSatisfy {
                allowedIDs.contains($0) && !existingIDs.contains($0)
            }
    }
}
