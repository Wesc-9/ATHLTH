import SwiftUI
import UIKit

struct ATHLTHInsightsView: View {
    var onSelectTab: (Int) -> Void = { _ in }

    @EnvironmentObject private var health: HealthKitManager

    @State private var trendSnapshot: HealthProgressSnapshot?
    @State private var isLoadingTrend = false
    @State private var trendError: String?
    @State private var scenarioSessionsPerWeek = 4
    @State private var scenarioFocus: InsightsScenarioFocus = .consistency

    var body: some View {
        let immersive =
            UIDevice.current.userInterfaceIdiom == .pad ||
            UIScreen.main.bounds.width >= 390

        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: ATHLTHTheme.accentDeep.opacity(0.62)
            ) {
                ATHLTHTabHero(
                    imageName: "ProgressHero",
                    title: "Insights",
                    subtitle: "Understand what is happening, what changed and what it means for your training.",
                    height: 236,
                    alignment: .leading,
                    focalOffsetX: immersive ? 4 : 16,
                    focalOffsetY: immersive ? 6 : 16,
                    titleFontSize: immersive ? 31 : 30,
                    copyWidthFraction: immersive ? 0.72 : 0.84,
                    immersiveCopy: immersive
                )
            } content: {
                LazyVStack(spacing: 16) {
                    pulseCard
                    nowCard
                    whatChangedCard
                    trendCard
                    whyItMattersCard
                    whatIfCard
                    replayCard
                    detailDestinationsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                if !health.shouldDeferAutomaticHealthWork {
                    await health.refreshAll()
                }
                await loadTrend()
            }
            .task {
                await loadTrend()
            }
        }
    }

    private var pulseCard: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(pulseTint.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: pulseIcon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(pulseTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ATHLTH Pulse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(pulseTitle)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(pulseDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if let score = health.recovery.score {
                    VStack(spacing: 1) {
                        Text("\(score)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(pulseTint)
                            .contentTransition(.numericText())

                        Text("/100")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        }
    }

    private var nowCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Now")

            Text("Your current signals, without making you interpret a dashboard first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                insightMetric(
                    title: "Sleep",
                    value: sleepValue,
                    detail: sleepDetail,
                    icon: "moon.fill",
                    tint: .purple
                )

                insightMetric(
                    title: "HRV",
                    value: hrvValue,
                    detail: hrvDetail,
                    icon: "waveform.path.ecg",
                    tint: .blue
                )

                insightMetric(
                    title: "Resting HR",
                    value: restingHRValue,
                    detail: restingHRDetail,
                    icon: "heart.fill",
                    tint: .red
                )

                insightMetric(
                    title: "Recovery",
                    value: recoveryValue,
                    detail: health.recovery.state.title,
                    icon: health.recovery.state.systemImage,
                    tint: pulseTint
                )
            }
            .padding(.top, 12)
        }
    }

    private var whatChangedCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("What changed?")
                        .font(.title3.weight(.bold))

                    Text("Meaningful differences versus your previous 28 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "sparkles")
                    .foregroundStyle(ATHLTHTheme.premiumGold)
            }

            if isLoadingTrend {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if whatChangedItems.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "equal.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("No major shift detected")
                            .font(.subheadline.weight(.semibold))

                        Text(
                            health.hasRequestedAuthorization
                                ? "Your recent 28-day pattern is broadly similar to the previous period, or there is not enough comparable data yet."
                                : "Connect Apple Health to let ATHLTH compare your training and health trends."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                let items = Array(whatChangedItems.prefix(3))

                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: item.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(item.tint)
                                .frame(width: 34, height: 34)
                                .background(
                                    item.tint.opacity(0.10),
                                    in: RoundedRectangle(
                                        cornerRadius: 11,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)

                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var trendCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trend")
                        .font(.title3.weight(.bold))

                    Text("Last 28 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ATHLTHProgressView()
                } label: {
                    HStack(spacing: 4) {
                        Text("All progress")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            if let snapshot = trendSnapshot {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    trendMetric(
                        title: "Workouts",
                        value: "\(snapshot.workoutCount)",
                        change: snapshot.workoutChangePercent,
                        icon: "dumbbell.fill"
                    )

                    trendMetric(
                        title: "Training",
                        value: formatDuration(snapshot.trainingDuration),
                        change: snapshot.trainingDurationChangePercent,
                        icon: "clock.fill"
                    )

                    trendMetric(
                        title: "Distance",
                        value: String(
                            format: "%.1f km",
                            snapshot.workoutDistanceMeters / 1_000
                        ),
                        change: snapshot.workoutDistanceChangePercent,
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    trendMetric(
                        title: "Daily steps",
                        value: snapshot.averageDailySteps.map {
                            Int($0.rounded()).formatted()
                        } ?? "—",
                        change: snapshot.stepsChangePercent,
                        icon: "figure.walk"
                    )
                }
                .padding(.top, 12)
            } else if let trendError {
                Label(
                    trendError,
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else {
                Text("ATHLTH will show trends when comparable training data is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
        }
    }

    private var whyItMattersCard: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 44, height: 44)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Why it matters")
                        .font(.title3.weight(.bold))

                    Text(whyItMattersText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Button {
                onSelectTab(1)
            } label: {
                HStack {
                    Label(
                        "Use this in today's training",
                        systemImage: "dumbbell.fill"
                    )

                    Spacer()

                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
            .padding(.top, 12)
        }
    }

    private var whatIfCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("What if?")
                        .font(.title3.weight(.bold))

                    Text("Model a training week before you commit to it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            Picker("Scenario focus", selection: $scenarioFocus) {
                ForEach(InsightsScenarioFocus.allCases) { focus in
                    Text(focus.title).tag(focus)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 12)

            Stepper(
                value: $scenarioSessionsPerWeek,
                in: 2...7
            ) {
                HStack {
                    Text("Sessions per week")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(scenarioSessionsPerWeek)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }
            .padding(.top, 12)

            HStack(spacing: 10) {
                simulatorMetric(
                    title: "Baseline",
                    value: "\(Int(baselineSessionMinutes.rounded())) min",
                    subtitle: "avg. session"
                )

                simulatorMetric(
                    title: "Scenario",
                    value: "\(Int(projectedWeeklyMinutes.rounded())) min",
                    subtitle: "per week"
                )
            }
            .padding(.top, 10)

            Text(scenarioExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Label(
                "Scenario only — this is not a prediction of future fitness or medical outcome.",
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 8)

            Button {
                onSelectTab(1)
            } label: {
                HStack {
                    Label("Build this in Train", systemImage: "wand.and.stars")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
            .padding(.top, 12)
        }
    }

    private var replayCard: some View {
        NavigationLink {
            GhostReplaySimulatorView()
        } label: {
            ATHLTHCard {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Race yourself")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(
                            "Replay an outdoor run and compare yourself against your previous effort — the Ghost Race engine you already use, now surfaced as an insight tool."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var detailDestinationsCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Go deeper")

            VStack(spacing: 0) {
                NavigationLink {
                    ATHLTHRecoveryView(onSelectTab: onSelectTab)
                } label: {
                    insightDestinationRow(
                        title: "Recovery details",
                        subtitle: "Readiness, sleep, soreness and recovery tools",
                        icon: "leaf.fill"
                    )
                }

                Divider()
                    .padding(.leading, 46)

                NavigationLink {
                    ATHLTHProgressView()
                } label: {
                    insightDestinationRow(
                        title: "Progress details",
                        subtitle: "Charts, records, consistency and achievements",
                        icon: "chart.bar.fill"
                    )
                }
            }
            .padding(.top, 6)
        }
    }

    private func insightMetric(
        title: String,
        value: String,
        detail: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)

                Spacer()
            }

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private func trendMetric(
        title: String,
        value: String,
        change: Double?,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let change {
                HStack(spacing: 3) {
                    Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                    Text("\(Int(abs(change).rounded()))%")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(change >= 0 ? ATHLTHTheme.accent : .orange)
            } else {
                Text("No comparison")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private func simulatorMetric(
        title: String,
        value: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ATHLTHTheme.champagneSoft.opacity(0.55),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private func insightDestinationRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private var pulseTitle: String {
        switch health.recovery.state {
        case .ready:
            return "STRONG"
        case .balanced:
            return "BALANCED"
        case .takeItEasy, .recover:
            return "RECOVER"
        case .buildingBaseline:
            return "LEARNING"
        }
    }

    private var pulseIcon: String {
        switch health.recovery.state {
        case .ready:
            return "bolt.heart.fill"
        case .balanced:
            return "circle.hexagongrid.fill"
        case .takeItEasy:
            return "gauge.with.dots.needle.33percent"
        case .recover:
            return "bed.double.fill"
        case .buildingBaseline:
            return "waveform.path.ecg"
        }
    }

    private var pulseTint: Color {
        switch health.recovery.state {
        case .ready:
            return ATHLTHTheme.vitality
        case .balanced:
            return ATHLTHTheme.accent
        case .takeItEasy:
            return .orange
        case .recover:
            return .red
        case .buildingBaseline:
            return .blue
        }
    }

    private var pulseDetail: String {
        switch health.recovery.state {
        case .ready:
            return "Your current recovery signals are supportive of a normal training day."
        case .balanced:
            return "Your current signals look broadly steady. Use how you feel and the planned session together."
        case .takeItEasy:
            return "Some recovery signals are softer than your recent baseline. Keep intensity flexible."
        case .recover:
            return "Recovery signals currently point toward a lighter day and more recovery focus."
        case .buildingBaseline:
            return "ATHLTH is still learning enough recent sleep, HRV and resting-heart-rate data to establish your baseline."
        }
    }

    private var sleepValue: String {
        guard health.sleep.totalAsleep > 0 else { return "—" }
        return formatDuration(health.sleep.totalAsleep)
    }

    private var sleepDetail: String {
        guard health.sleep.totalAsleep > 0 else {
            return "No recent sleep data"
        }

        if let baseline = health.recovery.averageSleepDuration,
           baseline > 0 {
            let deltaMinutes =
                (health.sleep.totalAsleep - baseline) / 60

            if abs(deltaMinutes) < 15 {
                return "Near your baseline"
            }

            return deltaMinutes > 0
                ? "\(Int(abs(deltaMinutes).rounded())) min above baseline"
                : "\(Int(abs(deltaMinutes).rounded())) min below baseline"
        }

        return "Last sleep period"
    }

    private var hrvValue: String {
        health.heart.hrvMilliseconds.map {
            "\(Int($0.rounded())) ms"
        } ?? "—"
    }

    private var hrvDetail: String {
        guard let current = health.heart.hrvMilliseconds else {
            return "No recent HRV"
        }

        guard let baseline = health.recovery.baselineHRVMilliseconds,
              baseline > 0
        else {
            return "Building baseline"
        }

        let difference = current - baseline
        if abs(difference) < 2 {
            return "Near your baseline"
        }

        return difference > 0
            ? "\(Int(abs(difference).rounded())) ms above baseline"
            : "\(Int(abs(difference).rounded())) ms below baseline"
    }

    private var restingHRValue: String {
        health.heart.restingHeartRate.map {
            "\(Int($0.rounded())) bpm"
        } ?? "—"
    }

    private var restingHRDetail: String {
        guard let current = health.heart.restingHeartRate else {
            return "No recent resting HR"
        }

        guard let baseline = health.recovery.baselineRestingHeartRate,
              baseline > 0
        else {
            return "Building baseline"
        }

        let difference = current - baseline
        if abs(difference) < 1.5 {
            return "Near your baseline"
        }

        return difference > 0
            ? "\(Int(abs(difference).rounded())) bpm above baseline"
            : "\(Int(abs(difference).rounded())) bpm below baseline"
    }

    private var recoveryValue: String {
        health.recovery.score.map { "\($0)/100" } ?? "—"
    }

    private var whatChangedItems: [InsightsChangeItem] {
        guard let snapshot = trendSnapshot else {
            return []
        }

        var items: [InsightsChangeItem] = []

        appendChange(
            to: &items,
            percent: snapshot.trainingDurationChangePercent,
            threshold: 8,
            noun: "Training time",
            icon: "clock.arrow.circlepath",
            tint: ATHLTHTheme.accent
        )

        appendChange(
            to: &items,
            percent: snapshot.workoutDistanceChangePercent,
            threshold: 8,
            noun: "Distance",
            icon: "point.topleft.down.to.point.bottomright.curvepath",
            tint: .blue
        )

        appendChange(
            to: &items,
            percent: snapshot.workoutChangePercent,
            threshold: 10,
            noun: "Workout frequency",
            icon: "calendar.badge.clock",
            tint: ATHLTHTheme.vitality
        )

        appendChange(
            to: &items,
            percent: snapshot.sleepChangePercent,
            threshold: 5,
            noun: "Average sleep",
            icon: "moon.stars.fill",
            tint: .purple
        )

        appendChange(
            to: &items,
            percent: snapshot.stepsChangePercent,
            threshold: 10,
            noun: "Daily steps",
            icon: "figure.walk",
            tint: .orange
        )

        return items.sorted {
            abs($0.percent) > abs($1.percent)
        }
    }

    private func appendChange(
        to items: inout [InsightsChangeItem],
        percent: Double?,
        threshold: Double,
        noun: String,
        icon: String,
        tint: Color
    ) {
        guard let percent,
              abs(percent) >= threshold
        else {
            return
        }

        let direction = percent >= 0 ? "up" : "down"
        let title = "\(noun) is \(direction) \(Int(abs(percent).rounded()))%"

        items.append(
            InsightsChangeItem(
                id: "\(noun)-\(direction)",
                title: title,
                detail: "Compared with the previous 28-day period.",
                icon: icon,
                tint: tint,
                percent: percent
            )
        )
    }

    private var whyItMattersText: String {
        if health.recovery.state == .recover {
            return "Recovery signals are currently below your usual pattern. ATHLTH treats this as context for today's decision — not a diagnosis — so consider keeping the planned workout flexible rather than chasing volume."
        }

        if health.recovery.state == .takeItEasy {
            return "Your recovery signals are softer than usual. A normal session can still be appropriate, but this is a useful day to pay attention to intensity and how the warm-up feels."
        }

        if let change = trendSnapshot?.trainingDurationChangePercent,
           change >= 25 {
            return "Training time has risen about \(Int(change.rounded()))% versus the previous 28 days. That is a meaningful load shift, so pairing the trend with recovery and how you feel gives more context than either signal alone."
        }

        if let change = trendSnapshot?.workoutDistanceChangePercent,
           change >= 25 {
            return "Distance has risen about \(Int(change.rounded()))% versus the previous period. ATHLTH highlights that change so you can decide whether today's plan still fits the direction you are taking."
        }

        if let change = trendSnapshot?.sleepChangePercent,
           change <= -10 {
            return "Average sleep is lower than the previous 28 days. ATHLTH surfaces the change next to training load so you can judge today's plan with both sides of the picture visible."
        }

        return "No single signal is dominating the picture right now. The useful pattern is the combination of your current recovery, recent training load and how consistently you are training."
    }

    private var baselineSessionMinutes: Double {
        let calendar = Calendar.current
        let cutoff = calendar.date(
            byAdding: .day,
            value: -28,
            to: Date()
        ) ?? Date().addingTimeInterval(-2_419_200)

        let relevant = health.workouts.filter {
            $0.startDate >= cutoff &&
            (
                scenarioFocus == .consistency ||
                $0.activity == .running
            )
        }

        guard !relevant.isEmpty else {
            if let snapshot = trendSnapshot,
               snapshot.workoutCount > 0 {
                return max(
                    (snapshot.trainingDuration / 60) /
                        Double(snapshot.workoutCount),
                    20
                )
            }

            return 45
        }

        let totalMinutes = relevant.reduce(0.0) {
            $0 + ($1.duration / 60)
        }

        return max(totalMinutes / Double(relevant.count), 20)
    }

    private var projectedWeeklyMinutes: Double {
        baselineSessionMinutes *
            Double(scenarioSessionsPerWeek)
    }

    private var scenarioExplanation: String {
        switch scenarioFocus {
        case .consistency:
            return "At your recent average session length, \(scenarioSessionsPerWeek) sessions would represent roughly \(Int(projectedWeeklyMinutes.rounded())) training minutes per week. Use this as a planning frame, not a target you must hit."
        case .fiveK:
            return "This uses your recent running-session duration as the baseline. A \(scenarioSessionsPerWeek)-run week could then be shaped in Train with a mix of easy work, quality and recovery rather than making every run hard."
        case .halfMarathon:
            return "For a half-marathon scenario, ATHLTH can use \(scenarioSessionsPerWeek) weekly runs as the planning structure and let Train build progression around your calendar and current history."
        }
    }

    @MainActor
    private func loadTrend() async {
        guard health.healthDataAvailable else {
            trendSnapshot = nil
            trendError = "Apple Health is unavailable on this device."
            return
        }

        guard health.hasRequestedAuthorization else {
            trendSnapshot = nil
            trendError = "Connect Apple Health to compare your recent trends."
            return
        }

        isLoadingTrend = true
        trendError = nil
        defer { isLoadingTrend = false }

        let calendar = Calendar.current
        let end = Date()
        let start =
            calendar.date(
                byAdding: .day,
                value: -28,
                to: end
            ) ??
            end.addingTimeInterval(-2_419_200)
        let previousStart =
            calendar.date(
                byAdding: .day,
                value: -28,
                to: start
            ) ??
            start.addingTimeInterval(-2_419_200)

        do {
            trendSnapshot = try await health.progressSnapshot(
                startDate: start,
                endDate: end,
                previousStartDate: previousStart,
                previousEndDate: start,
                grouping: .week
            )
        } catch {
            trendSnapshot = nil
            trendError = error.localizedDescription
        }
    }

    private func formatDuration(
        _ duration: TimeInterval
    ) -> String {
        guard duration > 0 else { return "—" }

        let totalMinutes = max(
            Int((duration / 60).rounded()),
            0
        )
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0
                ? "\(hours)h"
                : "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}

private enum InsightsScenarioFocus: String, CaseIterable, Identifiable {
    case consistency
    case fiveK
    case halfMarathon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .consistency:
            return "Consistency"
        case .fiveK:
            return "5K"
        case .halfMarathon:
            return "Half"
        }
    }
}

private struct InsightsChangeItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let percent: Double
}
