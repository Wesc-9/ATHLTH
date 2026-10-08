import CoreLocation
import SwiftUI
import UIKit

// MARK: - Home activity stream

private enum HomeActivityScopeFilter:
    String,
    CaseIterable,
    Identifiable {
    case all
    case mine
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(
                english: "All",
                norwegian: "Alle"
            )
        case .mine:
            return ATHLTHLocalization.choose(
                english: "Mine",
                norwegian: "Mine"
            )
        case .following:
            return ATHLTHLocalization.choose(
                english: "Following",
                norwegian: "Følger"
            )
        }
    }
}

private enum HomeActivityTypeFilter:
    String,
    CaseIterable,
    Identifiable {
    case all
    case running
    case strength
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(
                english: "All types",
                norwegian: "Alle typer"
            )
        case .running:
            return ATHLTHLocalization.choose(
                english: "Run",
                norwegian: "Løp"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .other:
            return ATHLTHLocalization.choose(
                english: "Other",
                norwegian: "Annet"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2.fill"
        case .running:
            return "figure.run"
        case .strength:
            return "dumbbell.fill"
        case .other:
            return "ellipsis"
        }
    }

    func includes(
        _ activity: WorkoutActivity?
    ) -> Bool {
        guard let activity else {
            return self == .all ||
                self == .other
        }

        switch self {
        case .all:
            return true
        case .running:
            return activity == .running ||
                activity == .walking ||
                activity == .hiking
        case .strength:
            return activity == .strength
        case .other:
            return ![
                WorkoutActivity.running,
                .walking,
                .hiking,
                .strength
            ].contains(activity)
        }
    }
}

private enum HomeActivityStreamSource {
    case mine(SocialPublishableWorkout)
    case following(SocialFeedItem)
}

private struct HomeActivityStreamItem:
    Identifiable {
    let source: HomeActivityStreamSource

    var id: String {
        switch source {
        case .mine(let workout):
            return "mine-\(workout.id.uuidString)"
        case .following(let item):
            return "following-\(item.id.uuidString)"
        }
    }

    var date: Date {
        switch source {
        case .mine(let workout):
            return workout.startDate
        case .following(let item):
            return item.activity.createdAt
        }
    }

    var activity: WorkoutActivity? {
        switch source {
        case .mine(let workout):
            return workout.activity
        case .following(let item):
            return Self.resolveActivity(
                item.activity
                    .metadata?["kind"]
            )
        }
    }

    var isMine: Bool {
        if case .mine = source {
            return true
        }
        return false
    }

    private static func resolveActivity(
        _ raw: String?
    ) -> WorkoutActivity? {
        guard let raw else {
            return nil
        }

        if let exact =
                WorkoutActivity(
                    rawValue: raw
                ) {
            return exact
        }

        switch raw
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased() {
        case "run",
             "running":
            return .running
        case "walk",
             "walking":
            return .walking
        case "hike",
             "hiking":
            return .hiking
        case "strength",
             "functional":
            return .strength
        case "cycling",
             "cycle":
            return .cycling
        case "hiit":
            return .hiit
        case "rowing":
            return .rowing
        case "yoga":
            return .yoga
        case "stairclimbing",
             "stair climbing":
            return .stairClimbing
        default:
            return .other
        }
    }
}

private enum HomeActivityVisibilityStore {
    static let changed =
        Notification.Name(
            "athlth.homeActivityVisibility.changed"
        )

    private static let storageName =
        "homeHiddenWorkoutIDs"

    static func hiddenWorkoutIDs(
        userID: UUID?
    ) -> Set<UUID> {
        guard let userID else {
            return []
        }

        let key =
            AccountLocalStorage.key(
                storageName,
                userID: userID
            )

        return Set(
            UserDefaults.standard
                .stringArray(
                    forKey: key
                )?
                .compactMap(UUID.init(uuidString:)) ??
            []
        )
    }

    static func hide(
        _ workoutIDs: Set<UUID>,
        userID: UUID?
    ) {
        guard let userID,
              !workoutIDs.isEmpty
        else {
            return
        }

        var hidden =
            hiddenWorkoutIDs(
                userID: userID
            )
        hidden.formUnion(workoutIDs)

        let key =
            AccountLocalStorage.key(
                storageName,
                userID: userID
            )
        UserDefaults.standard.set(
            hidden
                .map(\.uuidString)
                .sorted(),
            forKey: key
        )

        NotificationCenter.default.post(
            name: changed,
            object: nil
        )
    }
}

@MainActor
private enum HomePersonalWorkoutCatalog {
    static func merge(
        healthSummaries: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        phoneHistory: [PhoneWorkout],
        excludedIDs: Set<UUID> = []
    ) -> [SocialPublishableWorkout] {
        var byID: [UUID: SocialPublishableWorkout] =
            [:]

        for summary in healthSummaries
        where !excludedIDs.contains(summary.id) {
            let workout =
                SocialPublishableWorkout(
                    summary: summary
                )
            byID[workout.id] = workout
        }

        for phoneWorkout in phoneHistory
        where phoneWorkout.end != nil &&
              !excludedIDs.contains(phoneWorkout.id) &&
              phoneWorkout.healthID.map(excludedIDs.contains) != true {
            let workout =
                SocialPublishableWorkout(
                    phoneWorkout:
                        phoneWorkout
                )
            byID[workout.id] = workout
        }

        // ATHLTH strength logs deliberately win over HealthKit summaries:
        // they contain exercise names, set data and muscle metadata. Older or
        // interrupted logs may not yet have the HealthKit UUID, so remove a
        // near-identical Health summary by time before inserting the richer log.
        for strengthWorkout in
            strengthHistory
            .filter(\.isFinished)
        where !excludedIDs.contains(strengthWorkout.id) &&
              strengthWorkout.healthMetrics
                .healthKitWorkoutUUID
                .map(excludedIDs.contains) != true {
            let workout =
                SocialPublishableWorkout(
                    strengthWorkout:
                        strengthWorkout
                )

            let nearestHealthStrength =
                byID.values
                    .filter { candidate in
                        candidate.activity ==
                            .strength &&
                        candidate.source ==
                            "Apple Health"
                    }
                    .min { lhs, rhs in
                        abs(
                            lhs.startDate
                                .timeIntervalSince(
                                    strengthWorkout
                                        .startedAt
                                )
                        ) <
                        abs(
                            rhs.startDate
                                .timeIntervalSince(
                                    strengthWorkout
                                        .startedAt
                                )
                        )
                    }

            if strengthWorkout
                .healthMetrics
                .healthKitWorkoutUUID == nil,
               let candidate =
                    nearestHealthStrength,
               abs(
                    candidate.startDate
                        .timeIntervalSince(
                            strengthWorkout
                                .startedAt
                        )
               ) <= 120 {
                byID.removeValue(
                    forKey:
                        candidate.id
                )
            }

            byID[workout.id] =
                workout
        }

        return byID.values.sorted {
            $0.startDate > $1.startDate
        }
    }

    static func mergeRecent(
        healthSummaries: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        phoneHistory: [PhoneWorkout],
        excludedIDs: Set<UUID> = [],
        limitPerSource: Int = 24
    ) -> [SocialPublishableWorkout] {
        let limit = max(limitPerSource, 6)

        return merge(
            healthSummaries:
                Array(
                    healthSummaries
                        .prefix(limit)
                ),
            strengthHistory:
                Array(
                    strengthHistory
                        .lazy
                        .filter(\.isFinished)
                        .prefix(limit)
                ),
            phoneHistory:
                Array(
                    phoneHistory
                        .lazy
                        .filter {
                            $0.end != nil
                        }
                        .prefix(limit)
                ),
            excludedIDs:
                excludedIDs
        )
    }

    static func strengthWorkout(
        for workout:
            SocialPublishableWorkout,
        in history:
            [StrengthWorkoutLog]
    ) -> StrengthWorkoutLog? {
        if let exact =
                history.first(
                    where: {
                        (
                            $0.healthMetrics
                                .healthKitWorkoutUUID ??
                            $0.id
                        ) ==
                            workout.id
                    }
                ) {
            return exact
        }

        guard workout.activity ==
                .strength
        else {
            return nil
        }

        return history
            .filter(\.isFinished)
            .min {
                abs(
                    $0.startedAt
                        .timeIntervalSince(
                            workout.startDate
                        )
                ) <
                abs(
                    $1.startedAt
                        .timeIntervalSince(
                            workout.startDate
                        )
                )
            }
            .flatMap {
                abs(
                    $0.startedAt
                        .timeIntervalSince(
                            workout.startDate
                        )
                ) <= 120
                    ? $0
                    : nil
            }
    }

    static func phoneWorkout(
        for workout:
            SocialPublishableWorkout,
        in history:
            [PhoneWorkout]
    ) -> PhoneWorkout? {
        history.first {
            (
                $0.healthID ??
                $0.id
            ) == workout.id
        }
    }
}

@MainActor
private enum HomeActivityStreamBuilder {
    static func make(
        mine:
            [SocialPublishableWorkout],
        social: SocialStore
    ) -> [HomeActivityStreamItem] {
        let mineItems =
            mine.map {
                HomeActivityStreamItem(
                    source: .mine($0)
                )
            }

        let followingItems =
            social.feed
                .filter {
                    $0.activity.kind ==
                        "workout" &&
                    $0.actor.userID !=
                        social.currentUserID
                }
                .map {
                    HomeActivityStreamItem(
                        source:
                            .following($0)
                    )
                }

        return (
            mineItems +
            followingItems
        )
        .sorted {
            $0.date > $1.date
        }
    }
}

// MARK: - Home section

