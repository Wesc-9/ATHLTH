import SwiftUI

/// One optional workout, chosen by the athlete — never a mandatory running
/// goal. Estimates only future recorded minutes, never readiness or injury risk.
struct ATHLTHInsightsWhatIfView: View {
    let baselines: InsightsSessionBaselines
    let muscleSummary: ATHLTHInsightsMuscleSummary
    let onAskCoach: (String) -> Void
    let onOpenTrain: () -> Void

    @State private var activity: Activity = .strength
    @State private var selectedMuscle: Muscle = .back
    @State private var durationMinutes = 45
    @State private var runningDistance = 5.0
    @State private var runningPaceSeconds = 360
    @State private var strengthWorkingSets = 12
    @State private var customActivity = ""
    @State private var ownQuestion = ""
    @State private var mode: Mode = .freeText

    private enum Mode: String, CaseIterable, Identifiable {
        case freeText, guided
        var id: String { rawValue }
        var label: String {
            switch self {
            case .freeText: return ATHLTHLocalization.choose(
                english: "Write freely", norwegian: "Skriv selv"
            )
            case .guided: return ATHLTHLocalization.choose(
                english: "Choose workout", norwegian: "Velg økt"
            )
            }
        }
    }

    private var trimmedQuestion: String {
        ownQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var questionExamples: [String] {
        [
            ATHLTHLocalization.choose(
                english: "What if I train my back now?",
                norwegian: "Hva om jeg trener rygg nå?"
            ),
            ATHLTHLocalization.choose(
                english: "What if I go for a 5 km run?",
                norwegian: "Hva om jeg løper 5 km?"
            ),
            ATHLTHLocalization.choose(
                english: "What if I take a rest day?",
                norwegian: "Hva om jeg tar en hviledag?"
            )
        ]
    }

    private enum Activity: String, CaseIterable, Identifiable {
        case strength, running, walking, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .strength: return ATHLTHLocalization.choose(
                english: "Strength", norwegian: "Styrke")
            case .running: return ATHLTHLocalization.choose(
                english: "Run", norwegian: "Løp")
            case .walking: return ATHLTHLocalization.choose(
                english: "Walk", norwegian: "Gåtur")
            case .custom: return ATHLTHLocalization.choose(
                english: "Other", norwegian: "Annet")
            }
        }
    }

    private enum Muscle: String, CaseIterable, Identifiable {
        case back, chest, legs, shoulders, arms, core, fullBody
        var id: String { rawValue }

        var title: String {
            switch self {
            case .back: return ATHLTHLocalization.choose(
                english: "Back", norwegian: "Rygg")
            case .chest: return ATHLTHLocalization.choose(
                english: "Chest", norwegian: "Bryst")
            case .legs: return ATHLTHLocalization.choose(
                english: "Legs", norwegian: "Bein")
            case .shoulders: return ATHLTHLocalization.choose(
                english: "Shoulders", norwegian: "Skuldre")
            case .arms: return ATHLTHLocalization.choose(
                english: "Arms", norwegian: "Armer")
            case .core: return ATHLTHLocalization.choose(
                english: "Core", norwegian: "Mage/kjerne")
            case .fullBody: return ATHLTHLocalization.choose(
                english: "Full body", norwegian: "Helkropp")
            }
        }

        var regions: [StrengthMuscleRegion] {
            switch self {
            case .back: return [.lats, .upperBack, .lowerBack]
            case .chest: return [.chest]
            case .legs: return [.quads, .hamstrings, .glutes, .calves]
            case .shoulders: return [.frontDelts, .sideDelts, .rearDelts]
            case .arms: return [.biceps, .triceps, .forearms]
            case .core: return [.abs, .obliques]
            case .fullBody: return []
            }
        }
    }

    private var proposedDurationMinutes: Int {
        switch activity {
        case .running:
            return max(1, Int((runningDistance *
                Double(runningPaceSeconds) / 60).rounded()))
        case .strength, .walking, .custom:
            return durationMinutes
        }
    }

    private var weeklyMinutes: Double? {
        switch activity {
        case .strength: return baselines.strengthWeeklyMinutes
        case .running: return baselines.runningWeeklyMinutes
        case .walking: return baselines.walkingWeeklyMinutes
        case .custom: return baselines.allWeeklyMinutes
        }
    }

    private var weeklySessions: Double? {
        switch activity {
        case .strength: return baselines.strengthWeeklySessions
        case .running: return baselines.runningWeeklySessions
        case .walking: return baselines.walkingWeeklySessions
        case .custom: return baselines.allWeeklySessions
        }
    }

    private var comparison: ATHLTHInsightsWhatIfComparison {
        ATHLTHInsightsWhatIfComparison(
            historicalWeeklyMinutes: weeklyMinutes,
            historicalWeeklySessions: weeklySessions,
            additionalMinutes: proposedDurationMinutes
        )
    }

    private var recordedTargetMuscles: Bool {
        guard activity == .strength,
              muscleSummary.sessionCount > 0 else { return false }
        if selectedMuscle == .fullBody {
            return !muscleSummary.profile.activations.isEmpty
        }
        return muscleSummary.profile.activations.contains {
            selectedMuscle.regions.contains($0.region) &&
                $0.score.isFinite && $0.score > 0
        }
    }

    private var elevatedMuscleFocus: Bool {
        guard activity == .strength,
              selectedMuscle != .fullBody,
              muscleSummary.sessionCount >= 3
        else { return false }
        return ATHLTHInsightsMuscleRanking.all(muscleSummary).contains {
            selectedMuscle.regions.contains($0.region) &&
                $0.needsLoadBalanceAttention
        }
    }

    private var isValid: Bool {
        if mode == .freeText { return !trimmedQuestion.isEmpty }
        return activity != .custom ||
            !customActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title3)
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        ATHLTHInsightsStyle.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "What if I…", norwegian: "Hva om jeg …"
                    ))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    Text(ATHLTHLocalization.choose(
                        english: "Explore one workout before you decide. Nothing is added until you approve it.",
                        norwegian: "Utforsk én økt før du bestemmer deg. Ingenting legges til uten at du godkjenner det."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker(
                ATHLTHLocalization.choose(
                    english: "How do you want to explore?",
                    norwegian: "Hvordan vil du undersøke?"
                ),
                selection: $mode
            ) {
                ForEach(Mode.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if mode == .freeText {
                ownQuestionSection
            } else {
                guidedWorkoutSection
            }

            Label(
                mode == .freeText
                    ? ATHLTHLocalization.choose(
                        english: "The question is sent to Coach as written. No training session is created automatically.",
                        norwegian: "Spørsmålet sendes til Coach slik du skrev det. Ingen treningsøkt opprettes automatisk."
                    )
                    : ATHLTHLocalization.choose(
                        english: "Only training time is estimated. Not a prediction of recovery, injury risk, fitness, pace or future results.",
                        norwegian: "Kun treningstid beregnes. Dette er ingen prognose for restitusjon, skaderisiko, form eller fremtidige resultater."
                    ),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                guard isValid else { return }
                onAskCoach(coachPrompt)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text(mode == .freeText
                        ? ATHLTHLocalization.choose(
                            english: "Ask ATHLTH Coach",
                            norwegian: "Spør ATHLTH Coach"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Review this workout with Coach",
                            norwegian: "Vurder økten med Coach"
                        )
                    )
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
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.5)

            Button(action: onOpenTrain) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Open Training", norwegian: "Åpne Trening"
                    ),
                    systemImage: "dumbbell.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHInsightsStyle.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .athlthInsightsSurface()
    }

    /// Free-text questions can describe *anything* — a back workout,
    /// 5 km, rest, cycling or a custom goal. Never invent comparison figures
    /// from text that has not been explicitly structured by the athlete.
    private var ownQuestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                ATHLTHLocalization.choose(
                    english: "E.g. What if I train my back now?",
                    norwegian: "F.eks. Hva om jeg trener rygg nå?"
                ),
                text: $ownQuestion,
                axis: .vertical
            )
            .lineLimit(2...4)
            .font(.subheadline)
            .textInputAutocapitalization(.sentences)
            .padding(13)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(
                        ATHLTHInsightsStyle.accent.opacity(0.24),
                        lineWidth: 1
                    )
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Ask your own What if question",
                norwegian: "Skriv ditt eget Hva om-spørsmål"
            ))

            Text(ATHLTHLocalization.choose(
                english: "Or choose an example — you can edit it before sending.",
                norwegian: "Eller velg et eksempel – du kan redigere det før du sender."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)

            ForEach(questionExamples, id: \.self) { example in
                Button {
                    ownQuestion = example
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(ATHLTHInsightsStyle.accent)
                        Text(example)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.left")
                            .font(.caption)
                            .foregroundStyle(ATHLTHInsightsStyle.muted)
                    }
                    .frame(minHeight: 39)
                }
                .buttonStyle(.plain)
            }

            Text(ATHLTHLocalization.choose(
                english: "Coach answers your question. A free-text scenario does not generate made-up workout totals.",
                norwegian: "Coach vurderer spørsmålet ditt. Fritekst gir ingen oppdiktede beregninger av treningsmengden."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            ATHLTHInsightsStyle.canvas,
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private var guidedWorkoutSection: some View {
        VStack(alignment: .leading, spacing: 17) {
            Picker(ATHLTHLocalization.choose(
                english: "Workout type", norwegian: "Treningsform"
            ), selection: $activity) {
                ForEach(Activity.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 13) {
                switch activity {
                case .strength:
                    strengthControls
                case .running:
                    runningControls
                case .walking:
                    durationControl
                case .custom:
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "E.g. 30 minutes of cycling or yoga",
                            norwegian: "F.eks. 30 minutter sykling eller yoga"
                        ),
                        text: $customActivity,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
                    .font(.subheadline)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Describe your activity",
                        norwegian: "Beskriv aktiviteten"
                    ))
                    durationControl
                }
            }
            .padding(14)
            .background(
                ATHLTHInsightsStyle.canvas,
                in: RoundedRectangle(cornerRadius: 18)
            )

            summarySection

            if activity == .strength {
                Label(
                    elevatedMuscleFocus
                        ? ATHLTHLocalization.choose(
                            english: "Your recorded training focus for this area is unusually high compared with your previous baseline. Consider how another workout fits your week, without interpreting it as injury risk.",
                            norwegian: "Registrert treningsmengde for dette området er uvanlig høy sammenlignet med ditt tidligere nivå. Vurder hvordan en ny økt passer inn, uten å tolke dette som skaderisiko."
                        )
                        : recordedTargetMuscles
                        ? ATHLTHLocalization.choose(
                            english: "This muscle group is present in your recorded strength history. Duration alone cannot determine how much it should recover.",
                            norwegian: "Denne muskelgruppen finnes i styrkehistorikken din. Varighet alene kan ikke avgjøre hvor mye restitusjon den trenger."
                        )
                        : ATHLTHLocalization.choose(
                            english: "No reliable muscle-specific history for this selection. Coach can review the exercises, your restrictions and recovery with your permission.",
                            norwegian: "Vi har ikke tilstrekkelig muskelspesifikk historikk for dette valget. Coach kan vurdere øvelser, begrensninger og restitusjon hvis du gir tillatelse."
                        ),
                    systemImage: "figure.strengthtraining.traditional"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var strengthControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Text(ATHLTHLocalization.choose(
                    english: "Muscle focus", norwegian: "Muskelgruppe"
                ))
                .font(.subheadline.weight(.medium))
                Spacer()
                Picker(ATHLTHLocalization.choose(
                    english: "Muscle focus", norwegian: "Muskelgruppe"
                ), selection: $selectedMuscle) {
                    ForEach(Muscle.allCases) { muscle in
                        Text(muscle.title).tag(muscle)
                    }
                }
                .tint(ATHLTHInsightsStyle.accent)
            }

            Divider()

            Stepper(value: $strengthWorkingSets, in: 3...30, step: 3) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Planned working sets",
                        norwegian: "Planlagte arbeidssett"
                    ))
                    .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(strengthWorkingSets)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                }
            }
            durationControl
        }
    }

    private var runningControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Stepper(value: $runningDistance, in: 0.5...42.0, step: 0.5) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Distance", norwegian: "Distanse"
                    ))
                    .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(distanceText + " km")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                }
            }
            Divider()
            Stepper(value: $runningPaceSeconds, in: 180...900, step: 15) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Target pace", norwegian: "Måltempo"
                    ))
                    .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(paceText + " /km")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                }
            }
            Divider()
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Estimated duration", norwegian: "Beregnet varighet"
                ))
                .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(proposedDurationMinutes) min")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
            }
        }
    }

    private var durationControl: some View {
        Stepper(value: $durationMinutes, in: 15...180, step: 5) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Planned duration", norwegian: "Planlagt varighet"
                ))
                .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(durationMinutes) min")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
            }
        }
    }

    private var distanceText: String {
        runningDistance.formatted(
            .number.precision(.fractionLength(0...1))
        )
    }

    private var paceText: String {
        String(format: "%d:%02d",
               runningPaceSeconds / 60, runningPaceSeconds % 60)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(ATHLTHLocalization.choose(
                english: "What changes if you do this?",
                norwegian: "Hva endres hvis du gjør dette?"
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHInsightsStyle.ink)

            HStack(spacing: 9) {
                metric(
                    title: ATHLTHLocalization.choose(
                        english: "Recent weekly average",
                        norwegian: "Nylig ukesnitt"
                    ),
                    value: weeklyMinutes.map {
                        "\(Int($0.rounded())) min"
                    } ?? "—",
                    detail: ATHLTHLocalization.choose(
                        english: "Past 28 days",
                        norwegian: "Siste 28 dager"
                    )
                )
                metric(
                    title: ATHLTHLocalization.choose(
                        english: "With this workout",
                        norwegian: "Med denne økten"
                    ),
                    value: comparison.projectedWeeklyMinutes.map {
                        "\(Int($0.rounded())) min"
                    } ?? "+\(proposedDurationMinutes) min",
                    detail: weeklyMinutes == nil
                        ? ATHLTHLocalization.choose(
                            english: "No historical comparison",
                            norwegian: "Uten historisk sammenligning"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Hypothetical weekly total",
                            norwegian: "Hypotetisk ukestotal"
                        )
                )
            }

            Text(comparisonExplanation)
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            ATHLTHInsightsStyle.accent.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }

    private var comparisonExplanation: String {
        if activity == .custom {
            return ATHLTHLocalization.choose(
                english: "This adds about \(proposedDurationMinutes) planned minutes. Since you entered a custom activity, the reference uses all recorded training, not the specific activity.",
                norwegian: "Dette legger til omtrent \(proposedDurationMinutes) planlagte minutter. For egendefinert aktivitet bruker vi alle registrerte økter som sammenligningsgrunnlag."
            )
        }
        return ATHLTHLocalization.choose(
            english: "An additional \(activity.title.lowercased()) session adds about \(proposedDurationMinutes) planned minutes. The reference is the same workout category.",
            norwegian: "Én ekstra økt med \(activity.title.lowercased()) gir omtrent \(proposedDurationMinutes) planlagte minutter. Sammenligningen gjelder samme treningstype."
        )
    }

    private func metric(
        title: String, value: String, detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ATHLTHInsightsStyle.ink)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(12)
        .background(
            .white, in: RoundedRectangle(cornerRadius: 15)
        )
    }

    private var coachPrompt: String {
        if mode == .freeText {
            return String(trimmedQuestion.prefix(2_000))
        }
        let request: String
        switch activity {
        case .strength:
            request = ATHLTHLocalization.choose(
                english: "a \(selectedMuscle.title.lowercased()) strength workout now, with about \(strengthWorkingSets) working sets over \(durationMinutes) minutes",
                norwegian: "en \(selectedMuscle.title.lowercased())økt nå, med omtrent \(strengthWorkingSets) arbeidssett på \(durationMinutes) minutter"
            )
        case .running:
            request = ATHLTHLocalization.choose(
                english: "running \(runningDistance.formatted()) km today at \(paceText) minutes per kilometer",
                norwegian: "å løpe \(runningDistance.formatted()) km i dag med \(paceText) min/km"
            )
        case .walking:
            request = ATHLTHLocalization.choose(
                english: "a \(durationMinutes)-minute walk today",
                norwegian: "en gåtur på \(durationMinutes) minutter i dag"
            )
        case .custom:
            request = String(customActivity.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).prefix(250)) + ATHLTHLocalization.choose(
                english: ", lasting about \(durationMinutes) minutes",
                norwegian: ", omtrent \(durationMinutes) minutter"
            )
        }

        return ATHLTHLocalization.choose(
            english: "What if I do \(request)? Help me assess how it might fit my recent training and goals. Please ask about injuries, soreness and other relevant context before recommending changes. Do not assume access to my health data. Do not change any plan or schedule anything without my approval.",
            norwegian: "Hva om jeg gjennomfører \(request)? Hjelp meg å vurdere hvordan dette passer med treningen og målene mine. Spør om skader, stølhet og andre relevante forhold før du anbefaler endringer. Ikke anta tilgang til helsedata. Ikke endre treningsplan eller kalender uten min godkjenning."
        )
    }
}
