import Foundation
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


// Compact Coach header: no hero photo and no fabricated online indicator.
private struct RecoveryCoachCompactHeader<Avatar: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void
    private let avatar: Avatar
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        onBack: @escaping () -> Void,
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.avatar = avatar()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.82), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.09), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recoveryAIText("Back", "Tilbake"))

            Spacer(minLength: 2)

            avatar.frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            trailing.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .systemBackground).opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.7)
        }
    }
}

private func recoveryCoachMuscleName(_ value: String) -> String {
    guard ATHLTHLocalization.isNorwegian else { return value }
    switch value {
    case "Chest": return "Bryst"
    case "Back": return "Rygg"
    case "Shoulders": return "Skuldre"
    case "Arms": return "Armer"
    case "Core": return "Kjerne"
    case "Glutes": return "Setemuskler"
    case "Quads": return "Forside lår"
    case "Hamstrings": return "Bakside lår"
    case "Calves": return "Legger"
    default: return value
    }
}

private enum RecoveryCoachMuscleFeeling: String, CaseIterable, Identifiable {
    case ready
    case uncertain
    case sore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return recoveryAIText("Ready to train", "Føles klar")
        case .uncertain: return recoveryAIText("A little tired", "Litt sliten")
        case .sore: return recoveryAIText("Sore / needs rest", "Støl / trenger hvile")
        }
    }

    var message: String {
        switch self {
        case .ready: return recoveryAIText("feels ready to train", "føles klar til trening")
        case .uncertain: return recoveryAIText("feels a little tired", "føles litt sliten")
        case .sore: return recoveryAIText("feels sore and needs more rest", "kjennes støl ut og trenger mer hvile")
        }
    }
}

private extension View {
    func recoveryCoachLegacyConversationPanelChrome()
        -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.97),
                        ATHLTHTheme
                            .cardWarm
                            .opacity(0.76)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.78),
                    lineWidth: 0.8
                )
            }
    }

    func recoveryCoachLegacyConversationComposerChrome()
        -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(
                        Color.white.opacity(0.66)
                    )
                    .frame(height: 0.8)
            }
    }
}

struct RecoveryAIInsightCard: View {
    let insight: RecoveryAIInsight
    let context: RecoveryAIContext
    let isLoading: Bool

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
        // All four signal tiles share one fixed size. The training load
        // subtitle must never make its card taller or wider than the others.
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 86,
            maxHeight: 86,
            alignment: .topLeading
        )
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

struct RecoveryCoachInboxDestinationView:
    View {
    @EnvironmentObject private var health:
        HealthKitManager
    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var strengthWorkout:
        StrengthWorkoutStore

    @StateObject private var sorenessStore =
        RecoverySorenessStore()
    @State private var recoverySnapshot =
        RecoveryTrendSnapshot.empty
    @State private var derivedSnapshot =
        RecoveryDerivedSnapshot.empty
    @State private var insight:
        RecoveryAIInsight?
    @State private var isLoading = false

    var body: some View {
        Group {
            if !session.hasPaidAccess {
                ContentUnavailableView(
                    recoveryAIText(
                        "ATHLTH Coach requires ATHLTH+",
                        "ATHLTH Coach krever ATHLTH+"
                    ),
                    systemImage:
                        "sparkles",
                    description:
                        Text(
                            recoveryAIText(
                                "Coach uses your recovery context to answer training questions.",
                                "Coach bruker restitusjonsdataene dine til å svare på treningsspørsmål."
                            )
                        )
                )
            } else {
                RecoveryCoachView(
                    context:
                        coachContext,
                    insight:
                        insight ??
                        fallbackInsight,
                    showsDoneButton:
                        false
                )
            }
        }
        .task {
            await loadCoachContext()
        }
    }

    private var coachContext:
        RecoveryAIContext {
        RecoveryAIContext(
            recoveryScore:
                health.recovery.score,
            recoveryState:
                health.recovery.state.title,
            recoveryDetail:
                health.recovery.detail,
            sleepSeconds:
                health.sleep.totalAsleep > 0
                    ? health.sleep
                        .totalAsleep
                    : nil,
            baselineSleepSeconds:
                health.recovery
                    .averageSleepDuration,
            hrvMilliseconds:
                health.heart
                    .hrvMilliseconds,
            baselineHRVMilliseconds:
                health.recovery
                    .baselineHRVMilliseconds,
            restingHeartRate:
                health.heart
                    .restingHeartRate,
            baselineRestingHeartRate:
                health.recovery
                    .baselineRestingHeartRate,
            yesterdayTrainingMinutes:
                yesterdayTrainingMinutes,
            acuteTrainingMinutes:
                recoverySnapshot
                    .trainingLoad
                    .acuteMinutes,
            chronicWeeklyAverageMinutes:
                recoverySnapshot
                    .trainingLoad
                    .chronicWeeklyAverageMinutes,
            muscles:
                derivedSnapshot
                    .statuses
                    .sorted { $0.progress < $1.progress }
                    .prefix(10)
                    .map {
                        RecoveryAIMuscleInput(
                            name:
                                $0.muscleGroup,
                            recoveryPercent:
                                Int(
                                    (
                                        $0.progress *
                                        100
                                    )
                                    .rounded()
                                ),
                            status:
                                $0.statusTitle,
                            completedSets:
                                $0.completedSets
                        )
                    },
            checkIn:
                RecoveryAICheckIn(
                    energy:
                        sorenessStore
                            .todayEnergy,
                    stress:
                        sorenessStore
                            .todayStress,
                    overallSoreness:
                        sorenessStore
                            .todayOverallSoreness,
                    motivation:
                        sorenessStore
                            .todayMotivation
                )
        )
    }

    private var yesterdayTrainingMinutes:
        Double {
        let calendar =
            Calendar.current
        guard let yesterday =
                calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: Date()
                )
        else {
            return 0
        }

        return recoverySnapshot.days
            .first {
                calendar.isDate(
                    $0.date,
                    inSameDayAs:
                        yesterday
                )
            }?
            .trainingMinutes ??
            0
    }

    private var fallbackInsight:
        RecoveryAIInsight {
        RecoveryAIInsight(
            headline:
                health.recovery
                    .state.title,
            summary:
                health.recovery
                    .detail,
            factors: [
                RecoveryAIFactor(
                    title:
                        recoveryAIText(
                            "Sleep",
                            "Søvn"
                        ),
                    detail:
                        recoveryAIText(
                            "Compared with your recent baseline.",
                            "Sammenlignet med din nyere grunnlinje."
                        ),
                    impact:
                        "neutral"
                ),
                RecoveryAIFactor(
                    title: "HRV",
                    detail:
                        recoveryAIText(
                            "Compared with your recent baseline.",
                            "Sammenlignet med din nyere grunnlinje."
                        ),
                    impact:
                        "neutral"
                ),
                RecoveryAIFactor(
                    title:
                        recoveryAIText(
                            "Training load",
                            "Treningsbelastning"
                        ),
                    detail:
                        recoveryAIText(
                            "Based on your recent recorded training.",
                            "Basert på den siste registrerte treningen din."
                        ),
                    impact:
                        "neutral"
                )
            ],
            suggestion:
                RecoveryAISuggestion(
                    title:
                        recoveryAIText(
                            "Use today's signals",
                            "Bruk dagens signaler"
                        ),
                    subtitle:
                        recoveryAIText(
                            "Adjust as needed",
                            "Juster ved behov"
                        ),
                    reason:
                        health.recovery
                            .detail
                ),
            quickQuestions: [
                recoveryAIText(
                    "What should I train today?",
                    "Hva bør jeg trene i dag?"
                ),
                recoveryAIText(
                    "What matters most in my recovery data?",
                    "Hva er viktigst i restitusjonsdataene mine?"
                ),
                recoveryAIText(
                    "How should I plan tomorrow's workout?",
                    "Hvordan bør jeg planlegge morgendagens økt?"
                )
            ]
        )
    }

    @MainActor
    private func loadCoachContext()
        async {
        guard session.hasPaidAccess else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        recoverySnapshot =
            await health
                .recoveryTrendSnapshot()

        derivedSnapshot =
            await RecoveryDerivedSnapshotBuilder
                .build(
                    history:
                        strengthWorkout
                            .workoutHistory,
                    sorenessRatings:
                        sorenessStore
                            .todayRatings,
                    activityLoad:
                        recoverySnapshot
                            .trainingLoad
                )

        // Build health context locally. Opening the chat never sends
        // it to an AI provider; only confirmed messages may do that.
        insight = nil
    }
}

