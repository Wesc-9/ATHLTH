import SwiftUI

/// Training planning sandbox: real recent weekly minutes vs a user-controlled
/// example. This deliberately does not estimate illness, readiness or fitness.
struct ATHLTHInsightsWhatIfView: View {
    let baselines: InsightsSessionBaselines
    let onAskCoach: (String) -> Void
    let onOpenTrain: () -> Void

    @State private var goal: Goal = .consistency
    @State private var weeklySessions = 4
    @State private var sessionMinutes = 45

    private enum Goal: String, CaseIterable, Identifiable {
        case consistency, fiveK, halfMarathon
        var id: String { rawValue }

        var title: String {
            switch self {
            case .consistency:
                return ATHLTHLocalization.choose(
                    english: "General", norwegian: "Generelt"
                )
            case .fiveK: return "5 km"
            case .halfMarathon:
                return ATHLTHLocalization.choose(
                    english: "Half marathon", norwegian: "Halvmaraton"
                )
            }
        }

        var questionGoal: String {
            switch self {
            case .consistency:
                return ATHLTHLocalization.choose(
                    english: "a sustainable training routine",
                    norwegian: "en gjennomførbar treningsrytme"
                )
            case .fiveK:
                return ATHLTHLocalization.choose(
                    english: "training towards 5 km",
                    norwegian: "trening mot 5 km"
                )
            case .halfMarathon:
                return ATHLTHLocalization.choose(
                    english: "training towards a half marathon",
                    norwegian: "trening mot halvmaraton"
                )
            }
        }
    }

    private var historicalWeeklyMinutes: Double? {
        goal == .consistency
            ? baselines.allWeeklyMinutes : baselines.runningWeeklyMinutes
    }

    private var historicalWeeklySessions: Double? {
        goal == .consistency
            ? baselines.allWeeklySessions : baselines.runningWeeklySessions
    }

