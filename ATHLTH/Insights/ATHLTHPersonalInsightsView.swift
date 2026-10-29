import SwiftUI

/// The Overview shows two highlights; Development shows the complete
/// personal insight collection. Every result reveals its evidence and limits.
struct ATHLTHPersonalInsightsView: View {
    let findings: [ATHLTHPersonalInsight]
    var maxVisible: Int? = nil
    var onShowAll: (() -> Void)? = nil
    let onCheckIn: () -> Void

    @State private var selectedInsight: ATHLTHPersonalInsight?

    private var visible: [ATHLTHPersonalInsight] {
        if let maxVisible {
            return Array(findings.prefix(maxVisible))
        }
        return findings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        ATHLTHInsightsStyle.accent.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Your personal patterns",
                        norwegian: "Dine personlige sammenhenger"
                    ))
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)

                    Text(ATHLTHLocalization.choose(
                        english: "How sleep, daily life, body signals and how you feel fit together.",
                        norwegian: "Hvordan søvn, hverdagsliv, kroppssignaler og egen opplevelse henger sammen."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if findings.isEmpty {
                emptyState
            } else {
                ForEach(visible) { insight in
                    Button {
                        selectedInsight = insight
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.icon)
                                .font(.title3)
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                                .frame(width: 30, height: 30)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(insight.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                                Text(insight.explanation)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(4)
                                Text(ATHLTHLocalization.choose(
                                    english: "See measurements and context",
                                    norwegian: "Se målinger og forklaring"
                                ))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .background(
                            ATHLTHInsightsStyle.canvas,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Opens the observations supporting this pattern",
                        norwegian: "Åpner målingene bak sammenhengen"
                    ))
                }
                if let onShowAll, findings.count > visible.count {
                    Button(action: onShowAll) {
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "View all connections",
                                norwegian: "Se alle sammenhenger"
                            ))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(17)
        .athlthInsightsSurface()
        .sheet(item: $selectedInsight) { insight in
            ATHLTHPersonalInsightDetailsView(insight: insight)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(ATHLTHLocalization.choose(
                english: "Not enough overlapping observations yet",
                norwegian: "Foreløpig for få sammenlignbare målinger"
            ), systemImage: "chart.xyaxis.line")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHInsightsStyle.ink)

            Text(ATHLTHLocalization.choose(
                english: "Patterns appear when there are enough comparable days in Apple Health and, for personal wellbeing insights, daily check-ins. No patterns are invented when data is missing.",
                norwegian: "Sammenhenger vises når vi har nok sammenlignbare dager i Apple Health og, for personlige hverdagsinnsikter, daglige innsjekker. Manglende data blir ikke erstattet med gjetninger."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onCheckIn) {
                Label(ATHLTHLocalization.choose(
                    english: "Record how you feel",
                    norwegian: "Registrer hvordan du har det"
                ), systemImage: "square.and.pencil")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHInsightsStyle.accent)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            ATHLTHInsightsStyle.canvas,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

private struct ATHLTHPersonalInsightDetailsView: View {
    let insight: ATHLTHPersonalInsight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Label(insight.title, systemImage: insight.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(insight.explanation)
                        .font(.body)
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(ATHLTHLocalization.choose(
                        english: "The underlying measurements",
                        norwegian: "Målingene bak funnet"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHInsightsStyle.ink)

                    ForEach(insight.evidence, id: \.labelNO) { item in
                        HStack(spacing: 12) {
                            Text(item.label)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                            Spacer()
                            Text(item.value)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(ATHLTHInsightsStyle.ink)
                        }
                        .padding(14)
                        .background(
                            ATHLTHInsightsStyle.canvas,
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }

                    if insight.sampleCount > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Based on \(insight.sampleCount) comparable daily observations",
                                norwegian: "Basert på \(insight.sampleCount) sammenlignbare dagsmålinger"
                            ),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                    } else {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Compared with the previous 28-day period",
                                norwegian: "Sammenlignet med forrige 28-dagersperiode"
                            ),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                    }

                    Label(insight.caution, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .background(
                            ATHLTHInsightsStyle.canvas,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHInsightsStyle.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "About this insight",
                norwegian: "Om denne innsikten"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) { dismiss() }
                }
            }
        }
    }
}
