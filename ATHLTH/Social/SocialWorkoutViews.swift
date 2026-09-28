import MapKit
import SwiftUI
import UIKit

struct WorkoutFriendPicker: View {
    @EnvironmentObject private var social: SocialStore

    @Binding var selectedFriendIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Invite friends (optional)", systemImage: "person.2.fill")
                    .font(.headline)

                Spacer()

                if !selectedFriendIDs.isEmpty {
                    Text("\(selectedFriendIDs.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }
            }

            if social.friends.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(ATHLTHTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Train solo")
                            .font(.subheadline.weight(.semibold))
                        Text("Friends are optional. You can start this workout by yourself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 13) {
                        ForEach(social.friends) { friend in
                            Button {
                                if selectedFriendIDs.contains(friend.userID) {
                                    selectedFriendIDs.remove(friend.userID)
                                } else {
                                    selectedFriendIDs.insert(friend.userID)
                                }
                            } label: {
                                VStack(spacing: 7) {
                                    ZStack(alignment: .bottomTrailing) {
                                        SocialAvatar(profile: friend, size: 52)

                                        Image(
                                            systemName: selectedFriendIDs.contains(friend.userID)
                                                ? "checkmark.circle.fill"
                                                : "plus.circle.fill"
                                        )
                                        .font(.system(size: 18))
                                        .foregroundStyle(
                                            selectedFriendIDs.contains(friend.userID)
                                                ? ATHLTHTheme.accent
                                                : .secondary
                                        )
                                        .background(.white, in: Circle())
                                    }

                                    Text(friend.resolvedName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 74)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Text(
                selectedFriendIDs.isEmpty
                    ? "No invite is required to start."
                    : "Selected friends receive an invite and appear as training partners after they accept."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    var selectedFriends: [SocialProfileCard] {
        social.friends.filter { selectedFriendIDs.contains($0.userID) }
    }
}

struct QuickWorkoutStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var settings: AppSettingsStore

    let kind: WorkoutKind
    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (
        [SocialProfileCard],
        Set<UUID>,
        WatchAudioCoachConfiguration
    ) -> Void

    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var audioCoachLoaded = false

    private var canStart: Bool {
        trainingDeviceProvider == .appleWatch && watchConnected
    }

    private var workoutActivity: WorkoutActivity {
        switch kind {
        case .running:
            return .running
        case .walking:
            return .walking
        case .strength:
            return .strength
        case .mobility:
            return .yoga
        case .recovery, .custom:
            return .other
        }
    }

    private var deviceStatusText: String {
        switch trainingDeviceProvider {
        case .appleWatch:
            return watchConnected
                ? "Ready to start on Apple Watch."
                : "Finish Apple Watch setup before starting this outdoor workout."
        case .garmin:
            return "Garmin is selected. Record this workout on Garmin for now; direct Garmin sync will unlock after authorization is approved."
        case .none:
            return "No watch selected. ATHLTH stays fully usable, but direct outdoor workout capture is not enabled for this quick start yet."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHCard {
                        HStack(spacing: 14) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 52, height: 52)
                                .background(
                                    ATHLTHTheme.accent.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 15)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.title)
                                    .font(.title2.bold())
                                Text(deviceStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }

                    if kind == .running {
                        ATHLTHCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Route")
                                        .font(.headline)
                                    Text(
                                        "Optional · create or pick a saved route before you start."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                NavigationLink {
                                    RunRouteBuilderView()
                                } label: {
                                    Label(
                                        "Create",
                                        systemImage: "map.fill"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(ATHLTHTheme.accent)
                            }

                            NavigationLink {
                                SavedRoutesView()
                            } label: {
                                Label(
                                    "Saved Routes",
                                    systemImage: "map"
                                )
                                .font(.subheadline.weight(.semibold))
                            }
                            .padding(.top, 10)
                        }
                    }

                    AudioCoachSetupCard(
                        draft: $audioCoachDraft,
                        showRouteOptions:
                            kind == .running ||
                            kind == .walking,
                        showStructuredOptions: false
                    )

                    WorkoutGearSelectionCard(
                        selectedGearIDs: $selectedGearIDs,
                        activity: workoutActivity
                    )

                    ATHLTHCard {
                        WorkoutFriendPicker(
                            selectedFriendIDs: $selectedFriendIDs
                        )
                    }

                    Button {
                        let selected = social.friends.filter {
                            selectedFriendIDs.contains($0.userID)
                        }

                        onStart(
                            selected,
                            selectedGearIDs,
                            audioCoachDraft.configuration()
                        )
                        dismiss()
                    } label: {
                        Label(
                            selectedFriendIDs.isEmpty
                                ? "Start Solo"
                                : "Start with \(selectedFriendIDs.count) Friend\(selectedFriendIDs.count == 1 ? "" : "s")",
                            systemImage: "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                    .disabled(!canStart)
                }
                .padding()
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                if !audioCoachLoaded {
                    audioCoachDraft.load(from: settings)
                    audioCoachLoaded = true
                }

                if social.friends.isEmpty {
                    await social.refresh()
                }

                if gear.items.isEmpty {
                    await gear.refresh()
                }

                if selectedGearIDs.isEmpty {
                    selectedGearIDs =
                        gear.initialGearSelection(
                            for: workoutActivity
                        )
                }
            }
        }
    }
}

struct HomeActivitySection: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var showingPublish = false
    @State private var selectedPublishWorkoutID: UUID?
    @State private var workoutDetails: [UUID: WorkoutDetail] = [:]
    @State private var workoutAIInsights: [UUID: WorkoutAIInsight] = [:]
    @State private var loadingAIInsightIDs: Set<UUID> = []
    @State private var publishedActivities: [UUID: SocialActivityRecord] = [:]
    @State private var selectedCoachInsight: CoachInsightPresentation?

    private var ownWorkouts: [SocialPublishableWorkout] {
        let healthItems = health.workouts.map(SocialPublishableWorkout.init)

        let localStrengthItems = strength.workoutHistory
            .filter {
                $0.isFinished &&
                $0.healthMetrics.healthKitWorkoutUUID == nil
            }
            .map(SocialPublishableWorkout.init)

        return (healthItems + localStrengthItems)
            .sorted { $0.startDate > $1.startDate }
    }

    private var featuredWorkouts: [SocialPublishableWorkout] {
        var result: [SocialPublishableWorkout] = []

        if let outdoor = ownWorkouts.first(where: { isOutdoor($0.activity) }) {
            result.append(outdoor)
        }

        if let strengthWorkout = ownWorkouts.first(where: { $0.activity == .strength }),
           !result.contains(where: { $0.id == strengthWorkout.id }) {
            result.append(strengthWorkout)
        }

        for workout in ownWorkouts where result.count < 2 {
            if !result.contains(where: { $0.id == workout.id }) {
                result.append(workout)
            }
        }

        return result
    }

    private var circleFeed: [SocialFeedItem] {
        guard let currentUserID = social.currentUserID else {
            return social.feed
        }

        return social.feed.filter { $0.actor.userID != currentUserID }
    }

    private var detailLoadKey: String {
        featuredWorkouts
            .map(\.id.uuidString)
            .joined(separator: "-")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity Center")
                        .font(.system(size: 27, weight: .bold))

                    Text("Your latest workouts, routes, and community activity.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                NavigationLink {
                    SocialHubView(initialTab: .feed)
                } label: {
                    HStack(spacing: 5) {
                        Text("See all")
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if social.pendingRequestCount > 0 {
                NavigationLink {
                    SocialHubView(initialTab: .requests)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "bolt.badge.clock.fill")
                            .foregroundStyle(.orange)

                        Text(
                            "\(social.pendingRequestCount) need\(social.pendingRequestCount == 1 ? "s" : "") your attention"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(
                        Color.orange.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            if featuredWorkouts.isEmpty && circleFeed.isEmpty {
                ATHLTHCard {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run.circle")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.vitality)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your activity starts here")
                                .font(.subheadline.weight(.semibold))
                            Text(
                                "Completed workouts and shared activity will appear here automatically."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            } else {
                ForEach(featuredWorkouts) { workout in
                    if workout.activity == .strength {
                        HomeActivityStrengthCard(
                            workout: workout,
                            keyLifts: keyLifts(for: workout),
                            isPublished: isPublished(workout)
                        ) {
                            presentPublish(workout)
                        }
                    } else if isOutdoor(workout.activity) {
                        HomeActivityOutdoorCard(
                            workout: workout,
                            detail: workoutDetails[workout.id],
                            isPublished: isPublished(workout),
                            caption: caption(for: workout),
                            aiInsight:
                                workoutAIInsights[workout.id],
                            isAIInsightLoading:
                                loadingAIInsightIDs
                                    .contains(workout.id),
                            onCoach: { insight in
                                selectedCoachInsight =
                                    CoachInsightPresentation(
                                        id: workout.id,
                                        activityTitle:
                                            workout.activity.rawValue,
                                        date: workout.startDate,
                                        insight: insight
                                    )
                            }
                        ) {
                            presentPublish(workout)
                        }
                    } else {
                        HomeActivityGenericWorkoutCard(
                            workout: workout,
                            isPublished: isPublished(workout)
                        ) {
                            presentPublish(workout)
                        }
                    }
                }

                if !circleFeed.isEmpty {
                    HStack {
                        Text("Community Activity")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Spacer()

                        NavigationLink {
                            SocialHubView(initialTab: .feed)
                        } label: {
                            Text("See all")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                    VStack(spacing: 10) {
                        ForEach(Array(circleFeed.prefix(2))) { item in
                            HomeActivityCommunityCard(item: item)
                        }
                    }
                } else if social.isHomeFeedRefreshing {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating community activity…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .sheet(item: $selectedCoachInsight) { presentation in
            WorkoutCoachInsightDetailView(
                presentation: presentation
            )
        }
        .sheet(
            isPresented: $showingPublish,
            onDismiss: {
                selectedPublishWorkoutID = nil
                Task {
                    await loadPublishedActivityRecords()
                }
            }
        ) {
            WorkoutPublishView(
                initialWorkoutID: selectedPublishWorkoutID
            )
        }
        .task(id: detailLoadKey) {
            // Keep Home responsive: render the workout visual first,
            // then enrich the card with social state and Coach data.
            await loadFeaturedWorkoutDetails()
            await social.refreshHomeFeed()
            await loadPublishedActivityRecords()
            await loadWorkoutAIInsights()
        }
    }

    private func isOutdoor(_ activity: WorkoutActivity) -> Bool {
        switch activity {
        case .running, .walking, .cycling, .hiking:
            return true
        default:
            return false
        }
    }

    private func isPublished(_ workout: SocialPublishableWorkout) -> Bool {
        if publishedActivities[workout.id] != nil {
            return true
        }

        return social.feed.contains { item in
            item.actor.userID == social.currentUserID &&
            item.activity.kind == "workout" &&
            item.activity.metadata?["workout_id"] == workout.id.uuidString
        }
    }

    private func caption(for workout: SocialPublishableWorkout) -> String? {
        if let caption = publishedActivities[workout.id]?
            .metadata?["caption"] {
            return caption
        }

        return social.feed.first {
            $0.actor.userID == social.currentUserID &&
            $0.activity.kind == "workout" &&
            $0.activity.metadata?["workout_id"] == workout.id.uuidString
        }?.activity.metadata?["caption"]
    }

    private func presentPublish(_ workout: SocialPublishableWorkout) {
        selectedPublishWorkoutID = workout.id
        showingPublish = true
    }

    @MainActor
    private func loadPublishedActivityRecords() async {
        var refreshed: [UUID: SocialActivityRecord] = [:]

        for workout in featuredWorkouts {
            if let activity = await social.workoutActivity(
                for: workout.id
            ) {
                refreshed[workout.id] = activity
            }
        }

        publishedActivities = refreshed
    }

    private func keyLifts(for workout: SocialPublishableWorkout) -> [String] {
        guard workout.activity == .strength else { return [] }

        guard let log = strength.workoutHistory.first(where: {
            $0.id == workout.id ||
            $0.healthMetrics.healthKitWorkoutUUID == workout.id
        }) else {
            return []
        }

        return Array(
            log.exercises
                .map { $0.exercise.name }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(3)
        )
    }

    @MainActor
    private func loadFeaturedWorkoutDetails() async {
        for workout in featuredWorkouts where isOutdoor(workout.activity) {
            guard workoutDetails[workout.id] == nil,
                  health.workouts.contains(where: { $0.id == workout.id })
            else {
                continue
            }

            workoutDetails[workout.id] = await health.workoutDetail(
                for: workout.id
            )
        }
    }

    @MainActor
    private func loadWorkoutAIInsights() async {
        guard session.hasPaidAccess,
              session.aiHealthDataSharingEnabled
        else {
            workoutAIInsights.removeAll()
            loadingAIInsightIDs.removeAll()
            return
        }

        let service = WorkoutInsightAIService()

        for workout in featuredWorkouts
            where workout.activity == .running ||
                  workout.activity == .walking {
            guard workoutAIInsights[workout.id] == nil,
                  let summary =
                    health.workouts.first(
                        where: {
                            $0.id == workout.id
                        }
                    )
            else {
                continue
            }

            loadingAIInsightIDs.insert(
                workout.id
            )

            let context =
                await health
                    .workoutAIInsightContext(
                        for: summary,
                        maximumHeartRateBPM:
                            session
                                .onboardingProfile?
                                .maximumHeartRateBPM
                    )

            do {
                workoutAIInsights[workout.id] =
                    try await service.generate(
                        workoutID: workout.id,
                        context: context
                    )
            } catch {
                // Keep the deterministic local insight as a graceful
                // fallback when Coach is unavailable.
            }

            loadingAIInsightIDs.remove(
                workout.id
            )
        }
    }
}

private struct HomeActivityOutdoorCard: View {
    let workout: SocialPublishableWorkout
    let detail: WorkoutDetail?
    let isPublished: Bool
    let caption: String?
    let aiInsight: WorkoutAIInsight?
    let isAIInsightLoading: Bool
    let onCoach: (WorkoutAIInsight) -> Void
    let onPost: () -> Void

    private var routeCoordinates: [CLLocationCoordinate2D] {
        detail?.route.map(\.coordinate) ?? []
    }

    private var singleLocation: CLLocation? {
        if let workoutLocation = detail?.workoutLocation {
            return workoutLocation
        }

        if detail?.route.count == 1 {
            return detail?.route.first
        }

        return nil
    }

    private var mapRegion: MKCoordinateRegion {
        let coordinates: [CLLocationCoordinate2D]

        if routeCoordinates.count >= 2 {
            coordinates = routeCoordinates
        } else if let singleLocation {
            coordinates = [singleLocation.coordinate]
        } else {
            coordinates = []
        }

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 63.4305,
                    longitude: 10.3951
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.08,
                    longitudeDelta: 0.08
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

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    (maxLatitude - minLatitude) * 1.55,
                    0.008
                ),
                longitudeDelta: max(
                    (maxLongitude - minLongitude) * 1.55,
                    0.008
                )
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                mapBackground

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color.white.opacity(0.72),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.clear,
                        Color.black.opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 9) {
                            activityBadge

                            HStack(spacing: 10) {
                                Image(systemName: workout.activity.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Color.white.opacity(0.88),
                                        in: Circle()
                                    )
                                    .overlay {
                                        Circle()
                                            .stroke(Color.white.opacity(0.72), lineWidth: 0.8)
                                    }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(activityTitle)
                                        .font(.headline)
                                        .foregroundStyle(ATHLTHTheme.primaryText)

                                    Text(
                                        workout.startDate.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText.opacity(0.68)
                                    )
                                }
                            }
                        }

                        Spacer()

                        Menu {
                            Button {
                                onPost()
                            } label: {
                                Label(
                                    isPublished ? "Update post" : "Post workout",
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .frame(width: 36, height: 36)
                                .background(
                                    Color.white.opacity(0.88),
                                    in: Circle()
                                )
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.72), lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.title)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.80)

                        Text(outdoorDescription)
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.72)
                            )
                            .lineLimit(2)
                    }

                    Spacer(minLength: 16)
                }
                .padding(16)

                if routeCoordinates.count >= 2 {
                    VStack {
                        Spacer()

                        HStack {
                            Spacer()

                            VStack(alignment: .trailing, spacing: 7) {
                                Label(
                                    distanceText,
                                    systemImage:
                                        "point.topleft.down.to.point.bottomright.curvepath"
                                )
                                .homeRouteGlassPill()

                                if let ascentText {
                                    Label(
                                        ascentText,
                                        systemImage: "mountain.2.fill"
                                    )
                                    .homeRouteGlassPill()
                                }
                            }
                        }
                    }
                    .padding(15)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 240)
            .clipped()

            VStack(spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        metric(
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            title: "Distance",
                            value: distanceText
                        )
                        metricDivider
                        metric(
                            icon: "clock",
                            title: "Time",
                            value: durationText
                        )
                        metricDivider
                        metric(
                            icon: "speedometer",
                            title: "Avg. Pace",
                            value: paceText
                        )
                        metricDivider
                        metric(
                            icon: "heart",
                            title: "Avg. HR",
                            value: averageHeartRateText
                        )
                    }

                    HStack(spacing: 0) {
                        metric(
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            title: "Distance",
                            value: distanceText
                        )
                        metricDivider
                        metric(
                            icon: "clock",
                            title: "Time",
                            value: durationText
                        )
                        metricDivider
                        metric(
                            icon: "speedometer",
                            title: "Pace",
                            value: paceText
                        )
                    }
                }

                Button {
                    if let aiInsight {
                        onCoach(aiInsight)
                    }
                } label: {
                    HStack(spacing: 11) {
                        Image(
                            systemName:
                                aiInsight != nil ||
                                isAIInsightLoading
                                    ? "sparkles"
                                    : "chart.bar.fill"
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            aiInsight != nil ||
                            isAIInsightLoading
                                ? .indigo
                                : ATHLTHTheme.vitality
                        )
                        .frame(width: 38, height: 38)
                        .background(
                            (
                                aiInsight != nil ||
                                isAIInsightLoading
                                    ? Color.indigo.opacity(0.08)
                                    : ATHLTHTheme.vitalitySoft
                            ),
                            in: RoundedRectangle(
                                cornerRadius: 11,
                                style: .continuous
                            )
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(
                                    aiInsight != nil ||
                                    isAIInsightLoading
                                        ? "ATHLTH COACH"
                                        : "Insight"
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)

                                if aiInsight != nil ||
                                    isAIInsightLoading {
                                    Text("ATHLTH+")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            ATHLTHTheme.champagneSoft,
                                            in: Capsule()
                                        )
                                }
                            }

                            if isAIInsightLoading &&
                                aiInsight == nil {
                                HStack(spacing: 7) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text(
                                        "Analyzing route, effort and heart-rate response…"
                                    )
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                }
                            } else {
                                Text(
                                    aiInsight.map {
                                        "\($0.headline) — \($0.summary)"
                                    } ?? insightText
                                )
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(2)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Color.white.opacity(0.94),
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(aiInsight == nil)
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.17, blue: 0.17).opacity(0.93),
                        Color(red: 0.18, green: 0.23, blue: 0.22).opacity(0.91)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .background(Color.white.opacity(0.72))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.84), lineWidth: 0.8)
        }
        .shadow(
            color: Color.black.opacity(0.075),
            radius: 12,
            x: 0,
            y: 6
        )
    }

    @ViewBuilder
    private var mapBackground: some View {
        if routeCoordinates.count >= 2 || singleLocation != nil {
            HomeActivityRouteArtwork(
                coordinates: routeCoordinates,
                singleLocation: singleLocation?.coordinate
            )
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        ATHLTHTheme.accentSoft,
                        ATHLTHTheme.vitalitySoft,
                        ATHLTHTheme.cardWarm
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HomeActivityFlowLines()
                    .stroke(
                        ATHLTHTheme.vitality.opacity(0.28),
                        style: StrokeStyle(
                            lineWidth: 16,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(24)

                HomeActivityFlowLines()
                    .stroke(
                        Color.white.opacity(0.94),
                        style: StrokeStyle(
                            lineWidth: 5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(24)

                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 92, weight: .light))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep.opacity(0.09)
                    )
                    .offset(x: 105, y: -22)
            }
        }
    }

    private var activityBadge: some View {
        Text(isPublished ? "Published workout" : "Completed workout")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
                isPublished
                    ? Color.green.opacity(0.82)
                    : ATHLTHTheme.accentDeep
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                isPublished
                    ? Color.green.opacity(0.11)
                    : ATHLTHTheme.accentSoft.opacity(0.82),
                in: Capsule()
            )
    }

    private var activityTitle: String {
        switch workout.activity {
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Ride"
        case .hiking: return "Hike"
        default: return workout.activity.rawValue
        }
    }

    private var outdoorDescription: String {
        if let caption,
           !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return caption
        }

        if routeCoordinates.count >= 2 {
            return "Route, pace and workout data from your completed session."
        }

        return "Completed outdoor workout synced into ATHLTH."
    }

    private var distanceText: String {
        guard let distance = workout.distanceMeters,
              distance > 0
        else {
            return "—"
        }

        return String(format: "%.2f km", distance / 1_000)
    }

    private var durationText: String {
        let total = max(Int(workout.duration.rounded()), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    private var paceText: String {
        guard let distance = workout.distanceMeters,
              distance > 0
        else {
            return "—"
        }

        let paceSeconds = workout.duration / (distance / 1_000)
        guard paceSeconds.isFinite, paceSeconds > 0 else {
            return "—"
        }

        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds.rounded()) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    private var averageHeartRateText: String {
        guard let value = detail?.averageHeartRate,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return "\(Int(value.rounded())) bpm"
    }

    private var ascentText: String? {
        guard let route = detail?.route,
              route.count >= 2
        else {
            return nil
        }

        var gain = 0.0
        var previousAltitude = route[0].altitude

        for point in route.dropFirst() {
            let delta = point.altitude - previousAltitude

            if delta > 0, delta < 100 {
                gain += delta
            }

            previousAltitude = point.altitude
        }

        guard gain >= 5 else {
            return nil
        }

        return "\(Int(gain.rounded())) m ascent"
    }

    private var insightText: String {
        var parts: [String] = []

        if distanceText != "—" {
            parts.append("\(distanceText) completed")
        }

        if paceText != "—" {
            parts.append("at \(paceText) average pace")
        }

        if averageHeartRateText != "—" {
            parts.append("avg HR \(averageHeartRateText)")
        }

        if parts.isEmpty {
            return "Open the workout for full activity details."
        }

        return parts.joined(separator: " · ") + "."
    }

    private func metric(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)

                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.22))
            .frame(width: 1, height: 34)
    }
}

private struct CoachInsightPresentation: Identifiable {
    let id: UUID
    let activityTitle: String
    let date: Date
    let insight: WorkoutAIInsight
}

private struct WorkoutCoachInsightDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: CoachInsightPresentation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Label(
                                "ATHLTH COACH",
                                systemImage: "sparkles"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.indigo)

