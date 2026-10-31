import CoreLocation
import Combine
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

// Small, low-cost Home presence strip. Uses the same server-authorized
// mutual-follow status and avatar indicators as the rest of ATHLTH.
struct HomeActiveFriendsStrip: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var lastKnownFriends: [SocialProfileCard] = []
    @State private var cachedForUserID: UUID?
    @State private var selectedFriendID: UUID?
    @State private var destination: FriendQuickDestination?
    @State private var challengeFriend: SocialProfileCard?
    @State private var trainTogetherFriend: SocialProfileCard?
    @State private var shareRequest: ATHLTHFriendQuickShareRequest?

    private enum FriendQuickDestination: Hashable {
        case message(SocialProfileCard)
        case profile(UUID)
    }

    private enum FriendQuickAction {
        case message(SocialProfileCard)
        case challenge(SocialProfileCard)
        case trainTogether(SocialProfileCard)
        case share(SocialProfileCard, ATHLTHFriendQuickShareKind)
        case profile(UUID)
    }

    private func openAction(_ action: FriendQuickAction) {
        // Dismiss the anchored popover before presenting another destination
        // so iOS never attempts to present two layers at the same time.
        selectedFriendID = nil
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            switch action {
            case .message(let friend):
                destination = .message(friend)
            case .challenge(let friend):
                challengeFriend = friend
            case .trainTogether(let friend):
                trainTogetherFriend = friend
            case .share(let friend, let kind):
                shareRequest = ATHLTHFriendQuickShareRequest(
                    friend: friend, kind: kind
                )
            case .profile(let userID):
                destination = .profile(userID)
            }
        }
    }

    private struct RankedFriend {
        let profile: SocialProfileCard
        let training: Bool
        let online: Bool
        let affinity: Int
    }

    private var visibleFriends: [SocialProfileCard] {
        let current = orderedFriends
        if !current.isEmpty { return current }
        // Keep existing avatars in place during a transient social refresh.
        // Never reuse them across accounts or after a completed empty refresh.
        if social.isRefreshing && cachedForUserID == social.currentUserID {
            return lastKnownFriends.filter { !social.isMuted($0.userID) }
        }
        return []
    }

    private var orderedFriends: [SocialProfileCard] {
        // Compute each person's interaction score once per refresh, instead
        // of re-scanning messages during every sorting comparison.
        social.mutualFollows
            .filter { !social.isMuted($0.userID) }
            .map { friend in
                RankedFriend(
                    profile: friend,
                    training: realtime.isTrainingNow(friend.userID),
                    online: realtime.isOnline(friend.userID),
                    affinity: affinity(for: friend.userID)
                )
            }
            .sorted { lhs, rhs in
                if lhs.training != rhs.training { return lhs.training }
                if lhs.online != rhs.online { return lhs.online }
                if lhs.affinity != rhs.affinity {
                    return lhs.affinity > rhs.affinity
                }
                return lhs.profile.resolvedName.localizedStandardCompare(
                    rhs.profile.resolvedName
                ) == .orderedAscending
            }
            .map(\.profile)
    }

    // Only use interactions already authorized for this signed-in user.
    // Pinned conversations, recent messages and engagement are tie-breakers,
    // never a replacement for actual live training/online presence.
    private func affinity(for userID: UUID) -> Int {
        let pinned = messaging.conversation(with: userID).map {
            messaging.pinnedConversationIDs.contains($0.id)
        } ?? false
        let messages = messaging.recentMessages.filter {
            $0.deletedAt == nil &&
            ($0.senderID == userID || $0.recipientID == userID)
        }
        let fresh = messages.contains {
            $0.createdAt >= Date().addingTimeInterval(-14 * 86_400)
        }
        let engaged = social.feed.prefix(80).filter {
            $0.actor.userID == userID &&
            ($0.reactions.contains { $0.userID == social.currentUserID } ||
             $0.comments.contains { $0.userID == social.currentUserID })
        }.count

        return (pinned ? 50 : 0)
            + min(messages.count, 30) * 2
            + (fresh ? 8 : 0)
            + min(engaged, 10) * 3
    }

    private var activeCount: Int {
        visibleFriends.filter {
            realtime.isTrainingNow($0.userID) ||
            realtime.isOnline($0.userID)
        }.count
    }

    var body: some View {
        if !visibleFriends.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "Friends", norwegian: "Venner"
                    ))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    if activeCount > 0 {
                        Text(ATHLTHLocalization.choose(
                            english: "\(activeCount) active",
                            norwegian: "\(activeCount) aktive"
                        ))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(visibleFriends) { friend in
                            Button {
                                selectedFriendID = friend.userID
                            } label: {
                                VStack(spacing: 3) {
                                    ATHLTHSocialStatusAvatar(
                                        profile: friend, size: 43
                                    )
                                    .frame(width: 52, height: 52)

                                    Text(friend.resolvedName
                                        .components(separatedBy: " ")
                                        .first ?? friend.resolvedName)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                        .lineLimit(1)
                                }
                                .frame(width: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Show quick actions",
                                norwegian: "Vis hurtighandlinger"
                            ))
                            .popover(
                                isPresented: Binding(
                                    get: {
                                        selectedFriendID == friend.userID
                                    },
                                    set: { presented in
                                        if !presented &&
                                           selectedFriendID == friend.userID {
                                            selectedFriendID = nil
                                        }
                                    }
                                ),
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .bottom
                            ) {
                                HomeFriendQuickActionsPopover(
                                    friend: friend,
                                    isTraining: realtime.isTrainingNow(friend.userID),
                                    isOnline: realtime.isOnline(friend.userID),
                                    onMessage: {
                                        openAction(.message(friend))
                                    },
                                    onChallenge: {
                                        openAction(.challenge(friend))
                                    },
                                    onProfile: {
                                        openAction(.profile(friend.userID))
                                    },
                                    onTrainTogether: {
                                        openAction(.trainTogether(friend))
                                    },
                                    onShare: { kind in
                                        openAction(.share(friend, kind))
                                    }
                                )
                                .presentationCompactAdaptation(.popover)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.top, 2)
            .onAppear { rememberFriends() }
            .onChange(of: social.mutualFollows.map(\.userID)) { _, _ in
                rememberFriends()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                // Low-frequency refresh only while this strip is mounted.
                // No synthetic online status if the server data is stale.
                while !Task.isCancelled {
                    await realtime.refreshOnlineUsers()
                    do {
                        try await Task.sleep(for: .seconds(90))
                    } catch {
                        break
                    }
                }
            }
            .navigationDestination(item: $destination) { destination in
        switch destination {
        case .message(let friend):
            DirectMessageThreadView(friend: friend)
        case .profile(let userID):
            FriendProfileView(userID: userID)
        }
    }
            .sheet(item: $challengeFriend) { friend in
                ChallengeCreationView(preselectedFriends: [friend])
            }
            .sheet(item: $trainTogetherFriend) { friend in
                // Reuse Plan's real invitation editor. Its send action
                // creates a version-2 workout invite with the partner fixed.
                SessionEditorView(
                    standaloneDate: Date(),
                    partnerID: friend.userID,
                    physicalMeetup: true
                )
            }
            .sheet(item: $shareRequest) { request in
                ATHLTHFriendQuickShareFlow(request: request)
            }
        } else if social.isRefreshing {
            HStack(spacing: 8) {
                Text(ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner"))
                    .font(.system(size: 14, weight: .bold))
                Spacer(minLength: 0)
                ProgressView().controlSize(.small)
            }
            .foregroundStyle(ATHLTHTheme.mutedText)
            .frame(height: 75, alignment: .top)
            .padding(.top, 2)
        }
    }

    private func rememberFriends() {
        let current = orderedFriends
        if !current.isEmpty {
            lastKnownFriends = current
            cachedForUserID = social.currentUserID
        } else if !social.isRefreshing {
            lastKnownFriends = []
            cachedForUserID = nil
        }
    }
}

