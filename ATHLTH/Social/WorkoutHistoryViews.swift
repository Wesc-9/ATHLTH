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
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent Activity")
                        .font(.title3.bold())
                    Text("Your latest completed workouts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    Text("See All")
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
                        Text("No workouts yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Completed workouts will appear here automatically.")
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
            healthItems = summaries.map(SocialPublishableWorkout.init)
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
            Picker("Workout type", selection: $filter) {
                ForEach(WorkoutHistoryFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if loading && workouts.isEmpty {
                Spacer()
                ProgressView("Loading workout history…")
                Spacer()
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "No workouts",
                    systemImage: "figure.run.circle",
                    description: Text("Completed workouts from Apple Health and ATHLTH will appear here.")
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
                                        Color(.secondarySystemGroupedBackground),
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Workout History")
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
            healthItems = summaries.map(SocialPublishableWorkout.init)
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

                if healthDetailLoaded {
                    if healthDetail.route.count >= 2 ||
                        healthDetail.workoutLocation != nil ||
                        healthDetail.route.count == 1 {
                        WorkoutLocationMapCard(
                            detail: healthDetail,
                            activity: workout.activity
                        )
                    } else if workout.activity == .strength {
                        ATHLTHCard {
                            HStack(spacing: 12) {
                                Image(systemName: "location.slash.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Workout location unavailable")
                                        .font(.subheadline.weight(.semibold))
                                    Text(
                                        "This strength workout did not contain a saved location in Apple Health."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
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

                ATHLTHCard {
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

                ATHLTHCard {
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
        ATHLTHCard {
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
        ATHLTHCard {
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
        HStack(spacing: 10) {
            metric("Time", durationText(workout.duration), "clock.fill")

            if let distance = workout.distanceMeters, distance > 0 {
                metric(
                    "Distance",
                    String(format: "%.2f km", distance / 1_000),
                    "point.topleft.down.to.point.bottomright.curvepath"
                )
            }

            if let calories = workout.activeEnergyKilocalories,
               calories > 0 {
                metric(
                    "Energy",
                    String(format: "%.0f kcal", calories),
                    "flame.fill"
                )
            }
        }
    }

    private func metric(
        _ title: String,
        _ value: String,
        _ icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accent)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 17)
        )
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

private struct WorkoutLocationMapCard: View {
    let detail: WorkoutDetail
    let activity: WorkoutActivity

    private var routeCoordinates: [CLLocationCoordinate2D] {
        detail.route.map(\.coordinate)
    }

    private var singleLocation: CLLocation? {
        if let workoutLocation = detail.workoutLocation {
            return workoutLocation
        }

        return detail.route.count == 1 ? detail.route.first : nil
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
        ATHLTHCard {
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
    @State private var completionRoute: [CLLocation] = []
    @State private var isAdvancedReview = false
    @State private var showingTrainingPartners = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedPhotoPreviews: [Data] = []
    @State private var mediaErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    resultStrip

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

                    visibilityCard
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
                        completionAccent.opacity(0.12)
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
                        ATHLTHCard {
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

    private var summaryCard: some View {
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

                    Text(workout.source.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            Color.white.opacity(0.12),
                            in: Capsule()
                        )
                }

                Spacer()

                Text(completionActivityTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        Color.white.opacity(0.70)
                    )
                    .padding(.bottom, 4)

                Text(completionWorkoutTitle)
                    .font(
                        .system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)

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
        .frame(height: 224)
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
        if (workout.activity == .running ||
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
                    completionAccent,
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
                            red: 0.07,
                            green: 0.22,
                            blue: 0.17
                        ),
                        Color(
                            red: 0.06,
                            green: 0.08,
                            blue: 0.10
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
            Image("StrengthPostWorkoutHero")
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

    private var resultStrip: some View {
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
                    completionAccent.opacity(0.065),
                    Color.white.opacity(0.94)
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
        ATHLTHCard {
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
            Divider()
                .opacity(0.55)

            HStack(spacing: 12) {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Workout review",
                            norwegian: "Øktoppsummering"
                        )
                    )
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(
                        visibility ==
                            .privateOnly
                            ? "Private"
                            : visibility.title
                    )
                    .font(
                        .subheadline.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                }

                Spacer()

                Button {
                    Task {
                        await save()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if saving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(
                                systemName:
                                    visibility ==
                                        .privateOnly
                                        ? "checkmark"
                                        : "square.and.arrow.up"
                            )
                        }

                        Text(saveButtonTitle)
                    }
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(completionAccent)
                .disabled(saving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
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

    private var completionAccent: Color {
        switch workout.activity {
        case .running:
            return ATHLTHTheme.vitality
        case .walking,
             .hiking:
            return .teal
        case .cycling,
             .swimming:
            return .blue
        case .strength:
            return .indigo
        case .hiit:
            return .orange
        case .rowing,
             .elliptical,
             .stairClimbing:
            return .cyan
        case .yoga,
             .coreTraining:
            return .purple
        case .other:
            return ATHLTHTheme.accentDeep
        }
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

    @MainActor
    private func loadCompletionRoute() async {
        guard workout.activity == .running ||
                workout.activity == .walking
        else {
            completionRoute = []
            return
        }

        let detail =
            await health.workoutDetail(
                for: workout.id
            )

        completionRoute =
            detail.route
                .filter {
                    $0.horizontalAccuracy >= 0 &&
                    $0.horizontalAccuracy <= 65
                }
                .sorted {
                    $0.timestamp <
                    $1.timestamp
                }
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