                            Text("ATHLTH+")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    ATHLTHTheme.champagneSoft,
                                    in: Capsule()
                                )
                        }

                        Text(presentation.insight.headline)
                            .font(
                                .system(
                                    size: 28,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )

                        Text(
                            presentation.activityTitle.capitalized +
                            " · " +
                            presentation.date.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Coach analysis")
                            .font(.headline)

                        Text(presentation.insight.summary)
                            .font(.body)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.82)
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.white.opacity(0.82),
                        in: RoundedRectangle(
                            cornerRadius: 22,
                            style: .continuous
                        )
                    )
                }
                .padding()
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: Color.indigo.opacity(0.14)
                )
            )
            .navigationTitle("Coach Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


private struct HomeActivityRouteArtwork: View {
    let coordinates: [CLLocationCoordinate2D]
    let singleLocation: CLLocationCoordinate2D?

    @State private var image: UIImage?

    private var cacheKey: String {
        HomeActivityRouteSnapshotRenderer.cacheKey(
            coordinates: coordinates,
            singleLocation: singleLocation
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    ATHLTHTheme.vitalitySoft,
                    ATHLTHTheme.cardWarm
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                HomeActivityFlowLines()
                    .stroke(
                        ATHLTHTheme.vitality.opacity(0.78),
                        style: StrokeStyle(
                            lineWidth: 7,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(30)

                ProgressView()
                    .tint(ATHLTHTheme.accentDeep)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .task(id: cacheKey) {
            image =
                await HomeActivityRouteSnapshotRenderer
                    .shared
                    .image(
                        coordinates: coordinates,
                        singleLocation: singleLocation
                    )
        }
    }
}

@MainActor
private final class HomeActivityRouteSnapshotRenderer {
    static let shared =
        HomeActivityRouteSnapshotRenderer()

    private let cache =
        NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 8
        cache.totalCostLimit =
            20 * 1_024 * 1_024
    }

    static func cacheKey(
        coordinates: [CLLocationCoordinate2D],
        singleLocation: CLLocationCoordinate2D?
    ) -> String {
        let points: [CLLocationCoordinate2D]

        if !coordinates.isEmpty {
            points = sampled(
                coordinates,
                maximumCount: 14
            )
        } else if let singleLocation {
            points = [singleLocation]
        } else {
            return "activity-route-empty"
        }

        return points.map {
            String(
                format: "%.5f,%.5f",
                $0.latitude,
                $0.longitude
            )
        }
        .joined(separator: "|")
    }

    func image(
        coordinates: [CLLocationCoordinate2D],
        singleLocation: CLLocationCoordinate2D?
    ) async -> UIImage? {
        let key = Self.cacheKey(
            coordinates: coordinates,
            singleLocation: singleLocation
        ) as NSString

        if let cached = cache.object(
            forKey: key
        ) {
            return cached
        }

        let points: [CLLocationCoordinate2D]

        if coordinates.count >= 2 {
            points = Self.sampled(
                coordinates,
                maximumCount: 180
            )
        } else if let singleLocation {
            points = [singleLocation]
        } else {
            return nil
        }

        let options =
            MKMapSnapshotter.Options()
        options.region =
            Self.region(for: points)
        options.size =
            CGSize(width: 460, height: 285)
        options.scale = 2
        options.mapType = .satellite
        options.pointOfInterestFilter =
            .excludingAll
        options.traitCollection =
            UITraitCollection(
                userInterfaceStyle: .light
            )

        do {
            let snapshot =
                try await MKMapSnapshotter(
                    options: options
                )
                .start()

            let format =
                UIGraphicsImageRendererFormat
                    .default()
            format.scale = 2
            format.opaque = true

            let renderer =
                UIGraphicsImageRenderer(
                    size: options.size,
                    format: format
                )

            let rendered =
                renderer.image { context in
                    snapshot.image.draw(
                        in: CGRect(
                            origin: .zero,
                            size: options.size
                        )
                    )

                    let bounds = CGRect(
                        origin: .zero,
                        size: options.size
                    )

                    let overlayColors = [
                        UIColor(
                            red: 0.93,
                            green: 0.96,
                            blue: 0.91,
                            alpha: 0.18
                        ).cgColor,
                        UIColor(
                            red: 0.10,
                            green: 0.18,
                            blue: 0.17,
                            alpha: 0.10
                        ).cgColor
                    ] as CFArray

                    if let gradient =
                        CGGradient(
                            colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: overlayColors,
                            locations: [0, 1]
                        ) {
                        context.cgContext.drawLinearGradient(
                            gradient,
                            start: CGPoint(x: 0, y: 0),
                            end: CGPoint(
                                x: bounds.maxX,
                                y: bounds.maxY
                            ),
                            options: []
                        )
                    }

                    guard points.count >= 2
                    else {
                        if let point =
                            points.first {
                            let location =
                                snapshot.point(
                                    for: point
                                )
                            Self.drawEndpoint(
                                at: location,
                                fill:
                                    UIColor.systemGreen
                            )
                        }
                        return
                    }

                    let routePath =
                        UIBezierPath()
                    routePath.lineCapStyle =
                        .round
                    routePath.lineJoinStyle =
                        .round

                    for (
                        index,
                        coordinate
                    ) in points.enumerated() {
                        let point =
                            snapshot.point(
                                for: coordinate
                            )

                        if index == 0 {
                            routePath.move(
                                to: point
                            )
                        } else {
                            routePath.addLine(
                                to: point
                            )
                        }
                    }

                    UIColor.black
                        .withAlphaComponent(0.24)
                        .setStroke()
                    routePath.lineWidth = 18
                    routePath.stroke()

                    UIColor.white
                        .withAlphaComponent(0.86)
                        .setStroke()
                    routePath.lineWidth = 13
                    routePath.stroke()

                    UIColor(
                        red: 0.36,
                        green: 0.96,
                        blue: 0.68,
                        alpha: 1
                    )
                    .setStroke()
                    routePath.lineWidth = 8
                    routePath.stroke()

                    UIColor(
                        red: 0.70,
                        green: 1.00,
                        blue: 0.82,
                        alpha: 0.72
                    )
                    .setStroke()
                    routePath.lineWidth = 3
                    routePath.stroke()

                    if let first =
                        points.first {
                        Self.drawEndpoint(
                            at:
                                snapshot.point(
                                    for: first
                                ),
                            fill:
                                UIColor.systemGreen
                        )
                    }

                    if let last =
                        points.last {
                        Self.drawEndpoint(
                            at:
                                snapshot.point(
                                    for: last
                                ),
                            fill:
                                UIColor.systemBlue
                        )
                    }
                }

            cache.setObject(
                rendered,
                forKey: key,
                cost: Int(
                    rendered.size.width *
                    rendered.size.height *
                    rendered.scale *
                    rendered.scale *
                    4
                )
            )

            return rendered
        } catch {
            return nil
        }
    }

    private static func drawEndpoint(
        at point: CGPoint,
        fill: UIColor
    ) {
        let outer =
            CGRect(
                x: point.x - 8,
                y: point.y - 8,
                width: 16,
                height: 16
            )
        UIColor.white.setFill()
        UIBezierPath(
            ovalIn: outer
        ).fill()

        let inner =
            CGRect(
                x: point.x - 4.5,
                y: point.y - 4.5,
                width: 9,
                height: 9
            )
        fill.setFill()
        UIBezierPath(
            ovalIn: inner
        ).fill()
    }

    private static func sampled(
        _ values: [CLLocationCoordinate2D],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard values.count > maximumCount,
              maximumCount > 2
        else {
            return values
        }

        let lastIndex = values.count - 1
        let step =
            Double(lastIndex) /
            Double(maximumCount - 1)

        return (0..<maximumCount).map {
            index in
            values[
                min(
                    Int(
                        (
                            Double(index) *
                            step
                        )
                        .rounded()
                    ),
                    lastIndex
                )
            ]
        }
    }

    private static func region(
        for points: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 63.4305,
                        longitude: 10.3951
                    ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.08,
                    longitudeDelta: 0.08
                )
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for point in points.dropFirst() {
            minLatitude =
                min(
                    minLatitude,
                    point.latitude
                )
            maxLatitude =
                max(
                    maxLatitude,
                    point.latitude
                )
            minLongitude =
                min(
                    minLongitude,
                    point.longitude
                )
            maxLongitude =
                max(
                    maxLongitude,
                    point.longitude
                )
        }

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
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    (
                        maxLatitude -
                        minLatitude
                    ) * 1.48,
                    0.009
                ),
                longitudeDelta: max(
                    (
                        maxLongitude -
                        minLongitude
                    ) * 1.48,
                    0.009
                )
            )
        )
    }
}