    private var comparison: ATHLTHInsightsWhatIfComparison {
        ATHLTHInsightsWhatIfComparison(
            historicalWeeklyMinutes: historicalWeeklyMinutes,
            historicalWeeklySessions: historicalWeeklySessions,
            proposedSessions: weeklySessions,
            minutesPerSession: sessionMinutes
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        ATHLTHInsightsStyle.accent.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "Try a training week",
                        norwegian: "Prøv en treningsuke"
                    ))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)

                    Text(ATHLTHLocalization.choose(
                        english: "Change the number and length of sessions to see how your plan compares with your recent training.",
                        norwegian: "Juster antall og lengde på øktene. Se forskjellen fra det du vanligvis trener."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker(
                ATHLTHLocalization.choose(
                    english: "Training goal", norwegian: "Treningsmål"
                ),
                selection: $goal
            ) {
                ForEach(Goal.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Choose training scenario",
                norwegian: "Velg treningsscenario"
            ))

            VStack(spacing: 14) {
                Stepper(value: $weeklySessions, in: 1...7, step: 1) {
                    HStack(spacing: 8) {
                        Text(ATHLTHLocalization.choose(
                            english: "Sessions per week",
                            norwegian: "Økter per uke"
                        ))
                        .font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text(weeklySessions.formatted())
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHInsightsStyle.accent)
                    }
                }
                .accessibilityValue(String(weeklySessions))

                Divider()

                Stepper(value: $sessionMinutes, in: 20...180, step: 5) {
                    HStack(spacing: 8) {
                        Text(ATHLTHLocalization.choose(
                            english: "Minutes per session",
                            norwegian: "Minutter per økt"
                        ))
                        .font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text("\(sessionMinutes) min")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHInsightsStyle.accent)
                    }
                }
                .accessibilityValue("\(sessionMinutes) min")
            }
            .padding(14)
            .background(
                ATHLTHInsightsStyle.canvas,
                in: RoundedRectangle(cornerRadius: 17)
            )

            if let usual = goal == .consistency
                ? baselines.allSessionMinutes : baselines.runningSessionMinutes {
                Button {
                    weeklySessions = min(max(
                        Int((historicalWeeklySessions ?? 1).rounded()), 1
                    ), 7)
                    sessionMinutes = min(max(
                        Int((usual / 5).rounded()) * 5, 20
                    ), 180)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Start from my recent average",
                        norwegian: "Bruk mitt nylige snitt"
                    ), systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                metricTile(
                    title: ATHLTHLocalization.choose(
                        english: "Your recent week",
                        norwegian: "Din vanlige uke"
                    ),
                    value: historicalWeeklyMinutes.map {
                        "\(Int($0.rounded())) min"
                    } ?? "—",
                    subtitle: historicalWeeklySessions.map {
                        String(format: "%.1f", $0) + " " +
                            ATHLTHLocalization.choose(
                                english: "sessions / week",
                                norwegian: "økter / uke"
                            )
                    } ?? ATHLTHLocalization.choose(
                        english: "No recent data", norwegian: "Ingen nyere data"
                    )
                )
                metricTile(
                    title: ATHLTHLocalization.choose(
                        english: "Your test week",
                        norwegian: "Din testuke"
                    ),
                    value: "\(Int(comparison.proposedWeeklyMinutes)) min",
                    subtitle: "\(weeklySessions) " +
                        ATHLTHLocalization.choose(
                            english: "sessions / week",
                            norwegian: "økter / uke"
                        )
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(ATHLTHLocalization.choose(
                    english: "Difference in weekly training time",
                    norwegian: "Forskjell i ukentlig treningstid"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHInsightsStyle.muted)

                if let delta = comparison.differenceMinutes {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(signedMinutes(delta))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                        if let percent = comparison.changePercent {
                            Text(signedPercent(percent))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                        }
                    }
                    Text(changeExplanation)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "No recorded workouts for this category in the past 28 days. Compare once more training history is available.",
                        norwegian: "Ingen registrerte økter for dette valget de siste 28 dagene. Sammenligningen vises når du har treningshistorikk."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                ATHLTHInsightsStyle.accent.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 17)
            )

            Text(goalExplanation)
                .font(.subheadline)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                ATHLTHLocalization.choose(
                    english: "Comparison of minutes only. The intensity, recovery and fitness effect cannot be predicted from this scenario.",
                    norwegian: "Dette sammenligner bare minutter. Intensitet, restitusjon og effekt på formen kan ikke forutsies her."
                ),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                onAskCoach(coachPrompt)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text(ATHLTHLocalization.choose(
                        english: "Create a plan with Coach",
                        norwegian: "Lag en plan med Coach"
                    ))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 17)
                .frame(minHeight: 49)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            .buttonStyle(.plain)

            Button(action: onOpenTrain) {
                Label(ATHLTHLocalization.choose(
                    english: "Open Training", norwegian: "Åpne Trening"
                ), systemImage: "dumbbell.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHInsightsStyle.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .athlthInsightsSurface()
    }

    private func metricTile(
        title: String, value: String, subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ATHLTHInsightsStyle.ink)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 97, alignment: .leading)
        .padding(12)
        .background(
            ATHLTHInsightsStyle.canvas,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func signedMinutes(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let prefix = rounded > 0 ? "+" : ""
        return "\(prefix)\(rounded) min"
    }

    private func signedPercent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let prefix = rounded > 0 ? "+" : ""
        return "(\(prefix)\(rounded) %)"
    }

    private var changeExplanation: String {
        switch comparison.direction {
        case .more:
            return ATHLTHLocalization.choose(
                english: "You are planning more training time than your recent weekly average. Review the change and build a realistic schedule.",
                norwegian: "Du legger opp til mer treningstid enn ditt nylige ukesnitt. Vurder forskjellen og lag en realistisk plan."
            )
        case .less:
            return ATHLTHLocalization.choose(
                english: "You are planning less training time than usual. That can be intentional; decide how it fits your goals.",
                norwegian: "Du legger opp til mindre treningstid enn vanlig. Det kan være bevisst – se det i sammenheng med målene dine."
            )
        case .similar:
            return ATHLTHLocalization.choose(
                english: "The total training time is close to your recent weekly average. Your session intensity and distribution still matter.",
                norwegian: "Treningstiden er omtrent som ditt nylige ukesnitt. Intensitet og fordeling mellom øktene betyr fortsatt noe."
            )
        case .unknown:
            return ""
        }
    }

    private var goalExplanation: String {
        switch goal {
        case .consistency:
            return ATHLTHLocalization.choose(
                english: "All recorded workouts are included. Coach can help place training and recovery days so the week fits your routine.",
                norwegian: "Alle registrerte økter er med. Coach kan hjelpe deg å fordele økter og hviledager gjennom uken."
            )
        case .fiveK:
            return ATHLTHLocalization.choose(
                english: "Only running sessions are compared. For 5 km, the week should balance easy runs, quality sessions and recovery.",
                norwegian: "Bare løpeøkter sammenlignes. Mot 5 km bør uken kombinere rolig løping, kvalitetsøkter og hvile."
            )
        case .halfMarathon:
            return ATHLTHLocalization.choose(
                english: "Only running sessions are compared. A half-marathon plan needs gradual progress and enough recovery, not just more minutes.",
                norwegian: "Bare løpeøkter sammenlignes. Halvmaraton krever gradvis utvikling og nok restitusjon – ikke bare flere minutter."
            )
        }
    }

    private var coachPrompt: String {
        let objective = goal.questionGoal
        return ATHLTHLocalization.choose(
            english: "Help me build \(objective). I want to explore \(weeklySessions) workouts per week, around \(sessionMinutes) minutes each. Ask about my training experience, limitations, equipment and preferred starting date first. Check whether the weekly structure is realistic, propose a plan, and ask for approval before adding anything. Do not assume access to health data.",
            norwegian: "Hjelp meg å lage \(objective). Jeg vurderer \(weeklySessions) økter i uken på omtrent \(sessionMinutes) minutter hver. Spør først om erfaring, skader eller begrensninger, utstyr og ønsket startdato. Vurder om treningsuken er realistisk, foreslå en plan og be om godkjenning før du legger til noe. Ikke anta tilgang til helsedata."
        )
    }
}