struct RecoveryCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session:
        AppSessionStore

    let context: RecoveryAIContext
    let insight: RecoveryAIInsight
    var showsDoneButton: Bool = true

    @State private var question = ""
    @State private var messages:
        [RecoveryCoachMessage] = []
    @State private var quickQuestions:
        [String] = []
    @State private var isAsking = false
    @State private var errorMessage: String?
    @State private var didLoadConversation =
        false
    @State private var coachPinned = true
    @State private var shareHealthForNextQuestion = false
    @State private var pendingHealthQuestion: String?
    @State private var showingHealthShareConfirmation = false
    @State private var aiConsentApproved = false
    @State private var healthConsentApproved = false
    @State private var draftHealthPermission = false
    @State private var draftAutomaticHealthPermission = false
    @State private var showingCoachConsentSheet = false
    @State private var pendingShareAfterConsent = false
    @State private var showingMuscleFeedbackSheet = false
    @State private var feedbackMuscleName = ""
    @State private var feedbackFeeling: RecoveryCoachMuscleFeeling = .sore
    @State private var feedbackNote = ""

    private let service = RecoveryAIService()
    private let bottomAnchorID =
        "athlth-recovery-coach-bottom"

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.10)
            )

            VStack(spacing: 0) {
                coachConversationHero
                    .zIndex(2)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(
                            alignment: .leading,
                            spacing: 14
                        ) {
                            // Locally derived insight; opening this card never
                            // sends health information to the AI provider.
                            if context.recoveryScore != nil || !context.muscles.isEmpty {
                                coachInsightCard
                            }

                            if messages.isEmpty {
                                Text(
                                    recoveryAIText(
                                        "Ask a question to start a conversation. Coach remembers what you talk about on this device.",
                                        "Still et spørsmål for å starte en samtale. Coach husker det dere snakker om på denne enheten."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                                .padding(
                                    .horizontal,
                                    4
                                )
                            } else {
                                ForEach(messages) {
                                    message in

                                    coachMessageBubble(
                                        message
                                    )
                                }
                            }

                            if isAsking {
                                HStack(
                                    spacing: 8
                                ) {
                                    ProgressView()
                                        .controlSize(
                                            .small
                                        )

                                    Text(
                                        recoveryAIText(
                                            "ATHLTH is thinking…",
                                            "ATHLTH tenker…"
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                }
                                .padding(
                                    .horizontal,
                                    12
                                )
                                .padding(
                                    .vertical,
                                    10
                                )
                                .background(
                                    Color.white
                                        .opacity(0.72),
                                    in:
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                )
                            }

                            if let errorMessage {
                                Text(
                                    errorMessage
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .red
                                )
                                .padding(
                                    .horizontal,
                                    4
                                )
                            }

                            Color.clear
                                .frame(
                                    height: 1
                                )
                                .id(
                                    bottomAnchorID
                                )
                        }
                        .padding()
                        // Wrap long replies within the chat viewport.
                        .containerRelativeFrame(.horizontal)
                    }
                    .scrollDismissesKeyboard(
                        .interactively
                    )
                    .onChange(
                        of: messages.count
                    ) { _, _ in
                        withAnimation(
                            .easeOut(
                                duration:
                                    0.20
                            )
                        ) {
                            proxy.scrollTo(
                                bottomAnchorID,
                                anchor: .bottom
                            )
                        }
                    }
                    .onChange(
                        of: isAsking
                    ) { _, asking in
                        guard asking else {
                            return
                        }

                        withAnimation(
                            .easeOut(
                                duration:
                                    0.20
                            )
                        ) {
                            proxy.scrollTo(
                                bottomAnchorID,
                                anchor: .bottom
                            )
                        }
                    }
                    .task {
                        loadConversationIfNeeded()

                        await MainActor.run {
                            proxy.scrollTo(
                                bottomAnchorID,
                                anchor: .bottom
                            )
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .recoveryCoachLegacyConversationPanelChrome()
                .padding(
                    .horizontal,
                    4
                )
                .padding(.top, 0)
                .zIndex(1)
            }
            .containerRelativeFrame(.horizontal)
        }
        .safeAreaInset(
            edge: .bottom
        ) {
            coachComposer
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(
            .inline
        )
        .toolbar(
            .hidden,
            for: .navigationBar
        )
        .toolbar(
            .hidden,
            for: .tabBar
        )
        .onAppear {
            coachPinned =
                RecoveryCoachInboxPreferences
                    .isPinned(
                        userID: session.profile.userID
                    )
            loadCoachConsent()
        }
        .sheet(isPresented: $showingCoachConsentSheet) {
            coachConsentSheet
        }
        .sheet(isPresented: $showingMuscleFeedbackSheet) {
            coachMuscleFeedbackSheet
        }
        .alert(
            recoveryAIText(
                "Share health data with AI?",
                "Dele helsedata med AI?"
            ),
            isPresented: $showingHealthShareConfirmation
        ) {
            Button(
                recoveryAIText("Cancel", "Avbryt"),
                role: .cancel
            ) {
                pendingHealthQuestion = nil
                shareHealthForNextQuestion = false
            }
            Button(recoveryAIText("Share and send", "Del og send")) {
                guard let pending = pendingHealthQuestion else { return }
                pendingHealthQuestion = nil
                shareHealthForNextQuestion = false
                Task {
                    await ask(pending, shareHealthData: true)
                }
            }
        } message: {
            Text(
                recoveryAIText(
                    "ATHLTH will send your question, up to 16 recent chat messages, and your current sleep, HRV, resting heart rate, activity load, muscle recovery and any check-in values to its external AI provider Groq. This approval applies to this question only. Cancel to keep health data on your device.",
                    "ATHLTH sender spørsmålet ditt, inntil 16 tidligere chatmeldinger og opplysninger om søvn, HRV, hvilepuls, treningsbelastning, muskelrestitusjon og eventuell innsjekk til AI-leverandøren Groq. Du godkjenner bare denne sendingen. Velg Avbryt for å beholde helsedata på telefonen."
                )
            )
        }
    }


    // First-use opt-in for third-party AI; health sharing is a separate,
    // default-off choice, and must still be confirmed for each message.
    private var coachConsentSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 65, height: 65)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 21)
                        )

                    Text(recoveryAIText(
                        "Before you chat with Coach",
                        "Før du chatter med Coach"
                    ))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(recoveryAIText(
                        "ATHLTH Coach uses the external AI provider Groq. Each message you send is processed by Groq to create an answer. Do not include information you do not want to share.",
                        "ATHLTH Coach bruker den eksterne AI-leverandøren Groq. Hver melding du sender, behandles av Groq for å lage et svar. Ikke skriv informasjon du ikke ønsker å dele."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            recoveryAIText(
                                "AI chat (required to use Coach)",
                                "AI-chat (nødvendig for å bruke Coach)"
                            ),
                            systemImage: "bubble.left.and.bubble.right.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(recoveryAIText(
                            "Choose 'Allow AI chat' below to allow your messages to be sent to Groq. You can decline without affecting other ATHLTH features.",
                            "Velg «Tillat AI-chat» nedenfor for å tillate at meldingene sendes til Groq. Du kan avslå uten at andre ATHLTH-funksjoner påvirkes."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Divider()

                        Toggle(isOn: $draftHealthPermission) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(recoveryAIText(
                                    "Allow optional health-data sharing",
                                    "Tillat frivillig deling av helsedata"
                                ))
                                .font(.subheadline.weight(.semibold))

                                Text(recoveryAIText(
                                    "Sleep, HRV, resting heart rate, workout load, muscle recovery and check-in values. Off by default.",
                                    "Søvn, HRV, hvilepuls, treningsbelastning, muskelrestitusjon og innsjekk. Av som standard."
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(ATHLTHTheme.accentDeep)

                        Text(recoveryAIText(
                            "This does not send health metrics automatically. Select 'Share health data' in the chat and confirm every individual transfer.",
                            "Dette sender ikke helsemålinger automatisk. Velg «Del helsedata» i chatten og bekreft hver enkelt sending."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        Toggle(isOn: $draftAutomaticHealthPermission) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(recoveryAIText(
                                    "Personal Coach · automatic health access",
                                    "Personlig Coach · automatisk helsetilgang"
                                ))
                                .font(.subheadline.weight(.semibold))

                                Text(recoveryAIText(
                                    "A separate, ongoing opt-in for questions sent to Groq. Never enabled by earlier permissions. You can withdraw at any time.",
                                    "Eget, vedvarende samtykke for spørsmål sendt til Groq. Aktiveres aldri av tidligere tillatelser. Kan trekkes tilbake når som helst."
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(
                            !RecoveryCoachHealthSharingPreferences
                                .automaticTransferApprovedForRelease ||
                            !draftHealthPermission
                        )

                        if !RecoveryCoachHealthSharingPreferences
                            .automaticTransferApprovedForRelease {
                            Label(
                                recoveryAIText(
                                    "Not available yet. Automatic sharing remains blocked until the provider agreement, international transfers, retention and risk assessment have been verified.",
                                    "Ikke tilgjengelig ennå. Automatisk deling er sperret til databehandleravtale, overføring, lagring og risikovurdering er verifisert."
                                ),
                                systemImage: "lock.shield"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(17)
                    .background(
                        Color.white.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 21)
                    )

                    NavigationLink {
                        LegalDocumentView(kind: .privacy)
                    } label: {
                        Label(
                            recoveryAIText(
                                "Read the privacy policy",
                                "Les personvernerklæringen"
                            ),
                            systemImage: "doc.text"
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    Button {
                        saveCoachConsent()
                    } label: {
                        Text(recoveryAIText(
                            aiConsentApproved
                                ? "Save privacy choices"
                                : "Allow AI chat and continue",
                            aiConsentApproved
                                ? "Lagre personvernvalg"
                                : "Tillat AI-chat og fortsett"
                        ))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 51)
                        .background(
                            ATHLTHTheme.accentDeep,
                            in: RoundedRectangle(cornerRadius: 17)
                        )
                    }
                    .buttonStyle(.plain)

                    if aiConsentApproved {
                        Button(role: .destructive) {
                            revokeCoachConsent()
                        } label: {
                            Text(recoveryAIText(
                                "Withdraw AI permission",
                                "Trekk tilbake AI-tillatelsen"
                            ))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                        }
                    } else {
                        Button {
                            showingCoachConsentSheet = false
                            dismiss()
                        } label: {
                            Text(recoveryAIText("Not now", "Ikke nå"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(22)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHTheme.canvasTop)
            .navigationTitle(
                recoveryAIText("Privacy choices", "Personvernvalg")
            )
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!aiConsentApproved)
    }

    @MainActor
    private func loadCoachConsent() {
        let saved = RecoveryCoachConsentPreferences.load(
            userID: session.profile.userID
        )
        aiConsentApproved = saved != nil
        healthConsentApproved = saved?.healthSharingAllowed ?? false
        draftHealthPermission = healthConsentApproved
        draftAutomaticHealthPermission =
            RecoveryCoachHealthSharingPreferences.canAutomaticallyShare(
                userID: session.profile.userID
            )
        if !aiConsentApproved {
            showingCoachConsentSheet = true
        }
    }

    @MainActor
    private func saveCoachConsent() {
        let saved = RecoveryCoachConsentPreferences.approve(
            userID: session.profile.userID,
            healthSharingAllowed: draftHealthPermission
        )
        aiConsentApproved = true
        healthConsentApproved = saved.healthSharingAllowed

        // Save a distinct, versioned health-sharing choice. When the
        // compliance gate is closed, requested automatic access can only
        // become per-question access, never ongoing permission.
        let requestedMode: RecoveryCoachHealthSharingMode =
            !healthConsentApproved ? .off :
            draftAutomaticHealthPermission ? .automatic :
            .confirmEveryQuestion
        RecoveryCoachHealthSharingPreferences.save(
            userID: session.profile.userID,
            requestedMode: requestedMode
        )
        draftAutomaticHealthPermission =
            RecoveryCoachHealthSharingPreferences.canAutomaticallyShare(
                userID: session.profile.userID
            )

        if !healthConsentApproved {
            shareHealthForNextQuestion = false
            pendingHealthQuestion = nil
        } else if pendingShareAfterConsent {
            // Transfer still requires confirmation when the message is sent.
            shareHealthForNextQuestion = true
        }
        pendingShareAfterConsent = false
        showingCoachConsentSheet = false
    }

    @MainActor
    private func revokeCoachConsent() {
        RecoveryCoachConsentPreferences.revoke(
            userID: session.profile.userID
        )
        aiConsentApproved = false
        healthConsentApproved = false
        draftHealthPermission = false
        draftAutomaticHealthPermission = false
        shareHealthForNextQuestion = false
        pendingHealthQuestion = nil
        pendingShareAfterConsent = false
        showingCoachConsentSheet = false
        dismiss()
    }

    private var coachConversationHero:
        some View {
        RecoveryCoachCompactHeader(
            title:
                "ATHLTH Coach",
            subtitle:
                recoveryAIText(
                    "Your personal training coach",
                    "Din personlige treningscoach"
                ),
            onBack: {
                dismiss()
            }
        ) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(
                                    red: 0.09,
                                    green: 0.12,
                                    blue: 0.18
                                ),
                                ATHLTHTheme
                                    .accentDeep
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        )
                    )

                Image(
                    systemName:
                        "sparkles"
                )
                .font(
                    .system(
                        size: 16,
                        weight:
                            .semibold
                    )
                )
                .foregroundStyle(
                    .white
                )
            }
            .overlay {
                Circle()
                    .stroke(
                        Color.white
                            .opacity(0.86),
                        lineWidth: 1.4
                    )
            }
        } trailing: {
            Menu {
                Button {
                    coachPinned.toggle()

                    RecoveryCoachInboxPreferences
                        .setPinned(
                            coachPinned,
                            userID:
                                session
                                    .profile
                                    .userID
                        )
                } label: {
                    Label(
                        coachPinned
                            ? recoveryAIText(
                                "Unpin conversation",
                                "Løsne samtalen"
                            )
                            : recoveryAIText(
                                "Pin conversation",
                                "Fest samtalen"
                            ),
                        systemImage:
                            coachPinned
                                ? "pin.slash"
                                : "pin.fill"
                    )
                }

                Button {
                    draftHealthPermission = healthConsentApproved
                    pendingShareAfterConsent = false
                    showingCoachConsentSheet = true
                } label: {
                    Label(
                        recoveryAIText(
                            "AI & privacy settings",
                            "AI- og personvernvalg"
                        ),
                        systemImage: "hand.raised"
                    )
                }

                Button(
                    role: .destructive
                ) {
                    messages
                        .removeAll()
                    quickQuestions =
                        contextAwareQuestions()
                    errorMessage = nil
                    RecoveryCoachConversationPersistence.delete(
                        userID: session.profile.userID
                    )
                } label: {
                    Label(
                        recoveryAIText(
                            "Start new conversation",
                            "Start ny samtale"
                        ),
                        systemImage:
                            "bubble.left.and.exclamationmark.bubble.right"
                    )
                }
            } label: {
                Image(
                    systemName:
                        "ellipsis"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .bold
                    )
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.85), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.09), lineWidth: 0.8)
                }
            }
        }
    }

    private var coachInsightCard:
        some View {
        ATHLTHCard {
            HStack(spacing: 8) {
                Image(
                    systemName:
                        "chart.bar.fill"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )

                Text(
                    recoveryAIText(
                        "TODAY'S INSIGHT",
                        "DAGENS INNSIKT"
                    )
                )
                .font(
                    .caption
                        .weight(.bold)
                )
                .tracking(1.1)
                .foregroundStyle(
                    .secondary
                )

                Spacer()
            }

            HStack(
                alignment: .center,
                spacing: 14
            ) {
                scoreBadge

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        context
                            .recoveryState
                    )
                    .font(
                        .headline
                    )

                    Text(
                        insight.summary
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(2)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer(
                    minLength: 0
                )
            }
            .padding(.top, 9)

            HStack(spacing: 7) {
                coachMetricTile(
                    title:
                        recoveryAIText(
                            "Sleep",
                            "Søvn"
                        ),
                    value:
                        sleepValue,
                    icon:
                        "moon.fill",
                    tint:
                        .indigo
                )

                coachMetricTile(
                    title: "HRV",
                    value:
                        hrvValue,
                    icon:
                        "heart.fill",
                    tint:
                        .red
                )

                coachMetricTile(
                    title:
                        recoveryAIText(
                            "RHR",
                            "Hvilepuls"
                        ),
                    value:
                        restingHeartRateValue,
                    icon:
                        "heart.fill",
                    tint:
                        .pink
                )

                coachMetricTile(
                    title:
                        recoveryAIText(
                            "Load",
                            "Belastning"
                        ),
                    value:
                        loadValue,
                    icon:
                        "chart.bar.fill",
                    tint:
                        .green
                )
            }
            .padding(.top, 11)

            coachMuscleReadinessSection
                .padding(.top, 12)
        }
    }

    // Show both areas estimated to need rest and areas estimated ready.
    // These percentages are not a medical measurement or a guarantee.
    private var coachVisibleMuscles: [RecoveryAIMuscleInput] {
        let ordered = context.muscles.sorted {
            $0.recoveryPercent < $1.recoveryPercent
        }
        let needingRest = Array(ordered.prefix(3))
        let ready = ordered.reversed().filter { muscle in
            !needingRest.contains(where: { $0.name == muscle.name })
        }.prefix(2)
        return needingRest + ready
    }

    private var coachMuscleReadinessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(recoveryAIText("MUSCLE RECOVERY · INSIGHTS", "MUSKELRESTITUSJON · INNSIKT"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                Spacer(minLength: 0)
            }

            if context.muscles.isEmpty {
                Text(recoveryAIText(
                    "No muscle estimates available yet.",
                    "Ingen beregnede muskelverdier tilgjengelig ennå."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(coachVisibleMuscles, id: \.name) { muscle in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(muscle.recoveryPercent < 60 ? Color.orange :
                                  (muscle.recoveryPercent < 85 ? Color.yellow : Color.green))
                            .frame(width: 6, height: 6)

                        Text(recoveryCoachMuscleName(muscle.name))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)

                        Spacer(minLength: 5)

                        Text("\(muscle.recoveryPercent)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }

                Button {
                    feedbackMuscleName = coachVisibleMuscles.first?.name ?? ""
                    feedbackFeeling = .sore
                    feedbackNote = ""
                    showingMuscleFeedbackSheet = true
                } label: {
                    Label(
                        recoveryAIText(
                            "Tell Coach how your muscles actually feel",
                            "Fortell Coach hvordan musklene kjennes"
                        ),
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Text(recoveryAIText(
                "Estimates, not a verdict. Your own feeling matters. Nothing is shared without confirming a question.",
                "Beregnete verdier, ikke en fasit. Din egen opplevelse teller. Ingenting deles uten at du bekrefter et spørsmål."
            ))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }

    private var coachMuscleFeedbackSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        recoveryAIText("Muscle group", "Muskelgruppe"),
                        selection: $feedbackMuscleName
                    ) {
                        ForEach(context.muscles, id: \.name) { muscle in
                            Text(recoveryCoachMuscleName(muscle.name))
                                .tag(muscle.name)
                        }
                    }

                    Picker(
                        recoveryAIText("How does it feel?", "Hvordan kjennes det?"),
                        selection: $feedbackFeeling
                    ) {
                        ForEach(RecoveryCoachMuscleFeeling.allCases) { feeling in
                            Text(feeling.title).tag(feeling)
                        }
                    }
                } header: {
                    Text(recoveryAIText("Your assessment", "Din vurdering"))
                } footer: {
                    Text(recoveryAIText(
                        "The estimate in Insights will not be overwritten.",
                        "Beregningen i Innsikt blir ikke overskrevet."
                    ))
                }

                Section(recoveryAIText("Optional note", "Valgfri kommentar")) {
                    TextField(
                        recoveryAIText(
                            "For example: legs feel heavy after yesterday",
                            "For eksempel: tunge bein etter gårsdagen"
                        ),
                        text: $feedbackNote,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                }

                Section {
                    Button {
                        prepareMuscleFeedbackQuestion()
                    } label: {
                        Label(
                            recoveryAIText(
                                "Add to question",
                                "Legg til i spørsmål"
                            ),
                            systemImage: "text.bubble.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(feedbackMuscleName.isEmpty)
                } footer: {
                    Text(recoveryAIText(
                        "Review the draft in chat before you send it. If you want Coach to compare it with your health data, choose health sharing and confirm that particular question.",
                        "Se gjennom utkastet i chatten før du sender. Vil du at Coach skal sammenligne med helsedata, må du velge deling og bekrefte akkurat det spørsmålet."
                    ))
                }
            }
            .navigationTitle(recoveryAIText("Correct muscle estimate", "Korriger muskelvurdering"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(recoveryAIText("Cancel", "Avbryt")) {
                        showingMuscleFeedbackSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func prepareMuscleFeedbackQuestion() {
        guard !feedbackMuscleName.isEmpty else { return }
        let name = recoveryCoachMuscleName(feedbackMuscleName)
        let note = feedbackNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction: String
        if ATHLTHLocalization.isNorwegian {
            correction = "Min egen opplevelse er at \(name.lowercased()) \(feedbackFeeling.message). " +
                (note.isEmpty ? "" : "Tilleggsinfo: \(note). ") +
                "Kan du justere treningsrådet etter dette? Muskelprosenten er bare et usikkert estimat."
        } else {
            correction = "I feel that \(name.lowercased()) \(feedbackFeeling.message). " +
                (note.isEmpty ? "" : "Additional context: \(note). ") +
                "Please adapt your training recommendation to how I feel. Muscle recovery percentages are estimates."
        }
        let previous = question.trimmingCharacters(in: .whitespacesAndNewlines)
        question = previous.isEmpty ? correction : previous + "\n\n" + correction
        showingMuscleFeedbackSheet = false
        // Draft only: the normal send and explicit health-sharing
        // confirmation remain the sole way to contact Groq.
    }

    private var scoreBadge:
        some View {
        ZStack {
            Circle()
                .stroke(
                    Color.primary
                        .opacity(0.07),
                    lineWidth: 6
                )

            Circle()
                .trim(
                    from: 0,
                    to:
                        Double(
                            context
                                .recoveryScore ??
                            0
                        ) / 100
                )
                .stroke(
                    scoreTint,
                    style:
                        StrokeStyle(
                            lineWidth: 6,
                            lineCap: .round
                        )
                )
                .rotationEffect(
                    .degrees(-90)
                )

            Text(
                context
                    .recoveryScore
                    .map(String.init) ??
                "—"
            )
            .font(
                .system(
                    size: 19,
                    weight: .bold,
                    design: .rounded
                )
            )
        }
        .frame(
            width: 58,
            height: 58
        )
    }

    private func coachMetricTile(
        title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            HStack(spacing: 4) {
                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 9,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    tint
                )

                Text(title)
                    .font(
                        .system(
                            size: 8.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(1)
            }

            Text(value)
                .font(
                    .system(
                        size: 12.5,
                        weight: .bold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.70
                )
        }
        .padding(
            .horizontal,
            8
        )
        .padding(
            .vertical,
            8
        )
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            tint.opacity(0.055),
            in:
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
        )
    }

    private var coachComposer:
        some View {
        VStack(spacing: 8) {
            if !quickQuestions.isEmpty {
                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    HStack {
                        Text(
                            recoveryAIText(
                                "Suggested next questions",
                                "Forslag til neste spørsmål"
                            )
                        )
                        .font(
                            .caption
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            .secondary
                        )

                        Spacer()

                        Button {
                            withAnimation(
                                .easeInOut(
                                    duration: 0.18
                                )
                            ) {
                                quickQuestions =
                                    contextAwareQuestions()
                            }
                        } label: {
                            Image(
                                systemName:
                                    "arrow.clockwise"
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                .secondary
                            )
                            .frame(
                                width: 28,
                                height: 28
                            )
                            .contentShape(
                                Circle()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            recoveryAIText(
                                "Refresh suggestions",
                                "Oppdater forslag"
                            )
                        )
                    }
                    .padding(
                        .horizontal
                    )

                    ScrollView(
                        .horizontal,
                        showsIndicators: false
                    ) {
                        HStack(
                            spacing: 8
                        ) {
                            ForEach(
                                quickQuestions,
                                id: \.self
                            ) {
                                suggestion in
                                Button {
                                    requestAnswer(suggestion)
                                } label: {
                                    VStack(
                                        alignment:
                                            .leading,
                                        spacing: 7
                                    ) {
                                        Image(
                                            systemName:
                                                quickQuestionIcon(
                                                    for:
                                                        suggestion
                                                )
                                        )
                                        .font(
                                            .system(
                                                size: 12,
                                                weight:
                                                    .semibold
                                            )
                                        )
                                        .foregroundStyle(
                                            .indigo
                                        )

                                        Text(
                                            suggestion
                                        )
                                        .font(
                                            .caption
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .primaryText
                                        )
                                        .lineLimit(2)
                                        .multilineTextAlignment(
                                            .leading
                                        )
                                    }
                                    .padding(11)
                                    .frame(
                                        width: 165,
                                        height: 78,
                                        alignment:
                                            .leading
                                    )
                                    .background(
                                        Color.white
                                            .opacity(
                                                0.72
                                            ),
                                        in:
                                            RoundedRectangle(
                                                cornerRadius:
                                                    16,
                                                style:
                                                    .continuous
                                            )
                                    )
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius:
                                                16,
                                            style:
                                                .continuous
                                        )
                                        .stroke(
                                            Color.primary
                                                .opacity(
                                                    0.045
                                                ),
                                            lineWidth:
                                                0.8
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    isAsking
                                )
                            }
                        }
                        .padding(
                            .horizontal
                        )
                    }
                }
            }

            Button {
                if !aiConsentApproved {
                    pendingShareAfterConsent = false
                    draftHealthPermission = false
                    draftAutomaticHealthPermission = false
                    showingCoachConsentSheet = true
                } else if !healthConsentApproved {
                    pendingShareAfterConsent = true
                    draftHealthPermission = false
                    draftAutomaticHealthPermission = false
                    showingCoachConsentSheet = true
                } else {
                    shareHealthForNextQuestion.toggle()
                }
            } label: {
                Label(
                    shareHealthForNextQuestion
                        ? recoveryAIText(
                            "Health data selected · confirm when sending",
                            "Helsedata valgt · bekreft ved sending"
                        )
                        : recoveryAIText(
                            "Share health data for next question",
                            "Del helsedata i neste spørsmål"
                        ),
                    systemImage: shareHealthForNextQuestion
                        ? "checkmark.shield.fill"
                        : "lock.shield"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    shareHealthForNextQuestion
                        ? ATHLTHTheme.vitality
                        : ATHLTHTheme.mutedText
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                recoveryAIText(
                    "Normal questions are sent to Groq without health data. Activate and confirm to include your health data for one question.",
                    "Vanlige spørsmål sendes til Groq uten helsedata. Aktiver og bekreft for å inkludere helsedata i ett spørsmål."
                )
            )

            Text(
                recoveryAIText(
                    "Your message goes to Groq. Health metrics are added only after your confirmation.",
                    "Meldingen din sendes til Groq. Helsedata legges bare ved etter din bekreftelse."
                )
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Menu {
                    Button {
                        withAnimation(
                            .easeInOut(
                                duration: 0.18
                            )
                        ) {
                            quickQuestions =
                                contextAwareQuestions()
                        }
                    } label: {
                        Label(
                            recoveryAIText(
                                "New suggestions",
                                "Nye forslag"
                            ),
                            systemImage:
                                "arrow.clockwise"
                        )
                    }

                    Button(
                        role: .destructive
                    ) {
                        messages.removeAll()
                        quickQuestions =
                            contextAwareQuestions()
                        errorMessage = nil
                        RecoveryCoachConversationPersistence.delete(
                        userID: session.profile.userID
                    )
                    } label: {
                        Label(
                            recoveryAIText(
                                "Start new conversation",
                                "Start ny samtale"
                            ),
                            systemImage:
                                "bubble.left.and.exclamationmark.bubble.right"
                        )
                    }
                } label: {
                    Image(
                        systemName: "plus"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .background(
                        Color.white
                            .opacity(0.86),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                ATHLTHTheme
                                    .border,
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(.plain)

                TextField(
                    recoveryAIText(
                        "Ask ATHLTH Coach…",
                        "Spør ATHLTH Coach…"
                    ),
                    text: $question,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    requestAnswer(question)
                }
                .padding(
                    .horizontal,
                    15
                )
                .padding(
                    .vertical,
                    11
                )
                .background(
                    Color.white
                        .opacity(0.93),
                    in:
                        RoundedRectangle(
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
                        Color.white
                            .opacity(0.92),
                        lineWidth: 0.8
                    )
                }
                .shadow(
                    color:
                        ATHLTHTheme
                            .accentDeep
                            .opacity(0.035),
                    radius: 8,
                    y: 3
                )

                Button {
                    requestAnswer(question)
                } label: {
                    Image(
                        systemName:
                            "arrow.up"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .background(
                        ATHLTHTheme
                            .vitality,
                        in: Circle()
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    question
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty ||
                    isAsking
                )
                .opacity(
                    question
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                        ? 0.45
                        : 1
                )
            }
            .padding(
                .horizontal,
                14
            )
        }
        .padding(
            .vertical,
            9
        )
        .recoveryCoachLegacyConversationComposerChrome()
    }

    @ViewBuilder
    private func coachMessageBubble(
        _ message: RecoveryCoachMessage
    ) -> some View {
        HStack(alignment: .bottom) {
            if message.role == .user {
                Spacer(
                    minLength: 54
                )
            }

            if message.role == .assistant {
                Image(
                    systemName: "sparkles"
                )
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .white
                )
                .frame(
                    width: 28,
                    height: 28
                )
                .background(
                    Color(
                        red: 0.11,
                        green: 0.14,
                        blue: 0.20
                    ),
                    in: Circle()
                )
            }

            VStack(
                alignment:
                    message.role == .user
                        ? .trailing
                        : .leading,
                spacing: 4
            ) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(
                        message.role == .user
                            ? Color.white
                            : ATHLTHTheme
                                .primaryText
                    )
                    .lineSpacing(3)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(
                        .horizontal,
                        15
                    )
                    .padding(
                        .vertical,
                        11
                    )
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        ATHLTHTheme
                                            .vitality,
                                        ATHLTHTheme
                                            .accent
                                            .opacity(0.92)
                                    ],
                                    startPoint:
                                        .topLeading,
                                    endPoint:
                                        .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(
                                Color.white
                                    .opacity(0.96)
                            ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 20,
                                style:
                                    .continuous
                            )
                    )
                    .overlay {
                        if message.role != .user {
                            RoundedRectangle(
                                cornerRadius: 20,
                                style: .continuous
                            )
                            .stroke(
                                Color.white
                                    .opacity(0.92),
                                lineWidth: 0.8
                            )
                        }
                    }
                    .shadow(
                        color:
                            message.role == .user
                                ? ATHLTHTheme
                                    .vitality
                                    .opacity(0.08)
                                : ATHLTHTheme
                                    .accentDeep
                                    .opacity(0.04),
                        radius: 8,
                        y: 3
                    )

                Text(
                    message.createdAt
                        .formatted(
                            date: .omitted,
                            time: .shortened
                        )
                )
                .font(.caption2)
                .foregroundStyle(
                    .tertiary
                )
            }

            if message.role ==
                .assistant {
                Spacer(
                    minLength: 54
                )
            }
        }
        .frame(
            maxWidth: .infinity
        )
    }

    @MainActor
    private func loadConversationIfNeeded() {
        guard !didLoadConversation else {
            return
        }
        didLoadConversation = true

        let currentSignature =
            try? RecoveryAIService
                .cacheSignature(
                    for: context
                )

        if let saved =
                RecoveryCoachConversationPersistence
                    .load(
                        userID:
                            session
                                .profile
                                .userID
                    ) {
            messages =
                saved.messages

            if saved.contextSignature ==
                currentSignature,
               !saved.quickQuestions.isEmpty {
                quickQuestions =
                    normalizedQuestions(
                        saved
                            .quickQuestions
                    )
            } else {
                quickQuestions =
                    contextAwareQuestions()
                persistConversation(
                    contextSignature:
                        currentSignature
                )
            }
        } else {
            quickQuestions =
                contextAwareQuestions()
            persistConversation(
                contextSignature:
                    currentSignature
            )
        }
    }

    @MainActor
    private func requestAnswer(_ rawQuestion: String) {
        let clean = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isAsking else { return }

        guard aiConsentApproved,
              RecoveryCoachConsentPreferences.load(
                userID: session.profile.userID
              ) != nil
        else {
            pendingShareAfterConsent = false
            draftHealthPermission = false
            showingCoachConsentSheet = true
            return
        }

        if RecoveryCoachHealthSharingPreferences.canAutomaticallyShare(
            userID: session.profile.userID
        ) {
            // Still blocked by the release-level compliance gate. Should
            // this ever be enabled, the user must have explicitly opted in
            // through the separate v2 privacy choice.
            Task {
                await ask(clean, shareHealthData: true)
            }
        } else if shareHealthForNextQuestion {
            pendingHealthQuestion = clean
            showingHealthShareConfirmation = true
        } else {
            Task {
                await ask(clean, shareHealthData: false)
            }
        }
    }

    @MainActor
    private func ask(
        _ rawQuestion: String,
        shareHealthData: Bool
    ) async {
        let clean =
            rawQuestion
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !clean.isEmpty,
              !isAsking,
              aiConsentApproved,
              let currentConsent = RecoveryCoachConsentPreferences.load(
                  userID: session.profile.userID
              ),
              !shareHealthData || (
                  currentConsent.healthSharingAllowed &&
                  RecoveryCoachHealthSharingPreferences.effectiveMode(
                      userID: session.profile.userID
                  ) != .off
              )
        else {
            return
        }

        let priorHistory =
            messages
        messages.append(
            RecoveryCoachMessage(
                role: .user,
                text: clean
            )
        )

        question = ""
        isAsking = true
        errorMessage = nil
        persistConversation()
        defer {
            isAsking = false
        }

        do {
            let reply =
                try await service.ask(
                    clean,
                    context: context,
                    history: priorHistory,
                    shareHealthData: shareHealthData,
                    shareHealthAutomatically:
                        RecoveryCoachHealthSharingPreferences.canAutomaticallyShare(
                            userID: session.profile.userID
                        )
                )

            messages.append(
                RecoveryCoachMessage(
                    role: .assistant,
                    text:
                        reply.answer
                )
            )

            let nextQuestions =
                normalizedQuestions(
                    reply
                        .quickQuestions
                )

            quickQuestions =
                nextQuestions.isEmpty
                    ? contextAwareQuestions()
                    : nextQuestions

            persistConversation()
        } catch {
            errorMessage =
                error.localizedDescription
            quickQuestions =
                contextAwareQuestions()
            persistConversation()
        }
    }

    private func normalizedQuestions(
        _ questions: [String]
    ) -> [String] {
        let asked =
            Set(
                messages
                    .filter {
                        $0.role == .user
                    }
                    .suffix(12)
                    .map {
                        $0.text
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .lowercased()
                    }
            )

        var seen = Set<String>()
        var result: [String] = []

        for question in questions {
            let clean =
                question
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
            let key =
                clean.lowercased()

            guard !clean.isEmpty,
                  !asked.contains(key),
                  seen.insert(key)
                    .inserted
            else {
                continue
            }

            result.append(clean)

            if result.count == 3 {
                break
            }
        }

        return result
    }

    private func contextAwareQuestions()
        -> [String] {
        var candidates =
            insight.quickQuestions

        if let sleep =
                context.sleepSeconds,
           let baseline =
                context
                    .baselineSleepSeconds,
           baseline > 0,
           sleep <
                baseline * 0.90 {
            candidates.insert(
                recoveryAIText(
                    "How should shorter sleep affect today's training?",
                    "Hvordan bør kortere søvn påvirke treningen i dag?"
                ),
                at: 0
            )
        }

        if let baseline =
                context
                    .chronicWeeklyAverageMinutes,
           baseline > 0,
           context
                .acuteTrainingMinutes >
                baseline * 1.30 {
            candidates.insert(
                recoveryAIText(
                    "Is my recent training load too high?",
                    "Er treningsbelastningen min for høy nå?"
                ),
                at: 0
            )
        }

        if let leastRecovered =
                context.muscles
                    .min(
                        by: {
                            $0.recoveryPercent <
                            $1.recoveryPercent
                        }
                    ),
           leastRecovered
                .recoveryPercent < 70 {
            candidates.insert(
                recoveryAIText(
                    "How should I train around my least recovered muscles?",
                    "Hvordan bør jeg trene med de minst restituerte musklene?"
                ),
                at: 0
            )
        }

        if let stress =
                context.checkIn.stress,
           stress >= 4 {
            candidates.insert(
                recoveryAIText(
                    "Should high stress change today's workout?",
                    "Bør høyt stress endre dagens økt?"
                ),
                at: 0
            )
        }

        candidates.append(
            recoveryAIText(
                "What should I prioritize for better recovery tonight?",
                "Hva bør jeg prioritere for bedre restitusjon i kveld?"
            )
        )
        candidates.append(
            recoveryAIText(
                "What is the most important signal in my data right now?",
                "Hva er det viktigste signalet i dataene mine akkurat nå?"
            )
        )

        return normalizedQuestions(
            candidates
        )
    }

    @MainActor
    private func persistConversation(
        contextSignature:
            String? = nil
    ) {
        let signature =
            contextSignature ??
            (
                try? RecoveryAIService
                    .cacheSignature(
                        for: context
                    )
            )

        RecoveryCoachConversationPersistence
            .save(
                RecoveryCoachConversationState(
                    messages: messages,
                    quickQuestions:
                        quickQuestions,
                    contextSignature:
                        signature
                ),
                userID:
                    session.profile
                        .userID
            )
    }

    private func quickQuestionIcon(
        for question: String
    ) -> String {
        let value =
            question.lowercased()

        if value.contains("sleep") ||
            value.contains("søvn") {
            return "moon.fill"
        }

        if value.contains("strength") ||
            value.contains("styrke") {
            return "dumbbell.fill"
        }

        if value.contains("run") ||
            value.contains("løp") ||
            value.contains("interval") {
            return "figure.run"
        }

        if value.contains("recovery") ||
            value.contains("restitusjon") {
            return "heart.fill"
        }

        return "sparkles"
    }

    private var scoreTint:
        Color {
        guard let score =
                context.recoveryScore
        else {
            return .gray
        }

        switch score {
        case 80...:
            return .green
        case 60..<80:
            return .orange
        default:
            return .red
        }
    }

    private var sleepValue:
        String {
        guard let seconds =
                context.sleepSeconds
        else {
            return "—"
        }

        let minutes =
            Int(
                (
                    seconds /
                    60
                )
                .rounded()
            )

        return "\(minutes / 60)t \(minutes % 60)m"
    }

    private var hrvValue:
        String {
        context.hrvMilliseconds
            .map {
                "\(Int($0.rounded())) ms"
            } ??
        "—"
    }

    private var restingHeartRateValue:
        String {
        context.restingHeartRate
            .map {
                "\(Int($0.rounded())) bpm"
            } ??
        "—"
    }

    private var loadValue:
        String {
        let baseline =
            context
                .chronicWeeklyAverageMinutes

        guard let baseline,
              baseline > 0
        else {
            return "\(Int(context.acuteTrainingMinutes.rounded()))m"
        }

        return String(
            format:
                "%.1fx",
            context
                .acuteTrainingMinutes /
            baseline
        )
    }
}