private struct HomeActivityMuscleArtwork: View {
    let muscleGroups: [String]

    private var normalized:
        Set<String> {
        Set(
            muscleGroups.map {
                $0
                    .lowercased()
                    .replacingOccurrences(
                        of: "_",
                        with: " "
                    )
            }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let width =
                geometry.size.width
            let height =
                geometry.size.height

            ZStack {
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.indigo
                                .opacity(0.055),
                            ATHLTHTheme.cardWarm
                                .opacity(0.30),
                            Color.white
                                .opacity(0.88)
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                )

                bodyBase(
                    width: width,
                    height: height
                )

                muscleHighlights(
                    width: width,
                    height: height
                )

                bodyDetailLines(
                    width: width,
                    height: height
                )
            }
        }
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            normalized.isEmpty
                ? "Muscle focus illustration"
                : "Muscle focus: " +
                    normalized
                        .sorted()
                        .joined(
                            separator: ", "
                        )
        )
    }

    @ViewBuilder
    private func bodyBase(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let base =
            Color(
                red: 0.78,
                green: 0.79,
                blue: 0.82
            )

        Circle()
            .fill(base.opacity(0.72))
            .frame(
                width: width * 0.18,
                height: width * 0.18
            )
            .position(
                x: width * 0.50,
                y: height * 0.11
            )

        Capsule()
            .fill(base.opacity(0.65))
            .frame(
                width: width * 0.09,
                height: height * 0.09
            )
            .position(
                x: width * 0.50,
                y: height * 0.22
            )

        HomeActivityTorsoShape()
            .fill(base.opacity(0.72))
            .frame(
                width: width * 0.50,
                height: height * 0.43
            )
            .position(
                x: width * 0.50,
                y: height * 0.43
            )

        Capsule()
            .fill(base.opacity(0.68))
            .frame(
                width: width * 0.12,
                height: height * 0.39
            )
            .rotationEffect(.degrees(9))
            .position(
                x: width * 0.25,
                y: height * 0.43
            )

        Capsule()
            .fill(base.opacity(0.68))
            .frame(
                width: width * 0.12,
                height: height * 0.39
            )
            .rotationEffect(.degrees(-9))
            .position(
                x: width * 0.75,
                y: height * 0.43
            )

        Capsule()
            .fill(base.opacity(0.67))
            .frame(
                width: width * 0.16,
                height: height * 0.36
            )
            .rotationEffect(.degrees(2))
            .position(
                x: width * 0.42,
                y: height * 0.79
            )

        Capsule()
            .fill(base.opacity(0.67))
            .frame(
                width: width * 0.16,
                height: height * 0.36
            )
            .rotationEffect(.degrees(-2))
            .position(
                x: width * 0.58,
                y: height * 0.79
            )
    }

    @ViewBuilder
    private func muscleHighlights(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let active =
            LinearGradient(
                colors: [
                    Color.indigo
                        .opacity(0.92),
                    Color.blue
                        .opacity(0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        if hasAny(
            "chest",
            "pectorals",
            "pecs"
        ) {
            Ellipse()
                .fill(active)
                .frame(
                    width: width * 0.20,
                    height: height * 0.11
                )
                .position(
                    x: width * 0.43,
                    y: height * 0.34
                )

            Ellipse()
                .fill(active)
                .frame(
                    width: width * 0.20,
                    height: height * 0.11
                )
                .position(
                    x: width * 0.57,
                    y: height * 0.34
                )
        }

        if hasAny(
            "shoulder",
            "shoulders",
            "delts",
            "deltoids"
        ) {
            Circle()
                .fill(active)
                .frame(
                    width: width * 0.15
                )
                .position(
                    x: width * 0.31,
                    y: height * 0.31
                )

            Circle()
                .fill(active)
                .frame(
                    width: width * 0.15
                )
                .position(
                    x: width * 0.69,
                    y: height * 0.31
                )
        }

        if hasAny(
            "back",
            "lats",
            "latissimus",
            "upper back"
        ) {
            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.12,
                    height: height * 0.24
                )
                .rotationEffect(.degrees(13))
                .position(
                    x: width * 0.38,
                    y: height * 0.44
                )

            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.12,
                    height: height * 0.24
                )
                .rotationEffect(.degrees(-13))
                .position(
                    x: width * 0.62,
                    y: height * 0.44
                )
        }

        if hasAny(
            "arms",
            "biceps",
            "triceps"
        ) {
            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.075,
                    height: height * 0.19
                )
                .rotationEffect(.degrees(9))
                .position(
                    x: width * 0.25,
                    y: height * 0.42
                )

            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.075,
                    height: height * 0.19
                )
                .rotationEffect(.degrees(-9))
                .position(
                    x: width * 0.75,
                    y: height * 0.42
                )
        }

        if hasAny(
            "core",
            "abs",
            "abdominals"
        ) {
            RoundedRectangle(
                cornerRadius: width * 0.05,
                style: .continuous
            )
            .fill(active)
            .frame(
                width: width * 0.18,
                height: height * 0.20
            )
            .position(
                x: width * 0.50,
                y: height * 0.52
            )
        }

        if hasAny(
            "glutes",
            "glute",
            "gluteus"
        ) {
            Ellipse()
                .fill(active)
                .frame(
                    width: width * 0.15,
                    height: height * 0.10
                )
                .position(
                    x: width * 0.43,
                    y: height * 0.64
                )

            Ellipse()
                .fill(active)
                .frame(
                    width: width * 0.15,
                    height: height * 0.10
                )
                .position(
                    x: width * 0.57,
                    y: height * 0.64
                )
        }

        if hasAny(
            "quads",
            "quadriceps",
            "legs"
        ) {
            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.09,
                    height: height * 0.19
                )
                .position(
                    x: width * 0.42,
                    y: height * 0.73
                )

            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.09,
                    height: height * 0.19
                )
                .position(
                    x: width * 0.58,
                    y: height * 0.73
                )
        }

        if hasAny(
            "hamstrings",
            "hamstring"
        ) {
            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.075,
                    height: height * 0.18
                )
                .position(
                    x: width * 0.38,
                    y: height * 0.77
                )

            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.075,
                    height: height * 0.18
                )
                .position(
                    x: width * 0.62,
                    y: height * 0.77
                )
        }

        if hasAny(
            "calves",
            "calf"
        ) {
            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.07,
                    height: height * 0.16
                )
                .position(
                    x: width * 0.42,
                    y: height * 0.91
                )

            Capsule()
                .fill(active)
                .frame(
                    width: width * 0.07,
                    height: height * 0.16
                )
                .position(
                    x: width * 0.58,
                    y: height * 0.91
                )
        }
    }

    @ViewBuilder
    private func bodyDetailLines(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Path { path in
            path.move(
                to: CGPoint(
                    x: width * 0.50,
                    y: height * 0.29
                )
            )
            path.addLine(
                to: CGPoint(
                    x: width * 0.50,
                    y: height * 0.63
                )
            )

            for fraction in [
                0.44,
                0.49,
                0.54
            ] {
                path.move(
                    to: CGPoint(
                        x: width * 0.44,
                        y: height * fraction
                    )
                )
                path.addLine(
                    to: CGPoint(
                        x: width * 0.56,
                        y: height * fraction
                    )
                )
            }
        }
        .stroke(
            Color.white.opacity(0.42),
            style: StrokeStyle(
                lineWidth: 1,
                lineCap: .round
            )
        )
    }

    private func hasAny(
        _ names: String...
    ) -> Bool {
        names.contains { name in
            normalized.contains {
                value in
                value == name ||
                value.contains(name)
            }
        }
    }
}

