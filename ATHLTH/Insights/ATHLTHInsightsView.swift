import SwiftUI
import UIKit

struct ATHLTHInsightsView: View {
    var onSelectTab: (Int) -> Void = { _ in }
    var isActive: Bool = true

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: ATHLTHInsightsSection = .overview
    @StateObject private var checkInStore = RecoverySorenessStore()
    @State private var showingCheckIn = false
    @State private var showingReadinessExplanation = false
    @State private var recoverySnapshot = RecoveryTrendSnapshot.empty
    @State private var trainingDays: [ATHLTHInsightsTrainingDay] = []
    @State private var muscleSummary: ATHLTHInsightsMuscleSummary = .empty

    @State private var trendSnapshot: HealthProgressSnapshot?
    @State private var isLoadingTrend = false
    @State private var trendError: String?
    @State private var scenarioSessionsPerWeek = 4
    @State private var scenarioMinutesPerSession = 45
    @State private var scenarioFocus: InsightsScenarioFocus = .consistency
    @State private var showingScenarioCoach = false
    // Compute history aggregates only when the Health workout snapshot changes,
    // not every time SwiftUI recreates cards while the user scrolls.
    @State private var sessionBaselines = InsightsSessionBaselines.empty

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
                    // Same image/card overlap as Train Today, adjusted for
                    // the shorter Insights cover and four-option capsule.
                    .padding(.top, -26)
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
            .task(id: isActive) {
                guard isActive else { return }
                await loadTrend()
                await loadRecoverySignals()
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
        }
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
            signalPerspectiveCard
        }
    }
    private var trainingSection: some View {
        Group {
            ATHLTHInsightsMuscleCard(summary: muscleSummary)
            trainingRhythmCard
            ATHLTHInsightsReferenceDistributionCard(
                load: recoverySnapshot.trainingLoad,
                sessionCount: trainingDays.reduce(0) { $0 + $1.sessions }
            )
        }
    }
    private var developmentSection: some View {
        Group {
            whatChangedCard
            ATHLTHInsightsDailyCheckInCard(store: checkInStore) {
                showingCheckIn = true
            }
            whatIfCard
        }
    }

    private var signalPerspectiveCard: some View {
        let recent = recoverySnapshot.days.suffix(7)
        let hrv = recent.compactMap(\.hrvMilliseconds)
        let sleep = recent.compactMap { $0.sleepDuration.map { $0 / 3600 } }
        let number: String
        let description: String
        if hrv.count >= 3, let latest = hrv.last {
            let previous = hrv.dropLast().reduce(0, +) / Double(hrv.count - 1)
            number = String(format: "%+.0f %%", previous > 0 ?
                            (latest - previous) / previous * 100 : 0)
            description = tr(
                "Latest measured HRV compared with earlier days. Day-to-day variation is not a diagnosis.",
                "Siste målte HRV sammenlignet med tidligere dager. Daglige variasjoner er ikke en diagnose."
            )
        } else if sleep.count >= 3, let latest = sleep.last {
            let previous = sleep.dropLast().reduce(0, +) / Double(sleep.count - 1)
            number = String(format: "%+.0f min", (latest - previous) * 60)
            description = tr(
                "Last recorded sleep compared with preceding measured nights.",
                "Siste registrerte søvn sammenlignet med tidligere målte netter."
            )
        } else {
            number = "—"
            description = tr(
                "Your own comparison appears after several measured days in Apple Health.",
                "Din personlige sammenligning vises etter flere dager med målinger i Apple Health."
            )
        }
        return VStack(alignment: .leading, spacing: 10) {
            Label(tr("Your latest signal", "Ditt siste signal"),
                  systemImage: "waveform.path.ecg")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            Text(number)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHInsightsStyle.accent)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .athlthInsightsSurface()
    }

    private var trainingRhythmCard: some View {
        let activeDays = trainingDays.filter { $0.sessions > 0 }
        let totalMinutes = trainingDays.reduce(0.0) { $0 + $1.minutes }
        let averageMinutes = activeDays.isEmpty ? 0 :
            Int((totalMinutes / Double(activeDays.count)).rounded())
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(tr("Training rhythm", "Treningsrytme"),
                      systemImage: "calendar")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Spacer(minLength: 4)
                Text(tr("7 days", "7 dager"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(activeDays.count)/\(trainingDays.count)")
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Text(tr("days with activity", "dager med aktivitet"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            HStack(spacing: 6) {
                ForEach(trainingDays) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(day.sessions > 0 ?
                                  ATHLTHInsightsStyle.accent :
                                  ATHLTHInsightsStyle.track)
                            .frame(height: 33)
                            .overlay {
                                if day.sessions > 1 {
                                    Text("\(day.sessions)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10))
                            .foregroundStyle(ATHLTHInsightsStyle.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(activeDays.isEmpty
                ? tr("Your rhythm appears when workouts are recorded.",
                     "Treningsrytmen vises etter registrerte økter.")
                : tr("Average \(averageMinutes) minutes on active days. Rest days are also visible.",
                     "Gjennomsnittlig \(averageMinutes) minutter på aktive dager. Hviledager er også synlige."))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .padding(17)
        .athlthInsightsSurface()
    }

    @MainActor
    private func loadRecoverySignals() async {
        guard health.healthDataAvailable,
              health.hasRequestedAuthorization,
              !health.shouldDeferAutomaticHealthWork else {
            recoverySnapshot = .empty
            return
        }
        recoverySnapshot = await health.recoveryTrendSnapshot(days: 7)
    }

    private var dailyRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .foregroundStyle(ATHLTHTrainDesign.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Today's recommendation", "Dagens anbefaling"))
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    Text(tr("Based on your recent recovery signals",
                            "Basert på dine siste restitusjonssignaler"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                Spacer(minLength: 0)
            }
            Button { onSelectTab(1) } label: {
                HStack(spacing: 13) {
                    Image("GoalMountain")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 122, height: 94)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(dailyRecommendationTitle)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .multilineTextAlignment(.leading)
                        Text(dailyRecommendationDetail)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                .padding(9)
                .background(ATHLTHTrainDesign.canvas.opacity(0.83),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(17)
        .athlthInsightsSurface()
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
                readinessMetric(tr("Sleep", "Søvn"), sleepValue, "moon.stars.fill")
                readinessMetric(tr("Resting HR", "Hvilepuls"), restingHRValue, "heart.fill")
                readinessMetric("HRV", hrvValue, "waveform.path.ecg")
            }
        }
        .padding(18)
        .athlthInsightsSurface()
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
            return tr("ATHLTH is establishing your personal baseline from recent health data.",
                      "ATHLTH etablerer din personlige normal ut fra helsedata.")
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
    let allWeeklyMinutes: Double?
    let runningWeeklyMinutes: Double?
    let allWeeklySessions: Double?
    let runningWeeklySessions: Double?

    static let empty = InsightsSessionBaselines(
        allSessionMinutes: nil,
        runningSessionMinutes: nil,
        allWeeklyMinutes: nil,
        runningWeeklyMinutes: nil,
        allWeeklySessions: nil,
        runningWeeklySessions: nil
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

        // Four complete weeks of history, not the current calendar week.
        // Keep unavailable history nil: never invent a 45-minute baseline.
        return InsightsSessionBaselines(
            allSessionMinutes: allCount > 0
                ? allTotal / Double(allCount) : nil,
            runningSessionMinutes: runningCount > 0
                ? runningTotal / Double(runningCount) : nil,
            allWeeklyMinutes: allCount > 0 ? allTotal / 4 : nil,
            runningWeeklyMinutes: runningCount > 0 ? runningTotal / 4 : nil,
            allWeeklySessions: allCount > 0 ? Double(allCount) / 4 : nil,
            runningWeeklySessions: runningCount > 0
                ? Double(runningCount) / 4 : nil
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
