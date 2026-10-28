import Charts
import SwiftUI

struct ATHLTHExerciseProgressView: View {
    let progress: ATHLTHExerciseProgress.Summary

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(tr("YOUR PROGRESS", "DIN FREMGANG"),
                      systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Spacer()
                if let date = progress.lastTrained {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }

            if progress.uses == 0 {
                Text(tr(
                    "No completed working sets for this exercise yet. Your first recorded session will appear here.",
                    "Ingen gjennomførte arbeidssett registrert på denne øvelsen ennå. Første gjennomføring vises her."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                    statistic(tr("Times trained", "Ganger trent"),
                              value: "\(progress.uses)", symbol: "repeat")
                    statistic(tr("Completed sets", "Fullførte sett"),
                              value: "\(progress.totalSets)", symbol: "checkmark.circle")
                    statistic(tr("Repetitions", "Repetisjoner"),
                              value: "\(progress.totalRepetitions)", symbol: "number")
                    statistic(tr("Total recorded volume", "Registrert totalvolum"),
                              value: String(format: "%.0f kg", progress.totalVolume),
                              symbol: "scalemass")
                }

                if let best = progress.bestWeight {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(tr("Highest recorded working weight",
                                "Høyeste registrerte arbeidsvekt"))
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.1f kg", best))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if let change = progress.firstToLastWeightChange {
                    HStack {
                        Text(tr("First to latest session", "Første til siste økt"))
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%+.1f kg", change))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                }
                let weightPoints = progress.sessions.filter {
                    $0.highestWeightKilograms != nil
                }
                if weightPoints.count >= 2 {
                    Text(tr("Recorded working weight", "Registrert arbeidsvekt"))
                        .font(.caption.weight(.semibold))
                    Chart(weightPoints) { item in
                        if let weight = item.highestWeightKilograms {
                            LineMark(x: .value("Date", item.date),
                                     y: .value("kg", weight))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            PointMark(x: .value("Date", item.date),
                                      y: .value("kg", weight))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                    }
                    .frame(height: 148)
                    .chartYAxis { AxisMarks(position: .leading) }
                } else if progress.sessions.count >= 2 {
                    Text(tr("Completed reps per session",
                            "Fullførte repetisjoner per økt"))
                        .font(.caption.weight(.semibold))
                    Chart(progress.sessions) { item in
                        BarMark(x: .value("Date", item.date),
                                y: .value("Reps", item.repetitions))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                    .frame(height: 148)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("Recent sessions", "Siste gjennomføringer"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(progress.sessions.suffix(5).reversed())) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.date.formatted(date: .abbreviated,
                                                         time: .omitted))
                                    .font(.caption.weight(.semibold))
                                Text(item.workoutTitle)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer(minLength: 8)
                            Text("\(item.completedSets) " +
                                 tr("sets", "sett") + " · " +
                                 "\(item.repetitions) " + tr("reps", "reps"))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        Divider().opacity(0.4)
                    }
                }
            }
            Text(tr(
                "Based only on finished, logged working sets. Planned loads and warm-up sets are not counted.",
                "Kun basert på fullførte, registrerte arbeidssett. Planlagte vekter og oppvarmingssett telles ikke."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(15)
        .athlthPlanCard(radius: 19)
    }

    private func statistic(_ label: String, value: String,
                           symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(2)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(11)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 13))
    }
}
