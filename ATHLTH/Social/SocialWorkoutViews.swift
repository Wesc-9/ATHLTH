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
    @AppStorage("admin.activityCenterAIVisualsEnabled")
    private var activityCenterAIVisualsEnabled = false
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var showingPublish = false
    @State private var selectedPublishWorkoutID: UUID?
    @State private var workoutDetails: [UUID: WorkoutDetail] = [:]
    @State private var workoutAIInsights: [UUID: WorkoutAIInsight] = [:]
    @State private var loadingAIInsightIDs: Set<UUID> = []
    @State private var publishedActivities: [UUID: SocialActivityRecord] = [:]
    @State private var selectedCoachInsight: CoachInsightPresentation?
    @State private var selectedOutdoorWorkoutID: UUID?

    private var ownWorkouts: [SocialPublishableWorkout] {
        // Prefer ATHLTH's local strength log when the same workout also
        // exists in HealthKit. The local log carries exercise/muscle detail
        // that the generic HealthKit workout summary cannot preserve.
        let localStrengthItems =
            strength.workoutHistory
                .filter(\.isFinished)
                .map(
                    SocialPublishableWorkout.init
                )
        let localStrengthIDs =
            Set(
                localStrengthItems
                    .map(\.id)
            )

        let healthItems =
            health.workouts
                .map(
                    SocialPublishableWorkout.init
                )
                .filter {
                    !(
                        $0.activity ==
                            .strength &&
                        localStrengthIDs
                            .contains($0.id)
                    )
                }

        return (
            healthItems +
            localStrengthItems
        )
        .sorted {
            $0.startDate >
            $1.startDate
        }
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
                            keyLifts:
                                keyLifts(
                                    for: workout
                                ),
                            muscleSummary:
                                strengthMuscleSummary(
                                    for: workout
                                ),
                            strengthWorkout:
                                strengthWorkoutLog(
                                    for: workout
                                ),
                            isPublished:
                                isPublished(
                                    workout
                                )
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
                            useAIVisuals:
                                activityCenterAIVisualsEnabled,
                            onOpen: {
                                selectedOutdoorWorkoutID =
                                    workout.id
                            },
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
        .navigationDestination(
            item: $selectedOutdoorWorkoutID
        ) { workoutID in
            if let workout =
                featuredWorkouts.first(
                    where: {
                        $0.id == workoutID
                    }
                ) {
                HomeActivityRunDetailView(
                    workout: workout,
                    initialDetail:
                        workoutDetails[workoutID],
                    initialAIInsight:
                        workoutAIInsights[workoutID]
                )
            } else {
                ContentUnavailableView(
                    "Workout unavailable",
                    systemImage: "figure.run.circle",
                    description: Text(
                        "The workout could not be opened."
                    )
                )
            }
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
            if let feedItem =
                social.feed.first(
                    where: {
                        $0.actor.userID ==
                            social.currentUserID &&
                        $0.activity.kind ==
                            "workout" &&
                        $0.activity.metadata?[
                            "workout_id"
                        ] ==
                            workout.id.uuidString
                    }
                ) {
                refreshed[workout.id] =
                    feedItem.activity
                continue
            }

            if let activity =
                await social.workoutActivity(
                    for: workout.id
                ) {
                refreshed[workout.id] =
                    activity
            }
        }

        publishedActivities = refreshed
    }

    private func keyLifts(for workout: SocialPublishableWorkout) -> [String] {
        guard workout.activity == .strength else { return [] }

        guard let log =
            strengthWorkoutLog(
                for: workout
            )
        else {
            return []
        }

        return Array(
            log.exercises
                .map { $0.exercise.name }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(3)
        )
    }

    private func strengthWorkoutLog(
        for workout: SocialPublishableWorkout
    ) -> StrengthWorkoutLog? {
        guard workout.activity ==
            .strength
        else {
            return nil
        }

        return strength
            .workoutHistory
            .first {
                $0.id == workout.id ||
                $0
                    .healthMetrics
                    .healthKitWorkoutUUID ==
                    workout.id
            }
    }

    private func strengthMuscleSummary(
        for workout: SocialPublishableWorkout
    ) -> StrengthMuscleSessionSummary {
        guard let log =
            strengthWorkoutLog(
                for: workout
            )
        else {
            return .empty
        }

        return StrengthMuscleProfileBuilder
            .make(
                workout: log,
                library:
                    exerciseLibrary
                        .allExercises
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
                        detail:
                            workoutDetails[
                                workout.id
                            ],
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

private struct HomeActivityVisualRecipe: Equatable {
    let palette: String
    let scene: String
    let light: String
    let motif: String
    let energy: String
    let variant: Int

    static func local(
        for workout: SocialPublishableWorkout,
        hasRoute: Bool
    ) -> HomeActivityVisualRecipe {
        let hour =
            Calendar.current.component(
                .hour,
                from: workout.startDate
            )

        let palette: String
        let light: String

        switch hour {
        case 5..<11:
            palette = "sage"
            light = "sunrise"
        case 11..<17:
            palette = "ocean"
            light = "daylight"
        case 17..<22:
            palette = "amber"
            light = "golden_hour"
        default:
            palette = "slate"
            light = "dusk"
        }

        let scene: String
        switch workout.activity {
        case .hiking:
            scene = "mountain"
        case .cycling:
            scene = "coast"
        case .walking:
            scene =
                hour >= 17 || hour < 6
                    ? "city"
                    : "forest"
        default:
            scene =
                hasRoute
                    ? "mountain"
                    : "track"
        }

        let distance =
            workout.distanceMeters ?? 0
        let energy: String =
            distance >= 10_000
                ? "energetic"
                : "steady"

        let scalarSum =
            workout.id.uuidString
                .unicodeScalars
                .reduce(0) {
                    $0 + Int($1.value)
                }

        return HomeActivityVisualRecipe(
            palette: palette,
            scene: scene,
            light: light,
            motif: hasRoute ? "route" : "pulse",
            energy: energy,
            variant: (scalarSum % 4) + 1
        )
    }
}

private struct HomeActivityScenicWash: View {
    let recipe: HomeActivityVisualRecipe

    var body: some View {
        ZStack {
            LinearGradient(
                colors: paletteColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(
                recipe.energy == "energetic"
                    ? 0.38
                    : 0.30
            )

            lightWash
            motifArtwork

            HStack {
                Spacer()

                Image(systemName: sceneSymbol)
                    .font(
                        .system(
                            size: 78,
                            weight: .light
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        Color.white.opacity(0.13)
                    )
                    .rotationEffect(
                        .degrees(
                            recipe.variant
                                .isMultiple(of: 2)
                                ? -4
                                : 4
                        )
                    )
                    .offset(
                        x:
                            recipe.variant >= 3
                                ? 8
                                : 0,
                        y:
                            recipe.variant
                                .isMultiple(of: 2)
                                ? 8
                                : -2
                    )
                    .padding(.trailing, 26)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var lightWash: some View {
        switch recipe.light {
        case "sunrise":
            RadialGradient(
                colors: [
                    Color.yellow.opacity(0.20),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 190
            )
        case "golden_hour":
            RadialGradient(
                colors: [
                    Color.orange.opacity(0.22),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 6,
                endRadius: 200
            )
        case "dusk":
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.18),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            RadialGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 180
            )
        }
    }

    @ViewBuilder
    private var motifArtwork: some View {
        switch recipe.motif {
        case "route":
            HomeActivityFlowLines()
                .stroke(
                    Color.white.opacity(0.11),
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .padding(34)
                .rotationEffect(
                    .degrees(
                        recipe.variant
                            .isMultiple(of: 2)
                            ? -5
                            : 5
                    )
                )

        case "waves":
            Image(systemName: "water.waves")
                .font(
                    .system(
                        size: 108,
                        weight: .ultraLight
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.10)
                )
                .offset(x: 92, y: 48)

        case "steps":
            Image(systemName: "figure.walk")
                .font(
                    .system(
                        size: 96,
                        weight: .ultraLight
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.10)
                )
                .offset(x: 96, y: 38)

        case "streak":
            Image(systemName: "wind")
                .font(
                    .system(
                        size: 112,
                        weight: .ultraLight
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.10)
                )
                .offset(x: 92, y: 36)

        case "group":
            Image(systemName: "person.3.fill")
                .font(
                    .system(
                        size: 84,
                        weight: .ultraLight
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.09)
                )
                .offset(x: 94, y: 34)

        default:
            Image(systemName: "waveform.path.ecg")
                .font(
                    .system(
                        size: 102,
                        weight: .ultraLight
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.10)
                )
                .offset(x: 92, y: 38)
        }
    }

    private var paletteColors: [Color] {
        switch recipe.palette {
        case "ocean":
            return [
                Color.cyan.opacity(0.22),
                Color.blue.opacity(0.07),
                .clear
            ]
        case "amber":
            return [
                Color.orange.opacity(0.20),
                Color.yellow.opacity(0.07),
                .clear
            ]
        case "violet":
            return [
                Color.indigo.opacity(0.20),
                Color.purple.opacity(0.07),
                .clear
            ]
        case "rose":
            return [
                Color.pink.opacity(0.15),
                Color.orange.opacity(0.05),
                .clear
            ]
        case "slate":
            return [
                Color.indigo.opacity(0.18),
                Color.black.opacity(0.10),
                .clear
            ]
        default:
            return [
                ATHLTHTheme.vitality.opacity(0.18),
                Color.green.opacity(0.05),
                .clear
            ]
        }
    }

    private var sceneSymbol: String {
        switch recipe.scene {
        case "forest":
            return "tree.fill"
        case "city":
            return "building.2.fill"
        case "coast":
            return "water.waves"
        case "track":
            return "figure.run"
        case "studio":
            return "dumbbell.fill"
        default:
            return "mountain.2.fill"
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
    let useAIVisuals: Bool
    let onOpen: () -> Void
    let onCoach: (WorkoutAIInsight) -> Void
    let onPost: () -> Void

    private var routeCoordinates: [CLLocationCoordinate2D] {
        guard let route = detail?.route,
              !route.isEmpty
        else {
            return []
        }

        let maximumCount = 180
        guard route.count > maximumCount else {
            return route.map(\.coordinate)
        }

        let lastIndex = route.count - 1
        let step =
            Double(lastIndex) /
            Double(maximumCount - 1)

        return (0..<maximumCount).map {
            index in
            route[
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
            .coordinate
        }
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

    private var highestRoutePoint: CLLocation? {
        guard let route = detail?.route,
              route.count >= 2
        else {
            return nil
        }

        let finite =
            route.filter {
                $0.altitude.isFinite
            }
        let verticallyAccurate =
            finite.filter {
                $0.verticalAccuracy >= 0
            }
        let candidates =
            verticallyAccurate.isEmpty
                ? finite
                : verticallyAccurate

        return candidates.max {
            $0.altitude < $1.altitude
        }
    }

    private var visualRecipe:
        HomeActivityVisualRecipe {
        if useAIVisuals,
           let recipe =
            aiInsight?.visualRecipe {
            return HomeActivityVisualRecipe(
                palette: recipe.palette,
                scene: recipe.scene,
                light: recipe.light,
                motif: recipe.motif,
                energy: recipe.energy,
                variant: recipe.variant
            )
        }

        return HomeActivityVisualRecipe.local(
            for: workout,
            hasRoute:
                routeCoordinates.count >= 2
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Button(action: onOpen) {
                    mapBackground
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "View workout route details"
                )

                if useAIVisuals {
                    HomeActivityScenicWash(
                        recipe: visualRecipe
                    )
                }

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color.white.opacity(0.72),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(useAIVisuals ? 1 : 0)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.clear,
                        Color.black.opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(useAIVisuals ? 1 : 0)

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
                        Text(displayTitle)
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
                .opacity(useAIVisuals ? 1 : 0)
                .allowsHitTesting(useAIVisuals)

                if useAIVisuals &&
                    routeCoordinates.count >= 2 {
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

                if !useAIVisuals {
                    premiumMapChrome
                }
            }
            .frame(
                height:
                    useAIVisuals
                        ? 240
                        : 285
            )
            .clipped()

            VStack(spacing: 10) {
                if !useAIVisuals {
                    premiumWorkoutHeader
                }

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

                if useAIVisuals {
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
                } else {
                    premiumRouteLegend
                }
            }
            .padding(12)
            .background {
                if useAIVisuals {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.17, blue: 0.17).opacity(0.93),
                            Color(red: 0.18, green: 0.23, blue: 0.22).opacity(0.91)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.white.opacity(0.98)
                }
            }
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

    private var premiumMapChrome: some View {
        VStack {
            HStack {
                Image(
                    systemName:
                        "square.3.layers.3d"
                )
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .frame(width: 38, height: 38)
                .background(
                    .ultraThinMaterial,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white
                                .opacity(0.72),
                            lineWidth: 0.8
                        )
                }

                Spacer()

                Menu {
                    Button {
                        onPost()
                    } label: {
                        Label(
                            isPublished
                                ? "Update post"
                                : "Post workout",
                            systemImage:
                                "square.and.arrow.up"
                        )
                    }
                } label: {
                    Image(
                        systemName:
                            "ellipsis"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        .ultraThinMaterial,
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white
                                    .opacity(0.72),
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(14)
    }

    private var premiumWorkoutHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack(spacing: 8) {
                Label(
                    activityTitle,
                    systemImage:
                        workout.activity.icon
                )
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )

                Text("•")
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Spacer()

                Text(
                    isPublished
                        ? "Published"
                        : "Completed"
                )
                .font(
                    .caption2.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    isPublished
                        ? Color.green
                        : ATHLTHTheme.mutedText
                )
            }

            Text(displayTitle)
                .font(
                    .system(
                        size: 20,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)

            HStack(
                alignment: .firstTextBaseline,
                spacing: 10
            ) {
                Text(distanceText)
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                if let ascentText {
                    Label(
                        ascentText,
                        systemImage:
                            "mountain.2.fill"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var premiumRouteLegend: some View {
        Button(action: onOpen) {
            VStack(spacing: 8) {
            HStack {
                Label(
                    "Route Ribbon",
                    systemImage:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Spacer()

                Text("Start → Finish")
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }

            LinearGradient(
                colors: [
                    Color(
                        red: 0.05,
                        green: 0.62,
                        blue: 0.49
                    ),
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
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 8)
            .clipShape(Capsule())
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
                ATHLTHTheme.cardWarm
                    .opacity(0.64),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "View pace-colored route details"
        )
    }

    @ViewBuilder
    private var mapBackground: some View {
        if routeCoordinates.count >= 2 || singleLocation != nil {
            HomeActivityRouteArtwork(
                coordinates: routeCoordinates,
                singleLocation: singleLocation?.coordinate,
                highestPoint: highestRoutePoint?.coordinate,
                highestAltitudeMeters: highestRoutePoint?.altitude
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

    private var displayTitle: String {
        let trimmed =
            workout.title
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let genericTitles =
            Set([
                workout.activity.rawValue.lowercased(),
                activityTitle.lowercased(),
                "running",
                "walking",
                "cycling",
                "hiking",
                "workout"
            ])

        guard trimmed.isEmpty ||
              genericTitles.contains(
                trimmed.lowercased()
              )
        else {
            return trimmed
        }

        let hour =
            Calendar.current.component(
                .hour,
                from: workout.startDate
            )
        let daypart: String

        switch hour {
        case 5..<12:
            daypart = "Morning"
        case 12..<17:
            daypart = "Afternoon"
        case 17..<22:
            daypart = "Evening"
        default:
            daypart = "Night"
        }

        return "\(daypart) \(activityTitle)"
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
                .foregroundStyle(
                    useAIVisuals
                        ? Color.white.opacity(0.90)
                        : ATHLTHTheme.accentDeep
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(
                        useAIVisuals
                            ? Color.white.opacity(0.68)
                            : ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)

                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        useAIVisuals
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(
                useAIVisuals
                    ? Color.white.opacity(0.22)
                    : Color.black.opacity(0.10)
            )
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
    let highestPoint: CLLocationCoordinate2D?
    let highestAltitudeMeters: Double?

    @State private var image: UIImage?

    private var cacheKey: String {
        HomeActivityRouteSnapshotRenderer.cacheKey(
            coordinates: coordinates,
            singleLocation: singleLocation,
            highestPoint: highestPoint,
            highestAltitudeMeters: highestAltitudeMeters
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
            }
        }
        .clipped()
        .task(id: cacheKey) {
            let rendered =
                await HomeActivityRouteSnapshotRenderer
                    .shared
                    .image(
                        coordinates: coordinates,
                        singleLocation: singleLocation,
                        highestPoint: highestPoint,
                        highestAltitudeMeters: highestAltitudeMeters
                    )

            guard !Task.isCancelled else {
                return
            }

            image = rendered
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
        singleLocation: CLLocationCoordinate2D?,
        highestPoint: CLLocationCoordinate2D?,
        highestAltitudeMeters: Double?
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

        let routeKey =
            points.map {
                String(
                    format: "%.5f,%.5f",
                    $0.latitude,
                    $0.longitude
                )
            }
            .joined(separator: "|")

        let highlightKey: String
        if let highestPoint,
           let highestAltitudeMeters,
           highestAltitudeMeters.isFinite {
            highlightKey = String(
                format: "|high:%.5f,%.5f,%.0f",
                highestPoint.latitude,
                highestPoint.longitude,
                highestAltitudeMeters
            )
        } else {
            highlightKey = "|high:none"
        }

        return "premium-route-v2|" + routeKey + highlightKey
    }

    func image(
        coordinates: [CLLocationCoordinate2D],
        singleLocation: CLLocationCoordinate2D?,
        highestPoint: CLLocationCoordinate2D?,
        highestAltitudeMeters: Double?
    ) async -> UIImage? {
        guard !Task.isCancelled else {
            return nil
        }

        let key = Self.cacheKey(
            coordinates: coordinates,
            singleLocation: singleLocation,
            highestPoint: highestPoint,
            highestAltitudeMeters: highestAltitudeMeters
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

        let snapshotSize =
            CGSize(width: 460, height: 285)

        do {
            let snapshot: MKMapSnapshotter.Snapshot

            do {
                let premiumOptions =
                    Self.premiumSnapshotOptions(
                        for: points,
                        size: snapshotSize
                    )

                snapshot =
                    try await MKMapSnapshotter(
                        options: premiumOptions
                    )
                    .start()
            } catch {
                // Device/MapKit fallback: retain the current lightweight
                // 2D presentation rather than dropping the workout visual.
                let fallbackOptions =
                    Self.fallbackSnapshotOptions(
                        for: points,
                        size: snapshotSize
                    )

                snapshot =
                    try await MKMapSnapshotter(
                        options: fallbackOptions
                    )
                    .start()
            }

            guard !Task.isCancelled else {
                return nil
            }

            let format =
                UIGraphicsImageRendererFormat
                    .default()
            format.scale = 2
            format.opaque = true

            let renderer =
                UIGraphicsImageRenderer(
                    size: snapshotSize,
                    format: format
                )

            let rendered =
                renderer.image { context in
                    snapshot.image.draw(
                        in: CGRect(
                            origin: .zero,
                            size: snapshotSize
                        )
                    )

                    let bounds = CGRect(
                        origin: .zero,
                        size: snapshotSize
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

                    // ATHLTH Route Ribbon: a layered, dimensional route
                    // treatment rendered into the cached snapshot. This keeps
                    // Activity Center scrolling light while giving every GPS
                    // run the same premium visual identity.
                    UIColor.black
                        .withAlphaComponent(0.18)
                        .setStroke()
                    routePath.lineWidth = 24
                    context.cgContext.saveGState()
                    context.cgContext.setShadow(
                        offset: CGSize(width: 0, height: 7),
                        blur: 10,
                        color: UIColor.black
                            .withAlphaComponent(0.26)
                            .cgColor
                    )
                    routePath.stroke()
                    context.cgContext.restoreGState()

                    UIColor.white
                        .withAlphaComponent(0.96)
                        .setStroke()
                    routePath.lineWidth = 18
                    routePath.stroke()

                    // Paint short route segments separately so the ribbon can
                    // move through a restrained ATHLTH performance gradient.
                    let ribbonPalette: [UIColor] = [
                        UIColor(red: 0.05, green: 0.62, blue: 0.49, alpha: 1),
                        UIColor(red: 0.19, green: 0.78, blue: 0.45, alpha: 1),
                        UIColor(red: 0.68, green: 0.86, blue: 0.27, alpha: 1),
                        UIColor(red: 0.96, green: 0.73, blue: 0.18, alpha: 1),
                        UIColor(red: 0.96, green: 0.45, blue: 0.12, alpha: 1)
                    ]

                    let renderedPoints =
                        points.map {
                            snapshot.point(for: $0)
                        }

                    if renderedPoints.count >= 2 {
                        for index in 1..<renderedPoints.count {
                            let progress =
                                CGFloat(index - 1) /
                                CGFloat(max(renderedPoints.count - 2, 1))
                            let scaled =
                                progress *
                                CGFloat(ribbonPalette.count - 1)
                            let lower =
                                min(
                                    Int(floor(scaled)),
                                    ribbonPalette.count - 1
                                )
                            let upper =
                                min(lower + 1, ribbonPalette.count - 1)
                            let mix = scaled - CGFloat(lower)

                            let color =
                                Self.interpolate(
                                    ribbonPalette[lower],
                                    ribbonPalette[upper],
                                    fraction: mix
                                )

                            let segment = UIBezierPath()
                            segment.move(to: renderedPoints[index - 1])
                            segment.addLine(to: renderedPoints[index])
                            segment.lineCapStyle = .round
                            segment.lineJoinStyle = .round
                            color.setStroke()
                            segment.lineWidth = 12
                            segment.stroke()
                        }
                    }

                    UIColor.white
                        .withAlphaComponent(0.34)
                        .setStroke()
                    routePath.lineWidth = 3
                    routePath.stroke()

                    if let highestPoint,
                       let highestAltitudeMeters,
                       highestAltitudeMeters.isFinite,
                       highestAltitudeMeters > 0 {
                        let highlightLocation =
                            snapshot.point(
                                for: highestPoint
                            )

                        Self.drawHighestPoint(
                            at: highlightLocation,
                            altitudeMeters:
                                highestAltitudeMeters,
                            bounds: bounds
                        )
                    }

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
                        Self.drawFinishEndpoint(
                            at:
                                snapshot.point(
                                    for: last
                                )
                        )
                    }
                }

            guard !Task.isCancelled else {
                return nil
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

    private static func premiumSnapshotOptions(
        for points: [CLLocationCoordinate2D],
        size: CGSize
    ) -> MKMapSnapshotter.Options {
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = 2
        options.traitCollection =
            UITraitCollection(
                userInterfaceStyle: .light
            )

        let configuration =
            MKHybridMapConfiguration(
                elevationStyle: .realistic
            )
        configuration.showsTraffic = false
        // Keep Apple's geographic labels/terrain context. Workout-specific
        // callouts are drawn by ATHLTH on top of the snapshot.
        options.preferredConfiguration =
            configuration

        options.camera =
            premiumCamera(
                for: points
            )

        return options
    }

    private static func fallbackSnapshotOptions(
        for points: [CLLocationCoordinate2D],
        size: CGSize
    ) -> MKMapSnapshotter.Options {
        let options = MKMapSnapshotter.Options()
        options.region = region(for: points)
        options.size = size
        options.scale = 2

        let configuration =
            MKStandardMapConfiguration(
                elevationStyle: .flat
            )
        configuration.emphasisStyle = .muted
        configuration.pointOfInterestFilter =
            .excludingAll
        configuration.showsTraffic = false

        options.preferredConfiguration =
            configuration
        options.traitCollection =
            UITraitCollection(
                userInterfaceStyle: .light
            )

        return options
    }

    private static func premiumCamera(
        for points: [CLLocationCoordinate2D]
    ) -> MKMapCamera {
        let mapRect =
            mapRect(for: points)
        let center =
            MKMapPoint(
                x: mapRect.midX,
                y: mapRect.midY
            )
            .coordinate

        let metersPerPoint =
            MKMetersPerMapPointAtLatitude(
                center.latitude
            )
        let spanMeters =
            max(
                mapRect.size.width,
                mapRect.size.height
            ) * metersPerPoint

        let camera = MKMapCamera()
        camera.centerCoordinate = center
        camera.pitch = 58
        camera.heading =
            principalHeading(
                for: points
            )
        camera.altitude =
            min(
                max(
                    spanMeters * 1.72,
                    1_100
                ),
                65_000
            )

        return camera
    }

    private static func mapRect(
        for points: [CLLocationCoordinate2D]
    ) -> MKMapRect {
        guard let first = points.first else {
            return MKMapRect.world
        }

        var rect = MKMapRect(
            origin: MKMapPoint(first),
            size: MKMapSize(width: 0, height: 0)
        )

        for coordinate in points.dropFirst() {
            let point = MKMapPoint(coordinate)
            rect = rect.union(
                MKMapRect(
                    x: point.x,
                    y: point.y,
                    width: 0,
                    height: 0
                )
            )
        }

        let minimumDimension = 700.0
        let width = max(rect.size.width, minimumDimension)
        let height = max(rect.size.height, minimumDimension)
        let paddedWidth = width * 1.42
        let paddedHeight = height * 1.62

        return MKMapRect(
            x: rect.midX - (paddedWidth / 2),
            y: rect.midY - (paddedHeight / 2),
            width: paddedWidth,
            height: paddedHeight
        )
    }

    private static func principalHeading(
        for points: [CLLocationCoordinate2D]
    ) -> CLLocationDirection {
        guard points.count >= 2 else {
            return 18
        }

        let mapPoints =
            sampled(
                points,
                maximumCount: 80
            )
            .map { MKMapPoint($0) }

        let meanX =
            mapPoints.reduce(0.0) {
                $0 + $1.x
            } /
            Double(mapPoints.count)
        let meanY =
            mapPoints.reduce(0.0) {
                $0 + $1.y
            } /
            Double(mapPoints.count)

        var xx = 0.0
        var yy = 0.0
        var xy = 0.0

        for point in mapPoints {
            let dx = point.x - meanX
            let dy = point.y - meanY
            xx += dx * dx
            yy += dy * dy
            xy += dx * dy
        }

        let axisAngle =
            0.5 *
            atan2(
                2 * xy,
                xx - yy
            )

        let dx = cos(axisAngle)
        let dy = sin(axisAngle)
        var heading =
            atan2(
                dx,
                -dy
            ) *
            180 /
            .pi

        heading += 12

        while heading < 0 {
            heading += 360
        }
        while heading >= 360 {
            heading -= 360
        }

        return heading
    }

    private static func interpolate(
        _ from: UIColor,
        _ to: UIColor,
        fraction: CGFloat
    ) -> UIColor {
        let t = min(max(fraction, 0), 1)

        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        var tr: CGFloat = 0
        var tg: CGFloat = 0
        var tb: CGFloat = 0
        var ta: CGFloat = 0

        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)

        return UIColor(
            red: fr + ((tr - fr) * t),
            green: fg + ((tg - fg) * t),
            blue: fb + ((tb - fb) * t),
            alpha: fa + ((ta - fa) * t)
        )
    }

    private static func drawHighestPoint(
        at point: CGPoint,
        altitudeMeters: Double,
        bounds: CGRect
    ) {
        guard bounds.insetBy(dx: 10, dy: 10)
            .contains(point)
        else {
            return
        }

        let dotOuter =
            CGRect(
                x: point.x - 6,
                y: point.y - 6,
                width: 12,
                height: 12
            )
        UIColor.white.setFill()
        UIBezierPath(
            ovalIn: dotOuter
        )
        .fill()

        let dotInner =
            CGRect(
                x: point.x - 3.5,
                y: point.y - 3.5,
                width: 7,
                height: 7
            )
        UIColor(
            red: 0.96,
            green: 0.57,
            blue: 0.12,
            alpha: 1
        )
        .setFill()
        UIBezierPath(
            ovalIn: dotInner
        )
        .fill()

        let title = "Highest point"
        let value =
            "\(Int(altitudeMeters.rounded())) m"

        let paragraph =
            NSMutableParagraphStyle()
        paragraph.alignment = .left

        let titleAttributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    UIFont.systemFont(
                        ofSize: 10,
                        weight: .semibold
                    ),
                .foregroundColor:
                    UIColor.white
                        .withAlphaComponent(0.88),
                .paragraphStyle: paragraph
            ]
        let valueAttributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    UIFont.systemFont(
                        ofSize: 12,
                        weight: .bold
                    ),
                .foregroundColor:
                    UIColor.white,
                .paragraphStyle: paragraph
            ]

        let bubbleSize =
            CGSize(width: 82, height: 38)
        var origin =
            CGPoint(
                x: point.x + 10,
                y: point.y - 43
            )

        if origin.x + bubbleSize.width >
            bounds.maxX - 8 {
            origin.x =
                point.x -
                bubbleSize.width -
                10
        }
        origin.x =
            min(
                max(origin.x, bounds.minX + 8),
                bounds.maxX -
                    bubbleSize.width -
                    8
            )
        origin.y =
            min(
                max(origin.y, bounds.minY + 8),
                bounds.maxY -
                    bubbleSize.height -
                    8
            )

        let bubbleRect =
            CGRect(
                origin: origin,
                size: bubbleSize
            )

        UIColor.black
            .withAlphaComponent(0.58)
            .setFill()
        UIBezierPath(
            roundedRect: bubbleRect,
            cornerRadius: 11
        )
        .fill()

        (title as NSString).draw(
            in: CGRect(
                x: bubbleRect.minX + 9,
                y: bubbleRect.minY + 6,
                width: bubbleRect.width - 18,
                height: 13
            ),
            withAttributes:
                titleAttributes
        )
        (value as NSString).draw(
            in: CGRect(
                x: bubbleRect.minX + 9,
                y: bubbleRect.minY + 18,
                width: bubbleRect.width - 18,
                height: 16
            ),
            withAttributes:
                valueAttributes
        )
    }

    private static func drawFinishEndpoint(
        at point: CGPoint
    ) {
        let outer =
            CGRect(
                x: point.x - 9,
                y: point.y - 9,
                width: 18,
                height: 18
            )
        UIColor.white.setFill()
        UIBezierPath(
            ovalIn: outer
        )
        .fill()

        let middle =
            outer.insetBy(
                dx: 2,
                dy: 2
            )
        UIColor.black
            .withAlphaComponent(0.88)
            .setFill()
        UIBezierPath(
            ovalIn: middle
        )
        .fill()

        let tile: CGFloat = 4
        for row in 0..<2 {
            for column in 0..<2 {
                if (row + column).isMultiple(of: 2) {
                    let tileRect =
                        CGRect(
                            x:
                                point.x -
                                tile +
                                CGFloat(column) *
                                tile,
                            y:
                                point.y -
                                tile +
                                CGFloat(row) *
                                tile,
                            width: tile,
                            height: tile
                        )
                    UIColor.white.setFill()
                    UIBezierPath(
                        rect: tileRect
                    )
                    .fill()
                }
            }
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

        let latitudeDelta =
            max(
                (
                    maxLatitude -
                    minLatitude
                ) * 1.58,
                0.009
            )
        let longitudeDelta =
            max(
                (
                    maxLongitude -
                    minLongitude
                ) * 1.62,
                0.009
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
                        ) / 2 -
                        longitudeDelta * 0.075
                ),
            span: MKCoordinateSpan(
                latitudeDelta:
                    latitudeDelta,
                longitudeDelta:
                    longitudeDelta
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
    let muscleSummary: StrengthMuscleSessionSummary
    let strengthWorkout: StrengthWorkoutLog?
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

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(strengthDescription)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(3)

                    if !focusAreas.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Focus Areas")
                                .font(
                                    .system(
                                        size: 9.5,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )

                            ForEach(
                                focusAreas.prefix(4),
                                id: \.self
                            ) { group in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(
                                            Color.indigo
                                                .opacity(0.72)
                                        )
                                        .frame(
                                            width: 6,
                                            height: 6
                                        )

                                    Text(group)
                                        .font(
                                            .system(
                                                size: 10,
                                                weight: .medium
                                            )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

                StrengthMuscleMapView(
                    profile:
                        muscleSummary
                            .profile,
                    compact: true
                )
                .frame(
                    width: 132,
                    height: 158
                )
            }
            .padding(12)
            .background(
                Color.indigo.opacity(0.035),
                in: RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
                .stroke(
                    Color.indigo.opacity(0.07),
                    lineWidth: 0.8
                )
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
                HomeActivityStrengthDetailView(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout
                )
            } label: {
                HStack {
                    Text("View muscle & exercise details")
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                    Spacer()
                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .caption2.bold()
                    )
                }
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
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
        let visualFocus =
            muscleSummary
                .profile
                .topActivations
                .prefix(4)
                .map {
                    $0.region.title
                }

        if !visualFocus.isEmpty {
            return visualFocus
        }

        return Array(
            (
                workout
                    .strengthMuscleGroups ??
                []
            )
            .map {
                $0
                    .replacingOccurrences(
                        of: "_",
                        with: " "
                    )
                    .capitalized
            }
            .prefix(4)
        )
    }

    private var displayTitle: String {
        let trimmed =
            workout.title
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        let normalizedTitle =
            trimmed.lowercased()
        let generic =
            trimmed.isEmpty ||
            normalizedTitle == "strength" ||
            normalizedTitle == "strength training" ||
            normalizedTitle == "functional strength training" ||
            normalizedTitle == "traditional strength training" ||
            normalizedTitle == "workout"

        guard generic else {
            return trimmed
        }

        let normalizedAreas =
            Set(
                focusAreas.map {
                    $0.lowercased()
                }
            )
        let upperKeywords: Set<String> = [
            "chest",
            "shoulders",
            "back",
            "arms",
            "biceps",
            "triceps"
        ]
        let lowerKeywords: Set<String> = [
            "legs",
            "quads",
            "quadriceps",
            "hamstrings",
            "glutes",
            "calves"
        ]

        let hasUpper =
            !normalizedAreas
                .intersection(
                    upperKeywords
                )
                .isEmpty
        let hasLower =
            !normalizedAreas
                .intersection(
                    lowerKeywords
                )
                .isEmpty

        if hasUpper && hasLower {
            return "Full Body Strength"
        }

        if hasUpper {
            return "Upper Body Strength"
        }

        if hasLower {
            return "Lower Body Strength"
        }

        if normalizedAreas.contains("core") ||
            normalizedAreas.contains("abs") {
            return "Core Strength"
        }

        return "Strength Session"
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
        let localStrengthItems =
            strength.workoutHistory
                .filter(\.isFinished)
                .map(
                    SocialPublishableWorkout.init
                )
        let localStrengthIDs =
            Set(
                localStrengthItems
                    .map(\.id)
            )

        let healthItems =
            health.workouts
                .map(
                    SocialPublishableWorkout.init
                )
                .filter {
                    !(
                        $0.activity ==
                            .strength &&
                        localStrengthIDs
                            .contains($0.id)
                    )
                }

        return Array(
            (
                healthItems +
                localStrengthItems
            )
            .sorted {
                $0.startDate >
                $1.startDate
            }
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
