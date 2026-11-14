import Charts
import SwiftUI

/// A compact, low-noise progress footer for the exercise detail.
/// Full charts and recent sessions remain available, but are not expanded
/// in front of technique instructions or on first opening the exercise.
struct ATHLTHExerciseProgressView: View {
    let progress: ATHLTHExerciseProgress.Summary
    @State private var showingHistory = false

    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk
    private let gold = ATHLTHPlanDesign.accentInk

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(gold)
                    .frame(width: 3, height: 19)
                    .accessibilityHidden(true)
                Text(tr("Your progress", "Din fremgang"))
                    .font(.system(size: 21, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chart.xyaxis.line")
                    .font(.subheadline)
                    .foregroundStyle(gold)
                    .accessibilityHidden(true)
            }

            if progress.uses == 0 {
                Text(tr(
                    "No completed working sets registered yet.",
                    "Ingen fullførte arbeidssett registrert ennå."
                ))
                .font(.subheadline)
                .foregroundStyle(dim)
            } else {
                HStack(spacing: 8) {
                    statistic(tr("Sessions", "Økter"),
                              value: "\(progress.uses)")
                    statistic(tr("Sets", "Sett"),
                              value: "\(progress.totalSets)")
                    statistic(tr("Reps", "Reps"),
                              value: "\(progress.totalRepetitions)")
                }

                // For sit-ups and other bodyweight movements, zero kg is not
                // a meaningful performance metric. Show weight only when a
                // positive load was actually logged.
                if progress.hasMeaningfulLoad {
                    HStack(spacing: 7) {
                        Image(systemName: "trophy")
                            .foregroundStyle(gold)
                            .font(.caption)
                        if let best = progress.bestWeight {
                            Text(tr("Highest weight", "Høyeste vekt"))
                                .foregroundStyle(dim)
                            Text(String(format: "%.1f kg", best))
                                .fontWeight(.semibold)
                                .foregroundStyle(ink)
                        }
                        Spacer(minLength: 5)
                        if progress.totalVolume > 0 {
                            Text(tr("Volume", "Volum"))
                                .foregroundStyle(dim)
                            Text(String(format: "%.0f kg", progress.totalVolume))
                                .fontWeight(.semibold)
                                .foregroundStyle(ink)
                        }
                    }
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 5)
                }

                DisclosureGroup(isExpanded: $showingHistory) {
                    VStack(alignment: .leading, spacing: 13) {
                        if let change = progress.firstToLastWeightChange {
                            HStack(spacing: 8) {
                                Text(tr("First to latest session", "Første til siste økt"))
                                    .foregroundStyle(dim)
                                Spacer()
                                Text(String(format: "%+.1f kg", change))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(gold)
                            }
                            .font(.caption)
                        }

                        let weighted = progress.sessions.filter {
                            $0.highestWeightKilograms != nil
                        }
                        if weighted.count >= 2 {
                            Text(tr("Working weight", "Arbeidsvekt"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                            Chart(weighted) { item in
                                if let weight = item.highestWeightKilograms {
                                    LineMark(
                                        x: .value("Date", item.date),
                                        y: .value("kg", weight)
                                    )
                                    .foregroundStyle(gold)
                                    PointMark(
                                        x: .value("Date", item.date),
                                        y: .value("kg", weight)
                                    )
                                    .foregroundStyle(gold)
                                }
                            }
                            .frame(height: 118)
                            .chartYAxis { AxisMarks(position: .leading) }
                        } else if progress.sessions.count >= 2 {
                            Text(tr("Reps per session", "Reps per økt"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                            Chart(progress.sessions) { item in
                                BarMark(
                                    x: .value("Date", item.date),
                                    y: .value("Reps", item.repetitions)
                                )
                                .foregroundStyle(gold)
                            }
                            .frame(height: 118)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("Recent sessions", "Siste gjennomføringer"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            ForEach(Array(progress.sessions.suffix(5).reversed())) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.date.formatted(
                                            date: .abbreviated, time: .omitted
                                        ))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ink)
                                        Text(item.workoutTitle)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .foregroundStyle(dim)
                                    }
                                    Spacer(minLength: 5)
                                    Text("\(item.completedSets) " +
                                         tr("sets", "sett") + " · " +
                                         "\(item.repetitions) reps")
                                        .font(.caption2)
                                        .foregroundStyle(dim)
                                }
                                Divider().opacity(0.35)
                            }
                        }
                        Text(tr(
                            "Based on completed recorded working sets; planned loads and warm-up sets are excluded.",
                            "Kun registrerte arbeidssett. Planlagte vekter og oppvarmingssett telles ikke."
                        ))
                        .font(.caption2)
                        .foregroundStyle(dim)
                    }
                    .padding(.top, 10)
                } label: {
                    HStack {
                        Text(tr("History and development", "Historikk og utvikling"))
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 0)
                        Text("\(progress.uses)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(dim)
                    }
                    .foregroundStyle(gold)
                    .frame(minHeight: 40)
                }
                .tint(gold)
                .accessibilityIdentifier("athlth-exercise-progress-history")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainPaper()
        .accessibilityIdentifier("athlth-exercise-progress-footer")
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(dim)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 14))
    }
}
