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
            } else if !session
                .aiHealthDataSharingEnabled {
                ContentUnavailableView(
                    recoveryAIText(
                        "Coach health access is off",
                        "Tilgang til helsedata for Coach er av"
                    ),
                    systemImage:
                        "lock.shield.fill",
                    description:
                        Text(
                            recoveryAIText(
                                "Enable health-data use in Settings → Privacy & Data to use ATHLTH Coach.",
                                "Aktiver bruk av helsedata i Innstillinger → Personvern og data for å bruke ATHLTH Coach."
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
                    .prefix(8)
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
        guard session.hasPaidAccess,
              session
                .aiHealthDataSharingEnabled
        else {
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

        insight =
            try? await RecoveryAIService()
                .generate(
                    coachContext
                )
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

    private let service = RecoveryAIService()
    private let bottomAnchorID =
        "athlth-recovery-coach-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    coachInsightCard

                    if messages.isEmpty {
                        Text(
                            recoveryAIText(
                                "Ask a question to start a conversation. Coach remembers what you talk about on this device.",
                                "Still et spørsmål for å starte en samtale. Coach husker det dere snakker om på denne enheten."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    } else {
                        ForEach(messages) {
                            message in
                            coachMessageBubble(
                                message
                            )
                        }
                    }

                    if isAsking {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)

                            Text(
                                recoveryAIText(
                                    "ATHLTH is thinking…",
                                    "ATHLTH tenker…"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
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
                            Color.primary
                                .opacity(0.035),
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        16,
                                    style:
                                        .continuous
                                )
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(
                                .horizontal,
                                4
                            )
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding()
            }
            .scrollDismissesKeyboard(
                .interactively
            )
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        Color.indigo
                            .opacity(0.08)
                )
            )
            .onChange(
                of: messages.count
            ) { _, _ in
                withAnimation(
                    .easeOut(
                        duration: 0.20
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
                        duration: 0.20
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
        .safeAreaInset(edge: .bottom) {
            coachComposer
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(
            .inline
        )
        .toolbarBackground(
            .visible,
            for: .navigationBar
        )
        .toolbarBackground(
            Color.white.opacity(0.94),
            for: .navigationBar
        )
        .toolbar {
            ToolbarItem(
                placement: .principal
            ) {
                coachNavigationHeader
            }

            if showsDoneButton {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        recoveryAIText(
                            "Done",
                            "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            } else {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
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
                    } label: {
                        Image(
                            systemName:
                                "ellipsis"
                        )
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )
                        .contentShape(
                            Circle()
                        )
                    }
                }
            }
        }
        .onAppear {
            coachPinned =
                RecoveryCoachInboxPreferences
                    .isPinned(
                        userID:
                            session.profile
                                .userID
                    )
        }
    }

    private var coachNavigationHeader:
        some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(
                                    red: 0.10,
                                    green: 0.13,
                                    blue: 0.19
                                ),
                                Color.indigo
                                    .opacity(0.82)
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
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .white
                )
            }
            .frame(
                width: 34,
                height: 34
            )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text("ATHLTH Coach")
                    .font(
                        .system(
                            size: 14,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                HStack(spacing: 4) {
                    Text(
                        recoveryAIText(
                            "Online",
                            "På nett"
                        )
                    )
                    .font(
                        .system(
                            size: 10.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    Circle()
                        .fill(
                            Color.green
                        )
                        .frame(
                            width: 5,
                            height: 5
                        )
                }
            }
        }
        .accessibilityElement(
            children: .combine
        )
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
        }
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
                                    Task {
                                        await ask(
                                            suggestion
                                        )
                                    }
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
                        persistConversation()
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
                        width: 42,
                        height: 42
                    )
                    .background(
                        Color.primary
                            .opacity(0.055),
                        in: Circle()
                    )
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
                    Task {
                        await ask(
                            question
                        )
                    }
                }
                .padding(
                    .horizontal,
                    14
                )
                .padding(
                    .vertical,
                    10
                )
                .background(
                    Color.white
                        .opacity(0.86),
                    in:
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .stroke(
                        Color.primary
                            .opacity(0.06),
                        lineWidth: 0.8
                    )
                }

                Button {
                    Task {
                        await ask(
                            question
                        )
                    }
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
                        width: 42,
                        height: 42
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
            .padding(.horizontal)
        }
        .padding(.vertical, 9)
        .background(
            .ultraThinMaterial
        )
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
                        13
                    )
                    .padding(
                        .vertical,
                        10
                    )
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(
                                ATHLTHTheme
                                    .vitality
                            )
                            : AnyShapeStyle(
                                Color.white
                                    .opacity(
                                        0.82
                                    )
                            ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 18,
                                style:
                                    .continuous
                            )
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
    private func ask(
        _ rawQuestion: String
    ) async {
        let clean =
            rawQuestion
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !clean.isEmpty,
              !isAsking
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
                    history:
                        priorHistory
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
