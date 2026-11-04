import SwiftUI

/// Captured at the moment the user opens the card, so the detailed sheet
/// describes the same recommendation rather than recalculating its rationale.
struct HomeDailyRecommendationInfo: Identifiable {
    let id = UUID()
    let advice: HomeDailyRecommendationPolicy.Advice
    let history: HomeTrainingPatternAdvisor.Snapshot
    let readiness: HomeDailyRecommendationPolicy.Readiness
    let trainingLoadRatio: Double?
}

/// Detailed but non-diagnostic explanation of today's recommendation.
/// Uses recorded ATHLTH / Apple Health history already available on Home.
struct HomeDailyRecommendationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let info: HomeDailyRecommendationInfo

    private var dominantPattern: HomeTrainingPatternAdvisor.Pattern? {
        info.history.patterns.values.sorted {
            if $0.count42Days != $1.count42Days {
                return $0.count42Days > $1.count42Days
            }
            return $0.activity.rawValue < $1.activity.rawValue
        }.first
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    assessmentSection
                    trainingHistorySection
                    readinessSection
                    workoutSection
                    interpretationNote
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 15)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Today's recommendation", "Dagens anbefaling"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
            }
        }
        .accessibilityIdentifier("home-daily-recommendation-info-sheet")
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 48, height: 48)
                .background(
                    ATHLTHTrainDesign.paleGold.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(tr("YOUR TRAINING TODAY", "DIN TRENING I DAG"))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)

                Text(tr(
                    "Why this recommendation?",
                    "Hvorfor anbefaler vi dette?"
                ))
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var assessmentSection: some View {
        informationCard(
            title: tr("Today's assessment", "Dagens vurdering"),
            symbol: "text.alignleft"
        ) {
            Text(info.advice.dayDescription.isEmpty
                 ? tr(
                    "There is not enough recorded information yet for a detailed explanation.",
                    "Vi har foreløpig ikke nok registrert informasjon til en detaljert forklaring."
                 )
                 : info.advice.dayDescription)
                .font(.body)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trainingHistorySection: some View {
        informationCard(
            title: tr("Your training rhythm", "Din treningsrytme"),
            symbol: "chart.bar.xaxis"
        ) {
            if let pattern = dominantPattern {
                Text(tr(
                    "We compare your recent activity with your own recorded habits, not a fixed number of sessions everyone should complete.",
                    "Vi sammenligner den siste aktiviteten din med dine egne registrerte vaner, ikke et fast antall økter alle bør gjennomføre."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)

                metricRow(
                    tr("All workouts, last 6 weeks", "Alle økter, siste 6 uker"),
                    value: "\(info.history.totalCount42Days)"
                )
                metricRow(
                    tr("Most common activity", "Vanligste aktivitet"),
                    value: activityLabel(pattern.activity)
                )
                metricRow(
                    tr("Sessions per week", "Økter per uke"),
                    value: pattern.sessionsPerWeek.formatted(
                        .number.precision(.fractionLength(1))
                    )
                )

                if let days = pattern.daysSinceLast {
                    metricRow(
                        tr("Last recorded activity", "Siste registrerte aktivitet"),
                        value: tr("\(days) days ago", "For \(days) dager siden")
                    )
                }

                if let gap = pattern.usualGapDays {
                    metricRow(
                        tr("Usual gap between activity days", "Vanlig opphold mellom treningsdager"),
                        value: tr(
                            "About \(Int(gap.rounded())) days",
                            "Ca. \(Int(gap.rounded())) dager"
                        )
                    )
                }

                metricRow(
                    tr("Typical session duration", "Typisk varighet"),
                    value: "\(pattern.usualMinutes) min"
                )
            } else {
                Text(tr(
                    "No completed workouts are available in the last six weeks. We cannot determine your usual training rhythm yet.",
                    "Ingen gjennomførte økter er registrert de siste seks ukene. Vi kan derfor ikke beregne din vanlige treningsrytme ennå."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
    }

    private var readinessSection: some View {
        informationCard(
            title: tr("Recovery and training load", "Restitusjon og belastning"),
            symbol: "waveform.path.ecg"
        ) {
            metricRow(
                tr("Available recovery signal", "Tilgjengelig restitusjonssignal"),
                value: readinessLabel
            )

            if let ratio = info.trainingLoadRatio,
               ratio.isFinite, (0...20).contains(ratio) {
                let percent = Int((ratio * 100).rounded())
                metricRow(
                    tr("Recent training minutes", "Nylige treningsminutter"),
                    value: "\(percent) %"
                )

                Text(tr(
                    "The percentage compares recent training time with your personal four-week reference. It is not a medical measure of fatigue.",
                    "Prosenten sammenligner nylig treningstid med ditt eget fireukersnivå. Den måler ikke medisinsk utmattelse."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr(
                    "There is no reliable training-load comparison available right now.",
                    "Vi har foreløpig ikke et pålitelig sammenligningsgrunnlag for treningsbelastningen."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
    }

    private var workoutSection: some View {
        informationCard(
            title: tr("Recommended workout", "Anbefalt økt"),
            symbol: "figure.run"
        ) {
            Text(info.advice.suggestedTitle)
                .font(.headline)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(info.advice.suggestedDetail)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(ATHLTHTrainDesign.rule.opacity(0.45))
                .frame(height: 0.7)

            Text(workoutRationale)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var interpretationNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .accessibilityHidden(true)

            Text(tr(
                "ATHLTH uses completed workouts from available training history. Planned or unfinished workouts and step counts are not treated as completed running sessions. Recommendations are guidance, not a health diagnosis. Adjust intensity to how you feel.",
                "ATHLTH bruker gjennomførte økter fra tilgjengelig treningshistorikk. Planlagte eller ufullførte økter og skritt regnes ikke som gjennomførte løpeturer. Anbefalingen er veiledende, ikke en helsevurdering. Tilpass innsatsen til dagsformen."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTrainDesign.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
    }

    private var readinessLabel: String {
        switch info.readiness {
        case .ready:
            return tr("Ready", "Klar")
        case .balanced:
            return tr("Balanced", "Balansert")
        case .takeItEasy:
            return tr("Take it easy", "Ta det rolig")
        case .recover:
            return tr("Recovery recommended", "Restitusjon anbefalt")
        case .unavailable:
            return tr("Not available", "Ikke tilgjengelig")
        }
    }

    private var workoutRationale: String {
        switch info.advice.suggestedWorkout {
        case .planned:
            return tr(
                "This session is already in your plan. The recommendation does not move or change the planned workout.",
                "Økten ligger allerede i planen din. Anbefalingen flytter eller endrer ikke økten."
            )
        case .easyWalk:
            return tr(
                "Keep the pace comfortable. The session is intended as light movement rather than a demanding effort.",
                "Hold et behagelig tempo. Målet er lett bevegelse fremfor en krevende økt."
            )
        case .easyRun:
            return tr(
                "The shorter, easy effort helps you return to running without assuming you are ready for high intensity.",
                "Den korte, rolige økten gjør det enklere å komme i gang igjen uten å forutsette at du er klar for høy intensitet."
            )
        case .progressiveRun:
            return tr(
                "Begin gently and only increase your pace if it feels good. Staying at an easy pace is also fine.",
                "Start rolig og øk bare farten hvis det føles bra. Du kan også holde et rolig tempo gjennom hele økten."
            )
        case .tempoRun:
            return tr(
                "The aim is controlled effort based on repeated recent running, not a maximum-intensity session.",
                "Målet er en kontrollert innsats basert på regelmessig løping, ikke en maksimaløkt."
            )
        case .historicalStrength:
            return tr(
                "This uses exercises from previous completed strength sessions. Adjust sets and weights to today's condition.",
                "Dette bygger på øvelser fra tidligere gjennomførte styrkeøkter. Tilpass sett og vekter til dagsformen."
            )
        case .restDay:
            return tr(
                "A recovery day is an option, not a requirement. A different workout is not started automatically.",
                "En restitusjonsdag er et forslag, ikke et krav. Ingen annen treningsøkt startes automatisk."
            )
        }
    }

    private func activityLabel(
        _ activity: HomeTrainingPatternAdvisor.Activity
    ) -> String {
        switch activity {
        case .running: return tr("Running", "Løping")
        case .walking: return tr("Walking", "Gåturer")
        case .strength: return tr("Strength", "Styrke")
        case .cycling: return tr("Cycling", "Sykling")
        case .other: return tr("Other", "Annet")
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func informationCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)

            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ATHLTHTrainDesign.paper,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.35),
                              lineWidth: 0.8)
        }
    }
}