/// An anchored, compact friend card; secondary actions launch existing
/// invitation and messaging flows rather than expanding this popover.
private struct HomeFriendQuickActionsPopover: View {
    @EnvironmentObject private var social: SocialStore

    let friend: SocialProfileCard
    let isTraining: Bool
    let isOnline: Bool
    let onMessage: () -> Void
    let onChallenge: () -> Void
    let onProfile: () -> Void
    let onTrainTogether: () -> Void
    let onShare: (ATHLTHFriendQuickShareKind) -> Void

    @State private var performance: SocialPerformanceStats?
    @State private var followOverview: SocialFollowOverview?

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var status: String {
        if isTraining { return tr("Training now", "Trener nå") }
        if isOnline { return tr("Online", "Pålogget") }
        return tr("Friend", "Venn")
    }

    private var statusColor: Color {
        if isTraining { return .orange }
        if isOnline { return .green }
        return ATHLTHTheme.premiumGold
    }

    var body: some View {
        VStack(spacing: 12) {
            // Name AND portrait lead directly to the athlete's real profile.
            Button(action: onProfile) {
                HStack(spacing: 10) {
                    ATHLTHSocialStatusAvatar(profile: friend, size: 48)
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(friend.resolvedName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        if !friend.usernameLabel.isEmpty {
                            Text(friend.usernameLabel)
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                tr("Open profile for", "Åpne profilen til") + " " + friend.resolvedName
            )

            if performance != nil || followOverview != nil {
                HStack(spacing: 0) {
                    stat(
                        performance.map { $0.totalWorkoutCount.formatted() } ?? "—",
                        title: tr("Workouts", "Økter")
                    )
                    statDivider
                    stat(
                        followOverview.map { $0.followerCount.formatted() } ?? "—",
                        title: tr("Followers", "Følgere")
                    )
                    statDivider
                    stat(
                        followOverview.map { $0.followingCount.formatted() } ?? "—",
                        title: tr("Following", "Følger")
                    )
                }
                .padding(.vertical, 3)
            }

            Rectangle()
                .fill(ATHLTHPlanDesign.accentInk.opacity(0.12))
                .frame(height: 0.5)

            HStack(spacing: 8) {
                mainAction(tr("Message", "Melding"),
                           icon: "bubble.left", action: onMessage)
                mainAction(tr("Challenge", "Utfordre"),
                           icon: "trophy", action: onChallenge)
                mainAction(tr("Train Together", "Tren sammen"),
                           icon: "figure.run", action: onTrainTogether)
            }

            Rectangle()
                .fill(ATHLTHPlanDesign.accentInk.opacity(0.12))
                .frame(height: 0.5)

            HStack(spacing: 6) {
                shareAction(tr("Share plan", "Del plan"),
                            icon: "calendar") { onShare(.plan) }
                shareAction(tr("Send workout", "Send treningsøkt"),
                            icon: "dumbbell") { onShare(.workout) }
                shareAction(tr("Send route", "Send rute"),
                            icon: "point.topleft.down.to.point.bottomright.curvepath") {
                    onShare(.route)
                }
                shareAction(tr("Send exercise", "Send øvelse"),
                            icon: "figure.strengthtraining.traditional") {
                    onShare(.exercise)
                }
            }
        }
        .padding(14)
        .frame(width: 328)
        .background(
            Color(red: 0.995, green: 0.99, blue: 0.978),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .presentationBackground(.clear)
        .task(id: friend.userID) {
            async let loadedProfile = social.loadFriendProfile(friend.userID)
            async let loadedFollows = social.loadFollowOverview(for: friend.userID)
            let loaded = await loadedProfile
            let follows = await loadedFollows
            guard !Task.isCancelled else { return }
            performance = loaded?.performance
            followOverview = follows
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(ATHLTHPlanDesign.accentInk.opacity(0.14))
            .frame(width: 0.5, height: 28)
    }

    private func stat(_ value: String, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func mainAction(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 33, height: 33)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 69)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func shareAction(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 63)
            .background(
                ATHLTHPlanDesign.selectedSurface.opacity(0.75),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct HomePersonalRecentActivitySection:
    View {
    @Environment(\.scenePhase) private var scenePhase
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
                            .frame(width: 252)
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
        .task {
            await refreshRecentWorkouts()
        }
        .onAppear {
            // Returning from Activity Log may not create a new Home view;
            // refresh the existing section as it becomes visible again.
            Task { await refreshRecentWorkouts() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshRecentWorkouts() }
        }
        .onReceive(health.$workouts) { _ in
            // A HealthKit read may finish without changing the number of
            // workouts; don't rely exclusively on the old revision key.
            rebuildRecentWorkouts()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .athlthTrainingDataDidChange
            )
        ) { _ in
            rebuildRecentWorkouts()
            Task { await refreshRecentWorkouts(force: true) }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    HomeActivityVisibilityStore
                        .changed
            )
            .receive(on: DispatchQueue.main)
        ) { _ in
            rebuildRecentWorkouts()
        }
    }

    @MainActor
    private func refreshRecentWorkouts(force: Bool = false) async {
        guard scenePhase == .active else { return }
        // A narrow workout-only Health query is much cheaper than
        // refreshAll(), which also fetches sleep, readiness, HRV, etc.
        _ = await health.refreshRecentWorkoutsForHome(force: force)
        rebuildRecentWorkouts()
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
        HStack(alignment: .center, spacing: 12) {
            Text(
                ATHLTHLocalization.choose(
                    english: "Recent activity",
                    norwegian: "Siste aktivitet"
                )
            )
            .font(.headline.weight(.bold))
            .foregroundStyle(ATHLTHTheme.primaryText)

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
        _ item: HomeActivityStreamItem
    ) -> some View {
        // One shared outer card keeps the engagement actions separate from
        // the profile and activity navigation targets.
        VStack(spacing: 0) {
            switch item.source {
            case .mine(let workout):
                HomePersonalHorizontalWorkoutCard(
                    workout: workout,
                    strengthWorkout: strengthWorkout(for: workout),
                    phoneWorkout: localPhoneWorkout(for: workout)
                )
                HomeCompactActivityEngagementRow(
                    item: socialFeedItem(for: workout)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            case .following(let socialItem):
                HomeFollowingHorizontalWorkoutCard(item: socialItem)
                HomeCompactActivityEngagementRow(item: socialItem)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Color.white.opacity(0.98),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
                .allowsHitTesting(false)
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
        // The social strength publisher posts StrengthWorkoutLog.id,
        // while the personal history prefers its HealthKit UUID. Include
        // both IDs: otherwise the published strength post looks unlikable.
        let IDs = HomeSocialWorkoutIdentity.allIDs(
            visibleWorkoutID: workout.id,
            originalStrengthID: strengthWorkout(for: workout)?.id,
            originalPhoneID: localPhoneWorkout(for: workout)?.id
        )

        return social.feed.first { item in
            HomeSocialWorkoutIdentity.matches(
                item: item,
                ownerID: social.currentUserID,
                workoutIDs: IDs
            )
        }
    }
}

/// Published workout IDs do not necessarily equal HealthKit UUIDs.
/// Keep this mapping shared across running, strength and phone recording.
enum HomeSocialWorkoutIdentity {
    static func allIDs(
        visibleWorkoutID: UUID,
        originalStrengthID: UUID?,
        originalPhoneID: UUID?
    ) -> Set<String> {
        Set([visibleWorkoutID, originalStrengthID, originalPhoneID]
            .compactMap { $0?.uuidString.lowercased() })
    }

    static func matches(
        item: SocialFeedItem,
        ownerID: UUID?,
        workoutIDs: Set<String>
    ) -> Bool {
        guard item.activity.actorID == ownerID,
              item.activity.kind == "workout" else { return false }
        if let metadataID = item.activity.metadata?["workout_id"]?.lowercased(),
           workoutIDs.contains(metadataID) { return true }
        guard let eventKey = item.activity.eventKey?.lowercased() else {
            return false
        }
        return workoutIDs.contains {
            eventKey == "workout-\($0)" ||
            eventKey == "strength-workout-\($0)"
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

    @EnvironmentObject private var session: AppSessionStore

    private var isStrength: Bool { workout.activity == .strength }

    @ViewBuilder
    private var ownAvatar: some View {
        Group {
            if let url = session.profile.avatarURL {
                ATHLTHStorageImage(url: url, maxPixelSize: 144) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(ATHLTHTheme.accent.opacity(0.30), lineWidth: 1)
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Text(session.profile.displayName.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
    }

    @ViewBuilder
    private var activityLink: some View {
        HomePersonalActivityDestination(
            workout: workout,
            strengthWorkout: strengthWorkout,
            phoneWorkout: phoneWorkout
        )
    }

    var body: some View {
        let muscleProfile = isStrength ? homeMuscleProfile : .empty
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                activityLink
            } label: {
                HomePersonalWorkoutVisual(
                    workout: workout,
                    strengthWorkout: strengthWorkout,
                    phoneWorkout: phoneWorkout,
                    height: 114,
                    precomputedStrengthProfile: isStrength ? muscleProfile : nil,
                    recentActivityStrip: true
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                NavigationLink {
                    ATHLTHProfileView()
                } label: {
                    HStack(spacing: 8) {
                        ownAvatar
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.profile.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(
                                HomeRecentCardFormat.activity(workout.activity)
                                + " · " + HomeRecentCardFormat.date(workout.endDate)
                            )
                            .font(.system(size: 9.5))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.77)

                            if workout.duration.isFinite, workout.duration > 0 {
                                Label(
                                    HomeRecentCardFormat.duration(workout.duration),
                                    systemImage: "clock"
                                )
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Open your profile",
                        norwegian: "Åpne profilen din"
                    )
                )

                Menu {
                    NavigationLink {
                        activityLink
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(english: "View activity", norwegian: "Se aktivitet"),
                            systemImage: "figure.run"
                        )
                    }
                    NavigationLink {
                        ATHLTHProfileView()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(english: "View profile", norwegian: "Se profil"),
                            systemImage: "person.crop.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(
                    ATHLTHLocalization.choose(english: "Activity options", norwegian: "Aktivitetsvalg")
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 7)

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

private struct HomeFollowingHorizontalWorkoutCard: View {
    let item: SocialFeedItem

    private var activity: WorkoutActivity {
        HomeFollowingWorkoutPresentation.activity(for: item)
    }

    private var isStrength: Bool { activity == .strength }

    private var seconds: Double? {
        HomeRecentCardFormat.number(item, key: "duration_seconds")
    }

    private var meters: Double? {
        HomeRecentCardFormat.number(item, key: "distance_meters")
    }

    @ViewBuilder
    private var detail: some View {
        HomeFollowingWorkoutDetailView(item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                detail
            } label: {
                HomeFollowingWorkoutArtwork(
                    item: item,
                    activity: activity,
                    height: 114
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                NavigationLink {
                    FriendProfileView(userID: item.actor.userID)
                } label: {
                    HStack(spacing: 8) {
                        SocialAvatar(profile: item.actor, size: 32)
                            .overlay {
                                Circle().stroke(
                                    ATHLTHTheme.accent.opacity(0.25),
                                    lineWidth: 1
                                )
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.actor.resolvedName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(
                                HomeRecentCardFormat.activity(activity)
                                + " · " + HomeRecentCardFormat.date(item.activity.createdAt)
                            )
                            .font(.system(size: 9.5))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.77)

                            if let seconds {
                                Label(
                                    HomeRecentCardFormat.duration(seconds),
                                    systemImage: "clock"
                                )
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(english: "Open athlete profile", norwegian: "Åpne brukerprofil")
                )

                Menu {
                    NavigationLink {
                        detail
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(english: "View activity", norwegian: "Se aktivitet"),
                            systemImage: "figure.run"
                        )
                    }
                    NavigationLink {
                        FriendProfileView(userID: item.actor.userID)
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(english: "View profile", norwegian: "Se profil"),
                            systemImage: "person.crop.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(
                    ATHLTHLocalization.choose(english: "Activity options", norwegian: "Aktivitetsvalg")
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 7)

        }
    }
}

private struct HomeCompactActivityEngagementRow:
    View {
    @EnvironmentObject private var social:
        SocialStore

    let item: SocialFeedItem?

    @State private var showingComments = false
    @State private var pendingLiked: Bool?
    @State private var isSendingLike = false

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

    private var displayedLiked: Bool {
        pendingLiked ?? isLiked
    }

    private var displayedLikeCount: Int {
        guard let pendingLiked, pendingLiked != isLiked else {
            return likeCount
        }
        // Switching from a different reaction to heart changes its type,
        // not the number of people reacting.
        let alreadyReacted = currentItem?.reactions.contains {
            $0.userID == social.currentUserID
        } ?? false
        return max(0, likeCount + (pendingLiked
            ? (alreadyReacted ? 0 : 1)
            : -1))
    }

    private var commentCount: Int {
        currentItem?.comments.count ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                guard let currentItem, !isSendingLike else {
                    return
                }
                let shouldLike = !displayedLiked
                pendingLiked = shouldLike
                isSendingLike = true
                Task {
                    await social.setReaction(
                        activityID: currentItem.id,
                        reaction: shouldLike ? .heart : nil
                    )
                    // The shared social feed is the source of truth. A failed
                    // request restores the prior heart instead of inventing a like.
                    pendingLiked = nil
                    isSendingLike = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(
                        systemName:
                            displayedLiked
                                ? "heart.fill"
                                : "heart"
                    )

                    Text("\(displayedLikeCount)")
                        .monospacedDigit()
                }
                .foregroundStyle(
                    displayedLiked
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
            .disabled(currentItem == nil || isSendingLike)

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

// Shared typography, truthfully sourced metrics and date treatment for the
// compact activity cards. Values are intentionally omitted if not recorded.
private enum HomeRecentCardFormat {
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let total = max(1, Int((seconds / 60).rounded()))
        return total >= 60
            ? "\(total / 60)t \(total % 60)m"
            : "\(total) min"
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters > 0 else { return "—" }
        return String(format: "%.1f km", meters / 1_000)
    }

    static func pace(seconds: TimeInterval?, meters: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0,
              let meters, meters.isFinite, meters > 0 else { return "—" }
        let secondsPerKilometer = seconds * 1_000 / meters
        guard secondsPerKilometer.isFinite,
              secondsPerKilometer > 0,
              secondsPerKilometer < 3_600 else { return "—" }
        let pace = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d", pace / 60, pace % 60)
    }

    static func volume(_ kilograms: Double?) -> String {
        guard let kilograms, kilograms.isFinite, kilograms > 0 else { return "—" }
        return kilograms >= 1_000
            ? String(format: "%.1f t", kilograms / 1_000)
            : String(format: "%.0f kg", kilograms)
    }

    static func count(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        return "\(value)"
    }

    static func energy(_ kilocalories: Double?) -> String {
        guard let kilocalories, kilocalories.isFinite, kilocalories > 0 else { return "—" }
        return "\(Int(kilocalories.rounded())) kcal"
    }

    static func date(_ date: Date) -> String {
        let prefix: String
        if Calendar.current.isDateInToday(date) {
            prefix = ATHLTHLocalization.choose(english: "Today", norwegian: "I dag")
        } else if Calendar.current.isDateInYesterday(date) {
            prefix = ATHLTHLocalization.choose(english: "Yesterday", norwegian: "I går")
        } else {
            prefix = date.formatted(.dateTime.day().month(.abbreviated))
        }
        return prefix + " · " + date.formatted(date: .omitted, time: .shortened)
    }

    static func activity(_ kind: WorkoutActivity) -> String {
        switch kind {
        case .running:
            return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking:
            return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåtur")
        case .strength:
            return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        default:
            return kind.rawValue
        }
    }

    static func number(_ item: SocialFeedItem, key: String) -> Double? {
        guard let raw = item.activity.metadata?[key],
              let value = Double(raw),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    static func integer(_ item: SocialFeedItem, key: String) -> Int? {
        guard let raw = item.activity.metadata?[key],
              let value = Int(raw), value > 0 else { return nil }
        return value
    }
}

private struct HomeRecentCardMetric: View {
    let icon: String
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.77)
            }
            .foregroundStyle(ATHLTHTheme.primaryText)
            Text(title)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

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
                ATHLTHStrengthCompletedHeroCard(
                    profile: strengthMuscleProfile,
                    duration: HomeRecentCardFormat.number(item, key: "duration_seconds") ?? 0,
                    exerciseCount: HomeRecentCardFormat.integer(item, key: "exercise_count"),
                    volumeKilograms: HomeRecentCardFormat.number(item, key: "volume_kg"),
                    height: height,
                    compact: true,
                    showsCompletionLabel: false
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
            .receive(on: DispatchQueue.main)
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
                height: workout.activity == .strength ? 236 : 148
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

/// Empty muscle data should never render an inactive two-body atlas.
/// Shared by personal workouts and workouts in the activity feed.
enum HomeStrengthArtworkPolicy {
    static func usesFallbackPhoto(
        _ profile: StrengthMuscleProfile
    ) -> Bool {
        profile.activations.isEmpty
    }
}

/// Reusable premium background for strength cards in the activity log.
/// Uses the already bundled high-resolution strength artwork rather than
/// the tiny legacy 2.8 KB empty-workout image (which pixelated on iPhone).
/// No network request or per-card image loading is needed.
private struct HomePremiumStrengthStudioBackground: View {
    let height: CGFloat
    let preservesMuscleContrast: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("StrengthFeedGym")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .saturation(0.78)
                    .contrast(0.86)

                // Light, sun-drenched photographic grade that preserves
                // details at the edges while the anatomy floats above it.
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.99, green: 0.96, blue: 0.90)
                            .opacity(preservesMuscleContrast ? 0.24 : 0.12),
                              location: 0),
                        .init(color: Color.white
                            .opacity(preservesMuscleContrast ? 0.21 : 0.08),
                              location: 0.50),
                        .init(color: Color(red: 0.96, green: 0.94, blue: 0.91)
                            .opacity(preservesMuscleContrast ? 0.20 : 0.10),
                              location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.27),
                        Color.clear,
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
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
            Group {
                if HomeStrengthArtworkPolicy.usesFallbackPhoto(profile) {
                    // No recorded muscle groups: show the selected premium
                    // strength photo instead of two inactive body diagrams.
                    // Workout time remains live in the existing activity card.
                    HomePremiumStrengthStudioBackground(
                        height: height,
                        preservesMuscleContrast: false
                    )
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english: "Premium strength studio",
                            norwegian: "Styrkestudio"
                        )
                    )
                } else {
                    muscleMapArtwork
                }
            }
            .frame(
                width: proxy.size.width,
                height: height
            )
            .clipped()
        }
        .frame(height: height)
    }

    private var muscleMapArtwork: some View {
        GeometryReader { proxy in
            ZStack {
                // Premium studio photography replaces the old flat atlas
                // gradient. The anatomical map and its geometry stay intact.
                HomePremiumStrengthStudioBackground(
                    height: height,
                    preservesMuscleContrast: true
                )

                // Soft center scrim makes fine anatomical lines legible
                // without hiding the sunlit studio around the figures.
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.white.opacity(0.46))
                    .frame(
                        width: min(max(height * 1.82, 204),
                                   max(proxy.size.width - 28, 1)),
                        height: max(height - 8, 1)
                    )
                    .blur(radius: 17)
                    .allowsHitTesting(false)

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

// MARK: - Strength visual without recorded muscle groups

/// The photographic strength card is an empty-muscle-data state only.
/// When there are resolved muscle activations we keep the original muscle
/// atlas, including its colors, labels and workout-specific highlights.
enum HomeStrengthRecentCardMetrics {
    static func showsPhoto(for profile: StrengthMuscleProfile) -> Bool {
        HomeStrengthArtworkPolicy.usesFallbackPhoto(profile)
    }

    static func durationText(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "\(minutes) min"
    }

    static func detailText(
        exerciseCount: Int?, completedSetCount: Int?
    ) -> String? {
        let exercises = exerciseCount.flatMap { $0 > 0 ? $0 : nil }
        let sets = completedSetCount.flatMap { $0 > 0 ? $0 : nil }

        let exerciseText = exercises.map {
            ATHLTHLocalization.format(
                english: "%d exercises",
                norwegian: "%d øvelser",
                $0
            )
        }
        let setText = sets.map {
            ATHLTHLocalization.format(
                english: "%d sets", norwegian: "%d sett", $0
            )
        }
        let values = [exerciseText, setText].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

private struct HomeStrengthRecentPhotoArtwork: View {
    let duration: TimeInterval
    let exerciseCount: Int?
    let completedSetCount: Int?
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image("StrengthFeedGym")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .saturation(0.85)
                    .contrast(0.90)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.14), location: 0.38),
                        .init(color: .black.opacity(0.76), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    if let main = HomeStrengthRecentCardMetrics.durationText(duration) {
                        Text(main)
                            .font(.system(size: min(height * 0.24, 30),
                                          weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if let detail = HomeStrengthRecentCardMetrics.detailText(
                        exerciseCount: exerciseCount,
                        completedSetCount: completedSetCount
                    ) {
                        Text(detail)
                            .font(.system(size: min(height * 0.105, 15),
                                          weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                .padding(.horizontal, 13)
                .padding(.bottom, 11)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
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
    var recentActivityStrip = false

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
        // The activity name already appears in the card title below.
        // Let the muscle map, route and treadmill metrics remain unobscured.
        background
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

    private var strengthBackground: some View {
        ATHLTHStrengthCompletedHeroCard(
            profile: muscleProfile,
            duration: workout.duration,
            exerciseCount: workout.strengthExerciseCount
                ?? strengthWorkout?.exercises.count,
            volumeKilograms: workout.strengthTotalVolumeKilograms
                ?? strengthWorkout?.totalVolumeKilograms,
            height: height,
            compact: height < 250,
            showsCompletionLabel: height >= 220,
            recentActivityStrip: recentActivityStrip
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