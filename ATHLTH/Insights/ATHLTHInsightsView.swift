import Combine
import SwiftUI
import UIKit

/// Shared cover spacing policy: only Training uses the larger floating card.
/// Keeping this as a pure function makes compact and accessibility layouts
/// regression-testable without changing the data-source hierarchy.
enum ATHLTHInsightsCoverLayout {
    static func contentTopInset(
        section: ATHLTHInsightsSection,
        accessibilitySize: Bool
    ) -> CGFloat {
        guard section == .training else { return -26 }
        return accessibilitySize ? -36 : -58
    }
}

struct ATHLTHInsightsView: View {
    var onSelectTab: (Int) -> Void = { _ in }
    var isActive: Bool = true

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var session: AppSessionStore
    #if ATHLTH_GARMIN_PERSONAL && DEBUG
    @ObservedObject private var garminStore = GarminPersonalLocalStore.shared
    @Environment(\.scenePhase) private var garminScenePhase
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedSection: ATHLTHInsightsSection = .overview
    @StateObject private var checkInStore = RecoverySorenessStore()
    @State private var dailyFormHistory: [ATHLTHDailyFormPolicy.Day] = []
    @State private var showingCheckIn = false
    @State private var showingReadinessExplanation = false
    @State private var recoverySnapshot = RecoveryTrendSnapshot.empty
    @State private var trainingDays: [ATHLTHInsightsTrainingDay] = []
    @State private var muscleSummary: ATHLTHInsightsMuscleSummary = .empty

    @State private var trendSnapshot: HealthProgressSnapshot?
    @State private var isLoadingTrend = false
    @State private var trendError: String?
    @State private var showingScenarioCoach = false
    @State private var scenarioCoachPrompt = ""
    // Compute history aggregates only when the Health workout snapshot changes,
    // not every time SwiftUI recreates cards while the user scrolls.
    @State private var sessionBaselines = InsightsSessionBaselines.empty
    @State private var cachedPersonalFindings: [ATHLTHPersonalInsight] = []
    @State private var lastInsightsRefreshAt: Date?
    @State private var lastInsightsRefreshAccountID: UUID?
    @State private var lastInsightsWorkouts: [WorkoutSummary]?
    private struct ProjectionInput<Item: Equatable>: Equatable {
        let account: UUID
        let day: Date
        let timeZone: String
        let items: [Item]
    }
    @State private var workoutProjectionGate = ATHLTHProjectionChangeGate<ProjectionInput<WorkoutSummary>>()
    @State private var muscleProjectionGate = ATHLTHProjectionChangeGate<ProjectionInput<StrengthWorkoutLog>>()