private struct HomeRecentActivityRevision:
    Hashable {
    let healthCount: Int
    let healthFirstID: UUID?
    let strengthCount: Int
    let strengthFirstID: UUID?
    let strengthFirstEnd: Date?
    let phoneCount: Int
    let phoneFirstID: UUID?
    let phoneFirstEnd: Date?
}

struct HomePersonalRecentActivitySection:
    View {
    @EnvironmentObject private var health:
        HealthKitManager
    @EnvironmentObject private var strength:
        StrengthWorkoutStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    @EnvironmentObject private var social:
        SocialStore

    @State private var myWorkouts:
        [SocialPublishableWorkout] = []

    private var recentRevision:
        HomeRecentActivityRevision {
        HomeRecentActivityRevision(
            healthCount:
                health.workouts.count,
            healthFirstID:
                health.workouts.first?.id,
            strengthCount:
                strength.workoutHistory.count,
            strengthFirstID:
                strength.workoutHistory.first?.id,
            strengthFirstEnd:
                strength.workoutHistory
                    .first?
                    .endedAt,
            phoneCount:
                phoneWorkout.history.count,
            phoneFirstID:
                phoneWorkout.history.first?.id,
            phoneFirstEnd:
                phoneWorkout.history.first?.end
        )
    }

    private var stream:
        [HomeActivityStreamItem] {
        HomeActivityStreamBuilder.make(
            mine: myWorkouts,
            social: social
        )
    }

    private var visibleItems:
        [HomeActivityStreamItem] {
        guard let first = stream.first else {
            return []
        }

        var result:
            [HomeActivityStreamItem] =
                [first]

        let needsMine =
            !first.isMine
        let needsFollowing =
            first.isMine

        if needsMine,
           let mine =
                stream.first(
                    where: {
                        $0.isMine
                    }
                ) {
            result.append(mine)
        } else if needsFollowing,
                  let following =
                    stream.first(
                        where: {
                            !$0.isMine
                        }
                  ) {
            result.append(following)
        }

        for candidate in stream
        where result.count < 6 &&
              !result.contains(
                where: {
                    $0.id == candidate.id
                }
              ) {
            result.append(candidate)
        }

        return result
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            header

            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    LazyHStack(
                        alignment: .top,
                        spacing: 10
                    ) {
                        ForEach(
                            visibleItems
                        ) { item in
                            horizontalItem(
                                item
                            )
                            .frame(width: 202)
                        }
                    }
                    .padding(
                        .horizontal,
                        1
                    )
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(
                    .viewAligned
                )
            }
        }
        .task(id: recentRevision) {
            rebuildRecentWorkouts()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    HomeActivityVisibilityStore
                        .changed
            )
        ) { _ in
            rebuildRecentWorkouts()
        }
    }

    private func rebuildRecentWorkouts() {
        let refreshed =
            HomePersonalWorkoutCatalog
                .mergeRecent(
                    healthSummaries:
                        health.workouts,
                    strengthHistory:
                        strength
                            .workoutHistory,
                    phoneHistory:
                        phoneWorkout
                            .history,
                    excludedIDs:
                        HomeActivityVisibilityStore
                            .hiddenWorkoutIDs(
                                userID:
                                    social.currentUserID
                            )
                )

        if refreshed != myWorkouts {
            myWorkouts = refreshed
        }
    }

    private var header: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: 12
        ) {
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Recent activity",
                        norwegian:
                            "Siste aktivitet"
                    )
                )
                .font(
                    .headline.weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Your workouts and people you follow.",
                        norwegian:
                            "Dine økter og økter fra de du følger."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            NavigationLink {
                HomePersonalActivityHistoryView()
            } label: {
                HStack(spacing: 5) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "See all",
                            norwegian: "Se alle"
                        )
                    )

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                }
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .padding(
                    .horizontal,
                    11
                )
                .frame(height: 32)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func horizontalItem(
        _ item:
            HomeActivityStreamItem
    ) -> some View {
        switch item.source {
        case .mine(let workout):
            ZStack(alignment: .bottom) {
                NavigationLink {
                    HomePersonalActivityDestination(
                        workout: workout,
                        strengthWorkout:
                            strengthWorkout(
                                for: workout
                            ),
                        phoneWorkout:
                            localPhoneWorkout(
                                for: workout
                            )
                    )
                } label: {
                    HomePersonalHorizontalWorkoutCard(
                        workout: workout,
                        strengthWorkout:
                            strengthWorkout(
                                for: workout
                            ),
                        phoneWorkout:
                            localPhoneWorkout(
                                for: workout
                            )
                    )
                }
                .buttonStyle(.plain)

                HomeCompactActivityEngagementRow(
                    item:
                        socialFeedItem(
                            for: workout
                        )
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
                .zIndex(4)
            }

        case .following(let socialItem):
            ZStack(alignment: .bottom) {
                NavigationLink {
                    HomeFollowingWorkoutDetailView(
                        item: socialItem
                    )
                } label: {
                    HomeFollowingHorizontalWorkoutCard(
                        item: socialItem
                    )
                }
                .buttonStyle(.plain)

                HomeCompactActivityEngagementRow(
                    item: socialItem
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
                .zIndex(4)
            }
        }
    }

    @ViewBuilder
    private func featuredItem(
        _ item:
            HomeActivityStreamItem
    ) -> some View {
        switch item.source {
        case .mine(let workout):
            NavigationLink {
                HomePersonalActivityDestination(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout(
                            for: workout
                        )
                )
            } label: {
                HomePersonalFeaturedWorkoutCard(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout(
                            for: workout
                        ),
                    phoneWorkout:
                        localPhoneWorkout(
                            for: workout
                        )
                )
            }
            .buttonStyle(.plain)

        case .following(let socialItem):
            NavigationLink {
                HomeFollowingWorkoutDetailView(
                    item: socialItem
                )
            } label: {
                HomeFollowingFeaturedWorkoutCard(
                    item: socialItem
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func compactItem(
        _ item:
            HomeActivityStreamItem
    ) -> some View {
        switch item.source {
        case .mine(let workout):
            NavigationLink {
                HomePersonalActivityDestination(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout(
                            for: workout
                        )
                )
            } label: {
                HomePersonalCompactWorkoutCard(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout(
                            for: workout
                        )
                )
            }
            .buttonStyle(.plain)

        case .following(let socialItem):
            NavigationLink {
                HomeFollowingWorkoutDetailView(
                    item: socialItem
                )
            } label: {
                HomeFollowingCompactWorkoutCard(
                    item: socialItem
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "figure.run.circle.fill"
            )
            .font(.title2)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 48,
                height: 48
            )
            .background(
                ATHLTHTheme.accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "No recent workouts yet",
                        norwegian:
                            "Ingen nye økter ennå"
                    )
                )
                .font(
                    .subheadline.weight(
                        .semibold
                    )
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Your workouts and shared workouts from people you follow will appear here.",
                        norwegian:
                            "Dine økter og delte økter fra de du følger vises her."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(14)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
    }

    private func strengthWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> StrengthWorkoutLog? {
        HomePersonalWorkoutCatalog
            .strengthWorkout(
                for: workout,
                in:
                    Array(
                        strength
                            .workoutHistory
                            .prefix(32)
                    )
            )
    }

    private func localPhoneWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> PhoneWorkout? {
        HomePersonalWorkoutCatalog
            .phoneWorkout(
                for: workout,
                in:
                    Array(
                        phoneWorkout
                            .history
                            .prefix(32)
                    )
            )
    }

    private func socialFeedItem(
        for workout:
            SocialPublishableWorkout
    ) -> SocialFeedItem? {
        let workoutID =
            workout.id.uuidString
                .lowercased()

        return social.feed.first {
            item in

            guard item.activity.actorID ==
                    social.currentUserID,
                  item.activity.kind ==
                    "workout"
            else {
                return false
            }

            let metadataWorkoutID =
                item.activity
                    .metadata?["workout_id"]?
                    .lowercased()

            if metadataWorkoutID ==
                workoutID {
                return true
            }

            let eventKey =
                item.activity
                    .eventKey?
                    .lowercased()

            return eventKey ==
                    "workout-\(workoutID)" ||
                   eventKey ==
                    "strength-workout-\(workoutID)"
        }
    }
}

private struct HomePersonalHorizontalWorkoutCard:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    let phoneWorkout: PhoneWorkout?

    private var cardTitle: String {
        let generic = ["running", "run", "løping", "løp", "iphone run", "iPhone run".lowercased(), "running completed", "løpeøkt fullført"]
        if workout.activity == .running,
           workout.isIndoor == true,
           generic.contains(
               workout.title.trimmingCharacters(
                   in: .whitespacesAndNewlines
               ).lowercased()
           ) {
            return ATHLTHLocalization.choose(
                english: "Treadmill",
                norwegian: "Tredemølle"
            )
        }
        return workout.title
    }

    var body: some View {
        let muscleProfile =
            workout.activity == .strength
                ? homeMuscleProfile
                : .empty

        return VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomePersonalWorkoutVisual(
                workout: workout,
                strengthWorkout:
                    strengthWorkout,
                phoneWorkout:
                    phoneWorkout,
                height: 124,
                precomputedStrengthProfile:
                    workout.activity == .strength
                        ? muscleProfile
                        : nil
            )

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                HStack(spacing: 4) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "You",
                            norwegian: "Du"
                        )
                    )
                    .font(
                        .system(
                            size: 9.5,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Text("·")
                        .font(.system(size: 9.5))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(
                        workout.endDate.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                    .font(.system(size: 9.5))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                }

                Text(cardTitle)
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(2)

                Text(detailText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)

                if let muscleFocusText =
                        muscleFocusText(
                            from: muscleProfile
                        ) {
                    HStack(spacing: 6) {
                        Image(
                            systemName:
                                "figure.strengthtraining.traditional"
                        )
                        .font(
                            .system(
                                size: 9.5,
                                weight: .semibold
                            )
                        )

                        Text(muscleFocusText)
                            .font(
                                .system(
                                    size: 10,
                                    weight: .semibold
                                )
                            )
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .frame(height: 22)
                } else if let exerciseNames,
                          !exerciseNames.isEmpty {
                    Text(exerciseNames)
                        .font(
                            .system(
                                size: 8.5,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .frame(height: 252, alignment: .top)
        .background(
            Color.white.opacity(0.96),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
    }

    private var homeMuscleProfile:
        StrengthMuscleProfile {
        if let strengthWorkout {
            // Use the completed exercises and set counts, not a flat list
            // of muscle names. The log already carries its muscle metadata.
            let actual = StrengthMuscleProfileBuilder.make(
                workout: strengthWorkout,
                library: []
            ).profile
            if !actual.activations.isEmpty {
                return actual
            }
        }

        guard let groups =
                workout
                    .strengthMuscleGroups,
              !groups.isEmpty
        else {
            return .empty
        }

        var scores:
            [StrengthMuscleRegion: Double] =
                [:]

        for raw in groups {
            for region in
                StrengthMuscleResolver
                    .regions(for: raw) {
                scores[
                    region,
                    default: 0
                ] += 1
            }
        }

        return StrengthMuscleProfile(
            activations:
                scores.map {
                    StrengthMuscleActivation(
                        region: $0.key,
                        score: $0.value
                    )
                }
        )
    }

    private var strengthAccent:
        Color {
        Color(
            red: 0.91,
            green: 0.33,
            blue: 0.22
        )
    }

    private func muscleFocusText(
        from profile: StrengthMuscleProfile
    ) -> String? {
        var titles: [String] = []

        for activation in
            profile.topActivations {
            let title =
                activation
                    .region
                    .activityDisplayTitle

            guard !titles.contains(
                title
            )
            else {
                continue
            }

            titles.append(title)

            if titles.count == 3 {
                break
            }
        }

        if titles.isEmpty,
           let rawGroups =
                workout
                    .strengthMuscleGroups {
            for raw in rawGroups {
                let regions =
                    StrengthMuscleResolver
                        .regions(
                            for: raw
                        )

                if regions.isEmpty {
                    let clean =
                        raw.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    if !clean.isEmpty,
                       !titles.contains(clean) {
                        titles.append(clean)
                    }
                } else {
                    for region in regions {
                        let title =
                            region
                                .activityDisplayTitle

                        if !titles.contains(
                            title
                        ) {
                            titles.append(
                                title
                            )
                        }

                        if titles.count == 3 {
                            break
                        }
                    }
                }

                if titles.count == 3 {
                    break
                }
            }
        }

        guard !titles.isEmpty else {
            return nil
        }

        return titles.joined(
            separator: " · "
        )
    }

    private var detailText:
        String {
        if workout.activity == .strength {
            let count =
                workout
                    .strengthExerciseCount ??
                0

            if count > 0 {
                return ATHLTHLocalization.format(
                    english:
                        "%d exercises · %@",
                    norwegian:
                        "%d øvelser · %@",
                    count,
                    workout.summaryText
                )
            }
        }

        return workout.summaryText
    }

    private var exerciseNames:
        String? {
        guard let strengthWorkout else {
            return nil
        }

        let names =
            strengthWorkout.exercises
                .filter {
                    $0.isCompleted ||
                    $0.sets.contains {
                        $0.isCompleted
                    }
                }
                .prefix(3)
                .map {
                    $0.exercise.name
                }

        guard !names.isEmpty else {
            return nil
        }

        return names.joined(
            separator: " · "
        )
    }
}

private struct HomeFollowingHorizontalWorkoutCard:
    View {
    let item: SocialFeedItem

    private var activity:
        WorkoutActivity {
        HomeFollowingWorkoutPresentation
            .activity(for: item)
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomeFollowingWorkoutArtwork(
                item: item,
                activity: activity,
                height: 106
            )
            .overlay(
                alignment: .bottomLeading
            ) {
                SocialAvatar(
                    profile: item.actor,
                    size: 28
                )
                .padding(9)
            }

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                HStack(spacing: 4) {
                    Text(
                        item.actor
                            .resolvedName
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .lineLimit(1)

                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(
                        item.activity.createdAt,
                        style: .relative
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                }

                Text(
                    item.activity.title
                )
                .font(
                    .system(
                        size: 13,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(2)

                if activity == .strength,
                   let detail =
                    HomeFollowingWorkoutPresentation
                        .strengthDetailText(
                            for: item
                        ) {
                    HStack(spacing: 5) {
                        Image(
                            systemName:
                                "figure.strengthtraining.traditional"
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .semibold
                            )
                        )

                        Text(detail)
                            .font(
                                .system(
                                    size: 8.5,
                                    weight: .semibold
                                )
                            )
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        Color(
                            red: 0.91,
                            green: 0.33,
                            blue: 0.22
                        )
                    )
                    .padding(
                        .horizontal,
                        7
                    )
                    .frame(height: 22)
                    .background(
                        Color(
                            red: 0.91,
                            green: 0.33,
                            blue: 0.22
                        )
                        .opacity(0.09),
                        in: Capsule()
                    )
                } else if let subtitle =
                            item.activity.subtitle,
                          !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .frame(height: 220, alignment: .top)
        .background(
            Color.white.opacity(0.96),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
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
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
    }
}

private struct HomeCompactActivityEngagementRow:
    View {
    @EnvironmentObject private var social:
        SocialStore

    let item: SocialFeedItem?

    @State private var showingComments = false

    private var currentItem:
        SocialFeedItem? {
        guard let item else {
            return nil
        }

        return social.feed.first {
            $0.id == item.id
        } ?? item
    }

    private var isLiked: Bool {
        guard let currentItem,
              let userID =
                social.currentUserID
        else {
            return false
        }

        return currentItem.reactions
            .contains {
                $0.userID == userID &&
                $0.reaction == .heart
            }
    }

    private var likeCount: Int {
        currentItem?.reactions.count ?? 0
    }

    private var commentCount: Int {
        currentItem?.comments.count ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                guard let currentItem else {
                    return
                }

                Task {
                    await social.setReaction(
                        activityID:
                            currentItem.id,
                        reaction:
                            isLiked
                                ? nil
                                : .heart
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Image(
                        systemName:
                            isLiked
                                ? "heart.fill"
                                : "heart"
                    )

                    Text("\(likeCount)")
                        .monospacedDigit()
                }
                .foregroundStyle(
                    isLiked
                        ? Color.red
                        : ATHLTHTheme
                            .mutedText
                )
            }
            .buttonStyle(.plain)
            .frame(
                minWidth: 44,
                minHeight: 38
            )
            .contentShape(Rectangle())
            .disabled(currentItem == nil)

            Button {
                guard currentItem != nil else {
                    return
                }

                showingComments = true
            } label: {
                HStack(spacing: 4) {
                    Image(
                        systemName:
                            "bubble.left"
                    )

                    Text("\(commentCount)")
                        .monospacedDigit()
                }
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
            .buttonStyle(.plain)
            .frame(
                minWidth: 44,
                minHeight: 38
            )
            .contentShape(Rectangle())
            .disabled(currentItem == nil)

            Spacer(minLength: 0)
        }
        .font(
            .system(
                size: 10,
                weight: .semibold
            )
        )
        .frame(height: 25)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    Color.black
                        .opacity(0.055)
                )
                .frame(height: 0.5)
        }
        .sheet(
            isPresented:
                $showingComments
        ) {
            if let currentItem {
                HomeActivityCommentsSheet(
                    item: currentItem
                )
            }
        }
        .accessibilityElement(
            children: .contain
        )
    }
}

// MARK: - Own workout cards

private struct HomePersonalFeaturedWorkoutCard:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    let phoneWorkout: PhoneWorkout?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomePersonalWorkoutVisual(
                workout: workout,
                strengthWorkout:
                    strengthWorkout,
                phoneWorkout:
                    phoneWorkout,
                height: 154
            )

            VStack(
                alignment: .leading,
                spacing: 11
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 8
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        HStack(spacing: 6) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "YOU",
                                    norwegian: "DEG"
                                )
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .tracking(1.0)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )

                            Text("·")

                            Text(
                                workout
                                    .startDate
                                    .formatted(
                                        date:
                                            .abbreviated,
                                        time:
                                            .shortened
                                    )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }

                        Text(workout.title)
                            .font(
                                .title3.weight(
                                    .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(
                        systemName:
                            "arrow.up.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 30,
                        height: 30
                    )
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )
                }

                HStack(spacing: 8) {
                    metricChip(
                        workout.summaryText,
                        icon:
                            workout.activity.icon
                    )

                    if workout.activity ==
                        .strength,
                       let count =
                            workout
                                .strengthExerciseCount,
                       count > 0 {
                        metricChip(
                            ATHLTHLocalization
                                .format(
                                    english:
                                        "%d exercises",
                                    norwegian:
                                        "%d øvelser",
                                    count
                                ),
                            icon:
                                "list.bullet"
                        )
                    } else if let calories =
                                workout
                                    .activeEnergyKilocalories,
                              calories > 0 {
                        metricChip(
                            "\(Int(calories.rounded())) kcal",
                            icon:
                                "flame.fill"
                        )
                    }
                }

                if let strengthWorkout {
                    let names =
                        strengthWorkout
                            .exercises
                            .filter {
                                $0.isCompleted ||
                                $0.sets.contains(
                                    where: {
                                        $0.isCompleted
                                    }
                                )
                            }
                            .prefix(4)
                            .map {
                                $0.exercise.name
                            }

                    if !names.isEmpty {
                        Text(
                            names.joined(
                                separator: " · "
                            )
                        )
                        .font(
                            .caption.weight(
                                .medium
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                    }
                }
            }
            .padding(15)
        }
        .background(
            Color.white.opacity(0.96),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .clipShape(
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
                Color.black.opacity(
                    0.045
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.045
                ),
            radius: 16,
            y: 7
        )
    }

    private func metricChip(
        _ text: String,
        icon: String
    ) -> some View {
        Label(
            text,
            systemImage: icon
        )
        .font(
            .caption.weight(
                .semibold
            )
        )
        .foregroundStyle(
            ATHLTHTheme.primaryText
        )
        .padding(
            .horizontal,
            9
        )
        .frame(height: 30)
        .background(
            Color.black.opacity(
                0.035
            ),
            in: Capsule()
        )
        .lineLimit(1)
    }
}

private struct HomePersonalCompactWorkoutCard:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?

    var body: some View {
        HStack(spacing: 11) {
            Image(
                systemName:
                    workout.activity.icon
            )
            .font(
                .system(
                    size: 15,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                workout.activity ==
                    .strength
                    ? ATHLTHTheme
                        .premiumGold
                    : ATHLTHTheme
                        .accentDeep
            )
            .frame(
                width: 40,
                height: 40
            )
            .background(
                workout.activity ==
                    .strength
                    ? ATHLTHTheme
                        .champagneSoft
                    : ATHLTHTheme
                        .accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                HStack(spacing: 5) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "You",
                            norwegian: "Du"
                        )
                    )
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(
                        workout.endDate.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Text(workout.title)
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                Text(compactSubtitle)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption2.bold())
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
        }
        .padding(11)
        .background(
            Color.white.opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(
                    0.035
                ),
                lineWidth: 0.7
            )
        }
    }

    private var compactSubtitle:
        String {
        if workout.activity ==
            .strength,
           let strengthWorkout {
            let count =
                strengthWorkout
                    .exercises
                    .filter {
                        $0.isCompleted ||
                        $0.sets.contains(
                            where: {
                                $0.isCompleted
                            }
                        )
                    }
                    .count

            if count > 0 {
                return ATHLTHLocalization
                    .format(
                        english:
                            "%d exercises · %@",
                        norwegian:
                            "%d øvelser · %@",
                        count,
                        workout.summaryText
                    )
            }
        }

        return workout.summaryText
    }
}

// MARK: - Following cards

private struct HomeFollowingFeaturedWorkoutCard:
    View {
    let item: SocialFeedItem

    private var activity:
        WorkoutActivity {
        HomeFollowingWorkoutPresentation
            .activity(for: item)
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomeFollowingWorkoutArtwork(
                item: item,
                activity: activity,
                height: 132
            )
            .overlay(
                alignment:
                    .bottomLeading
            ) {
                HStack(spacing: 8) {
                    SocialAvatar(
                        profile: item.actor,
                        size: 34
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 1
                    ) {
                        Text(
                            item.actor
                                .resolvedName
                        )
                        .font(
                            .caption.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            .white
                        )

                        Text(
                            item.activity
                                .createdAt,
                            style: .relative
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            Color.white
                                .opacity(0.76)
                        )
                    }
                }
                .padding(12)
            }

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack {
                    Text(
                        item.activity.title
                    )
                    .font(
                        .title3.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                    Spacer()

                    Image(
                        systemName:
                            "arrow.up.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }

                if let subtitle =
                        item.activity
                            .subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(
                            .caption.weight(
                                .medium
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                }

                if activity == .strength,
                   let strengthText =
                        HomeFollowingWorkoutPresentation
                            .strengthDetailText(
                                for: item
                            ) {
                    Text(strengthText)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                }
            }
            .padding(15)
        }
        .background(
            Color.white.opacity(0.96),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .clipShape(
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
                Color.black.opacity(
                    0.045
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.04
                ),
            radius: 14,
            y: 6
        )
    }
}

private struct HomeFollowingCompactWorkoutCard:
    View {
    let item: SocialFeedItem

    private var activity:
        WorkoutActivity {
        HomeFollowingWorkoutPresentation
            .activity(for: item)
    }

    var body: some View {
        HStack(spacing: 11) {
            SocialAvatar(
                profile: item.actor,
                size: 40
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                HStack(spacing: 5) {
                    Text(
                        item.actor
                            .resolvedName
                    )
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )

                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                    Text(
                        item.activity
                            .createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Label(
                    item.activity.title,
                    systemImage:
                        activity.icon
                )
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)

                if activity == .strength,
                   let strengthText =
                        HomeFollowingWorkoutPresentation
                            .strengthDetailText(
                                for: item
                            ) {
                    Text(strengthText)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                } else if let subtitle =
                                item.activity
                                    .subtitle,
                          !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption2.bold())
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
        }
        .padding(11)
        .background(
            Color.white.opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }
}

private enum HomeFollowingWorkoutPresentation {
    static func activity(
        for item: SocialFeedItem
    ) -> WorkoutActivity {
        let raw =
            item.activity
                .metadata?["kind"] ??
            ""

        if let exact =
                WorkoutActivity(
                    rawValue: raw
                ) {
            return exact
        }

        switch raw.lowercased() {
        case "run",
             "running":
            return .running
        case "walk",
             "walking":
            return .walking
        case "hike",
             "hiking":
            return .hiking
        case "strength",
             "functional":
            return .strength
        case "cycling",
             "cycle":
            return .cycling
        case "hiit":
            return .hiit
        case "rowing":
            return .rowing
        case "yoga":
            return .yoga
        default:
            return .other
        }
    }

    static func distanceText(
        for item: SocialFeedItem
    ) -> String? {
        guard let raw =
                item.activity
                    .metadata?[
                        "distance_meters"
                    ],
              let meters =
                Double(raw),
              meters > 0
        else {
            return nil
        }

        return String(
            format: "%.2f km",
            meters / 1_000
        )
    }

    static func durationText(
        for item: SocialFeedItem
    ) -> String? {
        guard let raw =
                item.activity
                    .metadata?[
                        "duration_seconds"
                    ],
              let seconds =
                Double(raw),
              seconds > 0
        else {
            return nil
        }

        let minutes =
            Int(
                (
                    seconds / 60
                )
                .rounded()
            )

        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }

        return "\(minutes) min"
    }

    static func strengthDetailText(
        for item: SocialFeedItem
    ) -> String? {
        let metadata =
            item.activity.metadata

        if let groups =
                metadata?["muscle_groups"],
           !groups.isEmpty {
            var titles: [String] = []

            for raw in
                groups
                    .split(
                        separator: "|"
                    )
                    .map(String.init) {
                let regions =
                    StrengthMuscleResolver
                        .regions(
                            for: raw
                        )

                if regions.isEmpty {
                    let clean =
                        raw.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    if !clean.isEmpty,
                       !titles.contains(clean) {
                        titles.append(clean)
                    }
                } else {
                    for region in regions {
                        let title =
                            region
                                .activityDisplayTitle

                        if !titles.contains(
                            title
                        ) {
                            titles.append(
                                title
                            )
                        }
                    }
                }

                if titles.count >= 4 {
                    break
                }
            }

            if !titles.isEmpty {
                return titles
                    .prefix(4)
                    .joined(
                        separator: " · "
                    )
            }
        }

        if let raw =
                metadata?["exercise_count"],
           let count = Int(raw),
           count > 0 {
            return ATHLTHLocalization
                .counted(
                    count,
                    englishSingular:
                        "exercise",
                    englishPlural:
                        "exercises",
                    norwegianSingular:
                        "øvelse",
                    norwegianPlural:
                        "øvelser"
                )
        }

        return nil
    }

    static func volumeText(
        for item: SocialFeedItem
    ) -> String? {
        guard let raw =
                item.activity
                    .metadata?[
                        "volume_kg"
                    ],
              let value =
                Double(raw),
              value > 0
        else {
            return nil
        }

        if value >= 1_000 {
            return String(
                format: "%.1f t",
                value / 1_000
            )
        }

        return String(
            format: "%.0f kg",
            value
        )
    }
}

private struct HomeFollowingWorkoutArtwork:
    View {
    let item: SocialFeedItem
    let activity: WorkoutActivity
    let height: CGFloat

    private var strengthMuscleProfile:
        StrengthMuscleProfile {
        guard activity == .strength,
              let raw =
                item.activity
                    .metadata?["muscle_groups"],
              !raw.isEmpty
        else {
            return .empty
        }

        var scores:
            [StrengthMuscleRegion: Double] =
                [:]

        for muscle in
            raw.split(separator: "|") {
            let regions =
                StrengthMuscleResolver
                    .regions(
                        for:
                            String(muscle)
                    )

            for region in regions {
                scores[
                    region,
                    default: 0
                ] += 1
            }
        }

        return StrengthMuscleProfile(
            activations:
                scores.map {
                    StrengthMuscleActivation(
                        region: $0.key,
                        score: $0.value
                    )
                }
        )
    }

    var body: some View {
        Group {
            if activity == .strength {
                HomeStrengthMuscleArtwork(
                    profile:
                        strengthMuscleProfile,
                    height: height
                )
            } else {
                genericArtwork
            }
        }
        .frame(height: height)
        .clipped()
    }

    private var genericArtwork:
        some View {
        ZStack {
            LinearGradient(
                colors: artworkColors,
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )

            Image(
                systemName:
                    activity.icon
            )
            .font(
                .system(
                    size:
                        min(
                            height * 0.68,
                            104
                        ),
                    weight: .medium
                )
            )
            .symbolRenderingMode(
                .hierarchical
            )
            .foregroundStyle(
                Color.white.opacity(
                    0.16
                )
            )
            .offset(x: 92)

            LinearGradient(
                colors: [
                    Color.black.opacity(
                        0.02
                    ),
                    Color.black.opacity(
                        0.30
                    )
                ],
                startPoint:
                    .top,
                endPoint:
                    .bottom
            )
        }
    }

    private var artworkColors:
        [Color] {
        [
            ATHLTHTheme.accentDeep,
            Color(
                red: 0.05,
                green: 0.13,
                blue: 0.12
            )
        ]
    }
}


// MARK: - See all

struct HomePersonalActivityHistoryView:
    View {
    @EnvironmentObject private var health:
        HealthKitManager
    @EnvironmentObject private var strength:
        StrengthWorkoutStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    @EnvironmentObject private var social:
        SocialStore

    @State private var myWorkouts:
        [SocialPublishableWorkout] = []
    @State private var scope:
        HomeActivityScopeFilter
    @State private var type:
        HomeActivityTypeFilter = .all
    @State private var loading = false
    private let showOnlyMine: Bool

    init(
        showOnlyMine: Bool = false
    ) {
        self.showOnlyMine = showOnlyMine
        _scope = State(
            initialValue:
                showOnlyMine
                    ? .mine
                    : .all
        )
    }

    private var allItems:
        [HomeActivityStreamItem] {
        HomeActivityStreamBuilder.make(
            mine: myWorkouts,
            social: social
        )
    }

    private var filtered:
        [HomeActivityStreamItem] {
        allItems.filter { item in
            let scopeMatch: Bool

            if showOnlyMine {
                scopeMatch = item.isMine
            } else {
                switch scope {
                case .all:
                    scopeMatch = true
                case .mine:
                    scopeMatch =
                        item.isMine
                case .following:
                    scopeMatch =
                        !item.isMine
                }
            }

            return scopeMatch &&
                type.includes(
                    item.activity
                )
        }
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.17)
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(
                    spacing: 14
                ) {
                    if !showOnlyMine {
                        scopeBar
                    }
                    typeBar

                    if loading &&
                        myWorkouts.isEmpty {
                        ProgressView()
                            .padding(
                                .vertical,
                                60
                            )
                    } else if filtered.isEmpty {
                        emptyHistory
                    } else {
                        ForEach(filtered) {
                            item in
                            historyItem(item)
                        }
                    }
                }
                .padding(
                    .horizontal,
                    16
                )
                .padding(
                    .top,
                    10
                )
                .padding(
                    .bottom,
                    28
                )
                .frame(maxWidth: 820)
                .frame(
                    maxWidth: .infinity
                )
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Activity Log",
                norwegian:
                    "Aktivitetslogg"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .toolbarBackground(
            .hidden,
            for: .navigationBar
        )
        .task {
            await load()

            if !showOnlyMine {
                await social
                    .refreshActivityHistoryFeed()
            }
        }
        .refreshable {
            await load(
                forceRefresh: true
            )

            if !showOnlyMine {
                await social
                    .refreshActivityHistoryFeed()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    HomeActivityVisibilityStore
                        .changed
            )
        ) { _ in
            Task {
                await load()
            }
        }
    }

    @ViewBuilder
    private func historyItem(
        _ item:
            HomeActivityStreamItem
    ) -> some View {
        switch item.source {
        case .mine(let workout):
            NavigationLink {
                HomePersonalActivityDestination(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout(
                            for: workout
                        )
                )
            } label: {
                HomePersonalHistoryCard(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout(
                            for: workout
                        ),
                    phoneWorkout:
                        localPhoneWorkout(
                            for: workout
                        )
                )
            }
            .buttonStyle(.plain)

        case .following(let socialItem):
            HomeFollowingSocialFeedCard(
                item: socialItem
            )
        }
    }

    private var summaryHeader:
        some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "ACTIVITY",
                            norwegian:
                                "AKTIVITET"
                        )
                    )
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .tracking(1.7)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Your training circle",
                            norwegian:
                                "Din treningssirkel"
                        )
                    )
                    .font(
                        .title2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Your workouts plus shared sessions from people you follow.",
                            norwegian:
                                "Dine økter pluss delte økter fra de du følger."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "figure.run.circle.fill"
                )
                .font(.title2)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    width: 48,
                    height: 48
                )
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Circle()
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 9
            ) {
                summaryMetric(
                    "\(allItems.count)",
                    ATHLTHLocalization.choose(
                        english: "Activity",
                        norwegian: "Aktivitet"
                    )
                )

                summaryMetric(
                    "\(myWorkouts.count)",
                    ATHLTHLocalization.choose(
                        english: "Mine",
                        norwegian: "Mine"
                    )
                )

                summaryMetric(
                    "\(followingCount)",
                    ATHLTHLocalization.choose(
                        english: "Following",
                        norwegian: "Følger"
                    )
                )
            }
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(
                        0.96
                    ),
                    ATHLTHTheme.accentSoft
                        .opacity(0.56)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
        )
    }

    private var scopeBar:
        some View {
        HStack(spacing: 8) {
            ForEach(
                HomeActivityScopeFilter
                    .allCases
            ) { option in
                Button {
                    withAnimation(
                        .snappy(
                            duration: 0.22
                        )
                    ) {
                        scope = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(
                            systemName:
                                scopeIcon(
                                    option
                                )
                        )
                        .font(.caption)

                        Text(option.title)
                    }
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        scope == option
                            ? Color.white
                            : ATHLTHTheme
                                .primaryText
                    )
                    .frame(
                        maxWidth:
                            .infinity
                    )
                    .frame(height: 38)
                    .background(
                        scope == option
                            ? ATHLTHTheme
                                .accentDeep
                            : Color.white
                                .opacity(
                                    0.74
                                ),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                scope == option
                                    ? Color.clear
                                    : Color.black
                                        .opacity(
                                            0.045
                                        ),
                                lineWidth:
                                    0.8
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            Color.white.opacity(
                0.54
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
    }

    private var typeBar:
        some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 8) {
                ForEach(
                    HomeActivityTypeFilter
                        .allCases
                ) { option in
                    Button {
                        withAnimation(
                            .snappy(
                                duration: 0.22
                            )
                        ) {
                            type = option
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName:
                                    option
                                        .systemImage
                            )
                            .font(.caption)

                            Text(option.title)
                        }
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            type == option
                                ? Color.white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .padding(
                            .horizontal,
                            13
                        )
                        .frame(height: 36)
                        .background(
                            type == option
                                ? ATHLTHTheme
                                    .accentDeep
                                : Color.white
                                    .opacity(
                                        0.80
                                    ),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    type == option
                                        ? Color.clear
                                        : Color.black
                                            .opacity(
                                                0.045
                                            ),
                                    lineWidth:
                                        0.8
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(
                .horizontal,
                2
            )
        }
    }

    private func scopeIcon(
        _ option:
            HomeActivityScopeFilter
    ) -> String {
        switch option {
        case .all:
            return "square.stack.3d.up.fill"
        case .mine:
            return "person.crop.circle.fill"
        case .following:
            return "person.2.fill"
        }
    }

    private var emptyHistory:
        some View {
        ContentUnavailableView(
            ATHLTHLocalization.choose(
                english:
                    "No workouts here",
                norwegian:
                    "Ingen økter her"
            ),
            systemImage:
                "figure.run.circle",
            description:
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Try another filter, or complete a workout.",
                        norwegian:
                            "Prøv et annet filter, eller fullfør en økt."
                    )
                )
        )
        .padding(
            .vertical,
            48
        )
    }

    @MainActor
    private func load(
        forceRefresh: Bool = false
    ) async {
        loading = true
        defer {
            loading = false
        }

        if forceRefresh &&
            health
                .hasRequestedAuthorization {
            await health.refreshAll()
        }

        let healthSummaries:
            [WorkoutSummary]

        if health
            .hasRequestedAuthorization,
           let fetched =
                try? await health
                    .workoutHistory() {
            healthSummaries = fetched
        } else {
            healthSummaries =
                health.workouts
        }

        myWorkouts =
            HomePersonalWorkoutCatalog
                .merge(
                    healthSummaries:
                        healthSummaries,
                    strengthHistory:
                        strength
                            .workoutHistory,
                    phoneHistory:
                        phoneWorkout
                            .history,
                    excludedIDs:
                        HomeActivityVisibilityStore
                            .hiddenWorkoutIDs(
                                userID:
                                    social.currentUserID
                            )
                )
    }

    private func summaryMetric(
        _ value: String,
        _ title: String
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    .headline.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(
            .vertical,
            10
        )
        .background(
            Color.white.opacity(
                0.64
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
        )
    }

    private var followingCount:
        Int {
        allItems.filter {
            !$0.isMine
        }
        .count
    }

    private func strengthWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> StrengthWorkoutLog? {
        HomePersonalWorkoutCatalog
            .strengthWorkout(
                for: workout,
                in:
                    strength
                        .workoutHistory
            )
    }

    private func localPhoneWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> PhoneWorkout? {
        HomePersonalWorkoutCatalog
            .phoneWorkout(
                for: workout,
                in:
                    phoneWorkout
                        .history
            )
    }
}

// MARK: - Own history card

private struct HomePersonalHistoryCard:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    let phoneWorkout: PhoneWorkout?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomePersonalWorkoutVisual(
                workout: workout,
                strengthWorkout:
                    strengthWorkout,
                phoneWorkout:
                    phoneWorkout,
                height: 148
            )

            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "YOUR WORKOUT",
                                norwegian: "DIN ØKT"
                            )
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .tracking(1.1)
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )

                        Text(workout.title)
                            .font(
                                .title3.weight(
                                    .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                        Text(
                            workout.startDate
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Text(workout.source)
                        .font(
                            .caption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                        .padding(
                            .horizontal,
                            9
                        )
                        .frame(height: 27)
                        .background(
                            ATHLTHTheme
                                .accentSoft
                                .opacity(
                                    0.75
                                ),
                            in: Capsule()
                        )
                }

                metricRow

                if let strengthWorkout {
                    let names =
                        strengthWorkout
                            .exercises
                            .filter {
                                $0.isCompleted ||
                                $0.sets.contains(
                                    where: {
                                        $0.isCompleted
                                    }
                                )
                            }
                            .prefix(5)
                            .map {
                                $0.exercise.name
                            }

                    if !names.isEmpty {
                        Text(
                            names.joined(
                                separator: " · "
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                    }
                }
            }
            .padding(
                .horizontal,
                15
            )
            .padding(
                .vertical,
                14
            )
        }
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(
                        0.96
                    ),
                    ATHLTHTheme
                        .surfaceSage
                        .opacity(0.78)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
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
            .stroke(
                ATHLTHTheme
                    .vitality
                    .opacity(
                        0.07
                    ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.035
                ),
            radius: 12,
            y: 5
        )
    }

    private var metricRow:
        some View {
        HStack(spacing: 0) {
            historyMetric(
                ATHLTHLocalization.choose(
                    english: "Time",
                    norwegian: "Tid"
                ),
                durationText
            )

            divider

            if workout.activity ==
                .strength {
                historyMetric(
                    ATHLTHLocalization.choose(
                        english: "Exercises",
                        norwegian: "Øvelser"
                    ),
                    workout
                        .strengthExerciseCount
                        .map(String.init) ??
                    "—"
                )
            } else {
                historyMetric(
                    ATHLTHLocalization.choose(
                        english: "Distance",
                        norwegian: "Distanse"
                    ),
                    distanceText
                )
            }

            divider

            historyMetric(
                workout.activity ==
                    .strength
                    ? ATHLTHLocalization
                        .choose(
                            english: "Volume",
                            norwegian: "Volum"
                        )
                    : ATHLTHLocalization
                        .choose(
                            english: "Energy",
                            norwegian: "Energi"
                        ),
                tertiaryMetricText
            )
        }
    }

    private func historyMetric(
        _ title: String,
        _ value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(title.uppercased())
                .font(
                    .system(
                        size: 8.5,
                        weight: .bold
                    )
                )
                .tracking(0.8)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )

            Text(value)
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var divider:
        some View {
        Rectangle()
            .fill(
                ATHLTHTheme
                    .divider
                    .opacity(0.65)
            )
            .frame(
                width: 1,
                height: 28
            )
            .padding(
                .horizontal,
                10
            )
    }

    private var durationText:
        String {
        let minutes =
            max(
                Int(
                    (
                        workout.duration /
                        60
                    )
                    .rounded()
                ),
                0
            )

        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }

        return "\(minutes) min"
    }

    private var distanceText:
        String {
        guard let meters =
                workout.distanceMeters,
              meters > 0
        else {
            return "—"
        }

        return String(
            format: "%.2f km",
            meters / 1_000
        )
    }

    private var tertiaryMetricText:
        String {
        if workout.activity ==
            .strength,
           let volume =
                workout
                    .strengthTotalVolumeKilograms,
           volume > 0 {
            return volume >= 1_000
                ? String(
                    format: "%.1f t",
                    volume / 1_000
                )
                : String(
                    format: "%.0f kg",
                    volume
                )
        }

        if let calories =
                workout
                    .activeEnergyKilocalories,
           calories > 0 {
            return "\(Int(calories.rounded())) kcal"
        }

        return "—"
    }
}

// MARK: - Social activity feed card

private struct HomeFollowingSocialFeedCard: View {
    @EnvironmentObject private var social: SocialStore

    let item: SocialFeedItem

    @State private var commentText = ""
    @State private var showingComments = false

    private var activity: WorkoutActivity {
        HomeFollowingWorkoutPresentation
            .activity(for: item)
    }

    private var isLiked: Bool {
        guard let userID = social.currentUserID else {
            return false
        }
        return item.reactions.contains {
            $0.userID == userID &&
            $0.reaction == .heart
        }
    }

    private var caption: String? {
        let value =
            item.activity.metadata?["caption"] ??
            item.activity.metadata?["note"] ??
            item.activity.subtitle
        guard let value,
              !value.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            return nil
        }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                NavigationLink {
                    FriendProfileView(
                        userID: item.actor.userID
                    )
                } label: {
                    SocialAvatar(
                        profile: item.actor,
                        size: 42
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.actor.resolvedName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        item.activity.createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(14)

            NavigationLink {
                HomeFollowingWorkoutDetailView(
                    item: item
                )
            } label: {
                HomeFollowingWorkoutArtwork(
                    item: item,
                    activity: activity,
                    height: 190
                )
                .overlay(alignment: .bottomLeading) {
                    Label(
                        activityLabel,
                        systemImage: activity.icon
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        Color.black.opacity(0.30),
                        in: Capsule()
                    )
                    .padding(12)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 11) {
                Text(item.activity.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                metrics

                if let caption {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(3)
                }

                if item.reactions.count > 0 ||
                    item.comments.count > 0 {
                    HStack {
                        if item.reactions.count > 0 {
                            Text(
                                "\(item.reactions.count) " +
                                ATHLTHLocalization.choose(
                                    english: "likes",
                                    norwegian: "liker"
                                )
                            )
                        }

                        Spacer()

                        if item.comments.count > 0 {
                            Button {
                                showingComments = true
                            } label: {
                                Text(
                                    "\(item.comments.count) " +
                                    ATHLTHLocalization.choose(
                                        english: "comments",
                                        norwegian: "kommentarer"
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Divider().opacity(0.55)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await social.setReaction(
                                activityID: item.id,
                                reaction:
                                    isLiked ? nil : .heart
                            )
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Like",
                                norwegian: "Lik"
                            ),
                            systemImage:
                                isLiked
                                ? "heart.fill"
                                : "heart"
                        )
                        .foregroundStyle(
                            isLiked
                            ? Color.red
                            : ATHLTHTheme.primaryText
                        )
                    }

                    Button {
                        showingComments = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Comment",
                                norwegian: "Kommenter"
                            ),
                            systemImage: "bubble.left"
                        )
                    }

                    Spacer()

                    ShareLink(
                        item: item.activity.title
                    ) {
                        Image(
                            systemName:
                                "square.and.arrow.up"
                        )
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .buttonStyle(.plain)
            }
            .padding(14)
        }
        .background(
            Color.white.opacity(0.97),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .clipShape(
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
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.04),
            radius: 14,
            y: 6
        )
        .sheet(isPresented: $showingComments) {
            HomeActivityCommentsSheet(
                item: item
            )
        }
    }

    @ViewBuilder
    private var metrics: some View {
        HStack(spacing: 14) {
            if let distance =
                    HomeFollowingWorkoutPresentation
                        .distanceText(for: item) {
                Label(distance, systemImage: "ruler")
            }

            if let duration =
                    HomeFollowingWorkoutPresentation
                        .durationText(for: item) {
                Label(duration, systemImage: "clock")
            }

            if activity == .strength,
               let volume =
                    HomeFollowingWorkoutPresentation
                        .volumeText(for: item) {
                Label(volume, systemImage: "scalemass.fill")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(ATHLTHTheme.primaryText)
    }

    private var activityLabel: String {
        switch activity {
        case .running:
            return ATHLTHLocalization.choose(
                english: "RUN",
                norwegian: "LØP"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "STRENGTH",
                norwegian: "STYRKE"
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "WALK",
                norwegian: "GÅTUR"
            )
        default:
            return activity.rawValue.uppercased()
        }
    }
}

private struct HomeActivityCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore

    let item: SocialFeedItem
    @State private var text = ""

    private var currentItem: SocialFeedItem {
        social.feed.first(where: { $0.id == item.id }) ??
        item
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(currentItem.comments) { comment in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(comment.body)
                                        .font(.subheadline)
                                        .foregroundStyle(ATHLTHTheme.primaryText)

                                    Text(
                                        comment.createdAt,
                                        style: .relative
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                Color.black.opacity(0.025),
                                in: RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                        }
                    }
                    .padding(16)
                }

                HStack(spacing: 10) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Write a comment…",
                            norwegian: "Skriv en kommentar…"
                        ),
                        text: $text
                    )
                    .textFieldStyle(.plain)

                    Button {
                        let body =
                            text.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        guard !body.isEmpty else { return }
                        text = ""
                        Task {
                            await social.addComment(
                                activityID: item.id,
                                body: body
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Comments",
                    norwegian: "Kommentarer"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Following history card

private struct HomeFollowingHistoryCard:
    View {
    let item: SocialFeedItem

    private var activity:
        WorkoutActivity {
        HomeFollowingWorkoutPresentation
            .activity(for: item)
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomeFollowingWorkoutArtwork(
                item: item,
                activity: activity,
                height: 150
            )
            .overlay(
                alignment:
                    .bottomLeading
            ) {
                HStack(spacing: 10) {
                    SocialAvatar(
                        profile: item.actor,
                        size: 38
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            item.actor
                                .resolvedName
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .bold
                                )
                        )
                        .foregroundStyle(.white)

                        Text(
                            item.activity
                                .createdAt,
                            style: .relative
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            Color.white.opacity(
                                0.75
                            )
                        )
                    }
                }
                .padding(14)
            }

            VStack(
                alignment: .leading,
                spacing: 11
            ) {
                Text(
                    item.activity.title
                )
                .font(
                    .title3.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                HStack(spacing: 8) {
                    if let distance =
                            HomeFollowingWorkoutPresentation
                                .distanceText(
                                    for: item
                                ) {
                        socialMetric(
                            distance,
                            icon:
                                "ruler"
                        )
                    }

                    if let duration =
                            HomeFollowingWorkoutPresentation
                                .durationText(
                                    for: item
                                ) {
                        socialMetric(
                            duration,
                            icon:
                                "clock"
                        )
                    }

                    if activity == .strength,
                       let volume =
                            HomeFollowingWorkoutPresentation
                                .volumeText(
                                    for: item
                                ) {
                        socialMetric(
                            volume,
                            icon:
                                "scalemass.fill"
                        )
                    } else if let subtitle =
                                item.activity
                                    .subtitle,
                              !subtitle.isEmpty,
                              HomeFollowingWorkoutPresentation
                                .distanceText(
                                    for: item
                                ) == nil {
                        socialMetric(
                            subtitle,
                            icon:
                                activity.icon
                        )
                    }
                }

                if activity == .strength,
                   let strengthText =
                        HomeFollowingWorkoutPresentation
                            .strengthDetailText(
                                for: item
                            ) {
                    Text(strengthText)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                }
            }
            .padding(16)
        }
        .background(
            Color.white.opacity(0.96),
            in:
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(
                    0.04
                ),
                lineWidth: 0.8
            )
        }
    }

    private func socialMetric(
        _ text: String,
        icon: String
    ) -> some View {
        Label(
            text,
            systemImage: icon
        )
        .font(
            .caption.weight(
                .semibold
            )
        )
        .foregroundStyle(
            ATHLTHTheme.primaryText
        )
        .padding(
            .horizontal,
            9
        )
        .frame(height: 30)
        .background(
            Color.black.opacity(
                0.035
            ),
            in: Capsule()
        )
        .lineLimit(1)
    }
}

private struct HomeStrengthMuscleArtwork:
    View {
    let profile: StrengthMuscleProfile
    let height: CGFloat

    private let activationTint =
        Color(
            red: 0.93,
            green: 0.32,
            blue: 0.22
        )

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.992,
                            green: 0.988,
                            blue: 0.978
                        ),
                        Color(
                            red: 0.948,
                            green: 0.955,
                            blue: 0.958
                        )
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(spacing: 0) {
                    figureGlow
                    figureGlow
                }
                .frame(
                    width:
                        min(
                            proxy.size.width,
                            260
                        ),
                    height:
                        max(
                            height,
                            118
                        )
                )

                Rectangle()
                    .fill(
                        Color.black.opacity(
                            0.045
                        )
                    )
                    .frame(
                        width: 0.7,
                        height:
                            max(
                                height - 32,
                                80
                            )
                    )

                StrengthMuscleMapView(
                    profile: profile,
                    compact: true,
                    style: .activation,
                    presentation: .home,
                    activationTint:
                        activationTint
                )
                // Full-length figures with readable muscle detail.
                // Keep the lower feet clear of the front/back caption pills.
                .frame(
                    width: min(
                        max(height * 1.68, 184),
                        max(proxy.size.width - 12, 1)
                    ),
                    height: max(height - 26, 80)
                )
                .offset(y: -9)

                VStack {
                    Spacer()

                    HStack {
                        atlasLabel(
                            ATHLTHLocalization.choose(
                                english: "FRONT",
                                norwegian: "FORSIDE"
                            )
                        )

                        Spacer()

                        atlasLabel(
                            ATHLTHLocalization.choose(
                                english: "BACK",
                                norwegian: "BAKSIDE"
                            )
                        )
                    }
                    .frame(
                        width:
                            min(
                                proxy.size.width -
                                    64,
                                154
                            )
                    )
                    .padding(.bottom, 7)
                }

                LinearGradient(
                    colors: [
                        Color.white.opacity(
                            0.24
                        ),
                        Color.clear,
                        Color.black.opacity(
                            0.028
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .clipped()
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    private var figureGlow:
        some View {
        RadialGradient(
            colors: [
                activationTint.opacity(
                    0.14
                ),
                activationTint.opacity(
                    0.045
                ),
                Color.clear
            ],
            center: .center,
            startRadius: 3,
            endRadius: 76
        )
    }

    private func atlasLabel(
        _ text: String
    ) -> some View {
        Text(text)
            .font(
                .system(
                    size: 7.5,
                    weight: .bold
                )
            )
            .tracking(0.7)
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
                    .opacity(0.78)
            )
            .padding(
                .horizontal,
                7
            )
            .frame(height: 17)
            .background(
                Color.white.opacity(
                    0.74
                ),
                in: Capsule()
            )
    }
}

// MARK: - Rich own-workout visual

private struct HomePersonalWorkoutVisual:
    View {
    @EnvironmentObject private var health:
        HealthKitManager

    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    let phoneWorkout: PhoneWorkout?
    let height: CGFloat
    var precomputedStrengthProfile:
        StrengthMuscleProfile? = nil

    @State private var hasLoadedRoute = false
    @State private var routePreviewImage: UIImage?
    @State private var treadmillAverageHeartRate: Double?

    private var hasLocalRoute:
        Bool {
        (phoneWorkout?
            .points
            .count ?? 0) >= 2
    }

    private var muscleProfile:
        StrengthMuscleProfile {
        if let precomputedStrengthProfile {
            return precomputedStrengthProfile
        }
        if let strengthWorkout {
            let actual = StrengthMuscleProfileBuilder.make(
                workout: strengthWorkout,
                library: []
            ).profile
            if !actual.activations.isEmpty {
                return actual
            }
        }

        guard let groups =
                workout
                    .strengthMuscleGroups,
              !groups.isEmpty
        else {
            return .empty
        }

        var scores:
            [StrengthMuscleRegion: Double] =
                [:]

        for raw in groups {
            for region in
                StrengthMuscleResolver
                    .regions(
                        for: raw
                    ) {
                scores[
                    region,
                    default: 0
                ] += 1
            }
        }

        return StrengthMuscleProfile(
            activations:
                scores.map {
                    StrengthMuscleActivation(
                        region: $0.key,
                        score: $0.value
                    )
                }
        )
    }

    var body: some View {
        ZStack {
            background

            VStack {
                HStack {
                    Label(
                        activityLabel,
                        systemImage:
                            workout.activity.icon
                    )
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        workout.activity ==
                            .strength
                            ? Color(
                                red: 0.11,
                                green: 0.12,
                                blue: 0.13
                            )
                            : Color.white
                                .opacity(
                                    0.94
                                )
                    )
                    .padding(
                        .horizontal,
                        10
                    )
                    .frame(height: 30)
                    .background(
                        workout.activity ==
                            .strength
                            ? Color.white
                                .opacity(0.80)
                            : Color.black
                                .opacity(0.24),
                        in: Capsule()
                    )
                    .overlay {
                        if workout.activity ==
                            .strength {
                            Capsule()
                                .stroke(
                                    Color.black
                                        .opacity(
                                            0.055
                                        ),
                                    lineWidth:
                                        0.7
                                )
                        }
                    }

                    Spacer()
                }

                Spacer()
            }
            .padding(12)
        }
        .frame(height: height)
        .clipped()
        .task(id: workout.id) {
            await loadRoutePreviewIfNeeded()
            await loadTreadmillHeartRateIfNeeded()
        }
    }

    @ViewBuilder
    private var background:
        some View {
        if workout.activity == .running,
           workout.isIndoor == true {
            HomeTreadmillRecentArtwork(
                workout: workout,
                averageHeartRate: treadmillAverageHeartRate,
                height: height
            )
        } else if workout.activity ==
            .strength {
            strengthBackground
        } else if isOutdoorActivity,
                  (hasLocalRoute ||
                   hasLoadedRoute) {
            routeMap
        } else {
            genericBackground
        }
    }

    private var strengthBackground:
        some View {
        HomeStrengthMuscleArtwork(
            profile: muscleProfile,
            height: height
        )
    }

    private var routeMap:
        some View {
        ZStack {
            if let routePreviewImage {
                Image(uiImage: routePreviewImage)
                    .resizable()
                    .scaledToFill()
                    .athlthBoundedFill()
            } else {
                genericBackground
            }
        }
        .overlay {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.clear,
                    Color.black.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var genericBackground:
        some View {
        ZStack {
            LinearGradient(
                colors: [
                    visualAccent.opacity(
                        0.88
                    ),
                    Color(
                        red: 0.07,
                        green: 0.08,
                        blue: 0.10
                    )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )

            Image(
                systemName:
                    workout.activity.icon
            )
            .font(
                .system(
                    size:
                        min(
                            height * 0.56,
                            96
                        ),
                    weight: .medium
                )
            )
            .symbolRenderingMode(
                .hierarchical
            )
            .foregroundStyle(
                Color.white.opacity(
                    0.13
                )
            )
            .offset(x: 94)
        }
    }

    @MainActor
    private func loadRoutePreviewIfNeeded()
        async {
        guard isOutdoorActivity else {
            return
        }

        let route: [CLLocation]
        if let points =
                phoneWorkout?
                    .points,
           points.count >= 2 {
            route =
                points.map(\.location)
        } else {
            route = await health.workoutRoute(
                for: workout.id
            )
        }

        guard !Task.isCancelled else {
            return
        }

        hasLoadedRoute =
            route.count >= 2

        let coordinates =
            HomeActivityRouteSanitizer
                .sampledCoordinates(
                    from: route,
                    maximumCount: 96
                )

        guard coordinates.count >= 2 else {
            return
        }

        let rendered =
            await HomeActivityRouteSnapshotRendererV2
                .shared
                .image(
                    coordinates: coordinates
                )

        guard !Task.isCancelled else {
            return
        }

        routePreviewImage = rendered
    }

    @MainActor
    private func loadTreadmillHeartRateIfNeeded() async {
        guard workout.activity == .running,
              workout.isIndoor == true else {
            treadmillAverageHeartRate = nil
            return
        }
        // Optional: show a heart-rate value only when HealthKit has one.
        // Never substitute the numbers from the design illustration.
        let detail = await health.workoutDetail(for: workout.id)
        guard !Task.isCancelled else { return }
        let value = detail.averageHeartRate
        treadmillAverageHeartRate =
            (value?.isFinite == true && (value ?? 0) > 0)
                ? value
                : nil
    }

    private var isOutdoorActivity:
        Bool {
        guard workout.isIndoor != true else { return false }
        switch workout.activity {
        case .running,
             .walking,
             .cycling,
             .hiking:
            return true
        default:
            return false
        }
    }

    private var activityLabel:
        String {
        switch workout.activity {
        case .running:
            return workout.isIndoor == true
                ? ATHLTHLocalization.choose(
                    english: "TREADMILL",
                    norwegian: "TREDEMØLLE"
                )
                : ATHLTHLocalization.choose(
                    english: "RUN",
                    norwegian: "LØP"
                )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "WALK",
                norwegian: "GÅTUR"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "STRENGTH",
                norwegian: "STYRKE"
            )
        default:
            return workout
                .activity
                .rawValue
                .uppercased()
        }
    }

    private var visualAccent:
        Color {
        switch workout.activity {
        case .running,
             .walking,
             .hiking:
            return ATHLTHTheme.vitality
        case .strength:
            return ATHLTHTheme.premiumGold
        default:
            return ATHLTHTheme.accentDeep
        }
    }


}

// MARK: - Destinations

private struct HomePersonalActivityDestination:
    View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var strength:
        StrengthWorkoutStore
    @EnvironmentObject private var phoneWorkoutStore:
        IPhoneWorkoutStore
    @EnvironmentObject private var social:
        SocialStore

    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    var phoneWorkout: PhoneWorkout? = nil

    @State private var showingDeleteConfirmation =
        false

    var body: some View {
        Group {
            switch workout.activity {
            case .running,
                 .walking,
                 .hiking:
                HomeActivityRunDetailView(
                    workout: workout,
                    initialDetail: nil,
                    initialAIInsight:
                        nil
                )

            case .strength:
                HomeActivityStrengthDetailView(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout
                )

            default:
                WorkoutHistoryDetailView(
                    workout: workout
                )
            }
        }
        .toolbar {
            ToolbarItem(
                placement:
                    .topBarTrailing
            ) {
                Menu {
                    Button(
                        role: .destructive
                    ) {
                        showingDeleteConfirmation =
                            true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Remove from ATHLTH",
                                norwegian:
                                    "Fjern fra ATHLTH"
                            ),
                            systemImage:
                                "trash"
                        )
                    }
                } label: {
                    Image(
                        systemName:
                            "ellipsis.circle"
                    )
                }
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english:
                            "Workout options",
                        norwegian:
                            "Valg for økten"
                    )
                )
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english:
                    "Remove this workout from ATHLTH?",
                norwegian:
                    "Fjerne denne økten fra ATHLTH?"
            ),
            isPresented:
                $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english:
                        "Remove from ATHLTH",
                    norwegian:
                        "Fjern fra ATHLTH"
                ),
                role: .destructive
            ) {
                removeFromATHLTH()
            }

            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel",
                    norwegian: "Avbryt"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "The workout disappears from ATHLTH. Apple Health data is not deleted.",
                    norwegian:
                        "Økten forsvinner fra ATHLTH. Data i Apple Health blir ikke slettet."
                )
            )
        }
    }

    private var relatedWorkoutIDs:
        Set<UUID> {
        var ids: Set<UUID> = [
            workout.id
        ]

        if let strengthWorkout {
            ids.insert(
                strengthWorkout.id
            )
            if let healthID =
                    strengthWorkout
                        .healthMetrics
                        .healthKitWorkoutUUID {
                ids.insert(healthID)
            }
        }

        if let phoneWorkout {
            ids.insert(
                phoneWorkout.id
            )
            if let healthID =
                    phoneWorkout.healthID {
                ids.insert(healthID)
            }
        }

        return ids
    }

    private func removeFromATHLTH() {
        let ids = relatedWorkoutIDs

        HomeActivityVisibilityStore.hide(
            ids,
            userID:
                social.currentUserID
        )

        strength.removeWorkoutFromHistory(
            matching: ids
        )
        phoneWorkoutStore
            .removeWorkoutFromHistory(
                matching: ids
            )

        Task {
            await social
                .deleteWorkoutActivities(
                    matching: ids
                )
        }

        dismiss()
    }
}

