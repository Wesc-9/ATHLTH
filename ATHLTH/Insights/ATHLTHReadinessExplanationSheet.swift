import SwiftUI

/// Read-only explanation of exactly the score displayed in Insights.
/// Mirrors RecoveryReadinessEngine's 45/35/20 calculations; all values
/// stay on device, with no AI call, new permissions or additional score.
struct ATHLTHReadinessExplanationSheet: View {
    let recovery: RecoveryReadinessSummary
    let sleep: SleepSummary
    let heart: HeartSummary

    @Environment(\.dismiss) private var dismiss

    private var sleepRatio: Double? {
        guard sleep.totalAsleep.isFinite, sleep.totalAsleep > 0,
              let avg = recovery.averageSleepDuration,
              avg.isFinite, avg > 0 else { return nil }
        return min(max(sleep.totalAsleep / max(avg, 7.5 * 3600), 0), 1)
    }

    private var hrvRatio: Double? {
        guard let current = heart.hrvMilliseconds, current.isFinite,
              let avg = recovery.baselineHRVMilliseconds,
              avg.isFinite, avg > 0 else { return nil }
        return min(max(current / avg, 0), 1)
    }

    private var heartRatio: Double? {
        guard let current = heart.restingHeartRate, current.isFinite, current > 0,
              let avg = recovery.baselineRestingHeartRate,
              avg.isFinite, avg > 0 else { return nil }
        return min(max(avg / current, 0), 1)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    if let diagnostics = recovery.diagnostics {
                        coverageCard(diagnostics)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("What makes up your score",
                                "Slik beregnes scoren"))
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                        Text(tr(
                            "Three measured signals are compared with your own recent baseline. Their contributions are weighted, then rounded to a score out of 100.",
                            "Tre målte signaler sammenlignes med din personlige normal. Bidragene vektes og rundes av til en score av 100."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                    }

                    factorCard(
                        name: tr("Sleep", "Søvn"), icon: "moon.stars.fill",
                        weight: 45, factor: sleepRatio,
                        current: sleep.totalAsleep > 0
                            ? String(format: "%.1f t", sleep.totalAsleep / 3600) : "—",
                        baseline: recovery.averageSleepDuration.map {
                            String(format: "%.1f t", $0 / 3600)
                        } ?? "—",
                        color: Color(red: 0.51, green: 0.45, blue: 0.70),
                        explanation: tr(
                            "Relative to the higher of your normal sleep and 7.5 hours.",
                            "Sammenlignes med det høyeste av din normalsøvn og 7,5 timer."
                        )
                    )

                    factorCard(
                        name: "HRV", icon: "waveform.path.ecg",
                        weight: 35, factor: hrvRatio,
                        current: heart.hrvMilliseconds.map {
                            String(format: "%.0f ms", $0)
                        } ?? "—",
                        baseline: recovery.baselineHRVMilliseconds.map {
                            String(format: "%.0f ms", $0)
                        } ?? "—",
                        color: Color(red: 0.34, green: 0.56, blue: 0.61),
                        explanation: tr(
                            "Your most recent HRV compared with your baseline.",
                            "Siste registrerte HRV sammenlignet med din normalverdi."
                        )
                    )

                    factorCard(
                        name: tr("Resting heart rate", "Hvilepuls"),
                        icon: "heart.fill",
                        weight: 20, factor: heartRatio,
                        current: heart.restingHeartRate.map {
                            String(format: "%.0f bpm", $0)
                        } ?? "—",
                        baseline: recovery.baselineRestingHeartRate.map {
                            String(format: "%.0f bpm", $0)
                        } ?? "—",
                        color: Color(red: 0.70, green: 0.42, blue: 0.43),
                        explanation: tr(
                            "Lower resting HR relative to baseline helps the score.",
                            "Lavere hvilepuls enn normalt bidrar positivt."
                        )
                    )

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(tr(
                            "Each factor is capped at its weight. This is a training guidance indicator, not a diagnosis. Your reported fatigue or soreness may still call for an easier day.",
                            "Hver faktor er begrenset til sin andel av scoren. Dette er treningsveiledning, ikke en diagnose. Opplevd slitenhet eller stølhet kan likevel tilsi en roligere dag."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(15)
                    .background(ATHLTHInsightsStyle.canvas,
                                in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(19)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHInsightsStyle.canvas.ignoresSafeArea())
            .navigationTitle(tr("Readiness details", "Detaljer om dagsform"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(ATHLTHInsightsStyle.track, lineWidth: 9)
                    Circle()
                        .trim(from: 0,
                              to: CGFloat(recovery.score ?? 0) / 100)
                        .stroke(ATHLTHInsightsStyle.accent,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(recovery.score.map(String.init) ?? "—")
                        .font(.system(size: 38, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                        .monospacedDigit()
                }
                .frame(width: 113, height: 113)

                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("YOUR READINESS", "DIN DAGSFORM"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                    Text(readinessTitle)
                        .font(.system(size: 27, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                    Text(tr("Out of 100", "Av 100 mulige"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                }
            }
            Text(tr("Calculated locally from Apple Health data",
                    "Beregnet lokalt fra Apple Health-data"))
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthInsightsSurface()
    }

    /// Show the exact reason a score is unavailable, without displaying
    /// fabricated numbers or asking users to re-authorize all Health data.
    private func coverageCard(
        _ diagnostic: RecoveryReadinessDiagnostics
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Health data coverage", "Dekning av helsedata"))
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Spacer(minLength: 8)
                Text("\(diagnostic.completeDays)/\(diagnostic.requiredDays)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
            }

            Text(tr(
                "Days with all three measurements in the last \(diagnostic.lookbackDays) days.",
                "Dager med alle tre målinger de siste \(diagnostic.lookbackDays) dagene."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)

            HStack(spacing: 8) {
                coverageMetric(
                    .sleep,
                    count: diagnostic.sleepDays,
                    window: diagnostic.lookbackDays,
                    failed: diagnostic.failedSignals.contains(.sleep)
                )
                coverageMetric(
                    .hrv,
                    count: diagnostic.hrvDays,
                    window: diagnostic.lookbackDays,
                    failed: diagnostic.failedSignals.contains(.hrv)
                )
                coverageMetric(
                    .restingHeartRate,
                    count: diagnostic.restingHeartRateDays,
                    window: diagnostic.lookbackDays,
                    failed: diagnostic.failedSignals.contains(.restingHeartRate)
                )
            }

            if recovery.score == nil {
                Text(recovery.detail)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("athlth-readiness-missing-data-reason")
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(tr("Most recent measurements", "Nyeste målinger"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)

                recentSignalRow(.sleep, current: diagnostic.recentSleep)
                recentSignalRow(.hrv, current: diagnostic.recentHRV)
                recentSignalRow(
                    .restingHeartRate,
                    current: diagnostic.recentRestingHeartRate
                )
            }

            if recovery.score == nil {
                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("Last 7 completed days", "Siste 7 avsluttede dager"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)

                    ForEach(diagnostic.lastSevenDays, id: \.date) { day in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(day.date.formatted(
                                .dateTime.day().month(.abbreviated)
                            ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                            .frame(width: 60, alignment: .leading)

                            Spacer(minLength: 8)

                            Text(day.missingSignals.isEmpty
                                 ? tr("Complete", "Komplett")
                                 : tr("Missing: ", "Mangler: ") +
                                   day.missingSignals.map(\.title)
                                        .joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(ATHLTHInsightsStyle.muted)
                            .multilineTextAlignment(.trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Text(tr(
                    "Pull down in Insights to refresh. A score appears automatically when at least five complete days and fresh measurements are available.",
                    "Dra ned i Innsikt for å oppdatere. Dagsform beregnes automatisk når fem komplette dager og ferske målinger er tilgjengelige."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .athlthInsightsSurface()
        .accessibilityIdentifier("athlth-readiness-data-coverage")
    }

    private func coverageMetric(
        _ signal: RecoveryReadinessSignal,
        count: Int,
        window: Int,
        failed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(signal.title)
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(failed
                 ? tr("Read error", "Lesefeil")
                 : "\(count)/\(window)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ATHLTHInsightsStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            ATHLTHInsightsStyle.canvas,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func recentSignalRow(
        _ signal: RecoveryReadinessSignal,
        current: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: current ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(ATHLTHInsightsStyle.accent)
                .accessibilityHidden(true)
            Text(signal.title)
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            Spacer(minLength: 8)
            Text(current
                 ? tr("Within 48 hours", "Innen 48 timer")
                 : tr("Missing or older", "Mangler eller er eldre"))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var readinessTitle: String {
        switch recovery.state {
        case .ready: return tr("Strong", "Sterk")
        case .balanced: return tr("Balanced", "Balansert")
        case .takeItEasy: return tr("Take it easy", "Ta det rolig")
        case .recover: return tr("Recover", "Restitusjon")
        case .buildingBaseline: return tr("Learning", "Kartlegger")
        }
    }

    private func factorCard(
        name: String, icon: String, weight: Int,
        factor: Double?, current: String, baseline: String,
        color: Color, explanation: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 11))
                Text(name)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Spacer(minLength: 0)
                Text("\(weight)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Measured", "Målt"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                    Text(current)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tr("Your baseline", "Din normal"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                    Text(baseline)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(ATHLTHInsightsStyle.ink)

            GeometryReader { geo in
                Capsule().fill(ATHLTHInsightsStyle.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: geo.size.width *
                                   CGFloat(factor ?? 0))
                    }
            }
            .frame(height: 8)

            HStack {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                Spacer(minLength: 4)
                Text(factor.map {
                    String(format: "%.1f/%d", $0 * Double(weight), weight)
                } ?? "—")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
            }
        }
        .padding(17)
        .athlthInsightsSurface()
    }
}
