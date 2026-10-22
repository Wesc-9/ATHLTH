import Foundation
import CoreLocation
import MapKit
import SwiftUI

struct HomeActivityRunDetailView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var watch: AppleWatchConnectionStore

    let workout: SocialPublishableWorkout

    @State private var detail: WorkoutDetail?
    @State private var measuredPulse: [ATHLTHRunningHeartRatePoint] = []
    @State private var completedIntervalHistory: [ATHLTHCompletedRunningPerformance] = []
    @State private var aiInsight: WorkoutAIInsight?
    @State private var isLoadingDetail = false
    @State private var hasResolvedDetail = false
    @State private var isLoadingAIInsight = false
    @State private var linkedRoute: TrainingRoute?
    @State private var linkedRouteAttempt: RouteAttemptRecord?
    @State private var linkedRouteAttempts: [RouteAttemptRecord] = []
    @State private var isLoadingRouteResult = false
    @State private var showingResultShare = false
    @State private var showingFullscreenMap = false
    @State private var showingSaveRouteConfirmation = false
    @State private var savedRouteMessage: String?
    @State private var routeToOpen: TrainingRoute?

    init(
        workout: SocialPublishableWorkout,
        initialDetail: WorkoutDetail?,
        initialAIInsight: WorkoutAIInsight?
    ) {
        self.workout = workout
        _detail = State(
            initialValue: initialDetail
        )
        _hasResolvedDetail = State(initialValue: initialDetail != nil)
        _aiInsight = State(
            initialValue: initialAIInsight
        )
    }

    // Indoor running has no outdoor GPS track; preserve route features for outdoor workouts.
    private var structuredIntervalResult: ATHLTHCompletedRunningPerformance? {
        let phone = phoneWorkout.history.compactMap {
            ATHLTHCompletedRunningPerformance(phone: $0)
        }
        let stored = ATHLTHRunningPerformanceHistory.match(
            workoutID: workout.id,
            endDate: workout.endDate,
            duration: workout.duration,
            candidates: phone + completedIntervalHistory
        )
        if let stored { return stored }
        // A freshly finished Watch result may not yet have been persisted.
        // Only its identical HealthKit UUID can authorize a direct match.
        return watch.pendingWorkoutResults.compactMap {
            ATHLTHCompletedRunningPerformance(watch: $0)
        }.first { $0.healthWorkoutUUID == workout.id }
    }

    private var isTreadmillWorkout: Bool {
        workout.activity == .running && workout.isIndoor == true
    }

    private var isIndoorActivity: Bool {
        workout.isIndoor == true
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var route: [CLLocation] {
        let source = detail?.route ?? []
        let accurate =
            source
                .filter {
                    $0.coordinate.latitude.isFinite &&
                    $0.coordinate.longitude.isFinite &&
                    (
                        $0.horizontalAccuracy < 0 ||
                        $0.horizontalAccuracy <= 65
                    )
                }
                .sorted {
                    $0.timestamp < $1.timestamp
                }

        if accurate.count >= 2 {
            return accurate
        }

        return source
            .filter {
                $0.coordinate.latitude.isFinite &&
                $0.coordinate.longitude.isFinite
            }
            .sorted {
                $0.timestamp < $1.timestamp
            }
    }

    private var routeCoordinates:
        [CLLocationCoordinate2D] {
        route.map(\.coordinate)
    }

    private var paceSegments:
        [HomeActivityPaceSegment] {
        HomeActivityPaceSegmentBuilder.make(
            from: route
        )
    }

    private var paceBounds:
        (fast: Double, slow: Double) {
        let values =
            paceSegments
                .map(
                    \.paceSecondsPerKilometer
                )
                .filter(\.isFinite)
                .sorted()

        guard values.count >= 2 else {
            let fallback =
                values.first ??
                averagePaceSeconds ??
                360
            return (
                max(fallback * 0.92, 1),
                fallback * 1.08
            )
        }

        let last = values.count - 1
        let fastIndex =
            min(
                max(
                    Int(
                        (
                            Double(last) *
                            0.15
                        )
                        .rounded()
                    ),
                    0
                ),
                last
            )
        let slowIndex =
            min(
                max(
                    Int(
                        (
                            Double(last) *
                            0.85
                        )
                        .rounded()
                    ),
                    0
                ),
                last
            )

        let fast = values[fastIndex]
        let slow =
            max(
                values[slowIndex],
                fast + 1
            )

        return (fast, slow)
    }

    private var verifiedSplits: [ATHLTHRunningResultInsights.KilometerSplit] {
        ATHLTHRunningResultInsights.kilometerSplits(
            from: route, reportedDistanceMeters: workout.distanceMeters
        )
    }

    private var elevationProfile: [ATHLTHRunningResultInsights.ElevationPoint] {
        ATHLTHRunningResultInsights.elevationProfile(from: route)
    }

    private var recordedRouteSource: String {
        "recorded_workout:" + workout.id.uuidString
    }

    private var savedRecordedRoute: TrainingRoute? {
        session.savedRoutes.first { $0.routeSource == recordedRouteSource }
    }

    private func saveRecordedRoute() {
        guard !isIndoorActivity, route.count >= 2,
              savedRecordedRoute == nil,
              let distance = workout.distanceMeters,
              distance.isFinite, distance >= 100
        else { return }
        // Do not store dense traces or invent a route without usable GPS.
        let step = max(1, Int(ceil(Double(route.count) / 1_500)))
        let sampled = Swift.stride(from: 0, to: route.count, by: step)
            .map { route[$0] }
        let clean = sampled + (sampled.last?.timestamp != route.last?.timestamp
            ? [route[route.count - 1]] : [])
        guard clean.count >= 2 else { return }
        let coordinates = clean.enumerated().map { item in
            RouteCoordinate(
                latitude: item.element.coordinate.latitude,
                longitude: item.element.coordinate.longitude,
                altitude: item.element.verticalAccuracy >= 0
                    ? item.element.altitude : nil,
                sequence: item.offset
            )
        }
        let saved = TrainingRoute(
            id: UUID(),
            ownerID: session.profile.userID,
            title: tr("Recorded run", "Registrert løpetur") + " · " +
                workout.startDate.formatted(.dateTime.day().month(.abbreviated)),
            visibility: .privateOnly,
            coordinates: coordinates,
            distanceKilometers: distance / 1_000,
            elevationGainMeters: elevationProfile.count >= 5
                ? elevationGainMeters : nil,
            importedFilename: nil,
            createdAt: Date(),
            startName: nil,
            endName: nil,
            expectedTravelTimeSeconds: workout.duration,
            routeSource: recordedRouteSource
        )
        session.addImportedRoute(saved)
        savedRouteMessage = tr("Route saved privately. Open it from the menu to set up a Ghost Race.",
                               "Ruten er lagret privat. Åpne den fra menyen for å sette opp Ghost Race.")
    }

    private var leaderboardEntries:
        [RouteAttemptRecord] {
        var bestByUser:
            [UUID: RouteAttemptRecord] = [:]

        for attempt in linkedRouteAttempts
        where attempt.leaderboardEligible {
            if let current =
                    bestByUser[
                        attempt.userID
                    ] {
                if attempt.durationSeconds <
                    current.durationSeconds {
                    bestByUser[
                        attempt.userID
                    ] = attempt
                }
            } else {
                bestByUser[
                    attempt.userID
                ] = attempt
            }
        }

        return bestByUser
            .values
            .sorted {
                if abs(
                    $0.durationSeconds -
                    $1.durationSeconds
                ) > 0.1 {
                    return $0.durationSeconds <
                        $1.durationSeconds
                }

                return $0.routeMatchPercent >
                    $1.routeMatchPercent
            }
    }

    private var leaderboardLeader:
        RouteAttemptRecord? {
        leaderboardEntries.first
    }

    private var ownLeaderboardBest:
        RouteAttemptRecord? {
        leaderboardEntries.first {
            $0.userID ==
                session.profile.userID
        }
    }

    private var ownLeaderboardRank:
        Int? {
        guard let index =
                leaderboardEntries
                    .firstIndex(
                        where: {
                            $0.userID ==
                                session
                                    .profile
                                    .userID
                        }
                    )
        else {
            return nil
        }

        return index + 1
    }

    private var currentRouteTime:
        TimeInterval {
        linkedRouteAttempt?
            .durationSeconds ??
        workout.duration
    }

    private var routeLeaderGap:
        TimeInterval? {
        guard let leader =
                leaderboardLeader
        else {
            return nil
        }

        return currentRouteTime -
            leader.durationSeconds
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard

                if let intervals = structuredIntervalResult {
                    ATHLTHIntervalResultSummaryCard(
                        performance: intervals,
                        athleteMaximumBPM: session.onboardingProfile?.maximumHeartRateBPM.map(Double.init),
                        measuredHeartRate: measuredPulse,
                        workoutStartDate: workout.startDate,
                        workoutEndDate: workout.endDate,
                        previousPerformances: completedIntervalHistory +
                            phoneWorkout.history.compactMap {
                                ATHLTHCompletedRunningPerformance(phone: $0)
                            }
                    )
                }

                if !isIndoorActivity {
                    ATHLTHRunningResultAnalysisCard(
                        splits: verifiedSplits,
                        elevation: elevationProfile,
                        activeEnergyKilocalories: workout.activeEnergyKilocalories,
                        maxHeartRateBPM: detail?.maxHeartRate,
                        pulseSamples: measuredPulse
                    )
                }

                ATHLTHRunningPulseResultCard(
                    points: measuredPulse,
                    averageBPM: detail?.averageHeartRate,
                    maximumBPM: detail?.maxHeartRate,
                    athleteMaximumBPM: session.onboardingProfile?.maximumHeartRateBPM
                        .map(Double.init),
                    isStructured: structuredIntervalResult != nil
                )

                ATHLTHWorkoutLocationSection(
                    workout: workout,
                    hasRecordedGPS: routeCoordinates.count >= 2,
                    isLoadingGPS: !hasResolvedDetail
                ) {
                    mapCard
                }

                if isTreadmillWorkout {
                    treadmillFactsCard
                }

                if !isIndoorActivity {
                    if linkedRoute != nil { routeResultCard }
                    routeFactsCard
                }

                coachCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(detailNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingResultShare = true
                    } label: {
                        Label(tr("Share result", "Del resultat"),
                              systemImage: "square.and.arrow.up")
                    }
                    if !isIndoorActivity && routeCoordinates.count >= 2 {
                        Button {
                            showingFullscreenMap = true
                        } label: {
                            Label(tr("Open route map", "Åpne rutekart"),
                                  systemImage: "map")
                        }
                    }
                    if let existing = linkedRoute ?? savedRecordedRoute {
                        Button {
                            routeToOpen = existing
                        } label: {
                            Label(tr("Open saved route / Ghost", "Åpne lagret rute / Ghost"),
                                  systemImage: "figure.run.circle")
                        }
                    } else if !isIndoorActivity && routeCoordinates.count >= 2 {
                        Button {
                            showingSaveRouteConfirmation = true
                        } label: {
                            Label(tr("Save as private route", "Lagre som privat rute"),
                                  systemImage: "bookmark")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                .accessibilityLabel(tr("More workout actions", "Flere økthandlinger"))
            }
        }
        .task(id: workout.id) {
            completedIntervalHistory = ATHLTHRunningPerformanceHistory.load(
                userID: session.profile.userID
            )
            await loadDetailAndCoach()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .athlthTrainingDataDidChange
        )) { _ in
            completedIntervalHistory = ATHLTHRunningPerformanceHistory.load(
                userID: session.profile.userID
            )
        }
        .sheet(isPresented: $showingResultShare) {
            ATHLTHRunningResultShareSheet(
                workout: workout,
                averageHeartRateBPM: detail?.averageHeartRate,
                elevationGainMeters: isIndoorActivity ? nil :
                    (ascentText == nil ? nil : elevationGainMeters),
                rawRoute: isIndoorActivity ? [] : route,
                highlights: verifiedSplits,
                intervalPerformance: structuredIntervalResult
            )
        }
        .sheet(item: $routeToOpen) { route in
            NavigationStack {
                RouteDetailView(route: route)
            }
        }
        .confirmationDialog(
            tr("Save this route privately?", "Lagre denne ruten privat?"),
            isPresented: $showingSaveRouteConfirmation,
            titleVisibility: .visible
        ) {
            Button(tr("Save private route", "Lagre privat rute")) {
                saveRecordedRoute()
            }
        } message: {
            Text(tr("This saves your recorded GPS trail in your private route library. Sharing it later is a separate choice.",
                    "Den registrerte GPS-ruten lagres privat i rutebiblioteket. Deling velger du separat."))
        }
        .alert(tr("Saved route", "Lagret rute"), isPresented: Binding(
            get: { savedRouteMessage != nil },
            set: { if !$0 { savedRouteMessage = nil } }
        )) {
            Button("OK", role: .cancel) { savedRouteMessage = nil }
        } message: {
            Text(savedRouteMessage ?? "")
        }
        .sheet(isPresented: $showingFullscreenMap) {
            NavigationStack {
                routeMapContent
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(tr("Route", "Rute"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Done", "Ferdig")) {
                                showingFullscreenMap = false
                            }
                        }
                    }
            }
        }
    }

    // Result-first hierarchy shared with Training Plan: the detailed map
    // and measured insights follow; no duplicate metric strip on the map.
    private var summaryCard: some View {
        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ATHLTH  /  " + (structuredIntervalResult == nil
                            ? tr("RUNNING", "LØPING")
                            : tr("INTERVAL RUN", "INTERVALLØKT")))
                            .font(.caption2.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(workout.startDate.formatted(
                            .dateTime.day().month(.wide).year().hour().minute()
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    Spacer()
                    Label(tr("Completed", "Fullført"), systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
                }

                if let interval = structuredIntervalResult {
                    Text(interval.title)
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        Label("\(interval.workSteps.count) " + tr("efforts", "drag"),
                              systemImage: "figure.run")
                        Text("·")
                        Text(interval.source)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(distanceText)
                        .font(.system(size: 39, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(ATHLTHPlanDesign.warmDivider)
                    .frame(height: 0.7)

                ATHLTHWorkoutMetricGrid(
                    metrics: [
                        ATHLTHWorkoutDisplayMetric(
                            icon: "timer",
                            label: tr("Time", "Tid"),
                            value: durationText
                        ),
                        ATHLTHWorkoutDisplayMetric(
                            icon: "speedometer",
                            label: tr("Average pace", "Snittempo"),
                            value: paceText
                        ),
                        ATHLTHWorkoutDisplayMetric(
                            icon: "heart",
                            label: tr("Average HR", "Snittpuls"),
                            value: averageHeartRateText
                        ),
                        ATHLTHWorkoutDisplayMetric(
                            icon: isTreadmillWorkout
                                ? "heart.fill" : "mountain.2",
                            label: isTreadmillWorkout
                                ? tr("Max HR", "Makspuls")
                                : tr("Elevation gain", "Høydemeter"),
                            value: isTreadmillWorkout
                                ? maxHeartRateText : (ascentText ?? "—")
                        )
                    ],
                    columnCount: 2
                )

            }
        }
    }

    @ViewBuilder
    private var routeResultCard:
        some View {
        if let route = linkedRoute {
            ATHLTHPlanSurface {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "flag.checkered"
                        )
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .vitality
                        )
                        .frame(
                            width: 38,
                            height: 38
                        )
                        .background(
                            ATHLTHTheme
                                .vitalitySoft,
                            in: Circle()
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "ROUTE RESULT",
                                        norwegian:
                                            "RUTERESULTAT"
                                    )
                            )
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .tracking(1.3)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                            Text(route.title)
                                .font(
                                    .headline
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                                .lineLimit(2)
                        }

                        Spacer()

                        if linkedRouteAttempt?
                            .leaderboardEligible ==
                            true {
                            Image(
                                systemName:
                                    "checkmark.seal.fill"
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .vitality
                            )
                        }
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .flexible(),
                                spacing: 10
                            ),
                            GridItem(
                                .flexible(),
                                spacing: 10
                            )
                        ],
                        spacing: 10
                    ) {
                        routeResultMetric(
                            label:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "This run",
                                        norwegian:
                                            "Denne økten"
                                    ),
                            value:
                                routeTimeText(
                                    currentRouteTime
                                ),
                            icon:
                                "timer"
                        )

                        routeResultMetric(
                            label:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Route leader",
                                        norwegian:
                                            "Ruteleder"
                                    ),
                            value:
                                leaderboardLeader
                                    .map {
                                        routeTimeText(
                                            $0.durationSeconds
                                        )
                                    } ??
                                "—",
                            icon:
                                "trophy.fill"
                        )

                        routeResultMetric(
                            label:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Gap to leader",
                                        norwegian:
                                            "Bak leder"
                                    ),
                            value:
                                routeGapText(
                                    routeLeaderGap
                                ),
                            icon:
                                "arrow.left.arrow.right"
                        )

                        routeResultMetric(
                            label:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Your route PB",
                                        norwegian:
                                            "Din rute-PB"
                                    ),
                            value:
                                ownLeaderboardBest
                                    .map {
                                        routeTimeText(
                                            $0.durationSeconds
                                        )
                                    } ??
                                "—",
                            icon:
                                "medal.fill"
                        )
                    }

                    HStack(spacing: 10) {
                        if linkedRouteAttempt?
                            .leaderboardEligible ==
                            true,
                           let rank =
                            ownLeaderboardRank {
                            let isThisRunPB =
                                ownLeaderboardBest?
                                    .workoutID ==
                                linkedRouteAttempt?
                                    .workoutID

                            Label(
                                ATHLTHLocalization
                                    .format(
                                        english:
                                            isThisRunPB
                                                ? "This run: #%d of %d"
                                                : "Your PB: #%d of %d",
                                        norwegian:
                                            isThisRunPB
                                                ? "Denne økten: #%d av %d"
                                                : "Din PB: #%d av %d",
                                        rank,
                                        leaderboardEntries
                                            .count
                                    ),
                                systemImage:
                                    "list.number"
                            )
                            .font(
                                .caption
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                        } else if let attempt =
                                    linkedRouteAttempt {
                            Label(
                                ATHLTHLocalization
                                    .format(
                                        english:
                                            "%.0f%% route match · not ranked",
                                        norwegian:
                                            "%.0f%% rutetreff · ikke rangert",
                                        attempt
                                            .routeMatchPercent
                                    ),
                                systemImage:
                                    "location.slash.fill"
                            )
                            .font(
                                .caption
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                .orange
                            )
                        }

                        Spacer()

                        NavigationLink {
                            RouteDetailView(
                                route: route
                            )
                        } label: {
                            Label(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Leaderboard",
                                        norwegian:
                                            "Leaderboard"
                                    ),
                                systemImage:
                                    "chevron.right"
                            )
                            .font(
                                .caption
                                    .weight(
                                        .semibold
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            ATHLTHTheme
                                .vitality
                        )
                    }
                }
            }
    
        } else if isLoadingRouteResult {
            ATHLTHPlanSurface {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)

                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Loading route result…",
                                norwegian:
                                    "Laster ruteresultat…"
                            )
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Spacer()
                }
            }
    
        }
    }

    private func routeResultMetric(
        label: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .vitality
                )
                .frame(
                    width: 30,
                    height: 30
                )
                .background(
                    ATHLTHTheme
                        .surfaceSage,
                    in:
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)

                Text(value)
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.75
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            ATHLTHTheme
                .surfaceStone
                .opacity(0.62),
            in:
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
        )
    }

    private func routeTimeText(
        _ duration: TimeInterval
    ) -> String {
        let total =
            max(
                Int(duration.rounded()),
                0
            )
        let hours =
            total / 3_600
        let minutes =
            (total % 3_600) / 60
        let seconds =
            total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format:
                "%d:%02d",
            minutes,
            seconds
        )
    }

    private func routeGapText(
        _ gap: TimeInterval?
    ) -> String {
        guard let gap else {
            return "—"
        }

        if abs(gap) < 0.5 {
            return "0:00"
        }

        let prefix =
            gap > 0
                ? "+"
                : "−"

        return prefix +
            routeTimeText(
                abs(gap)
            )
    }

    @ViewBuilder
    // Reuse the same colour-coded route for the card and full-screen map.
    private var routeMapContent: some View {
    Map(
        initialPosition: .region(
            routeRegion
        )
    ) {
        MapPolyline(
            coordinates:
                routeCoordinates
        )
        .stroke(
            Color.white
                .opacity(0.92),
            lineWidth: 11
        )

        if paceSegments.isEmpty {
            MapPolyline(
                coordinates:
                    routeCoordinates
            )
            .stroke(
                ATHLTHTheme.vitality,
                lineWidth: 7
            )
        } else {
            ForEach(
                paceSegments
            ) { segment in
                MapPolyline(
                    coordinates:
                        segment
                            .coordinates
                )
                .stroke(
                    paceColor(
                        segment
                            .paceSecondsPerKilometer
                    ),
                    lineWidth: 7
                )
            }
        }

        if let first =
            routeCoordinates.first {
            Marker(
                "Start",
                coordinate: first
            )
            .tint(
                HomeActivityPaceScale
                    .fast
            )
        }

        if let last =
            routeCoordinates.last {
            Marker(
                tr("Finish", "Mål"),
                coordinate: last
            )
            .tint(.black)
        }
    }
    }

    private var mapCard: some View {
        ATHLTHPlanSurface {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(tr("Route", "Rute"))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        tr("Apple Maps · pace by segment", "Apple Kart · tempo per segment")
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                if isLoadingDetail {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if routeCoordinates.count >= 2 {
                routeMapContent
                .frame(height: 350)
                .clipShape(
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
                            .opacity(0.8),
                        lineWidth: 0.8
                    )
                }

                HStack {
                    Label(tr("Pace by segment", "Tempo per segment"),
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer()
                    Button {
                        showingFullscreenMap = true
                    } label: {
                        Label(tr("Full screen", "Fullskjerm"),
                              systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                    .buttonStyle(.plain)
                }
                paceLegend
            } else {
                ContentUnavailableView(
                    tr("No GPS route", "Ingen GPS-rute"),
                    systemImage: "map",
                    description: Text(
                        tr("Route details appear when this workout contains GPS data.", "Rutedetaljer vises når økten inneholder GPS-data.")
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 220
                )
                .background(
                    ATHLTHTheme.surfaceStone,
                    in: RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
            }
        }
        }

    }

    private var paceLegend: some View {
        VStack(spacing: 7) {
            LinearGradient(
                colors:
                    HomeActivityPaceScale
                        .legendColors,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 7)
            .clipShape(Capsule())

            HStack {
                Text(tr("Faster", "Raskere"))
                Spacer()
                Text(tr("Average", "Gjennomsnitt"))
                Spacer()
                Text(tr("Slower", "Roligere"))
            }
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )

            Text(
                tr("Colors are relative to this workout.", "Fargene viser tempo relativt til denne økten.")
            )
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
                    .opacity(0.78)
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(.horizontal, 2)
    }

    // No GPS-based claims on treadmill runs; keep measurements without
    // repeating the max HR or pace already shown in the result header.
    @ViewBuilder
    private var treadmillFactsCard: some View {
        if activeEnergyText != "—" || runningPowerText != "—" {
            ATHLTHPlanSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Additional measurements", "Flere målinger"))
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    HStack(spacing: 10) {
                        if activeEnergyText != "—" {
                            routeFact(icon: "flame.fill",
                                      label: tr("Active energy", "Aktiv energi"),
                                      value: activeEnergyText)
                        }
                        if runningPowerText != "—" {
                            routeFact(icon: "bolt.fill",
                                      label: tr("Average power", "Snitteffekt"),
                                      value: runningPowerText)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var routeFactsCard: some View {
        if highestPointText != "—" ||
           maxHeartRateText != "—" ||
           runningPowerText != "—" {
            ATHLTHPlanSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Route measurements", "Rutedetaljer"))
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        if highestPointText != "—" {
                            routeFact(icon: "mountain.2",
                                      label: tr("Highest point", "Høyeste punkt"),
                                      value: highestPointText)
                        }
                        if maxHeartRateText != "—" {
                            routeFact(icon: "heart.fill",
                                      label: tr("Max heart rate", "Makspuls"),
                                      value: maxHeartRateText)
                        }
                        if runningPowerText != "—" {
                            routeFact(icon: "bolt.fill",
                                      label: tr("Average power", "Snitteffekt"),
                                      value: runningPowerText)
                        }
                    }
                }
            }
        }
    }

    private var coachCard: some View {
        ATHLTHPlanSurface {
            VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(spacing: 8) {
                Label(
                    "ATHLTH COACH",
                    systemImage: "sparkles"
                )
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(ATHLTHPlanDesign.accent)

                Text("ATHLTH+")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(
                        .horizontal,
                        6
                    )
                    .padding(
                        .vertical,
                        3
                    )
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )

                Spacer()

                if isLoadingAIInsight {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let aiInsight {
                Text(aiInsight.headline)
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(aiInsight.summary)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            } else if isLoadingAIInsight {
                Text(
                    isIndoorActivity
                        ? tr("Coach is analyzing pace and effort…", "Coachen analyserer tempo og belastning…")
                        : tr("Coach is analyzing pace, route, elevation and effort…", "Coachen analyserer tempo, rute, høydemeter og belastning…")
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            } else {
                Text(coachUnavailableText)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
        }
        }
    }

    @MainActor
    private func loadDetailAndCoach() async {
        if detail == nil {
            isLoadingDetail = true
            detail =
                await health.workoutDetail(
                    for: workout.id
                )
            isLoadingDetail = false
        }
        hasResolvedDetail = true

        measuredPulse = await health.runningHeartRateTimeline(
            for: workout.id
        )

        if !isIndoorActivity {
            await loadRouteResultIfNeeded()
        }
        await loadCoachInsightIfNeeded()
    }

    @MainActor
    private func loadRouteResultIfNeeded() async {
        guard linkedRoute == nil,
              linkedRouteAttempt == nil,
              !isLoadingRouteResult
        else {
            return
        }

        isLoadingRouteResult = true
        defer {
            isLoadingRouteResult = false
        }

        let service =
            SupabaseRouteAttemptService()

        do {
            if let attempt =
                    try await service.load(
                        workoutID: workout.id
                    ),
               let route =
                    session.savedRoutes
                        .first(
                            where: {
                                $0.id ==
                                    attempt.routeID
                            }
                        ) {
                linkedRouteAttempt =
                    attempt
                linkedRoute =
                    route
                linkedRouteAttempts =
                    try await service.load(
                        routeID:
                            attempt.routeID
                    )
                return
            }
        } catch {
            // Fall through to local iPhone metadata when the route attempt
            // endpoint is temporarily unavailable.
        }

        guard let local =
                phoneWorkout.history
                    .first(
                        where: {
                            $0.healthID ==
                                workout.id
                        }
                    ),
              let routeID =
                local.plannedRouteID,
              let route =
                session.savedRoutes
                    .first(
                        where: {
                            $0.id ==
                                routeID
                        }
                    )
        else {
            return
        }

        linkedRoute = route

        do {
            linkedRouteAttempts =
                try await service.load(
                    routeID: routeID
                )
            linkedRouteAttempt =
                linkedRouteAttempts
                    .first(
                        where: {
                            $0.workoutID ==
                                workout.id
                        }
                    )
        } catch {
            linkedRouteAttempts = []
        }
    }

    @MainActor
    private func loadCoachInsightIfNeeded() async {
        guard aiInsight == nil,
              session.hasPaidAccess,
              session.aiHealthDataSharingEnabled,
              let summary =
                health.workouts.first(
                    where: {
                        $0.id == workout.id
                    }
                )
        else {
            return
        }

        isLoadingAIInsight = true
        defer {
            isLoadingAIInsight = false
        }

        let context =
            await health.workoutAIInsightContext(
                for: summary,
                detail: detail,
                maximumHeartRateBPM:
                    session
                        .onboardingProfile?
                        .maximumHeartRateBPM
            )

        do {
            aiInsight =
                try await WorkoutInsightAIService()
                    .generate(
                        workoutID: workout.id,
                        context: context
                    )
        } catch {
            // Keep the detail page useful even when Coach is temporarily unavailable.
        }
    }

    private func summaryMetric(
        _ label: String,
        _ value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)

            Text(value)
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 8)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(
                ATHLTHTheme.divider
            )
            .frame(
                width: 1,
                height: 34
            )
    }

    private func routeFact(
        icon: String,
        label: String,
        value: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHPlanDesign.accentInk
                )
                .frame(
                    width: 34,
                    height: 34
                )
                .background(
                    ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHPlanDesign.secondaryInk
                    )
                    .lineLimit(1)

                Text(value)
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHPlanDesign.ink
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.75
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            ATHLTHPlanDesign.warmSurface.opacity(0.65),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private func paceColor(
        _ pace: Double
    ) -> Color {
        HomeActivityPaceScale.color(
            pace:
                pace,
            fast:
                paceBounds.fast,
            slow:
                paceBounds.slow
        )
    }

    private var routeRegion:
        MKCoordinateRegion {
        guard let first =
                routeCoordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.05,
                        longitudeDelta: 0.05
                    )
            )
        }

        var minLatitude =
            first.latitude
        var maxLatitude =
            first.latitude
        var minLongitude =
            first.longitude
        var maxLongitude =
            first.longitude

        for coordinate in
            routeCoordinates.dropFirst() {
            minLatitude =
                min(
                    minLatitude,
                    coordinate.latitude
                )
            maxLatitude =
                max(
                    maxLatitude,
                    coordinate.latitude
                )
            minLongitude =
                min(
                    minLongitude,
                    coordinate.longitude
                )
            maxLongitude =
                max(
                    maxLongitude,
                    coordinate.longitude
                )
        }

        let latitudeDelta =
            max(
                (
                    maxLatitude -
                    minLatitude
                ) * 1.35,
                0.006
            )
        let longitudeDelta =
            max(
                (
                    maxLongitude -
                    minLongitude
                ) * 1.35,
                0.006
            )

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (
                            minLatitude +
                            maxLatitude
                        ) / 2,
                    longitude:
                        (
                            minLongitude +
                            maxLongitude
                        ) / 2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        latitudeDelta,
                    longitudeDelta:
                        longitudeDelta
                )
        )
    }

    private var elevationGainMeters: Double {
        guard route.count >= 2 else {
            return 0
        }

        var gain = 0.0

        for index in 1..<route.count {
            let delta =
                route[index].altitude -
                route[index - 1].altitude

            if delta > 0,
               delta < 50 {
                gain += delta
            }
        }

        return gain
    }

    private var highestAltitudeMeters: Double? {
        route
            .map(\.altitude)
            .filter(\.isFinite)
            .max()
    }

    private var averagePaceSeconds: Double? {
        guard let distance = workout.distanceMeters else {
            return nil
        }
        return ATHLTHRunningPace.average(
            elapsedSeconds: workout.duration,
            distanceMeters: distance
        )
    }

    private var detailNavigationTitle: String {
        if isTreadmillWorkout {
            return tr("Treadmill details", "Tredemølle")
        }
        switch workout.activity {
        case .running: return tr("Run details", "Løpedetaljer")
        case .walking: return tr("Walk details", "Gådetaljer")
        case .cycling: return tr("Ride details", "Sykkeldetaljer")
        case .hiking: return tr("Hike details", "Turdetaljer")
        default: return tr("Workout details", "Øktdetaljer")
        }
    }

    private var activityTitle: String {
        if isTreadmillWorkout {
            return tr("Treadmill", "Tredemølle")
        }
        switch workout.activity {
        case .running: return tr("Run", "Løping")
        case .walking: return tr("Walk", "Gåtur")
        case .cycling: return tr("Ride", "Sykling")
        case .hiking: return tr("Hike", "Fottur")
        default: return workout.activity.rawValue
        }
    }

    private var distanceText: String {
        guard let distance =
                workout.distanceMeters,
              distance > 0
        else {
            return "—"
        }

        return String(
            format:
                "%.2f km",
            distance / 1_000
        )
    }

    private var durationText: String {
        let total =
            max(
                Int(
                    workout.duration
                        .rounded()
                ),
                0
            )
        let hours =
            total / 3_600
        let minutes =
            (total % 3_600) / 60
        let seconds =
            total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format:
                "%d:%02d",
            minutes,
            seconds
        )
    }

    private var paceText: String {
        guard let pace =
                averagePaceSeconds
        else {
            return "—"
        }

        return Self.paceText(
            pace
        )
    }

    private var averageHeartRateText: String {
        guard let value =
                detail?
                    .averageHeartRate,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return "\(Int(value.rounded())) bpm"
    }

    private var maxHeartRateText: String {
        guard let value =
                detail?.maxHeartRate,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return "\(Int(value.rounded())) bpm"
    }

    private var ascentText: String? {
        guard elevationGainMeters >= 5
        else {
            return nil
        }

        return
            "\(Int(elevationGainMeters.rounded())) m"
    }

    private var highestPointText: String {
        guard let value =
                highestAltitudeMeters,
              value.isFinite
        else {
            return "—"
        }

        return "\(Int(value.rounded())) m"
    }

    private var activeEnergyText: String {
        guard let value =
                workout
                    .activeEnergyKilocalories,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return
            "\(Int(value.rounded())) kcal"
    }

    private var runningPowerText: String {
        guard let value =
                detail?
                    .averageRunningPowerWatts,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return
            "\(Int(value.rounded())) W"
    }

    private var coachUnavailableText: String {
        if !session.hasPaidAccess {
            return tr(
                "Coach insight is available with ATHLTH+.",
                "Coach-innsikt er tilgjengelig med ATHLTH+."
            )
        }
        if !session.aiHealthDataSharingEnabled {
            return tr(
                "Enable Coach health-data sharing in Settings to analyze this workout.",
                "Aktiver deling av helsedata med Coach i Innstillinger for å analysere økten."
            )
        }
        return tr(
            "Coach insight is not available for this workout yet.",
            "Coach-innsikt er ikke tilgjengelig for denne økten ennå."
        )
    }

    private static func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        guard secondsPerKilometer
            .isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let rounded =
            Int(
                secondsPerKilometer
                    .rounded()
            )
        let minutes =
            rounded / 60
        let seconds =
            rounded % 60

        return String(
            format:
                "%d:%02d /km",
            minutes,
            seconds
        )
    }
}

