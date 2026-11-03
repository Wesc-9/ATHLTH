import SwiftUI

/// A read-only confirmation of the exact ordered recipe that iPhone/Watch
/// will execute. Never writes, changes, or starts a workout.
struct ATHLTHWorkoutReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let title: String
    let blocks: [WorkoutTemplateBlock]
    let routeTitle: String?
    let fallbackDurationMinutes: Int?

    private var steps: [WorkoutTemplateBlock] {
        blocks.expandedForExecution()
    }
    private var elapsed: Double? {
        ATHLTHWorkoutDurationEstimator.previewSeconds(for: blocks)
    }
    private var estimatedKilometers: Double? {
        ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(for: blocks)
    }
    private var location: String? {
        guard let value = ATHLTHPlannedWorkoutMetrics.runningLocation(for: blocks)
        else { return nil }
        switch value {
        case .outdoor: return tr("Outdoor", "Ute")
        case .indoor: return tr("Indoor", "Innendørs")
        case .treadmill: return tr("Treadmill", "Tredemølle")
        case .mixed: return tr("Mixed environment", "Ute og inne")
        }
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(tr("WORKOUT REVIEW", "GJENNOMGANG"))
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                        if let location {
                            Label(location, systemImage: "figure.run")
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                        }
                        if let routeTitle {
                            Label(routeTitle, systemImage: "map")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        statistic(
                            tr("Duration", "Varighet"),
                            elapsed.map {
                                "~" + ATHLTHWorkoutDurationEstimator.conciseDuration($0)
                            } ?? fallbackDurationMinutes.map { "~\($0) min" } ?? "–",
                            symbol: "clock"
                        )
                        statistic(
                            tr("Distance", "Distanse"),
                            estimatedKilometers.map {
                                "~" + $0.formatted(
                                    .number.precision(.fractionLength(1)).locale(locale)
                                ) + " km"
                            } ?? "–",
                            symbol: "point.topleft.down.to.point.bottomright.curvepath"
                        )
                    }

                    Text(tr(
                        "Only explicitly entered pace and speed targets are used for distance. Unknown targets are not counted as a measured result.",
                        "Distansen beregnes bare når nødvendige tempo- og fartsmål er kjent. Ukjente mål er ikke et registrert resultat."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(ATHLTHWorkoutTimelinePresentation.sections(for: steps)) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(section.phase.title, systemImage: section.phase.symbol)
                                .font(.headline)
                                .foregroundStyle(ATHLTHTrainDesign.ink)
                            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 9) {
                                    Image(systemName: item.isRestOrActiveRecovery
                                          ? "pause.fill" : item.kind.systemImage)
                                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.isActiveRecovery
                                             ? tr("Active jogging recovery", "Aktiv joggepause")
                                             : item.kind == .rest
                                                 ? tr("Recovery", "Pause") : item.title)
                                            .font(.subheadline)
                                            .foregroundStyle(ATHLTHTrainDesign.ink)
                                        if let targets = item.targetText {
                                            Text(targets)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 3)
                                    Text(item.durationSeconds.map {
                                        ATHLTHWorkoutDurationEstimator.conciseDuration($0)
                                    } ?? item.distanceMeters.map {
                                        ($0 / 1_000).formatted(
                                            .number.precision(.fractionLength(0...2))
                                        ) + " km"
                                    } ?? "–")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(ATHLTHTrainDesign.ink)
                                }
                                .padding(.vertical, 7)
                                if item.editorDragID != section.blocks.last?.editorDragID {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                        .padding(14)
                        .background(ATHLTHPlanDesign.surface,
                                    in: RoundedRectangle(cornerRadius: 19))
                    }
                }
                .padding(16)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Review workout", "Se gjennom økten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
        }
    }

    private func statistic(_ caption: String, _ value: String,
                           symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .minimumScaleFactor(0.75)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
