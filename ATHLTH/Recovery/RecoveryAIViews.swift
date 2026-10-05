import SwiftUI

private func recoveryAIText(
    _ english: String,
    _ norwegian: String
) -> String {
    ATHLTHLocalization.choose(
        english: english,
        norwegian: norwegian
    )
}

struct RecoveryAIInsightCard: View {
    let insight: RecoveryAIInsight
    let context: RecoveryAIContext
    let isLoading: Bool
    let onScoreDetails: () -> Void
    let onAdjustTraining: () -> Void
    let onAskATHLTH: () -> Void

    var body: some View {
        ATHLTHCard {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.indigo)

                Text("ATHLTH COACH")
                    .font(.caption.weight(.bold))
                    .tracking(1.7)
                    .foregroundStyle(.secondary)

                Text("ATHLTH+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(recoveryAIText("Today", "I dag"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.headline)
                        .font(
                            .system(
                                size: 24,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    Text(insight.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 4)

                readinessRing
            }
            .padding(.top, 12)

            HStack(spacing: 7) {
                metricTile(
                    title: recoveryAIText("Sleep", "Søvn"),
                    value: sleepValue,
                    icon: "bed.double.fill",
                    tint: .indigo
                )

                metricTile(
                    title: "HRV",
                    value: hrvValue,
                    icon: "waveform.path.ecg",
                    tint: .red
                )

                metricTile(
                    title:
                        recoveryAIText(
                            "RHR",
                            "Hvilepuls"
                        ),
                    value: restingHeartRateValue,
                    icon: "heart.fill",
                    tint: .pink
                )

                metricTile(
                    title: recoveryAIText("Load", "Belastning"),
                    value: loadValue,
                    detail: recoveryAIText("7d · strength + walk + run", "7 d · styrke + gange + løp"),
                    icon: "chart.bar.fill",
                    tint: .green
                )
            }
            .padding(.top, 14)

            if !displayFactors.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(recoveryAIText("What matters most today", "Det viktigste i dag"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    ForEach(
                        Array(displayFactors.indices),
                        id: \.self
                    ) { index in
                        let factor = displayFactors[index]

                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    factorTint(factor)
                                )
                                .frame(width: 30, height: 30)
                                .background(
                                    factorTint(factor).opacity(0.10),
                                    in: RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                )

                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(factor.title)
                                    .font(
                                        .subheadline.weight(.semibold)
                                    )

                                Text(factor.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 16)
            }

        }
    }

    private var readinessRing: some View {
        let score = context.recoveryScore ?? 0
        let progress = Double(score) / 100

        return ZStack {
            Circle()
                .stroke(
                    Color.secondary.opacity(0.12),
                    lineWidth: 7
                )

            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(
                    ringTint,
                    style: StrokeStyle(
                        lineWidth: 7,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(score)")
                    .font(
                        .system(
                            size: 28,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(context.recoveryState)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ATHLTHLocalization.choose(english: "Readiness \(score), \(context.recoveryState)", norwegian: "Dagsform \(score), \(context.recoveryState)")
        )
    }

    private func metricTile(
        title: String,
        value: String,
        detail: String? = nil,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(
                    .system(
                        size: 15,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.60)

            if let detail {
                Text(detail)
                    .font(.system(size: 7.8, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            tint.opacity(0.055),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var displayFactors: [RecoveryAIFactor] {
        var factors = Array(insight.factors.prefix(3))

        if !factors.contains(
            where: {
                $0.title.localizedCaseInsensitiveContains("load") ||
                $0.title.localizedCaseInsensitiveContains("belastning")
            }
        ) {
            if factors.count >= 3 {
                factors = Array(factors.prefix(2))
            }

            factors.append(trainingLoadFactor)
        }

        return Array(factors.prefix(3))
    }

    private var trainingLoadFactor: RecoveryAIFactor {
        let acute = Int(context.acuteTrainingMinutes.rounded())
        let baseline = context.chronicWeeklyAverageMinutes.map {
            Int($0.rounded())
        }

        let detail: String
        if let baseline {
            detail =
                ATHLTHLocalization.choose(english: "The last 7 days total \(acute) min versus your recent weekly average of \(baseline) min. Imported strength, running and walking all count.", norwegian: "De siste 7 dagene utgjør \(acute) min sammenlignet med ditt nyere ukesnitt på \(baseline) min. Importert styrke, løping og gange teller med.")
        } else {
            detail =
                ATHLTHLocalization.choose(english: "The last 7 days total \(acute) min. Imported strength, running and walking all count while ATHLTH builds your baseline.", norwegian: "De siste 7 dagene utgjør \(acute) min. Importert styrke, løping og gange teller med mens ATHLTH bygger grunnlinjen din.")
        }

        let impact: String
        if let baseline, baseline > 0 {
            let ratio = context.acuteTrainingMinutes / Double(baseline)
            impact = ratio > 1.45 ? "negative" : ratio < 0.85 ? "positive" : "neutral"
        } else {
            impact = "neutral"
        }

        return RecoveryAIFactor(
            title: recoveryAIText("Training load", "Treningsbelastning"),
            detail: detail,
            impact: impact
        )
    }

    private func factorTint(
        _ factor: RecoveryAIFactor
    ) -> Color {
        switch factor.impact {
        case "negative": return .red
        case "positive": return .green
        default: return .blue
        }
    }

    private var ringTint: Color {
        guard let score = context.recoveryScore else {
            return .gray
        }

        switch score {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    private var sleepValue: String {
        guard let seconds = context.sleepSeconds else {
            return "—"
        }

        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var hrvValue: String {
        context.hrvMilliseconds.map {
            "\(Int($0.rounded())) ms"
        } ?? "—"
    }

    private var restingHeartRateValue: String {
        context.restingHeartRate.map {
            "\(Int($0.rounded())) bpm"
        } ?? "—"
    }

    private var loadValue: String {
        "\(Int(context.acuteTrainingMinutes.rounded())) min"
    }
}

struct RecoveryCoachEntryCard: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                Image(systemName: "sparkles")
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.indigo)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.indigo.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        recoveryAIText(
                            "Ask ATHLTH Coach",
                            "Spør ATHLTH Coach"
                        )
                    )
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        recoveryAIText(
                            "Follow up on recovery, sleep and training.",
                            "Følg opp dagsform, søvn og trening."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color.indigo.opacity(0.035)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    Color.indigo.opacity(0.08),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            recoveryAIText(
                "Ask ATHLTH Coach",
                "Spør ATHLTH Coach"
            )
        )
    }
}

struct RecoverySuggestedTodayCard: View {
    let suggestion: RecoveryAISuggestion
    let onOpenTrain: () -> Void

    var body: some View {
        ATHLTHCard {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(recoveryAIText("SUGGESTED TODAY", "FORSLAG I DAG"))
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("ATHLTH+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            Button(action: onOpenTrain) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 48, height: 48)
                        .background(
                            Color.blue.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(suggestion.title)
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text(suggestion.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.top, 10)
            }
            .buttonStyle(.plain)
        }
    }
}

struct RecoveryCoachView: View {
    @Environment(\.dismiss) private var dismiss

    let context: RecoveryAIContext
    let insight: RecoveryAIInsight

    @State private var question = ""
    @State private var answer: String?
    @State private var isAsking = false
    @State private var errorMessage: String?

    private let service = RecoveryAIService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ATHLTHCard {
                        Label(
                            "ATHLTH Coach",
                            systemImage: "sparkles"
                        )
                        .font(.title3.weight(.bold))

                        Text(insight.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text(recoveryAIText("Try asking", "Prøv å spørre"))
                            .font(.headline)

                        ForEach(
                            insight.quickQuestions.prefix(3),
                            id: \.self
                        ) { suggestion in
                            Button {
                                question = suggestion
                                Task {
                                    await ask(suggestion)
                                }
                            } label: {
                                HStack {
                                    Text(suggestion)
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(
                                    Color.primary.opacity(0.035),
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isAsking {
                        HStack {
                            Spacer()
                            ProgressView(recoveryAIText("ATHLTH is thinking…", "ATHLTH tenker…"))
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }

                    if let answer {
                        ATHLTHCard {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.indigo)
                                Text("ATHLTH")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.2)
                            }

                            Text(answer)
                                .font(.subheadline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                                .lineSpacing(3)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                                .padding(.top, 7)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 9) {
                    TextField(
                        recoveryAIText("Ask about today's recovery…", "Spør om dagens restitusjon…"),
                        text: $question,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                    Button {
                        Task {
                            await ask(question)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(
                                ATHLTHTheme.accentDeep,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        question
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty || isAsking
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("ATHLTH Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(recoveryAIText("Done", "Ferdig")) {
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private func ask(
        _ rawQuestion: String
    ) async {
        let clean = rawQuestion
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !clean.isEmpty else {
            return
        }

        question = clean
        isAsking = true
        answer = nil
        errorMessage = nil
        defer { isAsking = false }

        do {
            answer = try await service.ask(
                clean,
                context: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
