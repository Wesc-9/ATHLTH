import Foundation

@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var followerIDs: Set<UUID> = []
    @Published private(set) var followingIDs: Set<UUID> = []
    @Published private(set) var incomingRequests: [SocialFriendRequestDisplay] = []
    @Published private(set) var outgoingRequests: [SocialFriendRequestDisplay] = []
    @Published private(set) var discoverResults: [SocialProfileCard] = []
    @Published private(set) var challengeSearchResults: [ATHLTHChallenge] = []
    @Published private(set) var visibleProfiles: [SocialProfileCard] = []
    @Published private(set) var feed: [SocialFeedItem] = []
    @Published private(set) var blockedUsers: [SocialBlockedUser] = []
    @Published private(set) var mutedUserIDs: Set<UUID> = []
    @Published private(set) var inboxEvents: [SocialInboxEvent] = []
    @Published private(set) var workoutSessions: [SocialWorkoutSessionRecord] = []
    @Published private(set) var workoutParticipants: [SocialWorkoutParticipantRecord] = []
    @Published private(set) var workoutInvites: [SocialWorkoutInviteDisplay] = []
    @Published private(set) var activeWorkoutSession: SocialWorkoutSessionRecord?
    @Published private(set) var activeWorkoutParticipants: [SocialWorkoutParticipantRecord] = []
    @Published private(set) var coordinatedLobbySessionID: UUID?
    @Published private(set) var currentJoinedWorkoutSessionID: UUID?
    @Published private(set) var privacy: SocialPrivacySettings?
    @Published private(set) var workoutMedia: [WorkoutMediaRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isHomeFeedRefreshing = false
    @Published var errorMessage: String?

    private let service: SupabaseSocialService
    private var lastHomeFeedRefreshAt: Date?
    private var lastFullRefreshAt: Date?
    private var profileCache: [UUID: SocialFriendProfile] = [:]
    private let activationDate: Date

    init() {
        self.service = SupabaseSocialService()

        let defaults = UserDefaults.standard
        let key = "athlth.social.activationDate"

        if let existing = defaults.object(forKey: key) as? Date {
            activationDate = existing
        } else {
            let now = Date()
            defaults.set(now, forKey: key)
            activationDate = now
        }
    }

    var currentUserID: UUID? {
        service.currentUserID
    }

    var pendingRequestCount: Int {
        incomingRequests.count + workoutInvites.count
    }

    var followerCount: Int { followerIDs.count }
    var followingCount: Int { followingIDs.count }

    var followers: [SocialProfileCard] {
        visibleProfiles
            .filter { followerIDs.contains($0.userID) }
            .sorted {
                $0.resolvedName.localizedCaseInsensitiveCompare($1.resolvedName) == .orderedAscending
            }
    }

    var following: [SocialProfileCard] {
        visibleProfiles
            .filter { followingIDs.contains($0.userID) }
            .sorted {
                $0.resolvedName.localizedCaseInsensitiveCompare($1.resolvedName) == .orderedAscending
            }
    }

    func isFollowing(_ userID: UUID) -> Bool {
        followingIDs.contains(userID)
    }

    func isFollowedBy(_ userID: UUID) -> Bool {
        followerIDs.contains(userID)
    }

    func isMutualFollow(_ userID: UUID) -> Bool {
        followingIDs.contains(userID) &&
            followerIDs.contains(userID)
    }

    func isMuted(_ userID: UUID) -> Bool {
        mutedUserIDs.contains(userID)
    }

    func profile(for userID: UUID) -> SocialProfileCard? {
        visibleProfiles.first { $0.userID == userID }
    }

    var mutualFollows: [SocialProfileCard] {
        visibleProfiles
            .filter { isMutualFollow($0.userID) }
            .sorted {
                $0.resolvedName.localizedCaseInsensitiveCompare(
                    $1.resolvedName
                ) == .orderedAscending
            }
    }

    /// People who can be invited into a shared workout.
    /// Workout invitation RLS requires a mutual follow relationship.
    var trainingPartners: [SocialProfileCard] {
        mutualFollows
    }

    func acceptedTrainingPartnerNames(for workoutID: UUID) -> [String] {
        guard let session = workoutSessions.first(where: {
            $0.creatorID == currentUserID &&
            $0.sourceWorkoutID == workoutID
        }) else {
            return []
        }

        return workoutParticipants
            .filter {
                $0.sessionID == session.id &&
                $0.userID != currentUserID &&
                $0.state == .accepted
            }
            .map(\.displayNameSnapshot)
    }

    func refresh(
        challengeStore: ChallengeStore? = nil,
        notificationStore: ATHLTHNotificationStore? = nil,
        deliverSystemAlertsForImportedInbox: Bool = true
    ) async {
        guard let currentUserID = service.currentUserID else {
            reset()
            return
        }

        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            async let cardsTask = service.loadVisibleProfileCards()
            async let followersTask = service.loadFollowers(for: currentUserID)
            async let followingTask = service.loadFollowing(for: currentUserID)
            async let requestsTask = service.loadFriendRequests()
            async let privacyTask = service.loadPrivacySettings()
            async let feedTask = service.loadFeed()
            async let blockedTask = service.loadBlockedUsers()
            async let mutedTask = service.loadMutedUserIDs()
            async let inboxTask = service.loadInboxEvents()
            async let remoteChallengesTask = service.loadRemoteChallenges()
            async let workoutSessionsTask = service.loadWorkoutSessions()
            async let workoutParticipantsTask = service.loadWorkoutParticipants()

            let cards = try await cardsTask
            let followerRows = try await followersTask
            let followingRows = try await followingTask
            let requests = try await requestsTask
            let privacy = try await privacyTask
            let feed = try await feedTask
            let blocked = try await blockedTask
            let muted = try await mutedTask
            let inbox = try await inboxTask
            let remoteChallenges = try await remoteChallengesTask
            let workoutSessions = try await workoutSessionsTask
            let workoutParticipants = try await workoutParticipantsTask

            let blockedIDs = Set(blocked.map { $0.profile.userID })
            let visibleCards = cards.filter {
                !blockedIDs.contains($0.userID)
            }

            visibleProfiles = visibleCards
            followerIDs = Set(followerRows.map(\.followerID))
                .subtracting(blockedIDs)
            followingIDs = Set(followingRows.map(\.followingID))
                .subtracting(blockedIDs)

            applyRelationships(
                cards: visibleCards,
                requests: requests
            )

            self.privacy = privacy
            self.feed = feed.filter { item in
                item.activity.actorID == currentUserID ||
                followingIDs.contains(item.activity.actorID)
            }
            blockedUsers = blocked
            mutedUserIDs = muted
            inboxEvents = inbox
            applyWorkoutSessions(
                sessions: workoutSessions,
                participants: workoutParticipants,
                cards: visibleCards
            )

            if let challengeStore {
                challengeStore
                    .replaceWithRemoteChallenges(
                        remoteChallenges
                    )
            }

            if let notificationStore {
                importInboxEvents(
                    into: notificationStore,
                    deliverSystemAlerts: deliverSystemAlertsForImportedInbox
                )
            }

            lastFullRefreshAt = Date()
            errorMessage = nil
        } catch is CancellationError {
            // SwiftUI may cancel Community refresh work when the view
            // is replaced or pull-to-refresh supersedes an existing task.
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshChallenges(
        challengeStore: ChallengeStore
    ) async {
        guard service.currentUserID != nil else {
            return
        }

        do {
            let remoteChallenges =
                try await service
                    .loadRemoteChallenges()

            challengeStore
                .replaceWithRemoteChallenges(
                    remoteChallenges
                )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            errorMessage =
                error.localizedDescription
        }
    }

    func refreshIfStale(
        maxAge: TimeInterval = 120,
        challengeStore: ChallengeStore? = nil,
        notificationStore: ATHLTHNotificationStore? = nil,
        deliverSystemAlertsForImportedInbox: Bool = true
    ) async {
        if let lastFullRefreshAt,
           Date().timeIntervalSince(lastFullRefreshAt) < maxAge,
           privacy != nil,
           !visibleProfiles.isEmpty {
            return
        }

        await refresh(
            challengeStore: challengeStore,
            notificationStore: notificationStore,
            deliverSystemAlertsForImportedInbox:
                deliverSystemAlertsForImportedInbox
        )
    }

    /// Launch/Home bootstrap that loads only the relationship state needed
    /// to scope the feed, privacy, inbox and the small Activity Center page.
    /// Community performs the heavier relationship/session refresh on demand.
    func refreshHomeContext(
        notificationStore: ATHLTHNotificationStore? = nil,
        deliverSystemAlertsForImportedInbox: Bool = true,
        force: Bool = false
    ) async {
        guard let currentUserID = service.currentUserID else {
            reset()
            return
        }

        if !force,
           let lastHomeFeedRefreshAt,
           Date().timeIntervalSince(lastHomeFeedRefreshAt) < 120,
           !feed.isEmpty,
           privacy != nil {
            return
        }

        guard !isHomeFeedRefreshing else { return }

        isHomeFeedRefreshing = true
        defer { isHomeFeedRefreshing = false }

        do {
            async let followingTask = service.loadFollowing(
                for: currentUserID
            )
            async let privacyTask = service.loadPrivacySettings()
            async let feedTask = service.loadFeed(limit: 18)
            async let inboxTask = service.loadInboxEvents()

            let followingRows = try await followingTask
            let loadedPrivacy = try await privacyTask
            let loadedFeed = try await feedTask
            let loadedInbox = try await inboxTask

            followingIDs = Set(followingRows.map(\.followingID))
            privacy = loadedPrivacy
            feed = loadedFeed.filter { item in
                item.activity.actorID == currentUserID ||
                followingIDs.contains(item.activity.actorID)
            }
            inboxEvents = loadedInbox
            lastHomeFeedRefreshAt = Date()

            if let notificationStore {
                importInboxEvents(
                    into: notificationStore,
                    deliverSystemAlerts:
                        deliverSystemAlertsForImportedInbox
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the last cached Home content. A full Community refresh can
            // surface a detailed error if the backend remains unavailable.
        }
    }

    /// Lightweight Home refresh. The full social refresh fans out across
    /// relationships, privacy, inbox, challenges and workout sessions; Home
    /// only needs the activity feed for its Activity Center.
    func refreshHomeFeed(force: Bool = false) async {
        guard let currentUserID = service.currentUserID else {
            feed = []
            return
        }

        if !force,
           let lastHomeFeedRefreshAt,
           Date().timeIntervalSince(lastHomeFeedRefreshAt) < 120,
           !feed.isEmpty {
            return
        }

        guard !isHomeFeedRefreshing else { return }

        isHomeFeedRefreshing = true
        defer { isHomeFeedRefreshing = false }

        do {
            if followingIDs.isEmpty {
                let followingRows = try await service.loadFollowing(
                    for: currentUserID
                )
                followingIDs = Set(
                    followingRows.map(\.followingID)
                )
            }

            let refreshedFeed = try await service.loadFeed(limit: 18)
            feed = refreshedFeed.filter { item in
                item.activity.actorID == currentUserID ||
                followingIDs.contains(item.activity.actorID)
            }
            lastHomeFeedRefreshAt = Date()
        } catch {
            // A lightweight Home refresh must not overwrite a more important
            // social error state or clear already cached activity.
        }
    }

    func refreshActivityHistoryFeed(
        limit: Int = 100
    ) async {
        guard let currentUserID =
                service.currentUserID
        else {
            feed = []
            return
        }

        do {
            if followingIDs.isEmpty {
                let followingRows =
                    try await service
                        .loadFollowing(
                            for:
                                currentUserID
                        )
                followingIDs =
                    Set(
                        followingRows
                            .map(\.followingID)
                    )
            }

            let refreshedFeed =
                try await service.loadFeed(
                    limit:
                        min(
                            max(limit, 18),
                            150
                        )
                )

            feed =
                refreshedFeed.filter {
                    item in

                    item.activity.actorID ==
                        currentUserID ||
                    followingIDs.contains(
                        item.activity.actorID
                    )
                }
        } catch {
            // History keeps the previously cached feed if the network is
            // unavailable. Own local/Health workouts remain visible.
        }
    }

    func search(_ query: String) async {
        let requestedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard requestedQuery.count >= 2 else {
            discoverResults = []
            return
        }

        errorMessage = nil

        do {
            let blockedIDs = Set(
                blockedUsers.map { $0.profile.userID }
            )
            let results = try await service.searchProfiles(requestedQuery)

            guard !Task.isCancelled else { return }

            discoverResults = results.filter {
                !blockedIDs.contains($0.userID)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            discoverResults = []
            errorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        discoverResults = []
    }

    func searchChallenges(_ query: String) async {
        let requestedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard requestedQuery.count >= 2 else {
            challengeSearchResults = []
            return
        }

        do {
            let results =
                try await service.searchRemoteChallenges(
                    requestedQuery
                )

            guard !Task.isCancelled else { return }

            challengeSearchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            challengeSearchResults = []
        }
    }

    func clearChallengeSearch() {
        challengeSearchResults = []
    }

    func follow(_ profile: SocialProfileCard) async {
        errorMessage = nil

        do {
            try await service.follow(profile.userID)
            followingIDs.insert(profile.userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unfollow(_ userID: UUID) async {
        errorMessage = nil

        do {
            try await service.unfollow(userID)
            followingIDs.remove(userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendFollowRequest(to profile: SocialProfileCard) async {
        errorMessage = nil

        do {
            try await service.sendFollowRequest(to: profile.userID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept(_ request: SocialFriendRequestDisplay) async {
        await resolve(request, status: .accepted)
    }

    func decline(_ request: SocialFriendRequestDisplay) async {
        await resolve(request, status: .declined)
    }

    func cancel(_ request: SocialFriendRequestDisplay) async {
        await resolve(request, status: .cancelled)
    }

    @discardableResult
    func block(_ userID: UUID) async -> Bool {
        errorMessage = nil

        do {
            try await service.blockUser(userID)
            profileCache[userID] = nil
            followerIDs.remove(userID)
            followingIDs.remove(userID)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func unblock(_ userID: UUID) async {
        errorMessage = nil

        do {
            try await service.unblockUser(userID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func report(
        _ userID: UUID,
        reason: String,
        details: String?
    ) async -> Bool {
        errorMessage = nil

        do {
            try await service.reportUser(
                userID,
                reason: reason,
                details: details
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func relationshipState(with userID: UUID) -> SocialRelationshipState {
        if let currentUserID, userID == currentUserID {
            return .selfUser
        }

        if isMutualFollow(userID) {
            return .mutualFollow
        }

        if incomingRequests.contains(where: { $0.profile.userID == userID }) {
            return .incomingPending
        }

        if outgoingRequests.contains(where: { $0.profile.userID == userID }) {
            return .outgoingPending
        }

        if blockedUsers.contains(where: { $0.profile.userID == userID }) {
            return .blocked
        }

        return .none
    }

    func loadActivitiesForMatchup(
        _ userID: UUID
    ) async -> [SocialActivityRecord] {
        do {
            return try await service.loadActivities(
                for: userID
            )
        } catch is CancellationError {
            return []
        } catch {
            guard !Task.isCancelled else { return [] }
            errorMessage = error.localizedDescription
            return []
        }
    }

    func loadFriendProfile(
        _ userID: UUID,
        forceRefresh: Bool = false
    ) async -> SocialFriendProfile? {
        if blockedUsers.contains(where: {
            $0.profile.userID == userID
        }) {
            return nil
        }

        if !forceRefresh, let cached = profileCache[userID] {
            return cached
        }

        errorMessage = nil

        do {
            let profile = try await service.loadFriendProfile(userID)
            profileCache[userID] = profile
            return profile
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func loadFollowOverview(
        for userID: UUID
    ) async -> SocialFollowOverview {
        do {
            async let followerRowsTask = service.loadFollowers(for: userID)
            async let followingRowsTask = service.loadFollowing(for: userID)

            let followerRows = try await followerRowsTask
            let followingRows = try await followingRowsTask

            let cardByID = Dictionary(
                uniqueKeysWithValues:
                    visibleProfiles.map { ($0.userID, $0) }
            )

            let followerProfiles = followerRows
                .compactMap { cardByID[$0.followerID] }
                .sorted {
                    $0.resolvedName.localizedCaseInsensitiveCompare(
                        $1.resolvedName
                    ) == .orderedAscending
                }

            let followingProfiles = followingRows
                .compactMap { cardByID[$0.followingID] }
                .sorted {
                    $0.resolvedName.localizedCaseInsensitiveCompare(
                        $1.resolvedName
                    ) == .orderedAscending
                }

            return SocialFollowOverview(
                followerCount: followerRows.count,
                followingCount: followingRows.count,
                followers: followerProfiles,
                following: followingProfiles
            )
        } catch is CancellationError {
            return .empty
        } catch {
            guard !Task.isCancelled else { return .empty }
            return .empty
        }
    }

    func setReaction(
        activityID: UUID,
        reaction: SocialActivityReaction?
    ) async {
        errorMessage = nil

        do {
            try await service.setReaction(
                activityID: activityID,
                reaction: reaction
            )
            feed = scopedFeed(
                try await service.loadFeed()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addComment(
        activityID: UUID,
        body: String
    ) async {
        errorMessage = nil

        do {
            try await service.addComment(
                activityID: activityID,
                body: body
            )
            feed = scopedFeed(
                try await service.loadFeed()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteComment(_ commentID: UUID) async {
        errorMessage = nil

        do {
            try await service.deleteComment(commentID)
            feed = scopedFeed(
                try await service.loadFeed()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMuted(
        _ userID: UUID,
        muted: Bool
    ) async {
        errorMessage = nil

        do {
            try await service.setUserMuted(
                userID,
                muted: muted
            )

            if muted {
                mutedUserIDs.insert(userID)
            } else {
                mutedUserIDs.remove(userID)
            }

            feed = scopedFeed(
                try await service.loadFeed()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func updatePrivacy(_ updated: SocialPrivacySettings) async -> Result<Void, Error> {
        var updated = updated
        updated.normalizeSectionVisibility()
        // Public profiles are searchable without a separate setting.
        // Preserve explicit search opt-outs on existing non-public profiles.
        if updated.profileVisibility == "public" {
            updated.discoverable = true
        }
        privacy = updated
        errorMessage = nil

        do {
            try await service.updatePrivacySettings(updated)
            return .success(())
        } catch {
            errorMessage = error.localizedDescription
            privacy = try? await service.loadPrivacySettings()
            return .failure(error)
        }
    }

    func updateCorePrivacy(
        profileVisibility: ProfileVisibility,
        shareTrainingPresence: Bool
    ) async {
        guard var privacy else { return }

        let rawVisibility = profileVisibility.rawValue

        guard privacy.profileVisibility != rawVisibility ||
                privacy.shareTrainingPresence != shareTrainingPresence
        else {
            return
        }

        privacy.profileVisibility = rawVisibility
        privacy.shareTrainingPresence = shareTrainingPresence
        await updatePrivacy(privacy)
    }

    func syncOwnTrainingFocus(_ focus: TrainingFocus) async {
        errorMessage = nil

        do {
            try await service.syncTrainingFocus(focus)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncOwnPerformance(_ stats: ProfilePerformanceStats?) async {
        guard let stats else { return }

        do {
            try await service.syncPerformanceStats(stats)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncOwnTrophies(_ trophies: [TrophyProgressItem]) async {
        do {
            try await service.syncTrophyShowcase(trophies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncOwnGoals(
        _ goals: [ATHLTHGoal],
        enabled: Bool
    ) async {
        do {
            try await service.syncGoalShowcase(
                goals,
                enabled: enabled
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncPresence(_ presence: TrainingPresence) async {
        do {
            try await service.syncPresence(
                state: presence.state,
                workoutTitle: presence.workoutTitle,
                startedAt: presence.startedAt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func beginWorkoutWithFriends(
        title: String,
        kind: WorkoutKind,
        friends: [SocialProfileCard],
        creatorName: String,
        creatorUsername: String?,
        invitePayload: SocialWorkoutInvitePayload? = nil,
        creatorCaptureDevice: WorkoutCaptureDevice? = nil
    ) async -> Bool {
        guard !friends.isEmpty else {
            activeWorkoutSession = nil
            activeWorkoutParticipants = []
            coordinatedLobbySessionID = nil
            currentJoinedWorkoutSessionID = nil
            return true
        }

        errorMessage = nil

        do {
            if let activeWorkoutSession,
               activeWorkoutSession.status == .active,
               activeWorkoutSession.creatorID == currentUserID {
                let ownParticipant =
                    activeWorkoutParticipants.first {
                        $0.userID == currentUserID
                    }

                if ownParticipant?.workoutFinishedAt == nil &&
                    ownParticipant?.launchFailedAt == nil {
                    try? await service.cancelWorkoutSession(
                        activeWorkoutSession.id
                    )
                }
            }

            let session = try await service.createWorkoutSession(
                title: title,
                workoutKind: kind,
                creatorName: creatorName,
                creatorUsername: creatorUsername,
                friends: friends,
                invitePayload: invitePayload
            )

            activeWorkoutSession = session
            coordinatedLobbySessionID = session.id
            try await refreshWorkoutLobby(sessionID: session.id)

            if let creatorCaptureDevice,
               let creator = activeWorkoutParticipants.first(
                    where: { $0.userID == currentUserID }
               ) {
                try await service.setWorkoutReady(
                    participantID: creator.id,
                    captureDevice: creatorCaptureDevice
                )
                try await refreshWorkoutLobby(sessionID: session.id)
            }

            return await waitForCoordinatedWorkoutStart(
                sessionID: session.id
            )
        } catch is CancellationError {
            coordinatedLobbySessionID = nil
            return false
        } catch {
            coordinatedLobbySessionID = nil
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshWorkoutLobby(
        sessionID: UUID
    ) async throws {
        let (session, participants) =
            try await service.loadWorkoutLobby(
                sessionID: sessionID
            )

        if let index = workoutSessions.firstIndex(
            where: { $0.id == session.id }
        ) {
            workoutSessions[index] = session
        } else {
            workoutSessions.insert(session, at: 0)
        }

        workoutParticipants.removeAll {
            $0.sessionID == sessionID
        }
        workoutParticipants.append(
            contentsOf: participants
        )

        if session.creatorID == currentUserID {
            activeWorkoutSession = session
            activeWorkoutParticipants = participants
        }
    }

    @discardableResult
    func markCurrentUserReady(
        sessionID: UUID,
        captureDevice: WorkoutCaptureDevice
    ) async -> Bool {
        do {
            try await refreshWorkoutLobby(
                sessionID: sessionID
            )
            guard let currentUserID,
                  let participant = workoutParticipants.first(
                    where: {
                        $0.sessionID == sessionID &&
                        $0.userID == currentUserID
                    }
                  )
            else {
                return false
            }

            try await service.setWorkoutReady(
                participantID: participant.id,
                captureDevice: captureDevice
            )
            try await refreshWorkoutLobby(
                sessionID: sessionID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func scheduleCoordinatedWorkoutStart(
        sessionID: UUID,
        countdownSeconds: TimeInterval = 3
    ) async -> Bool {
        guard activeWorkoutSession?.creatorID == currentUserID else {
            return false
        }

        do {
            _ = try await service.scheduleWorkoutStart(
                sessionID: sessionID,
                countdownSeconds:
                    min(
                        max(
                            Int(
                                countdownSeconds
                                    .rounded()
                            ),
                            1
                        ),
                        10
                    )
            )
            try await refreshWorkoutLobby(
                sessionID: sessionID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func waitForCoordinatedWorkoutStart(
        sessionID: UUID
    ) async -> Bool {
        while !Task.isCancelled {
            do {
                try await refreshWorkoutLobby(
                    sessionID: sessionID
                )

                guard let session = workoutSessions.first(
                    where: { $0.id == sessionID }
                ), session.status == .active
                else {
                    if coordinatedLobbySessionID == sessionID {
                        coordinatedLobbySessionID = nil
                    }
                    return false
                }

                guard let currentUserID,
                      let currentParticipant =
                        workoutParticipants.first(
                            where: {
                                $0.sessionID == sessionID &&
                                $0.userID == currentUserID
                            }
                        ),
                      (
                        currentParticipant.state == .creator ||
                        currentParticipant.state == .accepted
                      )
                else {
                    if coordinatedLobbySessionID == sessionID {
                        coordinatedLobbySessionID = nil
                    }
                    return false
                }

                if let startAt = session.coordinatedStartAt {
                    let delay = startAt.timeIntervalSinceNow
                    if delay > 0 {
                        try await Task.sleep(
                            for: .milliseconds(
                                Int(delay * 1000)
                            )
                        )
                    }

                    guard currentParticipant.readyAt != nil
                    else {
                        return false
                    }

                    currentJoinedWorkoutSessionID =
                        sessionID

                    if coordinatedLobbySessionID == sessionID {
                        coordinatedLobbySessionID = nil
                    }
                    return true
                }

                try await Task.sleep(
                    for: .milliseconds(750)
                )
            } catch is CancellationError {
                if coordinatedLobbySessionID == sessionID {
                    coordinatedLobbySessionID = nil
                }
                return false
            } catch {
                errorMessage = error.localizedDescription
                try? await Task.sleep(
                    for: .seconds(1)
                )
            }
        }

        return false
    }

    @discardableResult
    func confirmCurrentJoinedWorkoutStarted() async -> Bool {
        guard let sessionID =
                currentJoinedWorkoutSessionID,
              let currentUserID
        else {
            return true
        }

        do {
            try await refreshWorkoutLobby(
                sessionID: sessionID
            )

            guard let participant =
                    workoutParticipants.first(
                        where: {
                            $0.sessionID == sessionID &&
                            $0.userID == currentUserID
                        }
                    ),
                  participant.launchFailedAt == nil
            else {
                return false
            }

            if participant.workoutStartedAt == nil {
                try await service
                    .markWorkoutParticipantStarted(
                        participantID:
                            participant.id
                    )
            }

            try? await refreshWorkoutLobby(
                sessionID: sessionID
            )
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func markCurrentJoinedWorkoutLaunchFailed() async {
        guard let sessionID =
                currentJoinedWorkoutSessionID,
              let currentUserID
        else {
            return
        }

        do {
            try await refreshWorkoutLobby(
                sessionID: sessionID
            )

            guard let participant =
                    workoutParticipants.first(
                        where: {
                            $0.sessionID == sessionID &&
                            $0.userID == currentUserID
                        }
                    ),
                  participant.workoutStartedAt == nil,
                  participant.launchFailedAt == nil
            else {
                currentJoinedWorkoutSessionID =
                    nil
                return
            }

            try await service
                .markWorkoutParticipantLaunchFailed(
                    participantID:
                        participant.id
                )
            try? await refreshWorkoutLobby(
                sessionID: sessionID
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }

        currentJoinedWorkoutSessionID = nil
    }

    func cancelActiveWorkout() async {
        guard let activeWorkoutSession,
              activeWorkoutSession.creatorID == currentUserID,
              activeWorkoutSession.status == .active
        else {
            return
        }

        do {
            try await service.cancelWorkoutSession(
                activeWorkoutSession.id
            )
            self.activeWorkoutSession = nil
            activeWorkoutParticipants = []
            coordinatedLobbySessionID = nil
            workoutSessions.removeAll {
                $0.id == activeWorkoutSession.id
            }
            workoutParticipants.removeAll {
                $0.sessionID == activeWorkoutSession.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishActiveWorkout(
        sourceWorkoutID: UUID,
        endedAt: Date
    ) async {
        let sessionID =
            currentJoinedWorkoutSessionID ??
            activeWorkoutSession?.id

        guard let sessionID,
              let currentUserID
        else {
            return
        }

        do {
            try await refreshWorkoutLobby(
                sessionID: sessionID
            )

            guard let session = workoutSessions.first(
                where: { $0.id == sessionID }
            ),
            session.status == .active,
            let participant = workoutParticipants.first(
                where: {
                    $0.sessionID == sessionID &&
                    $0.userID == currentUserID
                }
            )
            else {
                currentJoinedWorkoutSessionID = nil
                return
            }

            var participantDidStart =
                participant.workoutStartedAt != nil

            // A completed local workout is authoritative evidence that the
            // launch succeeded. Repair a missed social start marker if the
            // network was unavailable immediately after 3-2-1.
            if !participantDidStart,
               participant.readyAt != nil,
               participant.launchFailedAt == nil,
               session.coordinatedStartAt != nil {
                try await service
                    .markWorkoutParticipantStarted(
                        participantID:
                            participant.id
                    )
                participantDidStart = true
            }

            guard participantDidStart else {
                currentJoinedWorkoutSessionID = nil
                return
            }

            if session.creatorID == currentUserID {
                try await service.recordWorkoutSessionSource(
                    sessionID: sessionID,
                    sourceWorkoutID: sourceWorkoutID
                )
            }

            try await service.markWorkoutParticipantFinished(
                participantID: participant.id
            )

            try? await refreshWorkoutLobby(
                sessionID: sessionID
            )

            currentJoinedWorkoutSessionID = nil

            if activeWorkoutSession?.id == sessionID,
               workoutSessions.first(
                    where: { $0.id == sessionID }
               )?.status != .active {
                activeWorkoutSession = nil
                activeWorkoutParticipants = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func acceptWorkoutInvite(
        _ invite: SocialWorkoutInviteDisplay
    ) async -> Bool {
        await resolveWorkoutInvite(
            invite,
            state: .accepted
        )
    }

    func declineWorkoutInvite(
        _ invite: SocialWorkoutInviteDisplay
    ) async {
        _ = await resolveWorkoutInvite(
            invite,
            state: .declined
        )
    }

    func withdrawWorkoutParticipant(
        _ participant: SocialWorkoutParticipantRecord
    ) async {
        guard participant.userID != currentUserID,
              participant.workoutStartedAt == nil
        else {
            return
        }

        do {
            try await service.withdrawWorkoutParticipant(
                participantID: participant.id
            )
            try await refreshWorkoutLobby(
                sessionID:
                    participant.sessionID
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func workoutActivity(for workoutID: UUID) async -> SocialActivityRecord? {
        try? await service.workoutActivity(for: workoutID)
    }

    func refreshWorkoutMedia(
        for userID: UUID? = nil
    ) async {
        guard let resolvedUserID =
                userID ?? currentUserID
        else {
            workoutMedia = []
            return
        }

        do {
            workoutMedia =
                try await service.loadWorkoutMedia(
                    for: resolvedUserID
                )
        } catch is CancellationError {
            return
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func uploadWorkoutMedia(
        workoutID: UUID,
        jpegData: Data,
        caption: String?
    ) async -> Bool {
        do {
            let media =
                try await service
                    .uploadWorkoutMedia(
                        workoutID: workoutID,
                        jpegData: jpegData,
                        caption: caption
                    )
            workoutMedia.removeAll {
                $0.id == media.id
            }
            workoutMedia.insert(
                media,
                at: 0
            )
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func deleteWorkoutMedia(
        _ media: WorkoutMediaRecord
    ) async -> Bool {
        do {
            try await service
                .deleteWorkoutMedia(media)
            workoutMedia.removeAll {
                $0.id == media.id
            }
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func workoutAssociatedFriendIDs(for workoutID: UUID) -> Set<UUID> {
        guard let currentUserID,
              let session = workoutSessions.first(where: {
                  $0.creatorID == currentUserID &&
                  $0.sourceWorkoutID == workoutID
              })
        else {
            return []
        }

        return Set(
            workoutParticipants
                .filter {
                    $0.sessionID == session.id &&
                    $0.userID != currentUserID &&
                    ($0.state == .accepted || $0.state == .invited)
                }
                .map(\.userID)
        )
    }

    func saveWorkoutReview(
        _ workout: SocialPublishableWorkout,
        visibility: ProfileVisibility,
        description: String,
        effort: Int,
        friendIDs: Set<UUID>,
        creatorName: String,
        creatorUsername: String?
    ) async -> Bool {
        guard let currentUserID else { return false }

        errorMessage = nil

        do {
            var linkedSession = workoutSessions.first {
                $0.creatorID == currentUserID &&
                $0.sourceWorkoutID == workout.id
            }

            let selectedFriends = trainingPartners.filter {
                friendIDs.contains($0.userID)
            }

            if linkedSession == nil && !selectedFriends.isEmpty {
                linkedSession = try await service.createCompletedWorkoutSession(
                    workout: workout,
                    creatorName: creatorName,
                    creatorUsername: creatorUsername,
                    friends: selectedFriends
                )
                await refresh()
            } else if let linkedSession {
                let existingIDs = Set(
                    workoutParticipants
                        .filter { $0.sessionID == linkedSession.id }
                        .map(\.userID)
                )
                let newFriends = selectedFriends.filter {
                    !existingIDs.contains($0.userID)
                }

                if !newFriends.isEmpty {
                    try await service.addWorkoutParticipants(
                        sessionID: linkedSession.id,
                        friends: newFriends,
                        creatorID: currentUserID
                    )
                    await refresh()
                }
            }

            let resolvedSession = workoutSessions.first {
                $0.creatorID == currentUserID &&
                $0.sourceWorkoutID == workout.id
            } ?? linkedSession

            let acceptedPartners: [SocialWorkoutParticipantRecord]
            if let resolvedSession {
                acceptedPartners = workoutParticipants.filter {
                    $0.sessionID == resolvedSession.id &&
                    $0.userID != currentUserID &&
                    $0.state == .accepted
                }
            } else {
                acceptedPartners = []
            }

            var metadata: [String: String] = [
                "workout_id": workout.id.uuidString,
                "kind": workout.activity.rawValue,
                "source": workout.source,
                "effort": "\(max(1, min(effort, 10)))"
            ]
            Self.enrichWorkoutActivityMetadata(
                &metadata,
                workout: workout
            )

            let cleanDescription = description
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanDescription.isEmpty {
                metadata["caption"] = cleanDescription
            }

            if !acceptedPartners.isEmpty {
                metadata["with_names"] = acceptedPartners
                    .map(\.displayNameSnapshot)
                    .joined(separator: ", ")
                metadata["with_count"] = "\(acceptedPartners.count)"
            }

            if !selectedFriends.isEmpty {
                metadata["partner_count_selected"] = "\(selectedFriends.count)"
            }

            try await service.publishWorkoutActivity(
                eventKey: "workout-\(workout.id.uuidString)",
                title: workout.title,
                subtitle: workout.summaryText,
                metadata: metadata,
                visibility: visibility,
                workoutSessionID: resolvedSession?.id
            )

            feed = try await service.loadFeed().filter { item in
                item.activity.actorID == currentUserID ||
                followingIDs.contains(item.activity.actorID)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func publishWorkout(
        _ workout: SocialPublishableWorkout,
        visibility: ProfileVisibility,
        caption: String? = nil,
        routePreview: [RouteCoordinate] = [],
        hideRouteStartAndEnd: Bool = true
    ) async -> Bool {
        errorMessage = nil

        do {
            let linkedSession = workoutSessions.first {
                $0.creatorID == currentUserID &&
                $0.sourceWorkoutID == workout.id
            }

            let acceptedPartners: [SocialWorkoutParticipantRecord]
            if let linkedSession {
                acceptedPartners = workoutParticipants.filter {
                    $0.sessionID == linkedSession.id &&
                    $0.userID != currentUserID &&
                    $0.state == .accepted
                }
            } else {
                acceptedPartners = []
            }

            var metadata: [String: String] = [
                "workout_id": workout.id.uuidString,
                "kind": workout.activity.rawValue,
                "source": workout.source
            ]
            Self.enrichWorkoutActivityMetadata(
                &metadata,
                workout: workout
            )
            metadata["hide_route_start_end"] = String(hideRouteStartAndEnd)
            if let preview = WorkoutRouteSharing.encode(routePreview) {
                metadata["route_preview"] = preview
            }

            if !acceptedPartners.isEmpty {
                metadata["with_names"] = acceptedPartners
                    .map(\.displayNameSnapshot)
                    .joined(separator: ", ")
                metadata["with_count"] = "\(acceptedPartners.count)"
            }

            let cleanCaption = caption?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let cleanCaption, !cleanCaption.isEmpty {
                metadata["caption"] = cleanCaption
            }

            try await service.publishWorkoutActivity(
                eventKey: "workout-\(workout.id.uuidString)",
                title: workout.title,
                subtitle: workout.summaryText,
                metadata: metadata,
                visibility: visibility,
                workoutSessionID: linkedSession?.id
            )

            feed = try await service.loadFeed().filter { item in
                item.activity.actorID == currentUserID ||
                followingIDs.contains(item.activity.actorID)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func isWorkoutPublished(_ workoutID: UUID) async -> Bool {
        (try? await service.isActivityPublished(
            eventKey: "workout-\(workoutID.uuidString)"
        )) ?? false
    }

    func syncChallenges(_ challengeStore: ChallengeStore) async {
        guard service.currentUserID != nil else { return }

        for challenge in challengeStore.challenges {
            do {
                try await service.syncChallenge(challenge)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func joinPublicChallenge(
        _ challengeID: UUID
    ) async -> Bool {
        guard service.currentUserID != nil else {
            errorMessage =
                "Sign in to use ATHLTH social features."
            return false
        }

        do {
            try await service
                .joinPublicChallenge(
                    challengeID
                )
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    @discardableResult
    func syncChallenge(
        _ challenge: ATHLTHChallenge
    ) async -> Bool {
        guard service.currentUserID != nil else {
            errorMessage =
                "Sign in to use ATHLTH social features."
            return false
        }

        do {
            try await service.syncChallenge(
                challenge
            )
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteChallenge(
        challengeID: UUID
    ) async -> Bool {
        guard service.currentUserID != nil else {
            errorMessage =
                "Sign in to use ATHLTH social features."
            return false
        }

        do {
            try await service.deleteChallenge(
                challengeID:
                    challengeID
            )
            await refresh()
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    @discardableResult
    func withdrawChallengeInvite(
        participantID: UUID
    ) async -> Bool {
        guard service.currentUserID != nil else {
            errorMessage =
                "Sign in to use ATHLTH social features."
            return false
        }

        do {
            try await service
                .withdrawChallengeInvite(
                    participantID:
                        participantID
                )
            await refresh()
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func uploadChallengeCover(
        challengeID: UUID,
        jpegData: Data
    ) async -> String? {
        do {
            return try await service.uploadChallengeCover(
                challengeID: challengeID,
                jpegData: jpegData
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func removeChallengeCover(
        challengeID: UUID
    ) async {
        do {
            try await service.removeChallengeCover(
                challengeID: challengeID
            )
        } catch {
            // Best-effort cleanup only. A failed delete must not block
            // challenge creation/retry.
        }
    }

    func publishStrengthWorkout(
        _ workout: StrengthWorkoutLog,
        visibility: ProfileVisibility = .friends
    ) async {
        guard let endedAt = workout.endedAt,
              endedAt >= activationDate,
              let configuredVisibility = privacy.flatMap({
                  ProfileVisibility(rawValue: $0.recentActivityVisibility)
              }),
              configuredVisibility != .privateOnly
        else {
            return
        }

        let volume = workout.totalVolumeKilograms > 0
            ? String(format: "%.0f kg volume", workout.totalVolumeKilograms)
            : "\(workout.totalCompletedSets) sets"

        let performedExercises =
            workout.exercises.filter {
                $0.isCompleted ||
                $0.sets.contains(
                    where: {
                        $0.isCompleted
                    }
                )
            }

        var muscleGroups: [String] = []
        for raw in performedExercises.flatMap({
            $0.exercise.primaryMuscles +
            ($0.exercise.secondaryMuscles ?? [])
        }) {
            let value =
                raw.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            guard !value.isEmpty,
                  !muscleGroups.contains(
                    where: {
                        $0.caseInsensitiveCompare(
                            value
                        ) == .orderedSame
                    }
                  )
            else {
                continue
            }

            muscleGroups.append(value)
        }

        var metadata: [String: String] = [
            "workout_id": workout.id.uuidString,
            "kind": "strength",
            "duration_seconds": String(
                max(
                    endedAt.timeIntervalSince(
                        workout.startedAt
                    ),
                    0
                )
            ),
            "exercise_count":
                String(
                    performedExercises.count
                )
        ]

        if workout.totalVolumeKilograms > 0 {
            metadata["volume_kg"] =
                String(
                    workout.totalVolumeKilograms
                )
        }

        if !muscleGroups.isEmpty {
            metadata["muscle_groups"] =
                muscleGroups
                    .prefix(8)
                    .joined(
                        separator: "|"
                    )
        }

        do {
            try await service.publishActivity(
                eventKey: "strength-workout-\(workout.id.uuidString)",
                kind: "workout",
                title: workout.title,
                subtitle: volume,
                metadata: metadata,
                visibility: configuredVisibility
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publishWorkout(
        result: WatchWorkoutResult,
        visibility: ProfileVisibility = .friends
    ) async {
        guard result.endedAt >= activationDate,
              let configuredVisibility = privacy.flatMap({
                  ProfileVisibility(rawValue: $0.recentActivityVisibility)
              }),
              configuredVisibility != .privateOnly
        else {
            return
        }

        let distance: String
        if result.distanceMeters > 0 {
            distance = String(format: "%.2f km", result.distanceMeters / 1_000)
        } else {
            distance = Self.durationText(result.duration)
        }

        do {
            try await service.publishActivity(
                eventKey: "workout-\(result.id.uuidString)",
                kind: "workout",
                title: "\(result.kind.title) completed",
                subtitle: distance,
                metadata: [
                    "workout_id": result.id.uuidString,
                    "kind": result.kind.rawValue,
                    "distance_meters": String(
                        max(result.distanceMeters, 0)
                    ),
                    "duration_seconds": String(
                        max(result.duration, 0)
                    )
                ],
                visibility: configuredVisibility
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publishRunningPersonalRecords(
        _ records: [HealthPersonalRecord],
        visibility: ProfileVisibility = .friends
    ) async {
        guard let configuredVisibility = privacy.flatMap({
            ProfileVisibility(rawValue: $0.runningPRsVisibility)
        }),
        configuredVisibility != .privateOnly
        else {
            return
        }

        for record in records
        where record.date >= activationDate &&
              record.kind.isRunningRecord {
            do {
                try await service.publishActivity(
                    eventKey:
                        "running-pr-\(record.kind.rawValue)-" +
                        "\(Int(record.date.timeIntervalSince1970))-" +
                        "\(Int(record.value.rounded()))",
                    kind: "personal_record",
                    title: "New \(record.kind.title)",
                    subtitle: record.formattedValue,
                    metadata: [
                        "record_kind": record.kind.rawValue,
                        "pr_type": "running",
                        "verification": "apple_health",
                        "value": String(record.value)
                    ],
                    visibility: configuredVisibility
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        if !records.isEmpty {
            if let refreshedFeed = try? await service.loadFeed() {
                feed = refreshedFeed.filter { item in
                    item.activity.actorID == currentUserID ||
                    followingIDs.contains(item.activity.actorID)
                }
            }
        }
    }

    func publishStrengthRepPersonalRecords(
        _ records: [StrengthRepPersonalRecord],
        visibility: ProfileVisibility = .friends
    ) async {
        guard let configuredVisibility = privacy.flatMap({
            ProfileVisibility(rawValue: $0.strengthPRsVisibility)
        }),
        configuredVisibility != .privateOnly
        else {
            return
        }

        for record in records where record.date >= activationDate {
            do {
                try await service.publishActivity(
                    eventKey:
                        "strength-rep-pr-" +
                        "\(record.sourceWorkoutID.uuidString)-" +
                        "\(record.reps)-" +
                        "\(Int((record.weightKilograms * 10).rounded()))",
                    kind: "personal_record",
                    title: "New \(record.reps)-rep PR · \(record.exerciseName)",
                    subtitle: record.value,
                    metadata: [
                        "exercise": record.exerciseName,
                        "reps": String(record.reps),
                        "weight_kg": String(record.weightKilograms),
                        "pr_type": "strength",
                        "verification": "manual",
                        "source_workout_id": record.sourceWorkoutID.uuidString
                    ],
                    visibility: configuredVisibility
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        if !records.isEmpty {
            if let refreshedFeed = try? await service.loadFeed() {
                feed = refreshedFeed.filter { item in
                    item.activity.actorID == currentUserID ||
                    followingIDs.contains(item.activity.actorID)
                }
            }
        }
    }

    func publishTrophyUnlocks(
        _ unlocks: [TrophyUnlockRecord],
        visibility: ProfileVisibility = .friends
    ) async {
        guard let configuredVisibility = privacy.flatMap({
            ProfileVisibility(rawValue: $0.trophyCabinetVisibility)
        }),
        configuredVisibility != .privateOnly
        else {
            return
        }

        for unlock in unlocks where unlock.unlockedAt >= activationDate {
            do {
                try await service.publishActivity(
                    eventKey: "trophy-\(unlock.stageKey)",
                    kind: "trophy",
                    title: "Unlocked \(unlock.title)",
                    subtitle: unlock.stageTitle,
                    metadata: [
                        "trophy_id": unlock.trophyID,
                        "rarity": unlock.rarity.title
                    ],
                    visibility: configuredVisibility
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func shareTrophyUnlock(
        _ unlock: TrophyUnlockRecord
    ) async -> Bool {
        errorMessage = nil

        do {
            let settings: SocialPrivacySettings
            if let privacy {
                settings = privacy
            } else {
                settings = try await service.loadPrivacySettings()
                self.privacy = settings
            }

            guard let configuredVisibility =
                    ProfileVisibility(
                        rawValue:
                            settings.trophyCabinetVisibility
                    ),
                  configuredVisibility != .privateOnly
            else {
                errorMessage =
                    "Trophy sharing is disabled in your profile privacy settings."
                return false
            }

            try await service.publishActivity(
                eventKey: "trophy-\(unlock.stageKey)",
                kind: "trophy",
                title: "Unlocked \(unlock.title)",
                subtitle: unlock.stageTitle,
                metadata: [
                    "trophy_id": unlock.trophyID,
                    "rarity": unlock.rarity.title
                ],
                visibility: configuredVisibility
            )

            if let refreshed =
                    try? await service.loadFeed() {
                feed = scopedFeed(refreshed)
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func publishCompletedGoals(
        _ goals: [ATHLTHGoal],
        visibility: ProfileVisibility = .friends
    ) async {
        guard let configuredVisibility = privacy.flatMap({
            ProfileVisibility(rawValue: $0.goalsVisibility)
        }),
        configuredVisibility != .privateOnly
        else {
            return
        }

        for goal in goals {
            guard let completedAt = goal.completedAt,
                  completedAt >= activationDate
            else {
                continue
            }

            do {
                try await service.publishActivity(
                    eventKey: "goal-\(goal.id.uuidString)-complete",
                    kind: "goal",
                    title: "Goal completed",
                    subtitle: goal.title,
                    metadata: ["goal_id": goal.id.uuidString],
                    visibility: configuredVisibility
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func publishChallenges(
        _ challenges: [ATHLTHChallenge],
        visibility: ProfileVisibility = .friends
    ) async {
        guard let currentUserID,
              let configuredVisibility = privacy.flatMap({
                  ProfileVisibility(rawValue: $0.recentActivityVisibility)
              }),
              configuredVisibility != .privateOnly
        else {
            return
        }

        for challenge in challenges
        where challenge.creatorID == currentUserID &&
                challenge.createdAt >= activationDate {
            do {
                var metadata: [String: String] = [
                    "challenge_id": challenge.id.uuidString,
                    "sport": challenge.sport.rawValue
                ]

                if let summary = challenge.rules.summary,
                   !summary.isEmpty {
                    metadata["summary"] = summary
                }

                if let artwork = challenge.rules.coverArtworkName,
                   !artwork.isEmpty {
                    metadata["cover_artwork"] = artwork
                }

                if let imageURL = challenge.rules.coverImageURL,
                   !imageURL.isEmpty {
                    metadata["cover_image_url"] = imageURL
                }

                try await service.publishActivity(
                    eventKey: "challenge-\(challenge.id.uuidString)-created",
                    kind: "challenge",
                    title: "Challenge created",
                    subtitle: challenge.title,
                    metadata: metadata,
                    visibility: configuredVisibility
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func shareChallengeToCommunity(
        _ challenge: ATHLTHChallenge
    ) async -> Bool {
        do {
            var metadata: [String: String] = [
                "challenge_id": challenge.id.uuidString,
                "sport": challenge.sport.rawValue,
                "starts_at": ISO8601DateFormatter()
                    .string(from: challenge.rules.startsAt)
            ]

            if let summary = challenge.rules.summary,
               !summary.isEmpty {
                metadata["summary"] = summary
            }

            if let artwork = challenge.rules.coverArtworkName,
               !artwork.isEmpty {
                metadata["cover_artwork"] = artwork
            }

            if let imageURL = challenge.rules.coverImageURL,
               !imageURL.isEmpty {
                metadata["cover_image_url"] = imageURL
            }

            try await service.publishActivity(
                eventKey: "challenge-\(challenge.id.uuidString)-created",
                kind: "challenge",
                title: "Shared a challenge",
                subtitle: challenge.title,
                metadata: metadata,
                visibility: challenge.visibility
            )

            if let refreshed = try? await service.loadFeed() {
                feed = scopedFeed(refreshed)
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func shareCommunityEvent(
        id: UUID,
        title: String,
        activityType: CommunityEventActivity,
        startsAt: Date,
        meetingName: String,
        visibility: ProfileVisibility,
        coverArtworkName: String? = nil,
        coverImageURL: String? = nil
    ) async -> Bool {
        var metadata: [String: String] = [
            "event_id": id.uuidString,
            "activity_type":
                activityType.rawValue,
            "starts_at":
                ISO8601DateFormatter()
                    .string(from: startsAt)
        ]

        let cleanMeeting =
            meetingName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        if !cleanMeeting.isEmpty {
            metadata["meeting_name"] =
                cleanMeeting
        }

        if let coverArtworkName,
           !coverArtworkName.isEmpty {
            metadata["cover_artwork"] =
                coverArtworkName
        }

        if let coverImageURL,
           !coverImageURL.isEmpty {
            metadata["cover_image_url"] =
                coverImageURL
        }

        do {
            try await service.publishActivity(
                eventKey:
                    "event-\(id.uuidString)-shared",
                kind: "event",
                title: "Shared an event",
                subtitle: title,
                metadata: metadata,
                visibility: visibility
            )

            if let refreshed =
                try? await service
                    .loadFeed() {
                feed =
                    scopedFeed(
                        refreshed
                    )
            }

            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func markBackendInboxRead(_ eventID: UUID) async {
        do {
            try await service.markInboxEventRead(eventID)
            inboxEvents = try await service.loadInboxEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markChallengeEventsRead(
        from actorID: UUID
    ) async {
        let challengeKinds:
            Set<String> = [
                "challenge_invite",
                "challenge_result",
                "challenge_accepted",
                "challenge_declined",
                "challenge_withdrawn"
            ]

        let matching =
            inboxEvents.filter {
                $0.actorID == actorID &&
                challengeKinds.contains(
                    $0.kind
                ) &&
                $0.readAt == nil
            }

        guard !matching.isEmpty else {
            return
        }

        do {
            for event in matching {
                try await service
                    .markInboxEventRead(
                        event.id
                    )
            }

            inboxEvents =
                try await service
                    .loadInboxEvents()
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func markChallengeInviteRead(
        challengeID: UUID
    ) async {
        let matching = inboxEvents.filter {
            $0.kind == "challenge_invite" &&
            $0.entityID == challengeID &&
            $0.readAt == nil
        }

        guard !matching.isEmpty else {
            return
        }

        do {
            for event in matching {
                try await service
                    .markInboxEventRead(
                        event.id
                    )
            }

            inboxEvents =
                try await service
                    .loadInboxEvents()
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    private func resolveWorkoutInvite(
        _ invite: SocialWorkoutInviteDisplay,
        state: SocialWorkoutParticipantState
    ) async -> Bool {
        errorMessage = nil

        do {
            try await service.respondToWorkoutInvite(
                participantID: invite.participant.id,
                state: state
            )
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyWorkoutSessions(
        sessions: [SocialWorkoutSessionRecord],
        participants: [SocialWorkoutParticipantRecord],
        cards: [SocialProfileCard]
    ) {
        workoutSessions = sessions
        workoutParticipants = participants

        guard let currentUserID else {
            workoutInvites = []
            activeWorkoutSession = nil
            activeWorkoutParticipants = []
            return
        }

        let cardsByID = Dictionary(
            uniqueKeysWithValues: cards.map { ($0.userID, $0) }
        )
        let sessionsByID = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, $0) }
        )

        workoutInvites = participants
            .filter {
                $0.userID == currentUserID &&
                (
                    $0.state == .invited ||
                    (
                        $0.state == .accepted &&
                        $0.workoutStartedAt == nil &&
                        $0.launchFailedAt == nil
                    )
                )
            }
            .compactMap { participant in
                guard let session = sessionsByID[participant.sessionID],
                      session.status == .active
                else {
                    return nil
                }

                return SocialWorkoutInviteDisplay(
                    session: session,
                    participant: participant,
                    creator: cardsByID[session.creatorID]
                )
            }
            .sorted { $0.session.createdAt > $1.session.createdAt }

        activeWorkoutSession = sessions
            .filter { candidate in
                guard candidate.creatorID == currentUserID,
                      candidate.status == .active
                else {
                    return false
                }

                let ownParticipant =
                    participants.first {
                        $0.sessionID == candidate.id &&
                        $0.userID == currentUserID
                    }

                return ownParticipant?.workoutFinishedAt == nil &&
                    ownParticipant?.launchFailedAt == nil
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first

        if let activeWorkoutSession {
            activeWorkoutParticipants = participants
                .filter { $0.sessionID == activeWorkoutSession.id }
                .sorted { lhs, rhs in
                    if lhs.state == .creator { return true }
                    if rhs.state == .creator { return false }
                    return lhs.displayNameSnapshot < rhs.displayNameSnapshot
                }
        } else {
            activeWorkoutParticipants = []
        }
    }

    private func resolve(
        _ request: SocialFriendRequestDisplay,
        status: SocialFriendRequestState
    ) async {
        errorMessage = nil

        do {
            try await service.respondToFriendRequest(
                requestID: request.id,
                status: status
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyRelationships(
        cards: [SocialProfileCard],
        requests: [SocialFriendRequestRecord]
    ) {
        guard let currentUserID else {
            incomingRequests = []
            outgoingRequests = []
            return
        }

        let cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.userID, $0) })

        incomingRequests = requests
            .filter {
                $0.status == .pending &&
                $0.recipientID == currentUserID
            }
            .compactMap { request in
                guard let profile = cardByID[request.senderID] else { return nil }
                return SocialFriendRequestDisplay(
                    request: request,
                    profile: profile,
                    isIncoming: true
                )
            }
            .sorted { $0.request.createdAt > $1.request.createdAt }

        outgoingRequests = requests
            .filter {
                $0.status == .pending &&
                $0.senderID == currentUserID
            }
            .compactMap { request in
                guard let profile = cardByID[request.recipientID] else { return nil }
                return SocialFriendRequestDisplay(
                    request: request,
                    profile: profile,
                    isIncoming: false
                )
            }
            .sorted { $0.request.createdAt > $1.request.createdAt }
    }

    private func importInboxEvents(
        into notificationStore: ATHLTHNotificationStore,
        deliverSystemAlerts: Bool
    ) {
        for event in inboxEvents {
            notificationStore.add(
                ATHLTHNotificationDraft(
                    eventKey: "social-backend-\(event.id.uuidString)",
                    kind: notificationKind(for: event),
                    title: event.localizedTitle,
                    message: event.localizedMessage,
                    createdAt: event.createdAt,
                    challengeID: event.entityType == "challenge"
                        ? event.entityID
                        : nil,
                    backendEventID: event.id,
                    socialEventKind: event.kind,
                    socialEntityType: event.entityType,
                    socialEntityID: event.entityID
                ),
                deliverSystemAlert:
                    deliverSystemAlerts &&
                    event.pushNotifiedAt == nil &&
                    event.createdAt >= activationDate
            )
        }
    }

    private func scopedFeed(
        _ loaded: [SocialFeedItem]
    ) -> [SocialFeedItem] {
        guard let currentUserID else { return [] }

        return loaded.filter { item in
            item.activity.actorID == currentUserID ||
                followingIDs.contains(item.activity.actorID)
        }
    }

    private func notificationKind(
        for event: SocialInboxEvent
    ) -> ATHLTHNotificationKind {
        let kind = event.kind.lowercased()
        let entityType = event.entityType?.lowercased() ?? ""

        if kind.contains("challenge") ||
            entityType.contains("challenge") {
            return .challenge
        }

        return .social
    }

    private func reset() {
        followerIDs = []
        followingIDs = []
        incomingRequests = []
        outgoingRequests = []
        discoverResults = []
        challengeSearchResults = []
        visibleProfiles = []
        feed = []
        blockedUsers = []
        mutedUserIDs = []
        inboxEvents = []
        workoutSessions = []
        workoutParticipants = []
        workoutInvites = []
        activeWorkoutSession = nil
        activeWorkoutParticipants = []
        coordinatedLobbySessionID = nil
        currentJoinedWorkoutSessionID = nil
        privacy = nil
        workoutMedia = []
        profileCache = [:]
    }

    private static func enrichWorkoutActivityMetadata(
        _ metadata: inout [String: String],
        workout: SocialPublishableWorkout
    ) {
        metadata["duration_seconds"] =
            String(
                max(
                    workout.duration,
                    0
                )
            )

        if let distance =
                workout.distanceMeters,
           distance > 0 {
            metadata["distance_meters"] =
                String(distance)
        }

        if let calories =
                workout.activeEnergyKilocalories,
           calories > 0 {
            metadata["active_kcal"] =
                String(calories)
        }

        if let count =
                workout.strengthExerciseCount,
           count > 0 {
            metadata["exercise_count"] =
                String(count)
        }

        if let volume =
                workout
                    .strengthTotalVolumeKilograms,
           volume > 0 {
            metadata["volume_kg"] =
                String(volume)
        }

        if let groups =
                workout.strengthMuscleGroups,
           !groups.isEmpty {
            metadata["muscle_groups"] =
                groups
                    .prefix(8)
                    .joined(
                        separator: "|"
                    )
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int((duration / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes) min"
    }
}

enum SocialRelationshipState: Hashable {
    case selfUser
    case none
    case outgoingPending
    case incomingPending
    case mutualFollow
    case blocked
}
