import SwiftUI
import UIKit

struct ATHLTHInsightsView: View {
    // TabView may create all its tabs eagerly. Defer Health trend work until
    // Insights is selected, then refresh if the user returns to this tab.
    var isActive: Bool = true
    var onSelectTab: (Int) -> Void = { _ in }

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: ATHLTHInsightsSection = .overview
    @State private var trainingDays: [ATHLTHInsightsTrainingDay] = []
    @State private var muscleSummary: ATHLTHInsightsMuscleSummary = .empty
    @StateObject private var dailyCheckInStore = RecoverySorenessStore()
    @State private var dailyCheckInEntries: [RecoverySorenessEntry] = []
    @State private var showingDailyCheckIn = false

    @State private var trendSnapshot: HealthProgressSnapshot?
    @State private var isLoadingTrend = false
    @State private var trendError: String?
    @State private var scenarioSessionsPerWeek = 4
    @State private var scenarioFocus: InsightsScenarioFocus = .consistency
    // Compute history aggregates only when the Health workout snapshot changes,
    // not every time SwiftUI recreates cards while the user scrolls.
    @State private var sessionBaselines = InsightsSessionBaselines.empty

    var body: some View {
        let immersive =
            UIDevice.current.userInterfaceIdiom == .pad ||
            UIScreen.main.bounds.width >= 390

        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: ATHLTHTrainDesign.gold.opacity(0.28),
                pullDownFadeBridge: true,
                lightweightScrolling: true
            ) {
                ATHLTHTabHero(
                    imageName: "ProgressHero",
                    title: ATHLTHLocalization.choose(english: "Insights", norwegian: "Innsikt"),
                    subtitle: ATHLTHLocalization.choose(english: "Understand your body. Train smarter.", norwegian: "Forstå kroppen din. Tren smartere."),
                    height: 236,
                    alignment: .leading,
                    focalOffsetX: immersive ? 4 : 16,
                    focalOffsetY: immersive ? 6 : 16,
                    titleFontSize: immersive ? 31 : 30,
                    copyWidthFraction: immersive ? 0.72 : 0.84,
                    immersiveCopy: immersive
                )
            } content: {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ATHLTHInsightsNavigation(selection: $selectedSection)
                        .padding(.bottom, 3)

                    // Only the premium Insights screens are presented.
                    // Older Recovery screens no longer appear as destinations.
                    switch selectedSection {
                    case .overview:
                        AnyView(overviewSection)
                    case .health:
                        AnyView(healthSection)
                    case .training:
                        AnyView(trainingSection)
                    case .development:
                        AnyView(developmentSection)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: ATHLTHTrainDesign.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                if !health.shouldDeferAutomaticHealthWork {
                    await health.refreshAll()
                }
                refreshCheckInEntries()
                await loadTrend()
            }
            .task(id: isActive) {
                guard isActive else { return }
                // Seed from already loaded stores even if their published
                // values have not changed since the tab was constructed.
                trainingDays = ATHLTHInsightsTrainingDay.make(from: health.workouts)
                muscleSummary = ATHLTHInsightsMuscleSummary.make(
                    from: strength.workoutHistory
                )
                sessionBaselines = InsightsSessionBaselines.calculate(
                    workouts: health.workouts,
                    at: Date()
                )
                refreshCheckInEntries()
                await loadTrend()
            }
            .onReceive(health.$workouts) { workouts in
                let updated = InsightsSessionBaselines.calculate(
                    workouts: workouts,
                    at: Date()
                )
                if sessionBaselines != updated {
                    sessionBaselines = updated
                }
                trainingDays = ATHLTHInsightsTrainingDay.make(from: workouts)
            }
            .onReceive(strength.$workoutHistory) { history in
                muscleSummary = ATHLTHInsightsMuscleSummary.make(from: history)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("athlth.dailyCheckInDidUpdate")
                )
            ) { _ in
                // The reminder and other screens may write using another
                // RecoverySorenessStore instance; read the persisted history.
                refreshCheckInEntries()
            }
            .onReceive(dailyCheckInStore.$entries) { entries in
                dailyCheckInEntries = entries
            }
            .sheet(isPresented: $showingDailyCheckIn, onDismiss: {
                refreshCheckInEntries()
            }) {
                RecoverySorenessLogView(store: dailyCheckInStore)
            }
        }
    }

    private func refreshCheckInEntries() {
        dailyCheckInEntries = RecoverySorenessStore().entries
    }

    // Existing assets are authoritative. ATHLTHTabHero above continues to
    // use ProgressHero; no downloaded or mockup artwork is bundled here.
    private var overviewSection: some View {
        Group {
            readinessOverviewCard
            ATHLTHDailyWellbeingSummaryCard(
                entries: dailyCheckInEntries,
                onEdit: { showingDailyCheckIn = true },
                onViewTrend: { selectedSection = .development }
            )
            whyItMattersCard
            whatChangedCard
        }
    }

    private var healthSection: some View {
        Group {
            nowCard
            healthExplanationCard
            pulseCard
        }
    }

    private var trainingSection: some View {
        Group {
            ATHLTHInsightsTrainingWeekCard(days: trainingDays)
            ATHLTHInsightsMuscleCard(summary: muscleSummary)
            trendCard
            replayCard
        }
    }

    private var developmentSection: some View {
        Group {
            ATHLTHDailyWellbeingTrendCard(
                entries: dailyCheckInEntries,
                onEdit: { showingDailyCheckIn = true }
            )
            whatChangedCard
            trendCard
            whatIfCard
            replayCard
        }
    }

    private var readinessOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: pulseIcon)
                    .foregroundStyle(ATHLTHTrainDesign.gold)
                Text(tr("Today's readiness", "Dagens form"))
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer(minLength: 2)
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }

            HStack(alignment: .center, spacing: 17) {
                ZStack {
                    Circle()
                        .stroke(ATHLTHTrainDesign.paleGold, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(health.recovery.score ?? 0) / 100)
                        .stroke(
                            AngularGradient(
                                colors: [ATHLTHTrainDesign.paleGold, ATHLTHTrainDesign.gold,
                                         ATHLTHTrainDesign.bronze],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(health.recovery.score.map(String.init) ?? "—")
                            .font(.system(size: 37, weight: .regular, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                        Text(health.recovery.score == nil ? tr("No data", "Ingen data") : pulseTitle.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: 135, height: 135)
                .accessibilityLabel(tr("Readiness score", "Dagsformscore") +
                    ": " + (health.recovery.score.map(String.init) ?? tr("Unavailable", "Ikke tilgjengelig")))

                VStack(alignment: .leading, spacing: 9) {
                    Text(pulseTitle.capitalized)
                        .font(.system(size: 27, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    Text(pulseDetail)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        selectedSection = .health
                    } label: {
                        Label(tr("See health signals", "Se helsesignaler"),
                              systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 7) {
                readinessMetric(tr("Sleep", "Søvn"), sleepValue, "moon.stars.fill")
                readinessMetric("HRV", hrvValue, "waveform.path.ecg")
                readinessMetric(tr("Resting HR", "Hvilepuls"), restingHRValue, "heart.fill")
            }
        }
        .padding(18)
        .athlthTrainPaper(emphasized: true)
    }

    private func readinessMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTrainDesign.gold)
                .font(.caption)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.67)
            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(ATHLTHTrainDesign.canvas.opacity(0.88),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var healthExplanationCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(tr("How your body is responding", "Slik reagerer kroppen"),
                  systemImage: "waveform.path.ecg")
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(ATHLTHTrainDesign.ink)

            healthSignalRow(
                title: tr("Sleep", "Søvn"),
                value: sleepValue,
                explanation: sleepDetail,
                symbol: "moon.stars.fill"
            )
            Divider().overlay(ATHLTHTrainDesign.rule.opacity(0.4))
            healthSignalRow(
                title: tr("Resting heart rate", "Hvilepuls"),
                value: restingHRValue,
                explanation: restingHRDetail,
                symbol: "heart"
            )
            Divider().overlay(ATHLTHTrainDesign.rule.opacity(0.4))
            healthSignalRow(
                title: "HRV",
                value: hrvValue,
                explanation: hrvDetail,
                symbol: "waveform.path.ecg"
            )
        }
        .padding(18)
        .athlthTrainPaper()
    }

    private func healthSignalRow(title: String, value: String, explanation: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 34, height: 34)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func insightsPaper<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18)
            .athlthTrainPaper()
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var pulseCard: some View {
        insightsPaper {
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
                        .font(.system(size: 28, weight: .semibold, design: .serif))
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
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .monospacedDigit()
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
        insightsPaper {
            ATHLTHSectionHeader(title: ATHLTHLocalization.choose(english: "Now", norwegian: "Akkurat nå"))

            Text(ATHLTHLocalization.choose(english: "Your current signals, without making you interpret a dashboard first.", norwegian: "Dagens viktigste signaler, enkelt forklart."))
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
                    title: ATHLTHLocalization.choose(english: "Sleep", norwegian: "Søvn"),
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
                    title: ATHLTHLocalization.choose(english: "Resting HR", norwegian: "Hvilepuls"),
                    value: restingHRValue,
                    detail: restingHRDetail,
                    icon: "heart.fill",
                    tint: .red
                )

                insightMetric(
                    title: ATHLTHLocalization.choose(english: "Recovery", norwegian: "Restitusjon"),
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
        insightsPaper {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(english: "What changed?", norwegian: "Hva har endret seg?"))
                        .font(.title3.weight(.bold))

                    Text(ATHLTHLocalization.choose(english: "Meaningful differences versus your previous 28 days.", norwegian: "Utviklingen sammenlignet med de foregående 28 dagene."))
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
                        Text(ATHLTHLocalization.choose(english: "No major shift detected", norwegian: "Ingen store endringer"))
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
        insightsPaper {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(english: "Trend", norwegian: "Utvikling"))
                        .font(.title3.weight(.bold))

                    Text(ATHLTHLocalization.choose(english: "Last 28 days", norwegian: "Siste 28 dager"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ATHLTHProgressView()
                } label: {
                    HStack(spacing: 4) {
                        Text(ATHLTHLocalization.choose(english: "All progress", norwegian: "All fremgang"))
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
                        title: ATHLTHLocalization.choose(english: "Workouts", norwegian: "Treningsøkter"),
                        value: "\(snapshot.workoutCount)",
                        change: snapshot.workoutChangePercent,
                        icon: "dumbbell.fill"
                    )

                    trendMetric(
                        title: ATHLTHLocalization.choose(english: "Training", norwegian: "Trening"),
                        value: formatDuration(snapshot.trainingDuration),
                        change: snapshot.trainingDurationChangePercent,
                        icon: "clock.fill"
                    )

                    trendMetric(
                        title: ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                        value: String(
                            format: "%.1f km",
                            snapshot.workoutDistanceMeters / 1_000
                        ),
                        change: snapshot.workoutDistanceChangePercent,
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    trendMetric(
                        title: ATHLTHLocalization.choose(english: "Daily steps", norwegian: "Daglige steg"),
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
                Text(ATHLTHLocalization.choose(english: "ATHLTH will show trends when comparable training data is available.", norwegian: "Utviklingen vises når ATHLTH har nok sammenlignbare treningsdata."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
        }
    }

    private var whyItMattersCard: some View {
        insightsPaper {
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
                    Text(ATHLTHLocalization.choose(english: "Why it matters", norwegian: "Hva betyr dette?"))
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
        insightsPaper {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(english: "What if?", norwegian: "Hva om?"))
                        .font(.title3.weight(.bold))

                    Text(ATHLTHLocalization.choose(english: "Model a training week before you commit to it.", norwegian: "Se hvordan en treningsuke kan påvirke belastningen før du bestemmer deg."))
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
                    Text(ATHLTHLocalization.choose(english: "Sessions per week", norwegian: "Økter per uke"))
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
                    title: ATHLTHLocalization.choose(english: "Baseline", norwegian: "Utgangspunkt"),
                    value: "\(Int(baselineSessionMinutes.rounded())) min",
                    subtitle: ATHLTHLocalization.choose(english: "avg. session", norwegian: "gj.sn. økt")
                )

                simulatorMetric(
                    title: ATHLTHLocalization.choose(english: "Scenario", norwegian: "Forslag"),
                    value: "\(Int(projectedWeeklyMinutes.rounded())) min",
                    subtitle: ATHLTHLocalization.choose(english: "per week", norwegian: "per uke")
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
            insightsPaper {
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
                        Text(ATHLTHLocalization.choose(english: "Race yourself", norwegian: "Utfordre deg selv"))
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
                Text(ATHLTHLocalization.choose(english: "No comparison", norwegian: "Ingen sammenligning"))
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
            return ATHLTHLocalization.choose(english: "STRONG", norwegian: "STERK")
        case .balanced:
            return ATHLTHLocalization.choose(english: "BALANCED", norwegian: "BALANSERT")
        case .takeItEasy, .recover:
            return ATHLTHLocalization.choose(english: "RECOVER", norwegian: "RESTITUSJON")
        case .buildingBaseline:
            return ATHLTHLocalization.choose(english: "LEARNING", norwegian: "KARTLEGGER")
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
            noun: ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
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
            noun: ATHLTHLocalization.choose(english: "Daily steps", norwegian: "Daglige steg"),
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
        let cached = scenarioFocus == .consistency
            ? sessionBaselines.allSessionMinutes
            : sessionBaselines.runningSessionMinutes

        if let cached {
            return max(cached, 20)
        }

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

/// Immutable O(n) session averages. Recomputed on published Health workouts,
/// not on scroll/layout passes of the simulator card.
struct InsightsSessionBaselines: Equatable {
    let allSessionMinutes: Double?
    let runningSessionMinutes: Double?

    static let empty = InsightsSessionBaselines(
        allSessionMinutes: nil,
        runningSessionMinutes: nil
    )

    static func calculate(
        workouts: [WorkoutSummary],
        at date: Date,
        calendar: Calendar = .current
    ) -> InsightsSessionBaselines {
        let cutoff = calendar.date(byAdding: .day, value: -28, to: date)
            ?? date.addingTimeInterval(-2_419_200)

        var allTotal = 0.0
        var allCount = 0
        var runningTotal = 0.0
        var runningCount = 0

        for workout in workouts {
            guard workout.startDate >= cutoff,
                  workout.startDate <= date,
                  workout.duration.isFinite,
                  workout.duration > 0 else {
                continue
            }

            let minutes = workout.duration / 60
            allCount += 1
            allTotal += minutes
            if workout.activity == .running {
                runningCount += 1
                runningTotal += minutes
            }
        }

        return InsightsSessionBaselines(
            allSessionMinutes: allCount > 0
                ? allTotal / Double(allCount) : nil,
            runningSessionMinutes: runningCount > 0
                ? runningTotal / Double(runningCount) : nil
        )
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
