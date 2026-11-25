import Foundation

enum MessageShareKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case workout
    case trainingPlan = "training_plan"
    case exercise
    case runningWorkout = "running_workout"
    case route
    case challenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout: return "Workout"
        case .trainingPlan: return "Training Plan"
        case .exercise: return "Exercise"
        case .runningWorkout: return "Running Workout"
        case .route: return "Route"
        case .challenge: return "Challenge"
        }
    }

    var localizedTitle: String {
        switch self {
        case .workout:
            return ATHLTHLocalization.choose(english: "Workout", norwegian: "Økt")
        case .trainingPlan:
            return ATHLTHLocalization.choose(english: "Training Plan", norwegian: "Treningsplan")
        case .exercise:
            return ATHLTHLocalization.choose(english: "Exercise", norwegian: "Øvelse")
        case .runningWorkout:
            return ATHLTHLocalization.choose(english: "Running Workout", norwegian: "Løpeøkt")
        case .route:
            return ATHLTHLocalization.choose(english: "Route", norwegian: "Rute")
        case .challenge:
            return ATHLTHLocalization.choose(english: "Challenge", norwegian: "Utfordring")
        }
    }

    var systemImage: String {
        switch self {
        case .workout: return "dumbbell.fill"
        case .trainingPlan: return "calendar"
        case .exercise: return "figure.strengthtraining.traditional"
        case .runningWorkout: return "figure.run"
        case .route: return "map.fill"
        case .challenge: return "bolt.fill"
        }
    }
}

enum DirectMessageRequestStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
}

struct DirectConversationRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let userA: UUID
    let userB: UUID
    let createdAt: Date
    let updatedAt: Date
    let lastMessageAt: Date?
    let requestStatus: DirectMessageRequestStatus
    let requestedBy: UUID?
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userA = "user_a"
        case userB = "user_b"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
        case requestStatus = "request_status"
        case requestedBy = "requested_by"
        case respondedAt = "responded_at"
    }

    func otherUserID(for currentUserID: UUID) -> UUID? {
        if userA == currentUserID { return userB }
        if userB == currentUserID { return userA }
        return nil
    }
}

