import SwiftUI

/// Read-only presentation of the saved prescription, shared by Today and Plan.
/// Estimates never become recorded metrics or modify the workout at display time.
struct ATHLTHPlannedWorkoutSummaryView: View {
    let workout: PlannedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { facts }
                VStack(alignment: .leading, spacing: 8) { facts }
            }
            if let summary = ATHLTHWorkoutContentSummary.text(for: workout) {
                Text(summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !workout.exercises.isEmpty {
                Text(workout.exercises.map { $0.embeddedExercise.name }
                    .joined(separator: " · "))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let place = workout.plannedTrainingPlace {
                Label(place.name, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !groups.isEmpty {
                Label(groups.joined(separator: " · "), systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(ATHLTHTrainDesign.secondary)
    }

    private var groups: [String] {
        var seen: Set<UUID> = []
        return workout.resolvedWorkoutBlocks.compactMap { block in
            guard let id = block.groupID, seen.insert(id).inserted,
                  let kind = block.groupKind else { return nil }
            guard let rounds = block.groupRounds, rounds > 0 else { return kind.title }
            return kind.title + " · \(rounds) " + ATHLTHLocalization.choose(
                english: "rounds", norwegian: "runder")
        }
    }

    @ViewBuilder
    private var facts: some View {
        Label(workout.kind.title, systemImage: workout.kind.systemImage)
        if let duration = ATHLTHPlannedWorkoutPresentation.duration(for: workout) {
            Label(duration, systemImage: "clock")
        }
        if let distance = workout.targetDistanceKilometers,
           distance.isFinite, distance > 0 {
            Label(String(format: "%.1f km", distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
    }
}

enum ATHLTHPlannedWorkoutPresentation {
    static func structuredMinutes(for workout: PlannedSession) -> Int? {
        let blocks = workout.resolvedWorkoutBlocks.isEmpty
            ? ATHLTHUnifiedWorkout.editorBlocks(from: workout)
            : workout.resolvedWorkoutBlocks
        return ATHLTHWorkoutDurationEstimator.minutes(for: blocks)
    }

    static func duration(for workout: PlannedSession) -> String? {
        if !workout.resolvedWorkoutBlocks.isEmpty || !workout.resolvedRunningWorkouts.isEmpty {
            guard let minutes = structuredMinutes(for: workout) else {
                return ATHLTHLocalization.choose(
                    english: "Open duration", norwegian: "Åpen varighet")
            }
            return ATHLTHLocalization.choose(
                english: "Estimated \(minutes) min", norwegian: "Estimert \(minutes) min")
        }
        guard let minutes = workout.durationMinutes, minutes > 0 else { return nil }
        return ATHLTHLocalization.choose(
            english: "Planned \(minutes) min", norwegian: "Planlagt \(minutes) min")
    }
}