private struct HomeActivityPaceSegment:
    Identifiable {
    let id: Int
    let coordinates:
        [CLLocationCoordinate2D]
    let paceSecondsPerKilometer:
        Double
}

private enum HomeActivityPaceSegmentBuilder {
    static func make(
        from route: [CLLocation]
    ) -> [HomeActivityPaceSegment] {
        guard route.count >= 2 else {
            return []
        }

        var segments:
            [HomeActivityPaceSegment] = []
        var bucketCoordinates:
            [CLLocationCoordinate2D] = [
                route[0].coordinate
            ]
        var bucketDistance = 0.0
        var bucketDuration = 0.0
        var previous = route[0]

        func appendBucket(
            endingAt location: CLLocation
        ) {
            guard
                bucketCoordinates.count >= 2,
                bucketDistance >= 15,
                bucketDuration > 0
            else {
                return
            }

            let pace =
                bucketDuration /
                (bucketDistance / 1_000)

            guard pace.isFinite,
                  pace >= 25,
                  pace <= 2_400
            else {
                return
            }

            segments.append(
                HomeActivityPaceSegment(
                    id: segments.count,
                    coordinates:
                        bucketCoordinates,
                    paceSecondsPerKilometer:
                        pace
                )
            )
        }

        for current in route.dropFirst() {
            let elapsed =
                current.timestamp
                    .timeIntervalSince(
                        previous.timestamp
                    )
            let distance =
                current.distance(
                    from: previous
                )

            let valid =
                elapsed > 0 &&
                elapsed <= 120 &&
                distance >= 0 &&
                (
                    distance /
                    elapsed
                ) <= 12.5

            if valid {
                bucketCoordinates.append(
                    current.coordinate
                )
                bucketDistance +=
                    distance
                bucketDuration +=
                    elapsed

                if bucketDistance >= 70 ||
                    bucketDuration >= 24 {
                    appendBucket(
                        endingAt: current
                    )

                    bucketCoordinates = [
                        current.coordinate
                    ]
                    bucketDistance = 0
                    bucketDuration = 0
                }
            } else {
                if bucketDistance >= 15 {
                    appendBucket(
                        endingAt: previous
                    )
                }

                bucketCoordinates = [
                    current.coordinate
                ]
                bucketDistance = 0
                bucketDuration = 0
            }

            previous = current
        }

        if bucketDistance >= 15 {
            appendBucket(
                endingAt: previous
            )
        }

        return segments
    }
}