private struct HomeFollowingWorkoutDetailView:
    View {
    let item: SocialFeedItem

    private var activity:
        WorkoutActivity {
        HomeFollowingWorkoutPresentation
            .activity(for: item)
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.accent
                        .opacity(0.12)
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    HomeFollowingWorkoutArtwork(
                        item: item,
                        activity: activity,
                        height: 210
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 28,
                            style:
                                .continuous
                        )
                    )
                    .overlay(
                        alignment:
                            .bottomLeading
                    ) {
                        HStack(spacing: 11) {
                            SocialAvatar(
                                profile:
                                    item.actor,
                                size: 46
                            )

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 2
                            ) {
                                Text(
                                    item.actor
                                        .resolvedName
                                )
                                .font(
                                    .headline
                                        .weight(
                                            .bold
                                        )
                                )
                                .foregroundStyle(
                                    .white
                                )

                                Text(
                                    item.activity
                                        .createdAt,
                                    style:
                                        .relative
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    Color.white
                                        .opacity(
                                            0.76
                                        )
                                )
                            }
                        }
                        .padding(16)
                    }

                    ATHLTHCard {
                        VStack(
                            alignment: .leading,
                            spacing: 12
                        ) {
                            Label(
                                activity.rawValue,
                                systemImage:
                                    activity.icon
                            )
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )

                            Text(
                                item.activity.title
                            )
                            .font(
                                .title2.weight(
                                    .bold
                                )
                            )

                            if let subtitle =
                                    item.activity
                                        .subtitle,
                               !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(
                                        .subheadline
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                            }

                            HStack(spacing: 10) {
                                if let distance =
                                        HomeFollowingWorkoutPresentation
                                            .distanceText(
                                                for:
                                                    item
                                            ) {
                                    detailMetric(
                                        distance,
                                        icon:
                                            "ruler"
                                    )
                                }

                                if let duration =
                                        HomeFollowingWorkoutPresentation
                                            .durationText(
                                                for:
                                                    item
                                            ) {
                                    detailMetric(
                                        duration,
                                        icon:
                                            "clock"
                                    )
                                }

                                if activity == .strength,
                                   let volume =
                                        HomeFollowingWorkoutPresentation
                                            .volumeText(
                                                for:
                                                    item
                                            ) {
                                    detailMetric(
                                        volume,
                                        icon:
                                            "scalemass.fill"
                                    )
                                }
                            }

                            if activity == .strength,
                               let strengthText =
                                    HomeFollowingWorkoutPresentation
                                        .strengthDetailText(
                                            for: item
                                        ) {
                                Text(strengthText)
                                    .font(
                                        .subheadline
                                            .weight(
                                                .medium
                                            )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                            }
                        }
                    }

                    ATHLTHCard {
                        HStack(spacing: 12) {
                            Image(
                                systemName:
                                    activity ==
                                    .running
                                    ? "map.fill"
                                    : "person.crop.circle"
                            )
                            .font(.title3)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    activity ==
                                    .running
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Route privacy",
                                        norwegian:
                                            "Rutepersonvern"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Shared workout",
                                        norwegian:
                                            "Delt økt"
                                    )
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Only workout data this athlete chose to publish is shown here.",
                                        norwegian:
                                            "Her vises bare treningsdata brukeren har valgt å dele."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }

                            Spacer()
                        }
                    }

                    let sharedRoute = WorkoutRouteSharing.decode(item.activity.metadata?["route_preview"])
                    if !sharedRoute.isEmpty {
                        WorkoutRouteSharePreview(coordinates: sharedRoute)
                    }

                    NavigationLink {
                        FriendProfileView(
                            userID:
                                item.actor
                                    .userID
                        )
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Open profile",
                                norwegian:
                                    "Åpne profil"
                            ),
                            systemImage:
                                "person.crop.circle"
                        )
                        .font(
                            .headline.weight(
                                .semibold
                            )
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .tint(
                        ATHLTHTheme.accentDeep
                    )
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(
                    maxWidth: .infinity
                )
            }
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Workout",
                norwegian: "Økt"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private func detailMetric(
        _ text: String,
        icon: String
    ) -> some View {
        Label(
            text,
            systemImage: icon
        )
        .font(
            .caption.weight(
                .semibold
            )
        )
        .padding(
            .horizontal,
            10
        )
        .frame(height: 32)
        .background(
            ATHLTHTheme.accentSoft,
            in: Capsule()
        )
    }
}