    var body: some View {
        NavigationStack {
            // Match Train's single vertically scrolling editorial cover.
            // This ScrollView expands behind the status bar; the cover alone
            // compensates for the real device top inset so controls stay safe.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ATHLTHInsightsCoverHero(
                        imageName: insightsHeroImage,
                        subtitle: insightsHeroSubtitle,
                        selection: $selectedSection
                    )
                    .padding(.horizontal, -17)
                    // Section transitions may animate the content below,
                    // but must not animate the hero's measured dimensions.
                    .transaction { transaction in
                        transaction.animation = nil
                    }

                    LazyVStack(alignment: .leading, spacing: 16) {
                        switch selectedSection {
                        case .overview:
                            overviewSection
                        case .training:
                            trainingSection
                        case .development:
                            developmentSection
                        }
                    }
                    // Training begins with the load/balance surface floating
                    // over the cover image, matching Train's premium hero.
                    // Keep the existing Overview/Development offset unchanged.
                    // Reduce overlap for accessibility-sized titles.
                    .padding(.top, ATHLTHInsightsCoverLayout.contentTopInset(
                        section: selectedSection,
                        accessibilitySize: dynamicTypeSize.isAccessibilitySize
                    ))
                    .padding(.bottom, 40)
                    .zIndex(1)
                }
                .padding(.horizontal, 17)
                .frame(maxWidth: ATHLTHTrainDesign.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            .background(ATHLTHInsightsStyle.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingScenarioCoach) {
                RecoveryCoachInboxDestinationView(
                    initialQuestion: scenarioCoachPrompt,
                    submitInitialQuestion: true
                )
            }
            .sheet(isPresented: $showingCheckIn) {
                RecoverySorenessLogView(store: checkInStore)
            }
            .sheet(isPresented: $showingReadinessExplanation) {
                ATHLTHReadinessExplanationSheet(
                    recovery: health.recovery,
                    sleep: health.sleep,
                    heart: health.heart
                )
            }
            .refreshable {
                guard isActive else { return }
                if !health.shouldDeferAutomaticHealthWork {
                    await health.refreshAll()
                }
                await loadTrend()
                await loadRecoverySignals()
            }
            .task(id: "\(isActive)-\(session.profile.userID.uuidString)") {
                guard isActive else { return }
                checkInStore.reloadFromStorage()
                refreshDailyFormHistory()
                updateWorkoutProjection(health.workouts)
                updateMuscleProjection(strength.workoutHistory)
                // Keep the already-rendered insight snapshots on quick tab
                // returns, but invalidate on new workouts/account switches.
                let accountID = session.profile.userID
                let currentWorkouts = health.workouts
                if lastInsightsRefreshAccountID == accountID,
                   lastInsightsWorkouts == currentWorkouts,
                   let lastInsightsRefreshAt,
                   Date().timeIntervalSince(lastInsightsRefreshAt) < 90 {
                    return
                }

                let signpost = ATHLTHPerformance.begin("InsightsTabRefresh")
                async let trendLoad: Void = loadTrend()
                async let recoveryLoad: Void = loadRecoverySignals()
                _ = await (trendLoad, recoveryLoad)
                ATHLTHPerformance.end("InsightsTabRefresh", id: signpost)
                guard !Task.isCancelled, session.profile.userID == accountID else { return }
                lastInsightsRefreshAt = Date()
                lastInsightsRefreshAccountID = accountID
                lastInsightsWorkouts = currentWorkouts
            }
            .onReceive(health.$workouts.removeDuplicates()) { workouts in
                guard isActive else { return }
                updateWorkoutProjection(workouts)
            }
            .onReceive(strength.$workoutHistory.removeDuplicates()) { history in
                guard isActive else { return }
                updateMuscleProjection(history)
            }
            .onChange(of: session.profile.userID) { _, _ in
                workoutProjectionGate.reset()
                muscleProjectionGate.reset()
                lastInsightsWorkouts = nil
                trainingDays = []
                muscleSummary = .empty
                sessionBaselines = .empty
                cachedPersonalFindings = []
                dailyFormHistory = []
                checkInStore.reloadFromStorage()
                refreshDailyFormHistory()
                recoverySnapshot = .empty
                trendSnapshot = nil
                lastInsightsRefreshAt = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                guard isActive else { return }
                checkInStore.reloadFromStorage()
                refreshDailyFormHistory()
                updateWorkoutProjection(health.workouts)
                updateMuscleProjection(strength.workoutHistory)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("athlth.dailyCheckInDidUpdate")
            )) { _ in
                checkInStore.reloadFromStorage()
                refreshDailyFormHistory()
                updatePersonalFindings()
            }
        }
    }

    private func updateWorkoutProjection(_ workouts: [WorkoutSummary]) {
        let now = Date()
        let calendar = Calendar.current
        let input = ProjectionInput(account: session.profile.userID,
                                    day: calendar.startOfDay(for: now),
                                    timeZone: calendar.timeZone.identifier, items: workouts)
        guard workoutProjectionGate.changed(input) else { return }
        let signpost = ATHLTHPerformance.begin("InsightsWorkoutDerivedData")
        defer { ATHLTHPerformance.end("InsightsWorkoutDerivedData", id: signpost) }
        let updated = InsightsSessionBaselines.calculate(workouts: workouts, at: now)
        if sessionBaselines != updated { sessionBaselines = updated }
        trainingDays = ATHLTHInsightsTrainingDay.make(from: workouts, at: now)
    }

    private func updateMuscleProjection(_ history: [StrengthWorkoutLog]) {
        let now = Date()
        let calendar = Calendar.current
        let input = ProjectionInput(account: session.profile.userID,
                                    day: calendar.startOfDay(for: now),
                                    timeZone: calendar.timeZone.identifier, items: history)
        guard muscleProjectionGate.changed(input) else { return }
        let signpost = ATHLTHPerformance.begin("InsightsMuscleDerivedData")
        defer { ATHLTHPerformance.end("InsightsMuscleDerivedData", id: signpost) }
        muscleSummary = ATHLTHInsightsMuscleSummary.make(from: history, at: now)
    }

    // Each tab uses a distinct existing licensed image, following the
    // approved screenshot. Keep text readable and avoid external image loads.
    private var insightsHeroImage: String {
        switch selectedSection {
        case .overview: return "ProgressHero"
        case .training: return "GoalMountain"
        case .development: return "GoalProgress"
        }
    }

    private var insightsHeroSubtitle: String {
        switch selectedSection {
        case .overview:
            return tr("Understand your body. Train smarter.",
                      "Forstå kroppen din. Tren smartere.")
        case .training: return tr("Training", "Trening")
        case .development: return tr("Progress over time", "Utvikling over tid")
        }
    }

    private var overviewSection: some View {
        Group {
            readinessOverviewCard
            dailyFormAdviceCard
            ATHLTHInsightsDailyRhythmCard()
            ATHLTHInsightsMuscleCard(summary: muscleSummary)
            ATHLTHInsightsSleepStagesCard()
            personalInsightsHighlights
            ATHLTHInsightsHealthLibraryEntry()
        }
    }
    private var trainingSection: some View {
        Group {
            ATHLTHInsightsTrainingSignalsCard(
                trainingLoad: recoverySnapshot.trainingLoad,
                trainingDays: trainingDays
            )
        }
    }
    private var developmentSection: some View {
        Group {
            whatChangedCard
            personalInsightsLibrary
            ATHLTHInsightsDailyCheckInCard(store: checkInStore) {
                showingCheckIn = true
            }
            dailyFormHistoryCard
            whatIfCard
        }
    }

    /// All observations are compared locally. No health data is sent to
    /// external services simply by browsing Insights.
    /// Run local historical analysis when a source changes, never as a
    /// computed property invoked repeatedly by SwiftUI scroll rendering.
    @MainActor
    private func updatePersonalFindings() {
        cachedPersonalFindings = ATHLTHPersonalInsightEngine.findings(
            days: recoverySnapshot.days,
            checkIns: checkInStore.entries,
            stepsChangePercent: trendSnapshot?.stepsChangePercent,
            trainingChangePercent: trendSnapshot?.trainingDurationChangePercent,
            averageDailySteps: trendSnapshot?.averageDailySteps
        )
    }

    private func refreshDailyFormHistory() {
        dailyFormHistory = ATHLTHDailyFormPolicy.history(checkInStore.entries, days: 7)
    }

    private var dailyFormAdviceCard: some View {
        let assessment = ATHLTHDailyFormPolicy.assess(
            entry: checkInStore.todayEntry, measuredScore: health.recovery.score)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(tr("Your own assessment", "Din egen vurdering"), systemImage: "heart.text.square")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(tr("Check in", "Sjekk inn")) { showingCheckIn = true }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
            }
            Text(assessment.recommendation.title)
                .font(.title3.weight(.semibold))
            Text(assessment.explanation)
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            if let subjective = assessment.subjectiveScore {
                HStack {
                    Text(tr("Reported form", "Opplevd form"))
                    Spacer()
                    Text("\(subjective)/100").monospacedDigit().fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            if let contextual = assessment.contextualScore {
                HStack {
                    Text(tr("Combined guidance score", "Veiledende samlet score"))
                    Spacer()
                    Text("\(contextual)/100").monospacedDigit().fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            Text(tr("Guidance only. Measured readiness remains unchanged.",
                    "Veiledende. Målt restitusjonsscore er uendret."))
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private var dailyFormHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Daily form · last 7 days", "Dagsform · siste 7 dager"))
                .font(.headline)
            ForEach(dailyFormHistory) { day in
                HStack(spacing: 5) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .frame(minWidth: 38, alignment: .leading)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    Spacer(minLength: 1)
                    historyValue(day.energy, symbol: "bolt")
                    historyValue(day.stress, symbol: "waveform.path.ecg")
                    historyValue(day.soreness, symbol: "figure.cooldown")
                    historyValue(day.motivation, symbol: "flame")
                    historyValue(day.sleep, symbol: "moon")
                }
                .font(.caption)
            }
            Text(tr("Energy · stress · soreness · motivation · sleep. Dash means unanswered.",
                    "Energi · stress · ømhet · motivasjon · søvn. Strek betyr ubesvart."))
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private func historyValue(_ value: Int?, symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .accessibilityHidden(true)
            Text(value.map(String.init) ?? "—").monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var personalInsightsHighlights: some View {
        ATHLTHPersonalInsightsView(
            findings: cachedPersonalFindings,
            maxVisible: 2,
            onShowAll: {
                selectedSection = .development
            },
            onCheckIn: {
                showingCheckIn = true
            }
        )
    }

    private var personalInsightsLibrary: some View {
        ATHLTHPersonalInsightsView(
            findings: cachedPersonalFindings,
            onCheckIn: {
                showingCheckIn = true
            }
        )
    }

    @MainActor
    private func loadRecoverySignals() async {
        guard health.healthDataAvailable,
              health.hasRequestedAuthorization,
              !health.shouldDeferAutomaticHealthWork else {
            recoverySnapshot = .empty
            updatePersonalFindings()
            return
        }
        // Need enough paired days for meaningful personal comparisons.
        // HealthKit caches each time range to avoid unnecessary repeat work.
        let owner = session.profile.userID
        let updated = await health.recoveryTrendSnapshot(days: 28)
        guard !Task.isCancelled, session.profile.userID == owner else { return }
        recoverySnapshot = updated
        updatePersonalFindings()
    }

    private var dailyRecommendationTitle: String {
        guard health.recovery.score != nil else {
            return tr("See your training options", "Se treningsmulighetene dine")
        }
        switch health.recovery.state {
        case .ready: return tr("Ready for your planned session", "Klar for planlagt økt")
        case .balanced: return tr("Keep your training balanced", "Tren med god balanse")
        case .takeItEasy: return tr("Consider a lighter workout", "Vurder en lettere økt")
        case .recover: return tr("Prioritize recovery", "Prioriter restitusjon")
        case .buildingBaseline:
            return tr("Follow how you feel", "Ta hensyn til dagsformen")
        }
    }

    private var dailyRecommendationDetail: String {
        guard health.recovery.score != nil else {
            return tr("Your baseline is still being established.",
                      "Din personlige grunnlinje er ennå ikke etablert.")
        }
        return tr("Review and adapt today's plan in Train.",
                  "Se gjennom og tilpass dagens plan i Trening.")
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
                        .trim(from: 0.10, to: 0.90)
                         .stroke(ATHLTHInsightsStyle.track, style:
                            StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(90))
                    Circle()
                        .trim(from: 0.10,
                              to: 0.10 + 0.80 * CGFloat(health.recovery.score ?? 0) / 100)
                        .stroke(
                            AngularGradient(
                                colors: [Color(red: 0.89, green: 0.84, blue: 0.76),
                                         ATHLTHInsightsStyle.accent],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(90))
                    VStack(spacing: 2) {
                        Text(health.recovery.score.map(String.init) ?? "—")
                            .font(.system(size: 37, weight: .regular, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                        Text(readinessRingCaption)
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
                        showingReadinessExplanation = true
                    } label: {
                        Label(tr("See details", "Se detaljer"),
                              systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr(
                        "Opens a score breakdown without leaving Insights",
                        "Åpner en detaljert forklaring uten å forlate Innsikt"
                    ))
                }
            }

            HStack(spacing: 7) {
                readinessMetric(tr("Sleep", "Søvn"), sleepValue, "moon.stars.fill",
                                garmin: garminReading(.sleep))
                readinessMetric(tr("Resting HR", "Hvilepuls"), restingHRValue, "heart.fill",
                                garmin: garminReading(.restingHeartRate))
                readinessMetric("HRV", hrvValue, "waveform.path.ecg",
                                garmin: garminReading(.hrv))
            }
            if garminReading(.sleep) != nil || garminReading(.restingHeartRate) != nil || garminReading(.hrv) != nil {
                Text(tr("Garmin measurements are displayed here. The readiness score still uses the Apple Health baseline.",
                        "Garmin-målinger vises her. Dagsformscoren bruker fortsatt grunnlinjen fra Apple Helse."))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
        .padding(18)
        .athlthInsightsSurface()
        #if ATHLTH_GARMIN_PERSONAL && DEBUG
        .task(id: "\(isActive)|\(session.profile.userID)|\(garminStore.connected)|\(garminScenePhase)") {
            guard isActive, garminScenePhase == .active, session.signedIn, !session.previewModeEnabled else { return }
            garminStore.refresh(account: session.profile.userID)
        }
        #endif
    }

    private func garminReading(_ metric: WearableDisplayMetric) -> GarminDisplayReading? {
        #if ATHLTH_GARMIN_PERSONAL && DEBUG
        guard garminScenePhase == .active, session.signedIn, !session.previewModeEnabled,
              let snapshot = garminStore.snapshot(for: session.profile.userID),
              Calendar.current.isDateInToday(snapshot.measurementDay) else { return nil }
        let apple: Double?
        let garmin: Double?
        switch metric {
        case .sleep: apple = health.sleep.totalAsleep; garmin = snapshot.sleepSeconds
        case .restingHeartRate: apple = health.heart.restingHeartRate; garmin = snapshot.restingHeartRate
        case .hrv: apple = health.heart.hrvMilliseconds; garmin = snapshot.overnightHRV
        case .steps: apple = health.training.stepsToday; garmin = snapshot.steps.map(Double.init)
        }
        return WearableDisplaySourcePolicy.garminReading(metric: metric, apple: apple,
            garmin: garmin, preference: garminStore.preference(for: session.profile.userID))
        #else
        return nil
        #endif
    }

    private func readinessMetric(_ title: String, _ value: String, _ icon: String,
                                 garmin: GarminDisplayReading? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTrainDesign.gold)
                .font(.caption)
            Text(garmin?.formattedValue ?? value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.67)
            Text(garmin.map { title + " · " + $0.sourceLabel } ?? title)
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

    private func insightsPaper<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18)
            .athlthInsightsSurface()
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
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

    private var whatIfCard: some View {
        ATHLTHInsightsWhatIfView(
            baselines: sessionBaselines,
            muscleSummary: muscleSummary,
            onAskCoach: { prompt in
                scenarioCoachPrompt = prompt
                showingScenarioCoach = true
            },
            onOpenTrain: {
                onSelectTab(1)
            }
        )
    }


    private var readinessRingCaption: String {
        if health.recovery.score != nil { return pulseTitle.capitalized }
        guard let diagnostic = health.recovery.diagnostics else {
            return tr("Loading", "Henter data")
        }
        if !diagnostic.failedSignals.isEmpty {
            return tr("Read failed", "Lesefeil")
        }
        if diagnostic.completeDays >= diagnostic.requiredDays {
            return tr("Outdated", "Utdatert")
        }
        return "\(diagnostic.completeDays)/\(diagnostic.requiredDays) " +
            tr("days", "dager")
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
            if let diagnostic = health.recovery.diagnostics {
                if !diagnostic.failedSignals.isEmpty {
                    return tr("DATA UNAVAILABLE", "DATA UTILGJENGELIG")
                }
                if diagnostic.completeDays >= diagnostic.requiredDays {
                    return tr("NEEDS NEW DATA", "TRENGER NYE DATA")
                }
            }
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

    private var pulseDetail: String {
        switch health.recovery.state {
        case .ready:
            return tr("Your recovery signals support a normal training day.",
                      "Restitusjonssignalene støtter en normal treningsdag.")
        case .balanced:
            return tr("Your signals are steady. Adjust the plan to how you feel.",
                      "Signalene er stabile. Tilpass planen til hvordan du føler deg.")
        case .takeItEasy:
            return tr("Some signals are below your recent baseline. Keep intensity flexible.",
                      "Noen signaler ligger under normalen din. Tilpass intensiteten.")
        case .recover:
            return tr("Your recent signals suggest prioritizing a lighter day.",
                      "De siste signalene tyder på at en roligere dag kan være lurt.")
        case .buildingBaseline:
            return health.recovery.diagnostics == nil
                ? tr("Reading Apple Health measurements.",
                     "Henter målinger fra Apple Helse.")
                : health.recovery.detail
        }
    }

    private var sleepValue: String {
        guard health.sleep.totalAsleep > 0 else { return "—" }
        return formatDuration(health.sleep.totalAsleep)
    }

    private var hrvValue: String {
        health.heart.hrvMilliseconds.map {
            "\(Int($0.rounded())) ms"
        } ?? "—"
    }

    private var restingHRValue: String {
        health.heart.restingHeartRate.map {
            "\(Int($0.rounded())) bpm"
        } ?? "—"
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
            noun: tr("Training time", "Treningstid"),
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
            noun: tr("Workout frequency", "Øktfrekvens"),
            icon: "calendar.badge.clock",
            tint: ATHLTHTheme.vitality
        )

        appendChange(
            to: &items,
            percent: snapshot.sleepChangePercent,
            threshold: 5,
            noun: tr("Average sleep", "Gjennomsnittlig søvn"),
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
        let title = "\(noun): \(percent >= 0 ? tr("økt", "økt") : tr("reduced", "redusert")) \(Int(abs(percent).rounded())) %"

        items.append(
            InsightsChangeItem(
                id: "\(noun)-\(direction)",
                title: title,
                detail: tr("Compared with the previous 28 days.", "Sammenlignet med foregående 28 dager."),
                icon: icon,
                tint: tint,
                percent: percent
            )
        )
    }

    @MainActor
    private func loadTrend() async {
        guard health.healthDataAvailable else {
            trendSnapshot = nil
            trendError = "Apple Health is unavailable on this device."
            updatePersonalFindings()
            return
        }

        guard health.hasRequestedAuthorization else {
            trendSnapshot = nil
            trendError = "Connect Apple Health to compare your recent trends."
            updatePersonalFindings()
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

        let owner = session.profile.userID
        do {
            let updated = try await health.progressSnapshot(
                startDate: start,
                endDate: end,
                previousStartDate: previousStart,
                previousEndDate: start,
                grouping: .week
            )
            guard !Task.isCancelled, session.profile.userID == owner else { return }
            trendSnapshot = updated
            updatePersonalFindings()
        } catch {
            guard !Task.isCancelled, session.profile.userID == owner else { return }
            trendSnapshot = nil
            trendError = error.localizedDescription
            updatePersonalFindings()
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

private struct InsightsChangeItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let percent: Double
}

/// Compact companion to ATHLTHTrainTodayCoverView: same borderless
/// status-bar artwork, warm editorial type and overlaid section control.
private struct ATHLTHInsightsCoverHero: View {
    let imageName: String
    let subtitle: String
    @Binding var selection: ATHLTHInsightsSection

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 43

    var body: some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top,
                              ATHLTHCoverSafeArea.statusBarTop)

            ZStack(alignment: .topLeading) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    // Keep the cover cropped to the final container bounds.
                    // Do not interpolate its frame when Insights sections
                    // change: that briefly stretches the artwork on screen.
                    .frame(width: geometry.size.width,
                           height: geometry.size.height)
                    .clipped()
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .accessibilityHidden(true)

                // Train's bright readable cover treatment instead of the
                // opaque dark overlay previously obscuring the Insights art.
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.99, green: 0.985, blue: 0.965)
                            .opacity(0.91), location: 0),
                        .init(color: Color(red: 0.99, green: 0.985, blue: 0.965)
                            .opacity(0.73), location: 0.39),
                        .init(color: .clear, location: 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [.clear, ATHLTHInsightsStyle.canvas.opacity(0.28)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            eyebrow
                            Spacer(minLength: 3)
                            ATHLTHInsightsNavigation(selection: $selection)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            eyebrow
                            ATHLTHInsightsNavigation(selection: $selection)
                        }
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Insights", norwegian: "Innsikt"
                    ))
                    .font(.system(size: min(headingSize, 59),
                                  weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 22)
                    .accessibilityAddTraits(.isHeader)

                    Text(subtitle)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(ATHLTHInsightsStyle.ink.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24 + safeTop)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: 25,
                                   bottomTrailing: 25, topTrailing: 0),
                style: .continuous
            ))
        }
        // Deliberately shorter than Train Today (378 pt), but includes the
        // same measured status-bar bleed on phones with a Dynamic Island.
        .frame(height: (dynamicTypeSize.isAccessibilitySize ? 360 : 292)
                      + ATHLTHCoverSafeArea.statusBarTop)
        .accessibilityElement(children: .contain)
    }

    private var eyebrow: some View {
        Text(ATHLTHLocalization.choose(english: "INSIGHTS", norwegian: "INNSIKT"))
            .font(.caption2.weight(.semibold))
            .tracking(2.4)
            .foregroundStyle(ATHLTHInsightsStyle.ink.opacity(0.74))
            .lineLimit(1)
    }
}