private struct HomeActivityTorsoShape:
    Shape {
    func path(
        in rect: CGRect
    ) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.midX,
                y: rect.minY
            )
        )
        path.addCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.height * 0.18
            ),
            control1: CGPoint(
                x: rect.width * 0.66,
                y: rect.minY
            ),
            control2: CGPoint(
                x: rect.width * 0.90,
                y: rect.height * 0.05
            )
        )
        path.addCurve(
            to: CGPoint(
                x: rect.width * 0.70,
                y: rect.maxY
            ),
            control1: CGPoint(
                x: rect.width * 0.94,
                y: rect.height * 0.50
            ),
            control2: CGPoint(
                x: rect.width * 0.78,
                y: rect.height * 0.82
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.width * 0.30,
                y: rect.maxY
            )
        )
        path.addCurve(
            to: CGPoint(
                x: rect.minX,
                y: rect.height * 0.18
            ),
            control1: CGPoint(
                x: rect.width * 0.22,
                y: rect.height * 0.82
            ),
            control2: CGPoint(
                x: rect.width * 0.06,
                y: rect.height * 0.50
            )
        )
        path.addCurve(
            to: CGPoint(
                x: rect.midX,
                y: rect.minY
            ),
            control1: CGPoint(
                x: rect.width * 0.10,
                y: rect.height * 0.05
            ),
            control2: CGPoint(
                x: rect.width * 0.34,
                y: rect.minY
            )
        )
        path.closeSubpath()

        return path
    }
}