struct DirectMessageRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    let recipientID: UUID
    let body: String?
    let attachmentKindRaw: String?
    let attachmentTitle: String?
    let attachmentSubtitle: String?
    let attachmentPayload: String?
    let shareVersion: Int
    let sourceObjectID: UUID?
    let sourceOwnerID: UUID?
    let createdAt: Date
    let readAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case body
        case attachmentKindRaw = "attachment_kind"
        case attachmentTitle = "attachment_title"
        case attachmentSubtitle = "attachment_subtitle"
        case attachmentPayload = "attachment_payload"
        case shareVersion = "share_version"
        case sourceObjectID = "source_object_id"
        case sourceOwnerID = "source_owner_id"
        case createdAt = "created_at"
        case readAt = "read_at"
        case deletedAt = "deleted_at"
    }

    var attachmentKind: MessageShareKind? {
        attachmentKindRaw.flatMap(MessageShareKind.init(rawValue:))
    }

    var hasAttachment: Bool {
        attachmentKind != nil && attachmentPayload != nil
    }

    func decodeSnapshot<T: Decodable>(_ type: T.Type) -> T? {
        guard let attachmentPayload,
              let data = attachmentPayload.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// Responses use the existing workout attachment type with shareVersion 3.
// This keeps the messaging backend and its allowed attachment types unchanged.
enum PlannedWorkoutInviteDecision: String, Codable, Hashable {
    case accepted
    case declined
}

/// A message is immutable, so a pending invitation whose scheduled workout
/// has already started is presented as cancelled on every device, including
/// for older conversations that have no explicit cancellation event.
/// An accepted/declined answer remains historical evidence of that decision.
enum PlannedWorkoutInvitationPresentationState: Equatable {
    case pending
    case accepted
    case declined
    case cancelled

    static func resolve(
        start: Date?,
        decision: PlannedWorkoutInviteDecision?,
        organizerCancelled: Bool,
        now: Date = Date()
    ) -> Self {
        if organizerCancelled { return .cancelled }
        switch decision {
        case .accepted: return .accepted
        case .declined: return .declined
        case .none:
            if let start, start <= now { return .cancelled }
            return .pending
        }
    }

    var canRespond: Bool { self == .pending }
}

/// A cancellation is terminal for a source/organizer/recipient tuple.
enum PlannedWorkoutWithdrawalPolicy {
    static func isOrganizerWorkout(_ workout: PlannedSession) -> Bool {
        workout.sharedSourceOwnerID == nil &&
            workout.invitedPartnerID != nil &&
            workout.trainTogetherMode != nil &&
            workout.cancelledAt == nil
    }

    static func invitations(
        in messages: [DirectMessageRecord], sourceID: UUID, organizerID: UUID
    ) -> [DirectMessageRecord] {
        var seen = Set<UUID>()
        return messages.filter {
            $0.deletedAt == nil && $0.attachmentKind == .workout &&
            $0.shareVersion == 2 && $0.sourceObjectID == sourceID &&
            $0.sourceOwnerID == organizerID && $0.senderID == organizerID &&
            $0.recipientID != organizerID
        }.sorted { $0.createdAt > $1.createdAt }.filter {
            seen.insert($0.recipientID).inserted
        }
    }

    static func cancellation(
        in messages: [DirectMessageRecord], sourceID: UUID,
        organizerID: UUID, recipientID: UUID
    ) -> WorkoutInviteLifecycleUpdate? {
        messages.filter {
            $0.deletedAt == nil && $0.attachmentKind == .workout &&
            $0.shareVersion == 6 && $0.sourceObjectID == sourceID &&
            $0.sourceOwnerID == organizerID && $0.senderID == organizerID &&
            $0.recipientID == recipientID
        }.sorted { $0.createdAt > $1.createdAt }.compactMap {
            $0.decodeSnapshot(WorkoutInviteLifecycleUpdate.self)
        }.first {
            $0.sourceWorkoutID == sourceID && $0.organizerID == organizerID &&
            $0.kind == .cancelled
        }
    }
}

struct PlannedWorkoutInviteResponse: Codable, Hashable {
    let sourceWorkoutID: UUID
    let decision: PlannedWorkoutInviteDecision
}

/// Proposed challenge edits travel privately as version-2 challenge attachments.
/// The original challenge is not mutated until its creator approves.
struct ChallengeChangeProposal: Codable, Hashable, Identifiable {
    let id: UUID
    let challengerID: UUID
    let original: ATHLTHChallenge
    let proposed: ATHLTHChallenge
    let submittedAt: Date

    var challengeID: UUID { original.id }
    var hasChanges: Bool {
        original.title != proposed.title ||
        original.sport != proposed.sport ||
        original.rules != proposed.rules ||
        original.participants != proposed.participants
    }
}

struct ChallengeChangeProposalResponse: Codable, Hashable {
    let proposalID: UUID
    let challengeID: UUID
    let accepted: Bool
}

struct MessageShareDraft: Hashable {
    let kind: MessageShareKind
    let title: String
    let subtitle: String?
    let payload: String
    let sourceObjectID: UUID?
    let sourceOwnerID: UUID?
    let shareVersion: Int
    /// Friends-only exercises must never be sent through the normal
    /// first-contact message-request path.
    let requiresMutualFollow: Bool

    init<T: Encodable>(
        kind: MessageShareKind,
        title: String,
        subtitle: String? = nil,
        snapshot: T,
        sourceObjectID: UUID? = nil,
        sourceOwnerID: UUID? = nil,
        shareVersion: Int = 1,
        requiresMutualFollow: Bool = false
    ) throws {
        let data = try JSONEncoder().encode(snapshot)

        guard data.count <= 1_048_576 else {
            throw MessageShareError.snapshotTooLarge
        }

        guard let payload = String(data: data, encoding: .utf8) else {
            throw MessageShareError.encodingFailed
        }

        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.payload = payload
        self.sourceObjectID = sourceObjectID
        self.sourceOwnerID = sourceOwnerID
        self.shareVersion = shareVersion
        self.requiresMutualFollow = requiresMutualFollow
    }
}

enum MessageShareError: LocalizedError {
    case encodingFailed
    case snapshotTooLarge

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "ATHLTH could not prepare this item for sharing."
        case .snapshotTooLarge:
            return "This item is too large to send in a message. Try a shorter route or a smaller training plan."
        }
    }
}

struct DirectConversationParams: Encodable {
    let otherUser: UUID

    enum CodingKeys: String, CodingKey {
        case otherUser = "other_user"
    }
}

struct DirectMessageInsert: Encodable {
    var id: UUID = UUID()
    let conversationID: UUID
    let senderID: UUID
    let recipientID: UUID
    let body: String?
    let attachmentKind: String?
    let attachmentTitle: String?
    let attachmentSubtitle: String?
    let attachmentPayload: String?
    let shareVersion: Int
    let sourceObjectID: UUID?
    let sourceOwnerID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case body
        case attachmentKind = "attachment_kind"
        case attachmentTitle = "attachment_title"
        case attachmentSubtitle = "attachment_subtitle"
        case attachmentPayload = "attachment_payload"
        case shareVersion = "share_version"
        case sourceObjectID = "source_object_id"
        case sourceOwnerID = "source_owner_id"
    }
}


struct DirectMessageRequestResponseParams: Encodable {
    let conversationID: UUID
    let acceptRequest: Bool

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case acceptRequest = "accept_request"
    }
}


/// Push is an invalidation hint only; authenticated REST is still the source
/// of truth for messages and private read receipts.
enum ATHLTHDirectMessageRefreshPolicy {
    /// Four-second loop remains for legacy/offline servers; a connected
    /// socket only needs a safety reconciliation every 16 seconds.
    static func shouldPoll(realtimeConnected: Bool, elapsed: TimeInterval) -> Bool {
        !realtimeConnected || !elapsed.isFinite || elapsed < 0 || elapsed >= 16
    }

    static func matches(_ payload: [AnyHashable: Any], owner: UUID, conversation: UUID) -> Bool {
        guard payload["athlth_entity_type"] as? String == "direct_conversation",
              let recipient = payload["athlth_recipient_id"] as? String,
              let entity = payload["athlth_entity_id"] as? String else { return false }
        return UUID(uuidString: recipient) == owner && UUID(uuidString: entity) == conversation
    }
}
