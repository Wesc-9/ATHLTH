import SwiftUI

/// A compact, truthful preview of the currently selected running mode.
/// Only a saved GPS route has a map; free running records the route live.
struct ATHLTHRunModePreviewView: View {
    let mode: RunQuickStartMode
    let environment: RunEnvironment
    let route: TrainingRoute?
    let workoutTitle: String?
    let steps: [WorkoutTemplateBlock]
    let isGoalSelected: Bool
    let isGhostSelected: Bool

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if environment == .outdoor, mode == .route, let route {
                RouteMapSnapshotThumbnail(route: route, height: 152)
                    .accessibilityIdentifier("athlth-planned-run-route-map")
                HStack(spacing: 12) {
                    Label(route.title, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(route.distanceKilometers, format: .number.precision(.fractionLength(1)))
                        + Text(" km")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ink)
            } else if mode == .route {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Select a saved route to preview the map",
                        norwegian: "Velg en lagret rute for å se kartet"
                    ),
                    systemImage: "map"
                )
                .font(.caption)
                .foregroundStyle(ink.opacity(0.7))
            } else if mode == .structured, !isGoalSelected {
                Label(
                    workoutTitle ??
                        ATHLTHLocalization.choose(
                            english: "Workout overview", norwegian: "Øktoversikt"
                        ),
                    systemImage: "list.bullet.rectangle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(bronze)
                if steps.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose a workout to see its intervals and phases.",
                        norwegian: "Velg en treningsøkt for å se intervaller og deløkter."
                    ))
                    .font(.caption)
                    .foregroundStyle(ink.opacity(0.7))
                } else {
                    ForEach(Array(steps.prefix(3))) { step in
                        HStack(spacing: 7) {
                            Image(systemName: step.kind.systemImage)
                                .foregroundStyle(bronze)
                                .frame(width: 18)
                            Text(ATHLTHWorkoutStepCopy.title(
                                for: step,
                                workoutTitle: workoutTitle ?? "",
                                compact: true
                            ))
                            .lineLimit(1)
                            Spacer(minLength: 3)
                            if let seconds = step.durationSeconds, seconds > 0 {
                                Text(ATHLTHWorkoutDurationEstimator.conciseDuration(seconds))
                                    .monospacedDigit()
                                    .foregroundStyle(ink.opacity(0.65))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(ink)
                    }
                    if steps.count > 3 {
                        Text(ATHLTHLocalization.choose(
                            english: "+ \\(steps.count - 3) more parts",
                            norwegian: "+ \\(steps.count - 3) flere deløkter"
                        ))
                        .font(.caption2)
                        .foregroundStyle(ink.opacity(0.65))
                    }
                }
            } else {
                Label(
                    isGoalSelected
                        ? ATHLTHLocalization.choose(
                            english: "Goal-based run: follow the target set below",
                            norwegian: "Målstyrt løping: følg målet du velger nedenfor"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Free run: your GPS route is recorded as you run",
                            norwegian: "Fri løping: GPS-ruten registreres under økten"
                        ),
                    systemImage: isGoalSelected ? "target" : "location"
                )
                .font(.caption)
                .foregroundStyle(ink.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("athlth-basic-run-mode-preview")
    }
}