private extension View {
    func homeRouteGlassPill() -> some View {
        self
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Color.black.opacity(0.46),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(0.18),
                        lineWidth: 0.7
                    )
            }
    }
}

private struct HomeActivityFlowLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.minX + rect.width * 0.06,
                y: rect.minY + rect.height * 0.66
            )
        )
        path.addCurve(
            to: CGPoint(
                x: rect.minX + rect.width * 0.46,
                y: rect.minY + rect.height * 0.43
            ),
            control1: CGPoint(
                x: rect.minX + rect.width * 0.18,
                y: rect.minY + rect.height * 0.56
            ),
            control2: CGPoint(
                x: rect.minX + rect.width * 0.31,
                y: rect.minY + rect.height * 0.26
            )
        )
        path.addCurve(
            to: CGPoint(
                x: rect.minX + rect.width * 0.94,
                y: rect.minY + rect.height * 0.59
            ),
            control1: CGPoint(
                x: rect.minX + rect.width * 0.61,
                y: rect.minY + rect.height * 0.60
            ),
            control2: CGPoint(
                x: rect.minX + rect.width * 0.77,
                y: rect.minY + rect.height * 0.75
            )
        )

        return path
    }
}

private struct HomeActivityStrengthCard: View {
    let workout: SocialPublishableWorkout
    let keyLifts: [String]
    let isPublished: Bool
    let onPost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        isPublished
                            ? "Published workout"
                            : "Completed workout"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        isPublished
                            ? Color.indigo.opacity(0.82)
                            : ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        isPublished
                            ? Color.indigo.opacity(0.09)
                            : ATHLTHTheme.accentSoft.opacity(0.82),
                        in: Capsule()
                    )

                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 42, height: 42)
                            .background(
                                Color.indigo.opacity(0.09),
                                in: Circle()
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Strength")
                                .font(.headline)

                            Text(
                                workout.startDate.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }
                }

                Spacer()

                Menu {
                    Button {
                        onPost()
                    } label: {
                        Label(
                            isPublished ? "Update post" : "Post workout",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 36, height: 36)
                        .background(
                            Color.white.opacity(0.90),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.title)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(strengthDescription)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: 8) {
                    HomeActivityMuscleArtwork(
                        muscleGroups: focusAreas
                    )
                    .frame(width: 92, height: 128)

                    if !focusAreas.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Focus Areas")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.mutedText)

                            ForEach(focusAreas.prefix(4), id: \.self) { group in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.indigo.opacity(0.72))
                                        .frame(width: 6, height: 6)

                                    Text(group)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(width: 72, alignment: .leading)
                    }
                }
            }

            Divider()
                .opacity(0.45)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    strengthMetric(
                        icon: "dumbbell",
                        title: "Key Lifts",
                        value: keyLiftText
                    )
                    strengthDivider
                    strengthMetric(
                        icon: "sum",
                        title: "Total Volume",
                        value: volumeText
                    )
                    strengthDivider
                    strengthMetric(
                        icon: "clock",
                        title: "Duration",
                        value: durationText
                    )
                }

                VStack(spacing: 9) {
                    strengthMetric(
                        icon: "dumbbell",
                        title: "Key Lifts",
                        value: keyLiftText
                    )
                    strengthMetric(
                        icon: "sum",
                        title: "Total Volume",
                        value: volumeText
                    )
                    strengthMetric(
                        icon: "clock",
                        title: "Duration",
                        value: durationText
                    )
                }
            }

            NavigationLink {
                WorkoutHistoryDetailView(workout: workout)
            } label: {
                HStack {
                    Text("View workout")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                }
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.98),
                    ATHLTHTheme.cardWarm.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
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
            .stroke(Color.white.opacity(0.72), lineWidth: 0.8)
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.045),
            radius: 9,
            x: 0,
            y: 4
        )
    }

    private var focusAreas: [String] {
        Array(
            (workout.strengthMuscleGroups ?? [])
                .map { $0.capitalized }
                .prefix(4)
        )
    }

    private var strengthDescription: String {
        var parts: [String] = []

        if let count = workout.strengthExerciseCount, count > 0 {
            parts.append(
                count == 1
                    ? "1 exercise"
                    : "\(count) exercises"
            )
        }

        if !focusAreas.isEmpty {
            parts.append(focusAreas.joined(separator: " · "))
        }

        return parts.isEmpty
            ? "Completed strength session."
            : parts.joined(separator: " · ")
    }

    private var keyLiftText: String {
        if keyLifts.isEmpty {
            if let count = workout.strengthExerciseCount, count > 0 {
                return count == 1 ? "1 exercise" : "\(count) exercises"
            }
            return "—"
        }

        return keyLifts.joined(separator: ", ")
    }

    private var volumeText: String {
        guard let volume = workout.strengthTotalVolumeKilograms,
              volume > 0
        else {
            return "—"
        }

        if volume >= 1_000 {
            return String(format: "%.1f t", volume / 1_000)
        }

        return String(format: "%.0f kg", volume)
    }

    private var durationText: String {
        let minutes = max(Int((workout.duration / 60).rounded()), 0)

        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }

        return "\(minutes) min"
    }

    private func strengthMetric(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(ATHLTHTheme.mutedText)

                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var strengthDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 38)
    }
}

