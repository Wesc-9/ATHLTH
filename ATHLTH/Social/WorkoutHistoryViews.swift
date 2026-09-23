import MapKit
import SwiftUI

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
                    Text("Workout History")
                        .font(.title3.bold())
                    Text("Every completed workout in one place.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    Text("View All")
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

    @State private var workouts: [SocialPublishableWorkout] = []
    @State private var filter: WorkoutHistoryFilter = .all
    @State private var loading = false

    private var filtered: [SocialPublishableWorkout] {
        workouts.filter { filter.includes($0.activity) }
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

    let workout: SocialPublishableWorkout

    @State private var activity: SocialActivityRecord?
    @State private var healthDetail = WorkoutDetail()
    @State private var healthDetailLoaded = false
    @State private var showingReview = false

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

                metricGrid

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
            activity = await social.workoutActivity(for: workout.id)
            healthDetail = await health.workoutDetail(for: workout.id)
            healthDetailLoaded = true
        }
        .sheet(isPresented: $showingReview, onDismiss: {
            Task {
                activity = await social.workoutActivity(for: workout.id)
            }
        }) {
            PostWorkoutReviewView(
                workout: workout,
                wasAutoPublished: activity != nil
            )
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

struct PostWorkoutReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore

    let workout: SocialPublishableWorkout
    let wasAutoPublished: Bool

    @State private var visibility: ProfileVisibility = .friends
    @State private var descriptionText = ""
    @State private var effort = 5.0
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var saving = false
    @State private var alreadyPublished = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard

                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("How did it feel?")
                                .font(.headline)

                            HStack(alignment: .firstTextBaseline) {
                                Text("\(Int(effort))")
                                    .font(.system(size: 38, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(ATHLTHTheme.accent)

                                Text("/10")
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(Self.effortLabel(Int(effort)))
                                    .font(.subheadline.weight(.semibold))
                            }

                            Slider(value: $effort, in: 1...10, step: 1)
                                .tint(ATHLTHTheme.accent)

                            Text("Use this as your perceived effort for the session.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Description")
                                .font(.headline)

                            TextField(
                                "How did the workout go?",
                                text: $descriptionText,
                                axis: .vertical
                            )
                            .lineLimit(3...7)
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    ATHLTHCard {
                        WorkoutFriendPicker(
                            selectedFriendIDs: $selectedFriendIDs
                        )
                    }

                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Visibility")
                                .font(.headline)

                            Picker("Visibility", selection: $visibility) {
                                ForEach(ProfileVisibility.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)

                            visibilityExplanation
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if settings.autoPublishCompletedWorkouts {
                                Label(
                                    alreadyPublished || wasAutoPublished
                                        ? "This workout was published automatically. Saving updates it."
                                        : "Automatic workout publishing is enabled.",
                                    systemImage: "bolt.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                            }
                        }
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if saving {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(
                                visibility == .privateOnly
                                    ? "Save Workout"
                                    : alreadyPublished || wasAutoPublished
                                        ? "Update Workout"
                                        : "Save & Share"
                            )
                            .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                    .disabled(saving)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Workout Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadExistingReview()
            }
        }
    }

    private var summaryCard: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [ATHLTHTheme.accent.opacity(0.88), .black.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(.white.opacity(0.11))
                .frame(width: 175, height: 125)
                .offset(x: 190, y: -30)

            VStack(alignment: .leading, spacing: 8) {
                Label("WORKOUT COMPLETE", systemImage: "checkmark.circle.fill")
                    .font(.caption2.bold())
                    .tracking(1.3)

                Text(workout.title)
                    .font(.title.bold())

                HStack(spacing: 12) {
                    Label(durationText(workout.duration), systemImage: "clock.fill")

                    if let distance = workout.distanceMeters,
                       distance > 0 {
                        Label(
                            String(format: "%.2f km", distance / 1_000),
                            systemImage: "location.fill"
                        )
                    }

                    if let calories = workout.activeEnergyKilocalories,
                       calories > 0 {
                        Label(
                            String(format: "%.0f kcal", calories),
                            systemImage: "flame.fill"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24))
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

    private func loadExistingReview() async {
        visibility = settings.defaultActivityVisibility
        selectedFriendIDs = social.workoutAssociatedFriendIDs(for: workout.id)

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

        let success = await social.saveWorkoutReview(
            workout,
            visibility: visibility,
            description: descriptionText,
            effort: Int(effort),
            friendIDs: selectedFriendIDs,
            creatorName: session.profile.displayName,
            creatorUsername: session.profile.username
        )

        if success {
            dismiss()
        }
    }

    static func effortLabel(_ effort: Int) -> String {
        switch effort {
        case ...2: return "Very easy"
        case 3...4: return "Easy"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        case 9: return "Very hard"
        default: return "Maximum"
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