private enum HomeActivityPaceScale {
    static let fast =
        Color(
            red: 0.05,
            green: 0.62,
            blue: 0.49
        )

    static let legendColors: [Color] = [
        fast,
        Color(
            red: 0.19,
            green: 0.78,
            blue: 0.45
        ),
        Color(
            red: 0.68,
            green: 0.86,
            blue: 0.27
        ),
        Color(
            red: 0.96,
            green: 0.73,
            blue: 0.18
        ),
        Color(
            red: 0.96,
            green: 0.45,
            blue: 0.12
        )
    ]

    private static let rgb:
        [(Double, Double, Double)] = [
            (0.05, 0.62, 0.49),
            (0.19, 0.78, 0.45),
            (0.68, 0.86, 0.27),
            (0.96, 0.73, 0.18),
            (0.96, 0.45, 0.12)
        ]

    static func color(
        pace: Double,
        fast: Double,
        slow: Double
    ) -> Color {
        guard pace.isFinite,
              fast.isFinite,
              slow.isFinite,
              slow > fast
        else {
            return self.fast
        }

        let normalized =
            min(
                max(
                    (
                        pace -
                        fast
                    ) /
                    (
                        slow -
                        fast
                    ),
                    0
                ),
                1
            )
        let scaled =
            normalized *
            Double(rgb.count - 1)
        let lower =
            min(
                max(
                    Int(
                        floor(
                            scaled
                        )
                    ),
                    0
                ),
                rgb.count - 1
            )
        let upper =
            min(
                lower + 1,
                rgb.count - 1
            )
        let mix =
            scaled -
            Double(lower)

        let a = rgb[lower]
        let b = rgb[upper]

        return Color(
            red:
                a.0 +
                (
                    b.0 -
                    a.0
                ) *
                mix,
            green:
                a.1 +
                (
                    b.1 -
                    a.1
                ) *
                mix,
            blue:
                a.2 +
                (
                    b.2 -
                    a.2
                ) *
                mix
        )
    }
}
