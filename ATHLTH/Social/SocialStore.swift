import Foundation

@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var friends: [SocialProfileCard] = []
    @Published private(set) var friendships: [SocialFriendshipRecord] = []
    @Published private(set) var incomingRequests: [SocialFriendRequestDisplay] = []
    @Published private(set) var outgoingRequests: [SocialFriendRequestDisplay] = []
    @Published private(set) var discoverResults: [SocialProfileCard] = []
    @Published private(set) var feed: [SocialFeedItem] = []
    @Published private(set) var blockedUsers: [SocialBlockedUser] = []
    @Published private(set) var inboxEvents: [SocialInboxEvent] = []
    @Published private(set) var workoutSessions: [SocialWorkoutSessionRecord] = []
    @Published private(set) var workoutParticipants: [SocialWorkoutParticipantRecord] = []
    @Published private(set) var workoutInvites: [SocialWorkoutInviteDisplay] = []
    @Published private(set) var activeWorkoutSession: SocialWorkoutSessionRecord?
    @Published private(set) var activeWorkoutParticipants: [SocialWorkoutParticipantRecord] = []
    @Published private(set) var privacy: SocialPrivacySettings?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let service: SupabaseSocialService
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
        incomingRequests.count
    }

    func refresh(
        challengeStore: ChallengeStore? = nil,
        notificationStore: ATHLTHNotificationStore? = nil
    ) async {
        guard service.currentUserID != nil else {
            reset()
            return
        }

        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            async let cardsTask = service.loadVisibleProfileCards()
            async let friendshipsTask = service.loadFriendships()
            async let requestsTask = service.loadFriendRequests()
            async let privacyTask = service.loadPrivacySettings()
            async let feedTask = service.loadFeed()
            async let blockedTask = service.loadBlockedUsers()
            async let inboxTask = service.loadInboxEvents()
            async let remoteChallengesTask = service.loadRemoteChallenges()
            async let workoutSessionsTask = service.loadWorkoutSessions()
            async let workoutParticipantsTask = service.loadWorkoutParticipants()

            let cards = try await cardsTask
            let friendships = try await friendshipsTask
            let requests = try await requestsTask
            let privacy = try await privacyTask
            let feed = try await feedTask
            let blocked = try await blockedTask
            let inbox = try await inboxTask
            let remoteChallenges = try await remoteChallengesTask
            let workoutSessions = try await workoutSessionsTask
            let workoutParticipants = try await workoutParticipantsTask

            applyRelationships(
                cards: cards,
                friendships: friendships,
                requests: requests
            )

            self.privacy = privacy
            self.feed = feed
            blockedUsers = blocked
            inboxEvents = inbox
            applyWorkoutSessions(
                sessions: workoutSessions,
                participants: workoutParticipants,
                cards: cards
            )

            if let challengeStore {
                challengeStore.mergeRemoteChallenges(remoteChallenges)
            }

            if let notificationStore {
                importInboxEvents(into: notificationStore)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        errorMessage = nil

        do {
            discoverResults = try await service.searchProfiles(query)
        } catch {
            discoverResults = []
            errorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        discoverResults = []
    }

    func sendFriendRequest(to profile: SocialProfileCard) async {
        errorMessage = nil

        do {
            try await service.sendFriendRequest(to: profile.userID)
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

    func removeFriend(_ userID: UUID) async {
        guard let currentUserID,
              let friendship = friendships.first(where: {
                  $0.otherUserID(for: currentUserID) == userID
              })
        else {
            return
        }

        errorMessage = nil

        do {
            try await service.removeFriendship(friendship.id)
            profileCache[userID] = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func block(_ userID: UUID) async {
        errorMessage = nil

        do {
            try await service.blockUser(userID)
            profileCache[userID] = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
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

        if friends.contains(where: { $0.userID == userID }) {
            return .friends
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

    func loadFriendProfile(
        _ userID: UUID,
        forceRefresh: Bool = false
    ) async -> SocialFriendProfile? {
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
            feed = try await service.loadFeed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePrivacy(_ updated: SocialPrivacySettings) async {
        privacy = updated
        errorMessage = nil

        do {
            try await service.updatePrivacySettings(updated)
        } catch {
            errorMessage = error.localizedDescription
            privacy = try? await service.loadPrivacySettings()
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

    func beginWorkoutWithFriends(
        title: String,
        kind: WorkoutKind,
        friends: [SocialProfileCard],
        creatorName: String,
        creatorUsername: String?
    ) async {
        guard !friends.isEmpty else {
            activeWorkoutSession = nil
            activeWorkoutParticipants = []
            return
        }

        errorMessage = nil

        do {
            if let activeWorkoutSession,
               activeWorkoutSession.status == .active,
               activeWorkoutSession.creatorID == currentUserID {
                try? await service.cancelWorkoutSession(activeWorkoutSession.id)
            }

            let session = try await service.createWorkoutSession(
                title: title,
                workoutKind: kind,
                creatorName: creatorName,
                creatorUsername: creatorUsername,
                friends: friends
            )

            activeWorkoutSession = session
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishActiveWorkout(
        sourceWorkoutID: UUID,
        endedAt: Date
    ) async {
        guard let activeWorkoutSession,
              activeWorkoutSession.creatorID == currentUserID,
              activeWorkoutSession.status == .active
        else {
            return
        }

        do {
            try await service.completeWorkoutSession(
                sessionID: activeWorkoutSession.id,
                sourceWorkoutID: sourceWorkoutID,
                endedAt: endedAt
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptWorkoutInvite(_ invite: SocialWorkoutInviteDisplay) async {
        await resolveWorkoutInvite(invite, state: .accepted)
    }

    func declineWorkoutInvite(_ invite: SocialWorkoutInviteDisplay) async {
        await resolveWorkoutInvite(invite, state: .declined)
    }

    func publishWorkout(
        _ workout: SocialPublishableWorkout,
        visibility: ProfileVisibility,
        caption: String? = nil
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

            feed = try await service.loadFeed()
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

    func publishStrengthWorkout(
        _ workout: StrengthWorkoutLog,
        visibility: ProfileVisibility = .friends
    ) async {
        guard let endedAt = workout.endedAt,
              endedAt >= activationDate
        else {
            return
        }

        let volume = workout.totalVolumeKilograms > 0
            ? String(format: "%.0f kg volume", workout.totalVolumeKilograms)
            : "\(workout.totalCompletedSets) sets"

        do {
            try await service.publishActivity(
                eventKey: "strength-workout-\(workout.id.uuidString)",
                kind: "workout",
                title: workout.title,
                subtitle: volume,
                metadata: [
                    "workout_id": workout.id.uuidString,
                    "kind": "strength"
                ],
                visibility: visibility
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publishWorkout(
        result: WatchWorkoutResult,
        visibility: ProfileVisibility = .friends
    ) async {
        guard result.endedAt >= activationDate else { return }

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
                    "kind": result.kind.rawValue
                ],
                visibility: visibility
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publishTrophyUnlocks(
        _ unlocks: [TrophyUnlockRecord],
        visibility: ProfileVisibility = .friends
    ) async {
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
                    visibility: visibility
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func publishCompletedGoals(
        _ goals: [ATHLTHGoal],
        visibility: ProfileVisibility = .friends
    ) async {
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
                    visibility: visibility
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
        guard let currentUserID else { return }

        for challenge in challenges
        where challenge.creatorID == currentUserID &&
                challenge.createdAt >= activationDate {
            do {
                try await service.publishActivity(
                    eventKey: "challenge-\(challenge.id.uuidString)-created",
                    kind: "challenge",
                    title: "Challenge created",
                    subtitle: challenge.title,
                    metadata: [
                        "challenge_id": challenge.id.uuidString,
                        "sport": challenge.sport.rawValue
                    ],
                    visibility: visibility
                )
            } catch {
                errorMessage = error.localizedDescription
            }
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

    private func resolveWorkoutInvite(
        _ invite: SocialWorkoutInviteDisplay,
        state: SocialWorkoutParticipantState
    ) async {
        errorMessage = nil

        do {
            try await service.respondToWorkoutInvite(
                participantID: invite.participant.id,
                state: state
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
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
                $0.state == .invited
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
            .filter {
                $0.creatorID == currentUserID &&
                $0.status == .active
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
        friendships: [SocialFriendshipRecord],
        requests: [SocialFriendRequestRecord]
    ) {
        guard let currentUserID else {
            friends = []
            self.friendships = []
            incomingRequests = []
            outgoingRequests = []
            return
        }

        let cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.userID, $0) })

        self.friendships = friendships

        let friendIDs = Set(
            friendships.compactMap {
                $0.otherUserID(for: currentUserID)
            }
        )

        friends = friendIDs
            .compactMap { cardByID[$0] }
            .sorted {
                $0.resolvedName.localizedCaseInsensitiveCompare($1.resolvedName) == .orderedAscending
            }

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
        into notificationStore: ATHLTHNotificationStore
    ) {
        for event in inboxEvents {
            notificationStore.add(
                ATHLTHNotificationDraft(
                    eventKey: "social-backend-\(event.id.uuidString)",
                    kind: .social,
                    title: event.title,
                    message: event.message,
                    createdAt: event.createdAt,
                    challengeID: event.entityType == "challenge"
                        ? event.entityID
                        : nil,
                    backendEventID: event.id,
                    socialEventKind: event.kind,
                    socialEntityType: event.entityType,
                    socialEntityID: event.entityID
                ),
                deliverSystemAlert: event.createdAt >= activationDate
            )
        }
    }

    private func reset() {
        friends = []
        friendships = []
        incomingRequests = []
        outgoingRequests = []
        discoverResults = []
        feed = []
        blockedUsers = []
        inboxEvents = []
        workoutSessions = []
        workoutParticipants = []
        workoutInvites = []
        activeWorkoutSession = nil
        activeWorkoutParticipants = []
        privacy = nil
        profileCache = [:]
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
    case friends
    case blocked
}
