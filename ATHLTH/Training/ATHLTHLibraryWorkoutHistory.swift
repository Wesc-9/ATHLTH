import Foundation
import SwiftUI

/// History is private to the exact workout identity. Saving or editing a
/// personal copy must never make its completion appear on the library master.
enum ATHLTHLibraryWorkoutHistory {
    struct Summary: Equatable {
        let date: Date
        let result: String?
    }

    /// An unmodified catalogue workout is recorded using its stable catalogue
    /// ID. Never match a personal copy by template ID or by title.
    static func catalogOriginal(
        id: UUID, completions: [StructuredWorkoutCompletion]
    ) -> Summary? {
        let latest = completions
            .filter { $0.sourceWorkoutID == id && $0.sourcePlanID == nil }
            .max { $0.endedAt < $1.endedAt }
        return latest.map { structuredSummary($0) }
    }

    static func savedWorkout(
        id: UUID, completions: [StructuredWorkoutCompletion]
    ) -> Summary? {
        completions.filter { $0.sourceWorkoutID == id }
            .max { $0.endedAt < $1.endedAt }
            .map { structuredSummary($0) }
    }

    static func running(
        id: UUID, records: [ATHLTHCompletedRunningPerformance]
    ) -> Summary? {
        // An identical title, or sharedSourceWorkoutID, is not evidence of an
        // identical workout. Especially important for edited My Workouts copies.
        guard let record = records.filter({ $0.workoutID == id })
            .max(by: { $0.completedAt < $1.completedAt }) else { return nil }
        let speed = record.averageWorkSpeed
        let result: String?
        if let speed, speed.isFinite, speed > 0 {
            let seconds = Int((3_600 / speed).rounded())
            result = ATHLTHLocalization.choose(
                english: "Recorded pace", norwegian: "Registrert tempo"
            ) + String(format: " · %d:%02d min/km", seconds / 60, seconds % 60)
        } else {
            result = nil
        }
        return Summary(date: record.completedAt, result: result)
    }

    static func strengthExercise(
        id: UUID, canonicalName: String, isCustom: Bool,
        workouts: [StrengthWorkoutLog]
    ) -> Summary? {
        let exactName = ATHLTHExerciseReferenceResolver.key(canonicalName)
        var latest: (date: Date, count: Int, maxWeight: Double?)?
        for workout in workouts where workout.isFinished {
            for exercise in workout.exercises {
                let matchesIdentity = exercise.plannedExerciseID == id
                let matchesLegacyName = !isCustom &&
                    exercise.plannedExerciseID == nil &&
                    ATHLTHExerciseReferenceResolver.key(exercise.exercise.name) == exactName
                guard matchesIdentity || matchesLegacyName else { continue }
                let completed = exercise.sets.filter(\.isCompleted)
                guard !completed.isEmpty else { continue }
                let date = exercise.completedAt ??
                    completed.compactMap(\.completedAt).max() ??
                    workout.endedAt ?? workout.startedAt
                let maximum = completed.compactMap(\.completedWeightKilograms)
                    .filter { $0.isFinite && $0 > 0 }.max()
                if latest == nil || date > latest!.date {
                    latest = (date, completed.count, maximum)
                }
            }
        }
        guard let latest else { return nil }
        var result = ATHLTHLocalization.counted(
            latest.count, englishSingular: "set", englishPlural: "sets",
            norwegianSingular: "sett", norwegianPlural: "sett"
        )
        if let weight = latest.maxWeight {
            result += String(format: " · %.1f kg", weight)
        }
        return Summary(date: latest.date, result: result)
    }

    private static func structuredSummary(_ item: StructuredWorkoutCompletion) -> Summary {
        let description = ATHLTHLocalization.choose(
            english: "\(item.completedBlockCount)/\(item.totalBlockCount) steps",
            norwegian: "\(item.completedBlockCount)/\(item.totalBlockCount) øktdeler"
        )
        return Summary(date: item.endedAt, result: description)
    }
}

/// Compact metadata for browsing; full history context lives on the detail page.
/// A blank library session has no badge instead of an invented completion.
struct ATHLTHLastWorkoutHistoryLabel: View {
    let summary: ATHLTHLibraryWorkoutHistory.Summary

    var body: some View {
        Label {
            Text(ATHLTHLocalization.choose(
                english: "Last trained", norwegian: "Sist trent"
            ) + " · " + summary.date.formatted(date: .abbreviated, time: .omitted))
                .lineLimit(1)
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(ATHLTHPlanDesign.accentInk)
        .accessibilityElement(children: .combine)
    }
}

struct ATHLTHLastWorkoutHistoryCard: View {
    let summary: ATHLTHLibraryWorkoutHistory.Summary?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary == nil ? "clock" : "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 40, height: 40)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                Text(ATHLTHLocalization.choose(
                    english: "LAST SESSION", norwegian: "SIST GJENNOMFØRT"
                ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                if let summary {
                    Text(summary.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    if let result = summary.result {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "No previous session for this workout.",
                        norwegian: "Ingen tidligere gjennomføring av denne økten."
                    ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .athlthPlanCard(radius: 19)
    }
}
