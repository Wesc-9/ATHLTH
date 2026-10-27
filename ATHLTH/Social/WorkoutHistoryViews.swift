import MapKit
import PhotosUI
import SwiftUI
import UIKit

private enum WorkoutHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case walking
    case strength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Run"
        case .walking: return "Walk"
        case .strength: return "Strength"
        }
    }

    func includes(_ activity: WorkoutActivity) -> Bool {
        switch self {
        case .all:
            return true
        case .running:
            return activity == .running
        case .walking:
            return activity == .walking
        case .strength:
            return activity == .strength
        }
    }
}

struct WorkoutHistoryPreviewSection: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    @State private var workouts: [SocialPublishableWorkout] = []
    @State private var loading = false

    var body: some View {
        ATHLTHUnifiedCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(english: "Recent Activity", norwegian: "Siste aktivitet"))
                        .font(.title3.bold())
                    Text(ATHLTHLocalization.choose(english: "Your latest completed workouts.", norwegian: "Dine siste fullførte treningsøkter."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    Text(ATHLTHLocalization.choose(english: "See All", norwegian: "Se alle"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }
            }

            if loading && workouts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else if workouts.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(english: "No workouts yet", norwegian: "Ingen treningsøkter ennå"))
                            .font(.subheadline.weight(.semibold))
                        Text(ATHLTHLocalization.choose(english: "Completed workouts will appear here automatically.", norwegian: "Fullførte økter vises automatisk her."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts.prefix(3)) { workout in
                        NavigationLink {
                            WorkoutHistoryDetailView(workout: workout)
                        } label: {
                            WorkoutHistoryRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }

        let healthItems: [SocialPublishableWorkout]
        if health.hasRequestedAuthorization,
           let summaries = try? await health.workoutHistory() {
            healthItems = summaries.map { summary in
                // The same single Watch workout owns the linked strength log,
                // including timed cardio sets and their measurement provenance.
                // Never show it a second time as an independent running entry.
                if let linkedStrength = strength.workoutHistory.first(where: {
                    $0.healthMetrics.healthKitWorkoutUUID == summary.id
                }) {
                    return SocialPublishableWorkout(strengthWorkout: linkedStrength)
                }
                return SocialPublishableWorkout(summary: summary)
            }
        } else {
            healthItems = []
        }

        let localStrength = strength.workoutHistory
            .filter {
                $0.isFinished &&
                $0.healthMetrics.healthKitWorkoutUUID == nil
            }
            .map(SocialPublishableWorkout.init)

        workouts = (healthItems + localStrength)
            .sorted { $0.startDate > $1.startDate }
    }
}

struct WorkoutHistoryView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let startDate: Date?
    let endDate: Date?

    @State private var workouts: [SocialPublishableWorkout] = []
    @State private var filter: WorkoutHistoryFilter = .all
    @State private var loading = false

    init(
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
    }

    private var filtered: [SocialPublishableWorkout] {
        workouts.filter { workout in
            guard filter.includes(workout.activity) else {
                return false
            }

            if let startDate,
               workout.startDate < startDate {
                return false
            }

            if let endDate,
               workout.startDate > endDate {
                return false
            }

            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(ATHLTHLocalization.choose(english: "Workout type", norwegian: "Treningsform"), selection: $filter) {
                ForEach(WorkoutHistoryFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if loading && workouts.isEmpty {
                Spacer()
                ProgressView(ATHLTHLocalization.choose(english: "Loading workout history…", norwegian: "Laster treningshistorikk…"))
                Spacer()
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(english: "No workouts", norwegian: "Ingen treningsøkter"),
                    systemImage: "figure.run.circle",
                    description: Text(ATHLTHLocalization.choose(english: "Completed workouts from Apple Health and ATHLTH will appear here.", norwegian: "Fullførte økter fra Apple Health og ATHLTH vises her."))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 11) {
                        ForEach(filtered) { workout in
                            NavigationLink {
                                WorkoutHistoryDetailView(workout: workout)
                            } label: {
                                WorkoutHistoryRow(workout: workout)
                                    .padding(12)
                                    .background(
                                        ATHLTHUnifiedDesign.surface,
                                        in: RoundedRectangle(cornerRadius: 18)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(ATHLTHUnifiedDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(english: "Workout History", norwegian: "Treningshistorikk"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load(forceRefresh: true)
        }
    }

    private func load(forceRefresh: Bool = false) async {
        loading = true
        defer { loading = false }

        if forceRefresh && health.hasRequestedAuthorization {
            await health.refreshAll()
        }

        let healthItems: [SocialPublishableWorkout]
        if health.hasRequestedAuthorization,
           let summaries = try? await health.workoutHistory() {
            healthItems = summaries.map { summary in
                // The same single Watch workout owns the linked strength log,
                // including timed cardio sets and their measurement provenance.
                // Never show it a second time as an independent running entry.
                if let linkedStrength = strength.workoutHistory.first(where: {
                    $0.healthMetrics.healthKitWorkoutUUID == summary.id
                }) {
                    return SocialPublishableWorkout(strengthWorkout: linkedStrength)
                }
                return SocialPublishableWorkout(summary: summary)
            }
        } else {
            healthItems = []
        }

        let localStrength = strength.workoutHistory
            .filter {
                $0.isFinished &&
                $0.healthMetrics.healthKitWorkoutUUID == nil
            }
            .map(SocialPublishableWorkout.init)

        workouts = (healthItems + localStrength)
            .sorted { $0.startDate > $1.startDate }
    }
}

struct WorkoutHistoryRow: View {
    let workout: SocialPublishableWorkout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.activity.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 42, height: 42)
                .background(
                    ATHLTHTheme.accent.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(workout.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
    }
}

struct WorkoutHistoryDetailView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var ghostRace: GhostRaceStore

    let workout: SocialPublishableWorkout

    @State private var activity: SocialActivityRecord?
    @State private var healthDetail = WorkoutDetail()
    @State private var healthDetailLoaded = false
    @State private var replayContext: WorkoutAIInsightContext?
    @State private var showingReview = false
    @State private var startingGhostRace = false
    @State private var ghostRaceError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero

                // A single location rule across History, Run and Strength:
                // venue check-in for indoor; a real saved map for outdoor GPS.
                ATHLTHWorkoutLocationSection(
                    workout: workout,
                    hasRecordedGPS: healthDetailLoaded &&
                        ATHLTHWorkoutExperienceEngine.hasValidGPSLocation(
                            in: healthDetail
                        ),
                    isLoadingGPS: !healthDetailLoaded
                ) {
                    if healthDetailLoaded {
                        WorkoutLocationMapCard(
                            detail: healthDetail,
                            activity: workout.activity
                        )
                    }
                }

                ATHLTHWorkoutReplayCard(
                    workout: workout,
                    context: replayContext
                )

                if workout.activity == .running {
                    ghostRaceCard
                }

                metricGrid
                workoutGearCard

                ATHLTHUnifiedCard {
                    HStack {
                        Text("Workout Review")
                            .font(.headline)
                        Spacer()

                        Button(activity == nil ? "Add" : "Edit") {
                            showingReview = true
                        }
                        .font(.caption.weight(.semibold))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        reviewRow(
                            "Visibility",
                            activity.flatMap {
                                ProfileVisibility(rawValue: $0.visibility)?.title
                            } ?? "Not shared"
                        )

                        reviewRow(
                            "Effort",
                            effortText
                        )

                        if let names = activity?.metadata?["with_names"],
                           !names.isEmpty {
                            reviewRow("Trained with", names)
                        }

                        if let caption = activity?.metadata?["caption"],
                           !caption.isEmpty {
                            Divider()
                            Text(caption)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("No description added.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 10)
                }

                ATHLTHUnifiedCard {
                    ATHLTHSectionHeader(title: "Source")
                    HStack {
                        Label(workout.source, systemImage: sourceIcon)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Saved in ATHLTH")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .background(ATHLTHUnifiedDesign.canvas.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workout.id) {
            healthDetailLoaded = false
            let shouldRefreshGear = gear.items.isEmpty
            async let gearRefresh: Void = {
                if shouldRefreshGear {
                    await gear.refresh()
                }
            }()

            activity = await social.workoutActivity(for: workout.id)
            healthDetail = await health.workoutDetail(for: workout.id)
            replayContext = await health.athlthReplayContext(
                for: workout,
                maximumHeartRateBPM:
                    session.onboardingProfile?.maximumHeartRateBPM
            )
            await gearRefresh
            healthDetailLoaded = true
        }
        .alert(
            "Ghost Race",
            isPresented: Binding(
                get: { ghostRaceError != nil },
                set: { visible in
                    if !visible {
                        ghostRaceError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ghostRaceError ?? "")
        }
        .sheet(isPresented: $showingReview, onDismiss: {
            Task {
                activity = await social.workoutActivity(for: workout.id)
                await gear.refresh()
            }
        }) {
            PostWorkoutReviewView(
                workout: workout,
                wasAutoPublished: activity != nil
            )
        }
    }

    private var ghostRaceCard: some View {
        ATHLTHUnifiedCard {
            HStack(spacing: 13) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.vitality)
                    .frame(width: 46, height: 46)
                    .background(
                        ATHLTHTheme.vitalitySoft,
                        in: RoundedRectangle(
                            cornerRadius: 14
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Race this effort")
                        .font(.headline)

                    Text(
                        healthDetailLoaded &&
                        healthDetail.route.count >= 2
                            ? "Use this GPS run as a live ghost."
                            : "A saved GPS route is required."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await startGhostRace()
                    }
                } label: {
                    if startingGhostRace {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Race")
                            .font(.caption.weight(.bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.vitality)
                .disabled(
                    startingGhostRace ||
                    !healthDetailLoaded ||
                    healthDetail.route.count < 2 ||
                    settings.trainingDeviceProvider != .appleWatch ||
                    !watchConnection.isReady
                )
            }
        }
    }

    @MainActor
    private func startGhostRace() async {
        guard workout.activity == .running else {
            return
        }

        guard settings.trainingDeviceProvider == .appleWatch,
              watchConnection.isReady
        else {
            ghostRaceError =
                "Connect Apple Watch before starting a Ghost Race."
            return
        }

        startingGhostRace = true
        defer {
            startingGhostRace = false
        }

        do {
            try await GhostRaceStartService.start(
                workout: workout,
                detail: healthDetail,
                ownerID: session.profile.userID,
                ghostRace: ghostRace,
                watchConnection: watchConnection,
                settings: settings
            )
        } catch {
            ghostRaceError = error.localizedDescription
        }
    }

    private var assignedGear: [ProfileGearItem] {
        let selectedIDs = gear.gearIDs(for: workout.id)
        return gear.items.filter {
            selectedIDs.contains($0.id)
        }
        .sorted {
            if $0.category == .shoes &&
                $1.category != .shoes {
                return true
            }
            if $1.category == .shoes &&
                $0.category != .shoes {
                return false
            }
            return $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    private var workoutGearCard: some View {
        ATHLTHUnifiedCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gear")
                        .font(.headline)

                    Text(
                        assignedGear.isEmpty
                            ? "No gear attached to this workout."
                            : "Equipment used for this workout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(
                    assignedGear.isEmpty ? "Add" : "Edit"
                ) {
                    showingReview = true
                }
                .font(.caption.weight(.semibold))
            }

            if !assignedGear.isEmpty {
                VStack(spacing: 0) {
                    ForEach(assignedGear) { item in
                        NavigationLink {
                            ProfileGearDetailView(item: item)
                        } label: {
                            HStack(spacing: 11) {
                                ProfileGearCategoryIcon(
                                    category: item.category,
                                    size: 18
                                )
                                .frame(width: 38, height: 38)
                                .background(
                                    ATHLTHTheme.surfaceSage.opacity(0.55),
                                    in: RoundedRectangle(
                                        cornerRadius: 11
                                    )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(item.name)
                                        .font(
                                            .subheadline
                                                .weight(.semibold)
                                        )
                                        .foregroundStyle(.primary)

                                    if item.category == .shoes {
                                        let stats =
                                            gear.usageStats(for: item)
                                        Text(
                                            String(
                                                format: "%.0f km total",
                                                stats.totalDistanceMeters /
                                                    1_000
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    } else {
                                        Text(item.category.title)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)

                        if item.id != assignedGear.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [ATHLTHTheme.accent.opacity(0.90), .black.opacity(0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(.white.opacity(0.09))
                .frame(width: 200, height: 145)
                .rotationEffect(.degrees(-10))
                .offset(x: 170, y: -45)

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    workout.activity.rawValue.uppercased(),
                    systemImage: workout.activity.icon
                )
                .font(.caption2.bold())
                .tracking(1.2)

                Text(workout.title)
                    .font(.largeTitle.bold())

                if let venue = workout.plannedTrainingPlaceName {
                    Label(venue, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }

                Text(workout.startDate.formatted(date: .complete, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var metricGrid: some View {
        ATHLTHWorkoutMetricGrid(
            metrics: historicalMetrics,
            columnCount: historicalMetrics.count == 1 ? 2 : 3
        )
    }

    private var historicalMetrics: [ATHLTHWorkoutDisplayMetric] {
        var metrics = [
            ATHLTHWorkoutDisplayMetric(
                icon: "timer",
                label: ATHLTHLocalization.choose(
                    english: "Time", norwegian: "Tid"
                ),
                value: durationText(workout.duration)
            )
        ]

        if let distance = workout.distanceMeters,
           distance.isFinite, distance > 0 {
            metrics.append(
                ATHLTHWorkoutDisplayMetric(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    label: ATHLTHLocalization.choose(
                        english: "Distance", norwegian: "Distanse"
                    ),
                    value: String(format: "%.2f km", distance / 1_000)
                )
            )
        }

        if let calories = workout.activeEnergyKilocalories,
           calories.isFinite, calories > 0 {
            metrics.append(
                ATHLTHWorkoutDisplayMetric(
                    icon: "flame.fill",
                    label: ATHLTHLocalization.choose(
                        english: "Energy", norwegian: "Energi"
                    ),
                    value: String(format: "%.0f kcal", calories)
                )
            )
        }
        return metrics
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var effortText: String {
        guard let raw = activity?.metadata?["effort"],
              let effort = Int(raw)
        else {
            return "Not rated"
        }

        return "\(effort)/10 · \(PostWorkoutReviewView.effortLabel(effort))"
    }

    private var sourceIcon: String {
        if workout.source.contains("Garmin") {
            return "watch.analog"
        }

        if workout.source.contains("Watch") {
            return "applewatch"
        }

        if workout.source.contains("Health") {
            return "heart.fill"
        }

        return "figure.strengthtraining.traditional"
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }

        return String(format: "%d:%02d", minutes, remainder)
    }
}

struct WorkoutLocationMapCard: View {
    let detail: WorkoutDetail
    let activity: WorkoutActivity

    private var routeCoordinates: [CLLocationCoordinate2D] {
        detail.route.map(\.coordinate).filter {
            ATHLTHWorkoutExperienceEngine.isValidCoordinate($0)
        }
    }

    private var singleLocation: CLLocation? {
        if let workoutLocation = detail.workoutLocation,
           ATHLTHWorkoutExperienceEngine.isValidCoordinate(
               workoutLocation.coordinate
           ) {
            return workoutLocation
        }

        return detail.route.first {
            ATHLTHWorkoutExperienceEngine.isValidCoordinate($0.coordinate)
        }
    }

    private var isRoute: Bool {
        routeCoordinates.count >= 2
    }

    private var mapRegion: MKCoordinateRegion {
        let coordinates: [CLLocationCoordinate2D]

        if isRoute {
            coordinates = routeCoordinates
        } else if let singleLocation {
            coordinates = [singleLocation.coordinate]
        } else {
            coordinates = []
        }

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.01,
                    longitudeDelta: 0.01
                )
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let latitudeDelta = max((maxLatitude - minLatitude) * 1.45, 0.004)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.45, 0.004)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    var body: some View {
        ATHLTHUnifiedCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isRoute ? "Route" : "Workout Location")
                        .font(.headline)

                    Text(
                        isRoute
                            ? "GPS route from Apple Health"
                            : locationSubtitle
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(
                    systemName:
                        isRoute
                            ? "point.topleft.down.to.point.bottomright.curvepath"
                            : "mappin.and.ellipse"
                )
                .foregroundStyle(ATHLTHTheme.accent)
            }

            Map(initialPosition: .region(mapRegion)) {
                if isRoute {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(ATHLTHTheme.accent, lineWidth: 5)

                    if let start = routeCoordinates.first {
                        Marker("Start", coordinate: start)
                            .tint(.green)
                    }

                    if let finish = routeCoordinates.last {
                        Marker("Finish", coordinate: finish)
                            .tint(.red)
                    }
                } else if let singleLocation {
                    Marker(
                        activity == .strength
                            ? "Training location"
                            : "Workout location",
                        coordinate: singleLocation.coordinate
                    )
                    .tint(ATHLTHTheme.accent)
                }
            }
            .frame(height: 220)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .padding(.top, 10)
        }
    }

    private var locationSubtitle: String {
        if activity == .strength {
            return "Location saved with this strength workout"
        }

        return "Location saved with this workout"
    }
}

private struct PostWorkoutGhostSplit:
    Identifiable,
    Hashable {
    let kilometer: Int
    let userSplitSeconds: TimeInterval
    let ghostSplitSeconds: TimeInterval

    var id: Int { kilometer }

    var signedSegmentDeltaSeconds:
        TimeInterval {
        ghostSplitSeconds -
        userSplitSeconds
    }
}

struct PostWorkoutReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var workoutCompletion: WorkoutCompletionCoordinator
    @EnvironmentObject private var ghostRace:
        GhostRaceStore

    let workout: SocialPublishableWorkout
    let wasAutoPublished: Bool
    let initialVisibilityOverride: ProfileVisibility?

    init(
        workout: SocialPublishableWorkout,
        wasAutoPublished: Bool,
        initialVisibilityOverride: ProfileVisibility? = nil
    ) {
        self.workout = workout
        self.wasAutoPublished = wasAutoPublished
        self.initialVisibilityOverride = initialVisibilityOverride
    }

    @State private var visibility: ProfileVisibility = .friends
    @State private var descriptionText = ""
    @State private var effort = 5.0
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var saving = false
    @State private var alreadyPublished = false
    @State private var replayContext: WorkoutAIInsightContext?
    @State private var completionWaitingSeconds: TimeInterval?
    @State private var completionRoute: [CLLocation] = []
    @State private var isAdvancedReview = false
    @State private var showingKilometerDetails = false
    @State private var showingTrainingPartners = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedPhotoPreviews: [Data] = []
    @State private var mediaErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    if workout.activity != .strength {
                        resultStrip
                        if workout.activity == .running || workout.activity == .walking {
                            kilometerSplitsDisclosure
                        }
                    }
                    if let recorded = completedPhoneStepResults, !recorded.isEmpty {
                        recordedIntervalsReviewCard(recorded)
                    }

                    if let result =
                            relevantGhostResult,
                       let reference =
                            ghostRace.reference {
                        ghostRaceReviewCard(
                            result: result,
                            reference: reference
                        )
                    }

                    reflectionCard

                    sectionLabel(
                        "ATHLTH REPLAY",
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "A quick look back at how the session unfolded.",
                                norwegian:
                                    "Et raskt tilbakeblikk på hvordan økten utviklet seg."
                            )
                    )

                    ATHLTHWorkoutReplayCard(
                        workout: workout,
                        context: replayContext
                    )

                    if isAdvancedReview {
                        if let impact =
                                workoutCompletion.impact(
                                    for: workout.id
                                ),
                           !impact.items.isEmpty {
                            impactCard(impact)
                        }

                        workoutPhotoCard

                        sectionLabel(
                            ATHLTHLocalization.choose(
                                english: "DETAILS & SHARING",
                                norwegian: "DETALJER & DELING"
                            ),
                            subtitle:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Optional details for your training history and activity.",
                                    norwegian:
                                        "Valgfrie detaljer for treningshistorikken og aktiviteten din."
                                )
                        )

                        WorkoutGearSelectionCard(
                            selectedGearIDs: $selectedGearIDs,
                            activity: workout.activity
                        )

                        compactTrainTogetherButton
                    }

                    if isAdvancedReview {
                        visibilityCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHPlanDesign.accent.opacity(0.18)
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Workout Complete",
                    norwegian: "Økt fullført"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Later",
                            norwegian: "Senere"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button {
                        withAnimation(
                            .easeInOut(
                                duration: 0.18
                            )
                        ) {
                            isAdvancedReview
                                .toggle()
                        }
                    } label: {
                        Text(
                            isAdvancedReview
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Advanced",
                                        norwegian:
                                            "Avansert"
                                    )
                                : "Basic"
                        )
                        .font(
                            .caption.weight(
                                .bold
                            )
                        )
                        .padding(
                            .horizontal,
                            10
                        )
                        .frame(height: 32)
                        .foregroundStyle(
                            isAdvancedReview
                                ? Color.white
                                : completionAccent
                        )
                        .background(
                            isAdvancedReview
                                ? completionAccent
                                : completionAccent
                                    .opacity(0.10),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(
                isPresented:
                    $showingTrainingPartners
            ) {
                NavigationStack {
                    ScrollView {
                        ATHLTHUnifiedCard {
                            WorkoutFriendPicker(
                                selectedFriendIDs:
                                    $selectedFriendIDs
                            )
                        }
                        .padding(16)
                    }
                    .navigationTitle(
                        ATHLTHLocalization.choose(
                            english:
                                "Train Together",
                            norwegian:
                                "Tren sammen"
                        )
                    )
                    .navigationBarTitleDisplayMode(
                        .inline
                    )
                    .toolbar {
                        ToolbarItem(
                            placement:
                                .confirmationAction
                        ) {
                            Button(
                                ATHLTHLocalization.choose(
                                    english: "Done",
                                    norwegian: "Ferdig"
                                )
                            ) {
                                showingTrainingPartners =
                                    false
                            }
                        }
                    }
                    .task {
                        if social
                            .trainingPartners
                            .isEmpty {
                            await social.refresh()
                        }
                    }
                }
                .presentationDetents([
                    .medium,
                    .large
                ])
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
            .task {
                async let reviewLoad: Void =
                    loadExistingReview()
                async let replayLoad: Void =
                    loadReplayContext()
                async let routeLoad: Void =
                    loadCompletionRoute()
                async let mediaLoad: Void =
                    social.refreshWorkoutMedia()

                _ = await (
                    reviewLoad,
                    replayLoad,
                    routeLoad,
                    mediaLoad
                )
            }
            .onChange(
                of: selectedPhotoItems
            ) { _, items in
                Task {
                    await loadSelectedPhotos(
                        items
                    )
                }
            }
        }
    }

    /// Prefer genuine GPS kilometer markers outdoors. On a treadmill use
    /// recorded Watch/iPhone minute distance, never the planned target speed.
    private var reviewedKilometerSplits: [ATHLTHRunningResultInsights.KilometerSplit] {
        let routeSplits = ATHLTHRunningResultInsights.kilometerSplits(
            from: completionRoute, reportedDistanceMeters: workout.distanceMeters)
        if !routeSplits.isEmpty { return routeSplits }

        let history = ATHLTHRunningPerformanceHistory.load(
            userID: session.profile.userID)
        let recorded = ATHLTHRunningPerformanceHistory.match(
            workoutID: workout.id,
            endDate: workout.endDate,
            duration: workout.duration,
            candidates: history
        )
        let phoneMinutes: [ATHLTHRecordedRunningMinute]? = {
            guard let phone = phoneWorkout.lastCompletedWorkout,
                  phone.id == workout.id || phone.healthID == workout.id
            else { return nil }
            return phone.recordedRunningMinutes
        }()
        return ATHLTHRunningResultInsights.kilometerSplits(
            from: recorded?.minutes ?? phoneMinutes ?? [],
            reportedDistanceMeters: workout.distanceMeters
        )
    }

    private var kilometerSplitsDisclosure: some View {
        let splits = reviewedKilometerSplits
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    showingKilometerDetails.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Kilometer by kilometer",
                            norwegian: "Kilometer for kilometer"
                        ))
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text("\(splits.count) " + ATHLTHLocalization.choose(
                            english: "verified km splits", norwegian: "registrerte kilometersplitt"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: showingKilometerDetails
                          ? "chevron.up" : "chevron.down")
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showingKilometerDetails {
                Divider().padding(.horizontal, 14)
                if splits.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "No verified kilometer timestamps were recorded. We won't invent splits from the workout average.",
                        norwegian: "Det finnes ikke nok registrerte kilometermålinger. Vi beregner ikke fiktive splittider fra øktens snitt."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .padding(16)
                } else {
                    HStack {
                        Text("KM").frame(maxWidth: .infinity, alignment: .leading)
                        Text(ATHLTHLocalization.choose(
                            english: "Pace", norwegian: "Tempo"))
                            .frame(maxWidth: .infinity)
                        Text(ATHLTHLocalization.choose(
                            english: "Speed", norwegian: "Fart"))
                            .frame(maxWidth: .infinity)
                        Text(ATHLTHLocalization.choose(
                            english: "Time", norwegian: "Tid"))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .padding(.horizontal, 15)
                    .padding(.top, 12)
                    ForEach(splits) { split in
                        let seconds = Int(split.durationSeconds.rounded())
                        HStack(spacing: 5) {
                            Text("\(split.kilometer)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%d:%02d/km",
                                        seconds / 60, seconds % 60))
                                .frame(maxWidth: .infinity)
                            Text(String(format: "%.1f km/t",
                                        3_600 / split.durationSeconds))
                                .frame(maxWidth: .infinity)
                            Text(String(format: "%d:%02d",
                                        seconds / 60, seconds % 60))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .monospacedDigit()
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        if split.id != splits.last?.id {
                            Divider().padding(.horizontal, 15)
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Measured completed kilometres only; no planned targets.",
                        norwegian: "Kun fullførte, målte kilometere. Ingen planlagte mål."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .padding([.horizontal, .bottom], 15)
                }
            }
        }
        .athlthPlanCard(radius: 22)
    }

    private var completedPhoneStepResults: [ATHLTHRecordedRunningStep]? {
        guard let completed = phoneWorkout.lastCompletedWorkout,
              completed.id == workout.id || completed.healthID == workout.id else {
            return nil
        }
        return (completed.recordedRunningSteps ?? [])
            .sorted { $0.index < $1.index }
    }

    private func recordedIntervalsReviewCard(
        _ steps: [ATHLTHRecordedRunningStep]
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "timer")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(ATHLTHLocalization.choose(
                    english: "TIME PER WORKOUT PHASE",
                    norwegian: "TID PER ØKTDEL"
                ))
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(ATHLTHPlanDesign.ink)
            }
            Text(ATHLTHLocalization.choose(
                english: "Actual active time recorded for each part of the workout.",
                norwegian: "Registrert aktiv tid på oppvarming, drag, pauser og nedjogging."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            ForEach(steps, id: \.index) { step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        if let speed = step.actualSpeedKilometersPerHour {
                            Text(String(format: "%.1f km/t", speed))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Spacer()
                    Text(ATHLTHRunStepCountdown.display(step.activeSeconds))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                if step.index != steps.last?.index {
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }
            }
        }
        .padding(17)
        .athlthPlanCard(radius: 19)
    }

    @ViewBuilder
    private var summaryCard: some View {
        if workout.activity == .strength {
            ATHLTHStrengthCompletedHeroCard(
                profile: completionMuscleProfile,
                duration: workout.duration,
                exerciseCount: workout.strengthExerciseCount,
                volumeKilograms: workout.strengthTotalVolumeKilograms,
                height: 300
            )
        } else {
            nonStrengthSummaryCard
        }
    }

    private var nonStrengthSummaryCard: some View {
        ZStack(alignment: .bottomLeading) {
            summaryBackground

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.74)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            VStack(
                alignment: .leading,
                spacing: 0
            ) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "WORKOUT COMPLETE",
                            norwegian: "ØKT FULLFØRT"
                        ),
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .font(.caption2.bold())
                    .tracking(1.8)

                    Spacer()

                    Label(
                        workout.isIndoor == true &&
                        (workout.activity == .running || workout.activity == .walking)
                            ? ATHLTHLocalization.choose(
                                english: "TREADMILL", norwegian: "TREDEMØLLE")
                            : workout.source.uppercased(),
                        systemImage: workout.isIndoor == true &&
                            workout.activity == .running
                            ? "figure.run.treadmill" : workout.activity.icon
                    )
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .padding(.horizontal, 11)
                    .frame(height: 29)
                    .background(Color.black.opacity(0.29), in: Capsule())
                }

                Spacer()

                Text(heroHeadline)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(heroSubtitle)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.93))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 5)

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    Color.white.opacity(0.72)
                )
                .padding(.top, 5)
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 225)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.08),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.10),
            radius: 22,
            y: 12
        )
    }

    private var heroHeadline: String {
        if workout.isIndoor == true, workout.activity == .running {
            return ATHLTHLocalization.choose(
                english: "Indoor running", norwegian: "Løping innendørs")
        }
        if workout.isIndoor == true, workout.activity == .walking {
            return ATHLTHLocalization.choose(
                english: "Indoor walking", norwegian: "Gange innendørs")
        }
        return completionWorkoutTitle
    }

    private var heroSubtitle: String {
        if workout.isIndoor == true,
           workout.activity == .running || workout.activity == .walking {
            let trimmed = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "iPhone Run" ||
                trimmed == "iPhone Walk" || trimmed == "Running" ||
                trimmed == "Walking" {
                return ATHLTHLocalization.choose(
                    english: "Treadmill", norwegian: "Tredemølle")
            }
            return trimmed
        }
        return completionActivityTitle
    }

    private var completionActivityTitle: String {
        switch workout.activity {
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåtur")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .cycling: return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
        case .swimming: return ATHLTHLocalization.choose(english: "Swimming", norwegian: "Svømming")
        case .hiking: return ATHLTHLocalization.choose(english: "Hiking", norwegian: "Fottur")
        case .hiit: return "HIIT"
        case .rowing: return ATHLTHLocalization.choose(english: "Rowing", norwegian: "Roing")
        case .elliptical: return ATHLTHLocalization.choose(english: "Elliptical", norwegian: "Ellipsemaskin")
        case .stairClimbing: return ATHLTHLocalization.choose(english: "Stair climbing", norwegian: "Trappetrening")
        case .yoga: return "Yoga"
        case .coreTraining: return ATHLTHLocalization.choose(english: "Core training", norwegian: "Kjernetrening")
        case .other: return ATHLTHLocalization.choose(english: "Workout", norwegian: "Treningsøkt")
        }
    }

    private var completionWorkoutTitle: String {
        let original = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericEnglish = [
            workout.activity.rawValue,
            "\(workout.activity.rawValue) completed",
            "Run completed",
            "Walk completed",
            "Løp completed",
            "Styrke completed"
        ]
        guard genericEnglish.contains(where: {
            $0.caseInsensitiveCompare(original) == .orderedSame
        }) else {
            return original
        }
        let norwegianTitle: String
        switch workout.activity {
        case .running: norwegianTitle = "Løpeøkt fullført"
        case .walking: norwegianTitle = "Gåtur fullført"
        case .strength: norwegianTitle = "Styrkeøkt fullført"
        default: norwegianTitle = "\(completionActivityTitle) fullført"
        }
        return ATHLTHLocalization.choose(
            english: "\(workout.activity.rawValue) completed",
            norwegian: norwegianTitle
        )
    }

    @ViewBuilder
    private var summaryBackground: some View {
        if workout.isIndoor == true,
           workout.activity == .running || workout.activity == .walking {
            Image("TreadmillRecentCardHero")
                .resizable()
                .scaledToFill()
                .athlthBoundedFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

        } else if (workout.activity == .running ||
                workout.activity == .walking),
           completionRoute.count >= 2 {
            Map(
                initialPosition:
                    .region(
                        completionRouteRegion
                    )
            ) {
                MapPolyline(
                    coordinates:
                        completionRoute.map(
                            \.coordinate
                        )
                )
                .stroke(
                    ATHLTHPlanDesign.accent,
                    lineWidth: 5
                )
            }
            .id(completionRoute.count)
            .allowsHitTesting(false)

        } else if
            workout.activity == .strength,
            !completionMuscleProfile
                .activations.isEmpty {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.31,
                            green: 0.24,
                            blue: 0.17
                        ),
                        Color(
                            red: 0.10,
                            green: 0.09,
                            blue: 0.09
                        )
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack {
                    Spacer()

                    StrengthMuscleMapView(
                        profile:
                            completionMuscleProfile,
                        compact: true
                    )
                    .frame(
                        width: 190,
                        height: 172
                    )
                    .padding(.trailing, 10)
                    .opacity(0.92)
                }
            }

        } else if workout.activity == .strength {
            Image("StrengthFeedGym")
                .resizable()
                .scaledToFill()
                .athlthBoundedFill()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .clipped()

        } else {
            LinearGradient(
                colors: [
                    completionAccent.opacity(0.92),
                    Color(
                        red: 0.07,
                        green: 0.08,
                        blue: 0.11
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(
                systemName:
                    workout.activity.icon
            )
            .font(
                .system(
                    size: 132,
                    weight: .medium
                )
            )
            .symbolRenderingMode(
                .hierarchical
            )
            .foregroundStyle(
                Color.white.opacity(0.10)
            )
            .offset(x: 118, y: -4)
        }
    }

    private var completionMuscleProfile:
        StrengthMuscleProfile {
        var scores:
            [StrengthMuscleRegion: Double] =
                [:]

        for muscle in
            workout.strengthMuscleGroups ??
            [] {
            for region in
                StrengthMuscleResolver
                    .regions(
                        for: muscle
                    ) {
                scores[
                    region,
                    default: 0
                ] += 1
            }
        }

        return StrengthMuscleProfile(
            activations:
                StrengthMuscleRegion
                    .allCases
                    .compactMap {
                        region in

                        guard let score =
                                scores[
                                    region
                                ],
                              score > 0
                        else {
                            return nil
                        }

                        return StrengthMuscleActivation(
                            region: region,
                            score: score
                        )
                    }
        )
    }

    private var completionRouteRegion:
        MKCoordinateRegion {
        let coordinates =
            completionRoute.map(
                \.coordinate
            )

        guard let first =
                coordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.02,
                        longitudeDelta: 0.02
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
            coordinates.dropFirst() {
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
                0.004
            )
        let longitudeDelta =
            max(
                (
                    maxLongitude -
                    minLongitude
                ) * 1.35,
                0.004
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

    @ViewBuilder
    private var resultStrip: some View {
        if workout.activity == .running || workout.activity == .walking {
            enduranceResultsGrid
        } else {
            compactResultStrip
        }
    }

    /// All values here are backed by the completed workout or HealthKit.
    /// Missing pulse, energy, reliable GPS stillness or incline shows a dash.
    private var enduranceResultsGrid: some View {
        VStack(spacing: 0) {
            completionStatsRow(
                (ATHLTHLocalization.choose(english: "Time", norwegian: "Tid"),
                 durationText(workout.duration), "stopwatch", completionAccent),
                (ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                 completionDistanceText, "location.fill", completionAccent),
                (ATHLTHLocalization.choose(english: "Pace", norwegian: "Tempo"),
                 completionPaceText, "speedometer", completionAccent)
            )

            Rectangle().fill(ATHLTHTheme.divider.opacity(0.62)).frame(height: 0.7)

            completionStatsRow(
                (ATHLTHLocalization.choose(english: "Avg HR", norwegian: "Puls snitt"),
                 bpmText(replayContext?.averageHeartRateBPM), "heart.fill", .red),
                (ATHLTHLocalization.choose(english: "Max HR", norwegian: "Puls maks"),
                 bpmText(replayContext?.maxHeartRateBPM), "heart.text.square.fill", .red),
                (ATHLTHLocalization.choose(english: "Calories", norwegian: "Kalorier"),
                 calorieText, "flame.fill", completionAccent)
            )

            Rectangle().fill(ATHLTHTheme.divider.opacity(0.62)).frame(height: 0.7)

            completionStatsRow(
                (ATHLTHLocalization.choose(english: "Avg speed", norwegian: "Hastighet snitt"),
                 averageSpeedText, "speedometer", completionAccent),
                (ATHLTHLocalization.choose(english: "Waiting time", norwegian: "Ventetid"),
                 completionWaitingSeconds.map { waitingTimeText($0) } ?? "—",
                 "pause.circle", completionAccent),
                (workout.isIndoor == true
                    ? ATHLTHLocalization.choose(english: "Incline", norwegian: "Stigning")
                    : ATHLTHLocalization.choose(english: "Elevation", norwegian: "Høydemeter"),
                 elevationOrInclineText, "mountain.2.fill", completionAccent)
            )
            if completionWaitingSeconds != nil {
                Text(ATHLTHLocalization.choose(
                    english: "Estimated GPS stillness (stops of 10 s or longer). Pauses without location data may be missing.",
                    norwegian: "Anslått GPS-stillstand (stopp på minst 10 sek). Pauser uten posisjonsdata kan mangle."
                ))
                .font(.system(size: 10))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [ATHLTHPlanDesign.surface, ATHLTHPlanDesign.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 0.8)
        }
    }

    private func completionStatsRow(
        _ left: (String, String, String, Color),
        _ middle: (String, String, String, Color),
        _ right: (String, String, String, Color)
    ) -> some View {
        HStack(spacing: 0) {
            completionStat(left.0, value: left.1, icon: left.2, tint: left.3)
            Rectangle()
                .fill(ATHLTHPlanDesign.warmDivider.opacity(0.70))
                .frame(width: 1, height: 55)
            completionStat(middle.0, value: middle.1, icon: middle.2, tint: middle.3)
            Rectangle()
                .fill(ATHLTHPlanDesign.warmDivider.opacity(0.70))
                .frame(width: 1, height: 55)
            completionStat(right.0, value: right.1, icon: right.2, tint: right.3)
        }
        .frame(minHeight: 87)
    }

    private func completionStat(
        _ title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var completionDistanceText: String {
        guard let meters = workout.distanceMeters, meters.isFinite, meters > 0
        else { return "—" }
        return String(format: "%.2f km", meters / 1_000)
    }

    private var completionPaceText: String {
        guard let meters = workout.distanceMeters, meters > 0 else { return "—" }
        return averagePaceText(duration: workout.duration, distanceMeters: meters)
    }

    private func bpmText(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return "\(Int(value.rounded())) bpm"
    }

    private var calorieText: String {
        guard let value = workout.activeEnergyKilocalories ??
                replayContext?.activeEnergyKilocalories,
              value.isFinite, value > 0 else { return "—" }
        return "\(Int(value.rounded())) kcal"
    }

    private var averageSpeedText: String {
        guard let distance = workout.distanceMeters,
              distance.isFinite, distance > 0, workout.duration > 0
        else { return "—" }
        return String(format: "%.1f km/t", distance / workout.duration * 3.6)
    }

    private var elevationOrInclineText: String {
        if workout.isIndoor == true {
            guard let recorded = phoneWorkout.history.first(where: {
                $0.id == workout.id || $0.healthID == workout.id
            })?.treadmillInclinePercent,
            recorded.isFinite else { return "—" }
            return String(format: "%.0f %%", recorded)
        }
        guard let elevation = replayContext?.elevationGainMeters,
              elevation.isFinite, elevation >= 0 else { return "—" }
        return String(format: "+%.0f m", elevation)
    }

    private var compactResultStrip: some View {
        HStack(spacing: 0) {
            resultMetric(
                title: ATHLTHLocalization.choose(english: "Time", norwegian: "Tid"),
                value: durationText(
                    workout.duration
                ),
                icon: "timer"
            )

            resultDivider

            if let distance =
                    workout.distanceMeters,
               distance > 0 {
                resultMetric(
                    title: ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                    value: String(
                        format: "%.2f km",
                        distance / 1_000
                    ),
                    icon: "location.fill"
                )

                resultDivider

                resultMetric(
                    title: ATHLTHLocalization.choose(english: "Pace", norwegian: "Tempo"),
                    value: averagePaceText(
                        duration:
                            workout.duration,
                        distanceMeters:
                            distance
                    ),
                    icon: "speedometer"
                )
            } else if
                workout.activity == .strength,
                let exerciseCount =
                    workout.strengthExerciseCount,
                exerciseCount > 0 {
                resultMetric(
                    title: ATHLTHLocalization.choose(english: "Exercises", norwegian: "Øvelser"),
                    value: "\(exerciseCount)",
                    icon: "dumbbell.fill"
                )

                resultDivider

                resultMetric(
                    title: ATHLTHLocalization.choose(english: "Volume", norwegian: "Volum"),
                    value:
                        strengthVolumeText ??
                        "—",
                    icon:
                        "scalemass.fill"
                )
            } else if let calories =
                        workout
                            .activeEnergyKilocalories,
                      calories > 0 {
                resultMetric(
                    title: ATHLTHLocalization.choose(english: "Energy", norwegian: "Energi"),
                    value: String(
                        format: "%.0f kcal",
                        calories
                    ),
                    icon: "flame.fill"
                )
            } else {
                resultMetric(
                    title: ATHLTHLocalization.choose(english: "Activity", norwegian: "Aktivitet"),
                    value:
                        workout.activity.rawValue,
                    icon:
                        workout.activity.icon
                )
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 6)
        .background(
            Color.white.opacity(0.88),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.96),
                lineWidth: 0.8
            )
        }
    }

    private func resultMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    completionAccent
                )

            Text(value)
                .font(
                    .subheadline.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var resultDivider: some View {
        Rectangle()
            .fill(
                ATHLTHTheme.divider.opacity(0.80)
            )
            .frame(width: 1, height: 42)
    }

    private func impactCard(
        _ impact: WorkoutCompletionImpact
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(
                alignment: .top,
                spacing: 12
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text("WHAT THIS WORKOUT CHANGED")
                        .font(.caption2.weight(.bold))
                        .tracking(1.65)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text("Your session is already connected across ATHLTH.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(completionAccent)
                    .frame(width: 38, height: 38)
                    .background(
                        completionAccent.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
            }

            VStack(spacing: 0) {
                ForEach(
                    Array(impact.items.prefix(5))
                ) { item in
                    HStack(
                        alignment: .top,
                        spacing: 12
                    ) {
                        Image(
                            systemName:
                                item.systemImage
                        )
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            impactTint(
                                item.kind
                            )
                        )
                        .frame(
                            width: 36,
                            height: 36
                        )
                        .background(
                            impactTint(
                                item.kind
                            )
                            .opacity(0.09),
                            in: RoundedRectangle(
                                cornerRadius: 11,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(item.title)
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )

                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)

                    if item.id !=
                        impact.items
                            .prefix(5)
                            .last?
                            .id {
                        Divider()
                            .opacity(0.58)
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    completionAccent.opacity(0.055),
                    Color.white.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                completionAccent.opacity(0.10),
                lineWidth: 0.8
            )
        }
    }

    private func impactTint(
        _ kind: WorkoutCompletionImpactKind
    ) -> Color {
        switch kind {
        case .goal:
            return ATHLTHTheme.vitality
        case .challenge:
            return .orange
        case .gear:
            return .blue
        case .achievement:
            return .purple
        }
    }

    private var relevantGhostResult:
        GhostRaceResult? {
        guard workout.activity == .running,
              let result =
                ghostRace.result,
              ghostRace.reference != nil
        else {
            return nil
        }

        // sourceWorkoutID belongs to the Ghost reference, not the run that
        // just finished. Match the result to the review by finish time and
        // final elapsed time so an older Ghost result can never leak into a
        // later ordinary workout review.
        let finishDelta =
            abs(
                result.finishedAt
                    .timeIntervalSince(
                        workout.endDate
                    )
            )
        let durationDelta =
            abs(
                result.elapsedTime -
                workout.duration
            )

        guard finishDelta <= 15 * 60,
              durationDelta <=
                max(
                    180,
                    workout.duration *
                        0.25
                )
        else {
            return nil
        }

        return result
    }

    private func ghostRaceReviewCard(
        result: GhostRaceResult,
        reference: GhostRaceReference
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            HStack(
                alignment: .top,
                spacing: 12
            ) {
                Image(
                    systemName:
                        "figure.run.circle.fill"
                )
                .font(
                    .system(
                        size: 19,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    completionAccent
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    completionAccent
                        .opacity(0.09),
                    in:
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("GHOST RACE")
                        .font(
                            .caption2
                                .weight(.bold)
                        )
                        .tracking(1.7)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                    Text(
                        ghostResultHeadline(
                            result
                        )
                    )
                    .font(
                        .title3
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    Text(
                        ghostResultSubtitle(
                            result,
                            reference:
                                reference
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer(
                    minLength: 4
                )

                Text(
                    ghostOverallDeltaText(
                        result
                    )
                )
                .font(
                    .headline
                        .monospacedDigit()
                )
                .foregroundStyle(
                    ghostResultTint(
                        result
                    )
                )
                .padding(
                    .horizontal,
                    10
                )
                .frame(
                    minHeight: 34
                )
                .background(
                    ghostResultTint(
                        result
                    )
                    .opacity(0.09),
                    in: Capsule()
                )
            }

            HStack(spacing: 8) {
                ghostMetric(
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Your time",
                                norwegian:
                                    "Din tid"
                            ),
                    value:
                        durationText(
                            workout.duration
                        )
                )

                ghostMetric(
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Ghost time",
                                norwegian:
                                    "Ghost-tid"
                            ),
                    value:
                        durationText(
                            result
                                .referenceDuration
                        )
                )

                ghostMetric(
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Lead changes",
                                norwegian:
                                    "Lederskifter"
                            ),
                    value:
                        "\(result.leadChangeCount)"
                )
            }

            if result.maximumLeadMeters > 1 ||
                result.maximumDeficitMeters > 1 {
                HStack(spacing: 8) {
                    if result.maximumLeadMeters >
                        1 {
                        Label(
                            ATHLTHLocalization
                                .format(
                                    english:
                                        "Max lead %@",
                                    norwegian:
                                        "Maks foran %@",
                                    compactGhostDistance(
                                        result
                                            .maximumLeadMeters
                                    )
                                ),
                            systemImage:
                                "arrow.up.right"
                        )
                        .foregroundStyle(
                            .green
                        )
                    }

                    if result.maximumDeficitMeters >
                        1 {
                        Label(
                            ATHLTHLocalization
                                .format(
                                    english:
                                        "Max behind %@",
                                    norwegian:
                                        "Maks bak %@",
                                    compactGhostDistance(
                                        result
                                            .maximumDeficitMeters
                                    )
                                ),
                            systemImage:
                                "arrow.down.right"
                        )
                        .foregroundStyle(
                            .orange
                        )
                    }

                    Spacer(
                        minLength: 0
                    )
                }
                .font(
                    .caption
                        .weight(.semibold)
                )
            }

            let splits =
                ghostSplitComparisons(
                    reference:
                        reference
                )

            if !splits.isEmpty {
                Divider()
                    .opacity(0.60)

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    HStack {
                        Text(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "KILOMETER BY KILOMETER",
                                    norwegian:
                                        "KILOMETER FOR KILOMETER"
                                )
                        )
                        .font(
                            .caption2
                                .weight(.bold)
                        )
                        .tracking(1.35)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Spacer()

                        Text(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "You · Ghost",
                                    norwegian:
                                        "Du · Ghost"
                                )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    ForEach(splits) {
                        split in
                        ghostSplitRow(
                            split
                        )

                        if split.id !=
                            splits.last?.id {
                            Divider()
                                .opacity(
                                    0.45
                                )
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    completionAccent
                        .opacity(0.055),
                    Color.white
                        .opacity(0.96)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                completionAccent
                    .opacity(0.11),
                lineWidth: 0.8
            )
        }
    }

    private func ghostMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)

            Text(value)
                .font(
                    .subheadline
                        .weight(.bold)
                        .monospacedDigit()
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
        .padding(
            .horizontal,
            11
        )
        .padding(
            .vertical,
            9
        )
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.primary
                .opacity(0.035),
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }

    private func ghostSplitRow(
        _ split: PostWorkoutGhostSplit
    ) -> some View {
        HStack(spacing: 10) {
            Text(
                "\(split.kilometer) km"
            )
            .font(
                .subheadline
                    .weight(.bold)
            )
            .frame(
                width: 48,
                alignment: .leading
            )

            Text(
                splitPaceText(
                    split.userSplitSeconds
                )
            )
            .font(
                .subheadline
                    .weight(.semibold)
                    .monospacedDigit()
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            Text(
                splitPaceText(
                    split.ghostSplitSeconds
                )
            )
            .font(
                .caption
                    .monospacedDigit()
            )
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
            .frame(
                width: 62,
                alignment: .trailing
            )

            Text(
                ghostSplitDeltaText(
                    split
                        .signedSegmentDeltaSeconds
                )
            )
            .font(
                .caption
                    .weight(.bold)
                    .monospacedDigit()
            )
            .foregroundStyle(
                split
                    .signedSegmentDeltaSeconds >=
                    0
                    ? Color.green
                    : Color.orange
            )
            .frame(
                width: 54,
                alignment: .trailing
            )
        }
    }

    private func ghostSplitComparisons(
        reference: GhostRaceReference
    ) -> [PostWorkoutGhostSplit] {
        guard completionRoute.count >= 2,
              let officialDistance =
                workout.distanceMeters,
              officialDistance >= 1_000,
              reference.points.count >= 2
        else {
            return []
        }

        let sortedRoute =
            completionRoute.sorted {
                $0.timestamp <
                $1.timestamp
            }
        let rawCumulative =
            routeCumulativeDistances(
                sortedRoute
            )
        guard let rawTotal =
                rawCumulative.last,
              rawTotal > 100
        else {
            return []
        }

        let firstTimestamp =
            sortedRoute[0].timestamp
        let timestampSpan =
            sortedRoute.last?
                .timestamp
                .timeIntervalSince(
                    firstTimestamp
                ) ?? 0

        let routeDistance =
            min(
                officialDistance,
                reference.points.last?
                    .cumulativeMeters ??
                reference
                    .routeDistanceMeters
            )
        let completedKilometers =
            Int(
                floor(
                    routeDistance /
                    1_000
                )
            )

        guard completedKilometers > 0
        else {
            return []
        }

        var result:
            [PostWorkoutGhostSplit] = []
        var previousUserElapsed:
            TimeInterval = 0
        var previousGhostElapsed:
            TimeInterval = 0

        for kilometer in
            1...completedKilometers {
            let target =
                Double(kilometer) *
                1_000

            guard let userElapsed =
                    userElapsedAtDistance(
                        target,
                        locations:
                            sortedRoute,
                        rawCumulative:
                            rawCumulative,
                        rawTotal:
                            rawTotal,
                        officialDistance:
                            officialDistance,
                        firstTimestamp:
                            firstTimestamp,
                        timestampSpan:
                            timestampSpan
                    ),
                  let ghostElapsed =
                    ghostElapsedAtDistance(
                        target,
                        reference:
                            reference
                    )
            else {
                continue
            }

            let userSplit =
                max(
                    userElapsed -
                    previousUserElapsed,
                    0
                )
            let ghostSplit =
                max(
                    ghostElapsed -
                    previousGhostElapsed,
                    0
                )

            if userSplit > 0,
               ghostSplit > 0 {
                result.append(
                    PostWorkoutGhostSplit(
                        kilometer:
                            kilometer,
                        userSplitSeconds:
                            userSplit,
                        ghostSplitSeconds:
                            ghostSplit
                    )
                )
            }

            previousUserElapsed =
                userElapsed
            previousGhostElapsed =
                ghostElapsed
        }

        return result
    }

    private func routeCumulativeDistances(
        _ locations: [CLLocation]
    ) -> [Double] {
        guard !locations.isEmpty
        else {
            return []
        }

        var values =
            Array(
                repeating: 0.0,
                count:
                    locations.count
            )

        guard locations.count > 1
        else {
            return values
        }

        for index in
            1..<locations.count {
            values[index] =
                values[index - 1] +
                max(
                    locations[index]
                        .distance(
                            from:
                                locations[
                                    index - 1
                                ]
                        ),
                    0
                )
        }

        return values
    }

    private func userElapsedAtDistance(
        _ targetMeters: Double,
        locations: [CLLocation],
        rawCumulative: [Double],
        rawTotal: Double,
        officialDistance: Double,
        firstTimestamp: Date,
        timestampSpan: TimeInterval
    ) -> TimeInterval? {
        guard locations.count ==
                rawCumulative.count,
              locations.count >= 2,
              rawTotal > 0,
              officialDistance > 0
        else {
            return nil
        }

        let targetRawDistance =
            min(
                max(
                    targetMeters /
                    officialDistance,
                    0
                ),
                1
            ) *
            rawTotal

        guard let upperIndex =
                rawCumulative
                    .firstIndex(
                        where: {
                            $0 >=
                                targetRawDistance
                        }
                    )
        else {
            return workout.duration
        }

        if upperIndex == 0 {
            return 0
        }

        let lowerIndex =
            upperIndex - 1
        let lowerDistance =
            rawCumulative[
                lowerIndex
            ]
        let upperDistance =
            rawCumulative[
                upperIndex
            ]
        let span =
            max(
                upperDistance -
                lowerDistance,
                0.001
            )
        let fraction =
            min(
                max(
                    (
                        targetRawDistance -
                        lowerDistance
                    ) / span,
                    0
                ),
                1
            )

        let lowerProgress:
            Double
        let upperProgress:
            Double

        if timestampSpan > 10,
           workout.duration > 0 {
            lowerProgress =
                min(
                    max(
                        locations[
                            lowerIndex
                        ]
                        .timestamp
                        .timeIntervalSince(
                            firstTimestamp
                        ) /
                        timestampSpan,
                        0
                    ),
                    1
                )
            upperProgress =
                min(
                    max(
                        locations[
                            upperIndex
                        ]
                        .timestamp
                        .timeIntervalSince(
                            firstTimestamp
                        ) /
                        timestampSpan,
                        0
                    ),
                    1
                )
        } else {
            lowerProgress =
                lowerDistance /
                rawTotal
            upperProgress =
                upperDistance /
                rawTotal
        }

        let progress =
            lowerProgress +
            (
                upperProgress -
                lowerProgress
            ) *
            fraction

        return workout.duration *
            progress
    }

    private func ghostElapsedAtDistance(
        _ targetMeters: Double,
        reference: GhostRaceReference
    ) -> TimeInterval? {
        let points =
            reference.points

        guard points.count >= 2,
              let upperIndex =
                points.firstIndex(
                    where: {
                        $0.cumulativeMeters >=
                            targetMeters
                    }
                )
        else {
            return nil
        }

        if upperIndex == 0 {
            return points[0]
                .elapsedTime
        }

        let lower =
            points[
                upperIndex - 1
            ]
        let upper =
            points[
                upperIndex
            ]
        let distanceSpan =
            max(
                upper.cumulativeMeters -
                lower.cumulativeMeters,
                0.001
            )
        let fraction =
            min(
                max(
                    (
                        targetMeters -
                        lower.cumulativeMeters
                    ) /
                    distanceSpan,
                    0
                ),
                1
            )

        return lower.elapsedTime +
            (
                upper.elapsedTime -
                lower.elapsedTime
            ) *
            fraction
    }

    private func ghostResultHeadline(
        _ result: GhostRaceResult
    ) -> String {
        guard result.completedRoute,
              let signed =
                result.signedTimeSeconds
        else {
            return ATHLTHLocalization
                .choose(
                    english:
                        "Ghost comparison saved",
                    norwegian:
                        "Ghost-sammenligning lagret"
                )
        }

        if abs(signed) < 1 {
            return ATHLTHLocalization
                .choose(
                    english:
                        "Dead even with your Ghost",
                    norwegian:
                        "Helt likt med Ghost"
                )
        }

        return signed > 0
            ? ATHLTHLocalization
                .choose(
                    english:
                        "You beat your Ghost",
                    norwegian:
                        "Du slo Ghost"
                )
            : ATHLTHLocalization
                .choose(
                    english:
                        "Ghost finished ahead",
                    norwegian:
                        "Ghost kom foran"
                )
    }

    private func ghostResultSubtitle(
        _ result: GhostRaceResult,
        reference: GhostRaceReference
    ) -> String {
        if !result.completedRoute {
            return ATHLTHLocalization
                .choose(
                    english:
                        "ATHLTH could not confirm the full reference route, but the race data below is still useful.",
                    norwegian:
                        "ATHLTH kunne ikke bekrefte hele referanseruten, men løpsdataene under er fortsatt nyttige."
                )
        }

        return ATHLTHLocalization
            .format(
                english:
                    "Against %@ · %@",
                norwegian:
                    "Mot %@ · %@",
                reference.title,
                ghostOverallDeltaDetail(
                    result
                )
            )
    }

    private func ghostOverallDeltaText(
        _ result: GhostRaceResult
    ) -> String {
        guard let signed =
                result.signedTimeSeconds,
              result.completedRoute
        else {
            return "—"
        }

        let prefix =
            signed > 0
                ? "−"
                : signed < 0
                    ? "+"
                    : "±"

        return prefix +
            compactGhostDuration(
                abs(signed)
            )
    }

    private func ghostOverallDeltaDetail(
        _ result: GhostRaceResult
    ) -> String {
        guard let signed =
                result.signedTimeSeconds,
              result.completedRoute
        else {
            return ATHLTHLocalization
                .choose(
                    english:
                        "route comparison incomplete",
                    norwegian:
                        "rutesammenligning ufullstendig"
                )
        }

        if abs(signed) < 1 {
            return ATHLTHLocalization
                .choose(
                    english:
                        "same finish time",
                    norwegian:
                        "samme sluttid"
                )
        }

        return ATHLTHLocalization
            .format(
                english:
                    signed > 0
                        ? "%@ ahead"
                        : "%@ behind",
                norwegian:
                    signed > 0
                        ? "%@ foran"
                        : "%@ bak",
                compactGhostDuration(
                    abs(signed)
                )
            )
    }

    private func ghostResultTint(
        _ result: GhostRaceResult
    ) -> Color {
        guard let signed =
                result.signedTimeSeconds,
              result.completedRoute
        else {
            return .secondary
        }

        return signed >= 0
            ? .green
            : .orange
    }

    private func ghostSplitDeltaText(
        _ signedSeconds:
            TimeInterval
    ) -> String {
        if abs(signedSeconds) < 0.5 {
            return "±0s"
        }

        let prefix =
            signedSeconds >= 0
                ? "−"
                : "+"

        return prefix +
            compactGhostDuration(
                abs(signedSeconds)
            )
    }

    private func compactGhostDuration(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(
                    seconds
                        .rounded()
                ),
                0
            )

        if total < 60 {
            return "\(total)s"
        }

        return String(
            format:
                "%d:%02d",
            total / 60,
            total % 60
        )
    }

    private func compactGhostDistance(
        _ meters: Double
    ) -> String {
        if meters >= 1_000 {
            return String(
                format:
                    "%.2f km",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m"
    }

    private func splitPaceText(
        _ seconds:
            TimeInterval
    ) -> String {
        let total =
            max(
                Int(
                    seconds
                        .rounded()
                ),
                0
            )

        return String(
            format:
                "%d:%02d",
            total / 60,
            total % 60
        )
    }

    private var reflectionCard: some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            HStack(
                alignment: .top,
                spacing: 14
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "HOW DID IT FEEL?",
                            norwegian: "HVORDAN FØLTES ØKTEN?"
                        )
                    )
                        .font(.caption2.weight(.bold))
                        .tracking(1.7)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(
                        Self.effortLabel(
                            Int(effort)
                        )
                    )
                    .font(.title3.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                }

                Spacer()

                HStack(
                    alignment: .firstTextBaseline,
                    spacing: 2
                ) {
                    Text("\(Int(effort))")
                        .font(
                            .system(
                                size: 36,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            completionAccent
                        )

                    Text("/10")
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }

            Slider(
                value: $effort,
                in: 1...10,
                step: 1
            )
            .tint(completionAccent)

            HStack {
                Text(ATHLTHLocalization.choose(english: "Easy", norwegian: "Lett"))
                Spacer()
                Text(ATHLTHLocalization.choose(english: "Max", norwegian: "Maks"))
            }
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .padding(.top, -8)

            if isAdvancedReview {
                Divider()
                    .opacity(0.65)

                VStack(
                    alignment: .leading,
                    spacing: 9
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Quick note",
                            norwegian: "Kort notat"
                        )
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "What stood out about this workout?",
                            norwegian:
                                "Hva skilte seg ut med denne økten?"
                        ),
                        text: $descriptionText,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .padding(13)
                    .background(
                        Color.black.opacity(
                            0.035
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                    )
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHPlanDesign.selectedSurface,
                    ATHLTHPlanDesign.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                completionAccent.opacity(0.10),
                lineWidth: 0.8
            )
        }
    }

    private var workoutPhotoCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(
                alignment: .top,
                spacing: 12
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "PHOTOS FROM THIS WORKOUT",
                            norwegian:
                                "BILDER FRA ØKTEN"
                        )
                    )
                    .font(
                        .caption2.weight(.bold)
                    )
                    .tracking(1.65)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Add moments you want to keep on your profile.",
                            norwegian:
                                "Legg til øyeblikk du vil beholde på profilen."
                        )
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                }

                Spacer()

                PhotosPicker(
                    selection:
                        $selectedPhotoItems,
                    maxSelectionCount: 6,
                    matching: .images
                ) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Add",
                            norwegian: "Legg til"
                        ),
                        systemImage:
                            "photo.badge.plus"
                    )
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        completionAccent
                    )
                    .padding(
                        .horizontal,
                        11
                    )
                    .frame(height: 34)
                    .background(
                        completionAccent
                            .opacity(0.09),
                        in: Capsule()
                    )
                }
            }

            if !selectedPhotoPreviews.isEmpty ||
                !existingWorkoutMedia.isEmpty {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 9) {
                        ForEach(
                            Array(
                                selectedPhotoPreviews
                                    .enumerated()
                            ),
                            id: \.offset
                        ) { _, data in
                            if let image =
                                UIImage(data: data) {
                                Image(
                                    uiImage: image
                                )
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: 92,
                                    height: 92
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 16,
                                        style:
                                            .continuous
                                    )
                                )
                            }
                        }

                        ForEach(
                            existingWorkoutMedia
                        ) { media in
                            ATHLTHStorageImage(
                                url:
                                    URL(
                                        string:
                                            media.imageURL
                                    )
                            ) { phase in
                                switch phase {
                                case .success(
                                    let image
                                ):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    ZStack {
                                        Color.black
                                            .opacity(
                                                0.04
                                            )
                                        Image(
                                            systemName:
                                                "photo"
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                    }
                                }
                            }
                            .frame(
                                width: 92,
                                height: 92
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 16,
                                    style:
                                        .continuous
                                )
                            )
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "photo.on.rectangle.angled"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        completionAccent
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Up to 6 photos. They will appear in Photos & highlights on your profile.",
                            norwegian:
                                "Opptil 6 bilder. De vises under Bilder og høydepunkter på profilen."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }
                .padding(12)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .background(
                    Color.black.opacity(
                        0.025
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }

            if let mediaErrorMessage {
                Label(
                    mediaErrorMessage,
                    systemImage:
                        "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    completionAccent
                        .opacity(0.055),
                    Color.white.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                completionAccent.opacity(
                    0.10
                ),
                lineWidth: 0.8
            )
        }
    }

    private var existingWorkoutMedia:
        [WorkoutMediaRecord] {
        social.workoutMedia.filter {
            $0.workoutID == workout.id
        }
    }

    private var compactTrainTogetherButton:
        some View {
        Button {
            showingTrainingPartners = true
        } label: {
            HStack(spacing: 11) {
                Image(
                    systemName:
                        "person.2.fill"
                )
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    completionAccent
                )
                .frame(
                    width: 34,
                    height: 34
                )
                .background(
                    completionAccent
                        .opacity(0.09),
                    in: Circle()
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Train Together",
                            norwegian:
                                "Tren sammen"
                        )
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        selectedFriendIDs
                            .isEmpty
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Add training partners",
                                    norwegian:
                                        "Legg til treningspartnere"
                                )
                            : ATHLTHLocalization
                                .format(
                                    english:
                                        "%d selected",
                                    norwegian:
                                        "%d valgt",
                                    selectedFriendIDs
                                        .count
                                )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                if !selectedFriendIDs
                    .isEmpty {
                    Text(
                        "\(selectedFriendIDs.count)"
                    )
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        completionAccent
                    )
                    .padding(
                        .horizontal,
                        9
                    )
                    .frame(height: 26)
                    .background(
                        completionAccent
                            .opacity(0.09),
                        in: Capsule()
                    )
                }

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            }
            .padding(
                .horizontal,
                14
            )
            .frame(height: 58)
            .background(
                Color.white.opacity(
                    0.90
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
                    Color.black.opacity(
                        0.045
                    ),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var visibilityCard: some View {
        ATHLTHUnifiedCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Label(
                        "Visibility",
                        systemImage: "eye.fill"
                    )
                    .font(.headline)

                    Spacer()

                    Text(
                        visibility.title
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Picker(
                    "Visibility",
                    selection: $visibility
                ) {
                    ForEach(
                        ProfileVisibility.allCases
                    ) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)

                visibilityExplanation
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings
                    .autoPublishCompletedWorkouts {
                    Label(
                        alreadyPublished
                            ? "Already shared. Saving updates the existing activity."
                            : "Nothing is posted until you save this review.",
                        systemImage: "bolt.fill"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        completionAccent
                    )
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ATHLTHTheme.divider.opacity(0.55))
                .frame(height: 0.7)

            HStack(spacing: 12) {
                Menu {
                    ForEach(ProfileVisibility.allCases) { option in
                        Button {
                            visibility = option
                        } label: {
                            Label(
                                option.title,
                                systemImage: visibility == option
                                    ? "checkmark.circle.fill" : "eye"
                            )
                        }
                    }
                } label: {
                    HStack(alignment: .bottom, spacing: 7) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Workout review", norwegian: "Øktoppsummering"
                            ))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            Text(visibility == .privateOnly
                                 ? ATHLTHLocalization.choose(english: "Private", norwegian: "Privat")
                                 : visibility.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .padding(.bottom, 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Change who can see this workout",
                    norwegian: "Endre hvem som kan se denne økten"
                ))

                Spacer(minLength: 2)

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 10) {
                        if saving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: visibility == .privateOnly
                                ? "checkmark" : "square.and.arrow.up")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        Text(saveButtonTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minWidth: 160, minHeight: 54)
                    .background(
                        LinearGradient(
                            colors: [
                                ATHLTHPlanDesign.accentInk,
                                ATHLTHPlanDesign.ink
                            ],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .background(.regularMaterial)
    }

    private func sectionLabel(
        _ title: String,
        subtitle: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.7)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    // The same accessible bronze accent across all workouts as Training Plan.
    private var completionAccent: Color {
        ATHLTHPlanDesign.accentInk
    }

    private var strengthVolumeText: String? {
        guard let volume =
                workout
                    .strengthTotalVolumeKilograms,
              volume > 0
        else {
            return nil
        }

        if volume >= 1_000 {
            return String(
                format: "%.1f t",
                volume / 1_000
            )
        }

        return String(
            format: "%.0f kg",
            volume
        )
    }

    private var saveButtonTitle: String {
        if visibility == .privateOnly {
            return ATHLTHLocalization.choose(english: "Save", norwegian: "Lagre")
        }

        if alreadyPublished || wasAutoPublished {
            return ATHLTHLocalization.choose(english: "Update", norwegian: "Oppdater")
        }

        return ATHLTHLocalization.choose(
            english: "Save & Share",
            norwegian: "Lagre og del"
        )
    }

    private func averagePaceText(
        duration: TimeInterval,
        distanceMeters: Double
    ) -> String {
        guard distanceMeters > 0 else {
            return "—"
        }

        let secondsPerKilometer =
            duration /
            (distanceMeters / 1_000)

        guard secondsPerKilometer.isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let total =
            max(
                Int(
                    secondsPerKilometer
                        .rounded()
                ),
                0
            )

        return String(
            format: "%d:%02d/km",
            total / 60,
            total % 60
        )
    }

    private func muscleGroupsText(
        limit: Int
    ) -> String? {
        guard let groups = workout.strengthMuscleGroups,
              !groups.isEmpty
        else {
            return nil
        }

        let cleanGroups = groups.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .capitalized
        }
        .filter { !$0.isEmpty }

        guard !cleanGroups.isEmpty else {
            return nil
        }

        let shown = Array(cleanGroups.prefix(max(limit, 1)))
        let remaining = cleanGroups.count - shown.count
        let base = shown.joined(separator: " · ")

        return remaining > 0
            ? "\(base) +\(remaining)"
            : base
    }

    @ViewBuilder
    private var visibilityExplanation: some View {
        switch visibility {
        case .privateOnly:
            Text("Only you can see this workout in ATHLTH.")
        case .friends:
            Text("Friends allowed by your social privacy settings can see it.")
        case .publicProfile:
            Text("Visible on your ATHLTH profile to people allowed to view public activity.")
        }
    }

    @MainActor
    private func loadReplayContext() async {
        replayContext = await health.athlthReplayContext(
            for: workout,
            maximumHeartRateBPM:
                session.onboardingProfile?.maximumHeartRateBPM
        )
    }

    private func waitingTimeText(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    @MainActor
    private func loadCompletionRoute() async {
        guard workout.activity == .running ||
                workout.activity == .walking
        else {
            completionRoute = []
            completionWaitingSeconds = nil
            return
        }

        let detail = await health.workoutDetail(for: workout.id)
        completionRoute = detail.route
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 65 }
            .sorted { $0.timestamp < $1.timestamp }

        completionWaitingSeconds = workout.isIndoor == true
            ? nil
            : ATHLTHStationaryTimeEstimator.waitingSeconds(
                from: completionRoute,
                workoutDuration: workout.duration
            )
    }

    private func loadExistingReview() async {
        visibility =
            initialVisibilityOverride ??
            .friends
        selectedFriendIDs =
            social.workoutAssociatedFriendIDs(
                for: workout.id
            )

        if gear.items.isEmpty {
            await gear.refresh()
        }
        selectedGearIDs = gear.gearIDs(
            for: workout.id
        )

        if let activity = await social.workoutActivity(for: workout.id) {
            alreadyPublished = true

            if let existingVisibility = ProfileVisibility(rawValue: activity.visibility) {
                visibility = existingVisibility
            }

            if let caption = activity.metadata?["caption"] {
                descriptionText = caption
            }

            if let rawEffort = activity.metadata?["effort"],
               let existingEffort = Double(rawEffort) {
                effort = min(max(existingEffort, 1), 10)
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }

        let gearSaved = await gear.saveGearUsage(
            for: workout,
            gearIDs: selectedGearIDs
        )

        if gearSaved {
            notifications.syncGearUsageAlerts(
                from: gear
            )
        }

        let reviewSaved = await social.saveWorkoutReview(
            workout,
            visibility: visibility,
            description: descriptionText,
            effort: Int(effort),
            friendIDs: selectedFriendIDs,
            creatorName: session.profile.displayName,
            creatorUsername: session.profile.username
        )

        let mediaSaved =
            await uploadSelectedPhotos()

        if gearSaved &&
            reviewSaved &&
            mediaSaved {
            dismiss()
        }
    }

    private func loadSelectedPhotos(
        _ items: [PhotosPickerItem]
    ) async {
        var loaded: [Data] = []

        for item in items.prefix(6) {
            guard let data =
                    try? await item
                        .loadTransferable(
                            type: Data.self
                        ),
                  let prepared =
                    preparedWorkoutPhotoData(
                        from: data
                    )
            else {
                continue
            }

            loaded.append(prepared)
        }

        await MainActor.run {
            selectedPhotoPreviews =
                loaded
            mediaErrorMessage = nil
        }
    }

    @MainActor
    private func uploadSelectedPhotos()
        async -> Bool
    {
        guard !selectedPhotoPreviews
            .isEmpty
        else {
            return true
        }

        mediaErrorMessage = nil

        for jpeg in
            selectedPhotoPreviews {
            let uploaded =
                await social
                    .uploadWorkoutMedia(
                        workoutID:
                            workout.id,
                        jpegData: jpeg,
                        caption:
                            descriptionText
                    )

            if !uploaded {
                mediaErrorMessage =
                    ATHLTHLocalization.choose(
                        english:
                            "A photo could not be uploaded. Try again.",
                        norwegian:
                            "Et bilde kunne ikke lastes opp. Prøv igjen."
                    )
                return false
            }
        }

        selectedPhotoItems = []
        selectedPhotoPreviews = []
        return true
    }

    private func preparedWorkoutPhotoData(
        from data: Data
    ) -> Data? {
        guard let image =
                UIImage(data: data)
        else {
            return nil
        }

        let maximumDimension:
            CGFloat = 2_048
        let sourceSize = image.size
        let sourceMaximum =
            max(
                sourceSize.width,
                sourceSize.height
            )

        guard sourceMaximum > 0 else {
            return nil
        }

        if sourceMaximum <=
            maximumDimension {
            return image.jpegData(
                compressionQuality: 0.82
            )
        }

        let scale =
            maximumDimension /
            sourceMaximum
        let targetSize =
            CGSize(
                width:
                    max(
                        1,
                        sourceSize.width *
                        scale
                    ),
                height:
                    max(
                        1,
                        sourceSize.height *
                        scale
                    )
            )

        let renderer =
            UIGraphicsImageRenderer(
                size: targetSize
            )
        let resized =
            renderer.image { _ in
                image.draw(
                    in: CGRect(
                        origin: .zero,
                        size: targetSize
                    )
                )
            }

        return resized.jpegData(
            compressionQuality: 0.82
        )
    }

    static func effortLabel(_ effort: Int) -> String {
        switch effort {
        case ...2: return ATHLTHLocalization.choose(english: "Very easy", norwegian: "Svært lett")
        case 3...4: return ATHLTHLocalization.choose(english: "Easy", norwegian: "Lett")
        case 5...6: return ATHLTHLocalization.choose(english: "Moderate", norwegian: "Moderat")
        case 7...8: return ATHLTHLocalization.choose(english: "Hard", norwegian: "Hard")
        case 9: return ATHLTHLocalization.choose(english: "Very hard", norwegian: "Svært hard")
        default: return ATHLTHLocalization.choose(english: "Maximum", norwegian: "Maksimal")
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }

        return String(format: "%d:%02d", minutes, remainder)
    }
}


/// Conservative stationary-time estimate from continuous recorded GPS fixes.
/// It never infers waiting during unrecorded GPS gaps or indoor treadmill use.
enum ATHLTHStationaryTimeEstimator {
    static func waitingSeconds(
        from samples: [CLLocation],
        workoutDuration: TimeInterval
    ) -> TimeInterval? {
        guard workoutDuration.isFinite, workoutDuration > 0 else { return nil }

        let good = samples
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 20 }
            .sorted { $0.timestamp < $1.timestamp }
        guard good.count >= 4 else { return nil }

        var observedSeconds: TimeInterval = 0
        var waitingSeconds: TimeInterval = 0
        var candidateSeconds: TimeInterval = 0
        var candidatePairs = 0
        func finishCandidate() {
            if candidateSeconds >= 10, candidatePairs >= 2 {
                waitingSeconds += candidateSeconds
            }
            candidateSeconds = 0
            candidatePairs = 0
        }

        for index in 1..<good.count {
            let previous = good[index - 1]
            let next = good[index]
            let delta = next.timestamp.timeIntervalSince(previous.timestamp)
            // Never treat a gap in HealthKit location samples as a pause.
            guard delta >= 1, delta <= 20 else {
                finishCandidate()
                continue
            }
            observedSeconds += delta

            let displacement = previous.distance(from: next)
            let inferredSpeed = displacement / delta
            let limitedDrift = displacement <= max(
                3.5, min(max(previous.horizontalAccuracy,
                             next.horizontalAccuracy) * 0.65, 9)
            )
            // Speed < 0 signals that a GPS speed fix is unavailable.
            let speedAllowsStop = next.speed < 0 || next.speed <= 0.55
            if limitedDrift && inferredSpeed <= 0.55 && speedAllowsStop {
                candidateSeconds += delta
                candidatePairs += 1
            } else {
                finishCandidate()
            }
        }
        finishCandidate()

        // Sparse tracks are not evidence of zero waiting time.
        // Require a meaningful portion of the workout to be represented.
        // A tiny route fragment must never report zero waiting for a long run.
        guard observedSeconds >= max(30, workoutDuration * 0.45) else { return nil }
        return min(waitingSeconds, workoutDuration)
    }
}