private struct HomeActivityGenericWorkoutCard: View {
    let workout: SocialPublishableWorkout
    let isPublished: Bool
    let onPost: () -> Void

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: workout.activity.icon)
                    .font(.system(size: 20, weight: .semibold))
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
                    Text(
                        isPublished
                            ? "Published workout"
                            : "Completed workout"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(workout.title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(workout.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        onPost()
                    } label: {
                        Label(
                            isPublished ? "Update post" : "Post workout",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                WorkoutHistoryDetailView(workout: workout)
            } label: {
                HStack {
                    Text("View workout")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                }
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeActivityCommunityCard: View {
    let item: SocialFeedItem

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 11) {
                NavigationLink {
                    FriendProfileView(userID: item.actor.userID)
                } label: {
                    SocialAvatar(profile: item.actor, size: 42)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(item.actor.resolvedName)
                            .font(.subheadline.weight(.semibold))

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text(item.activity.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.activity.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    if let subtitle = item.activity.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let caption = item.activity.metadata?["caption"],
                       !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.80)
                            )
                            .lineLimit(2)
                    }

                    let reactionCount = item.reactions.count
                    if reactionCount > 0 {
                        Text(
                            "🔥 \(reactionCount) reaction\(reactionCount == 1 ? "" : "s")"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: activityIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )
            }
        }
    }

    private var activityIcon: String {
        switch item.activity.kind {
        case "workout": return "figure.run"
        case "trophy": return "trophy.fill"
        case "goal": return "target"
        case "challenge": return "person.2.fill"
        case "personal_record": return "bolt.fill"
        default: return "sparkles"
        }
    }
}

struct WorkoutPublishView: View {
    let initialWorkoutID: UUID?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var selectedWorkoutID: UUID?
    @State private var visibility: ProfileVisibility = .friends
    @State private var caption = ""
    @State private var publishing = false
    @State private var selectedAlreadyPublished = false
    @State private var successMessage: String?

    init(initialWorkoutID: UUID? = nil) {
        self.initialWorkoutID = initialWorkoutID
    }

    private var workouts: [SocialPublishableWorkout] {
        let healthItems = health.workouts.map(SocialPublishableWorkout.init)

        let localStrengthItems = strength.workoutHistory
            .filter {
                $0.isFinished &&
                $0.healthMetrics.healthKitWorkoutUUID == nil
            }
            .map(SocialPublishableWorkout.init)

        return Array(
            (healthItems + localStrengthItems)
                .sorted { $0.startDate > $1.startDate }
                .prefix(60)
        )
    }

    private var selectedWorkout: SocialPublishableWorkout? {
        guard let selectedWorkoutID else { return nil }
        return workouts.first { $0.id == selectedWorkoutID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    if workouts.isEmpty {
                        Text("No recent workouts are available to publish.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workouts) { workout in
                            Button {
                                selectedWorkoutID = workout.id
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: workout.activity.icon)
                                        .font(.title3)
                                        .foregroundStyle(ATHLTHTheme.accent)
                                        .frame(width: 36)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(workout.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)

                                        Text(
                                            "\(workout.summaryText) · \(workout.startDate.formatted(date: .abbreviated, time: .shortened))"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        Text(workout.source)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(
                                        systemName: selectedWorkoutID == workout.id
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .foregroundStyle(
                                        selectedWorkoutID == workout.id
                                            ? ATHLTHTheme.accent
                                            : .secondary
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let workout = selectedWorkout {
                    let partners = social.acceptedTrainingPartnerNames(
                        for: workout.id
                    )

                    if !partners.isEmpty {
                        Section("Training Together") {
                            Label(
                                partners.joined(separator: ", "),
                                systemImage: "person.2.fill"
                            )
                            .foregroundStyle(ATHLTHTheme.accent)

                            Text("Only friends who accepted the training invite are attached to this post.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Post") {
                        TextField(
                            "Add a caption (optional)",
                            text: $caption,
                            axis: .vertical
                        )
                        .lineLimit(2...5)

                        Picker("Who can see this", selection: $visibility) {
                            ForEach(ProfileVisibility.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }

                        if selectedAlreadyPublished {
                            Label(
                                "This workout is already published.",
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(ATHLTHTheme.accent)
                        }
                    }
                }

                if let successMessage {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(ATHLTHTheme.accent)
                    }
                }
            }
            .navigationTitle("Post Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        selectedAlreadyPublished
                            ? "Update"
                            : "Publish"
                    ) {
                        Task { await publish() }
                    }
                    .disabled(
                        selectedWorkout == nil ||
                        publishing
                    )
                }
            }
            .task {
                visibility = settings.defaultActivityVisibility

                if health.hasRequestedAuthorization && health.workouts.isEmpty {
                    await health.refreshAll()
                }

                if selectedWorkoutID == nil,
                   let initialWorkoutID,
                   workouts.contains(where: { $0.id == initialWorkoutID }) {
                    selectedWorkoutID = initialWorkoutID
                }
            }
            .task(id: selectedWorkoutID) {
                guard let selectedWorkoutID else {
                    selectedAlreadyPublished = false
                    caption = ""
                    visibility = settings.defaultActivityVisibility
                    return
                }

                if let activity = await social.workoutActivity(
                    for: selectedWorkoutID
                ) {
                    selectedAlreadyPublished = true
                    caption = activity.metadata?["caption"] ?? ""
                    visibility =
                        ProfileVisibility(
                            rawValue: activity.visibility
                        ) ??
                        settings.defaultActivityVisibility
                } else {
                    selectedAlreadyPublished = false
                    caption = ""
                    visibility = settings.defaultActivityVisibility
                }
            }
        }
    }

    private func publish() async {
        guard let workout = selectedWorkout else { return }

        let wasPublished = selectedAlreadyPublished
        publishing = true
        defer { publishing = false }

        let success = await social.publishWorkout(
            workout,
            visibility: visibility,
            caption: caption
        )

        if success {
            selectedAlreadyPublished = true
            successMessage =
                wasPublished
                    ? "Workout updated in Activity."
                    : "Workout published to Activity."

            try? await Task.sleep(for: .milliseconds(650))
            dismiss()
        }
    }
}
