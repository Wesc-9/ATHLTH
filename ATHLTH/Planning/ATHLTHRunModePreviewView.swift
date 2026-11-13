import MapKit
import SwiftUI

/// A truthful map and session overview shared by Quick Train and planning.
/// A route line appears only when the user has selected a saved route.
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
            if environment == .outdoor {
                if let route {
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
                } else {
                    // Use the device's map position if already authorized.
                    // Never infer a GPS trace before an unscripted run starts.
                    Map(initialPosition: .userLocation(fallback: .automatic)) {
                        UserAnnotation()
                    }
                    .mapControlVisibility(.hidden)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .frame(height: 152)
                    .overlay(alignment: .bottomLeading) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "GPS route recorded during the workout",
                                norwegian: "GPS-ruten registreres under økten"
                            ),
                            systemImage: "location"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ink)
                        .padding(9)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
                        .padding(9)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .accessibilityIdentifier("athlth-planned-run-location-map")
                }
            } else {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Map preview is available for outdoor workouts",
                        norwegian: "Kartvisning er tilgjengelig for utendørsøkter"
                    ),
                    systemImage: "map"
                )
                .font(.caption)
                .foregroundStyle(ink.opacity(0.7))
            }

            if mode == .route && route == nil {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Choose a saved route to preview its path",
                        norwegian: "Velg en lagret rute for å se rutelinjen"
                    ),
                    systemImage: "map"
                )
                .font(.caption)
                .foregroundStyle(ink.opacity(0.7))
            } else if mode == .structured && !isGoalSelected {
                Label(
                    workoutTitle ?? ATHLTHLocalization.choose(
                        english: "Workout overview", norwegian: "Øktoversikt"
                    ),
                    systemImage: "list.bullet.rectangle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(bronze)
                if steps.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose a workout to see intervals and phases.",
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
                                for: step, workoutTitle: workoutTitle ?? "",
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
                            english: "+ \(steps.count - 3) more parts",
                            norwegian: "+ \(steps.count - 3) flere deløkter"
                        ))
                        .font(.caption2)
                        .foregroundStyle(ink.opacity(0.65))
                    }
                }
            } else if mode == .free || isGoalSelected {
                Label(
                    isGoalSelected
                        ? ATHLTHLocalization.choose(
                            english: "Goal-based run: follow your chosen target",
                            norwegian: "Målstyrt løping: følg målet du velger"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Free run: GPS draws your route as you run",
                            norwegian: "Fri løping: GPS tegner ruten mens du løper"
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
