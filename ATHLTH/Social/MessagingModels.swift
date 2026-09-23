import Foundation

enum MessageShareKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case workout
    case trainingPlan = "training_plan"
    case runningWorkout = "running_workout"
    case route
    case challenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout: return "Workout"
        case .trainingPlan: return "Training Plan"
        case .runningWorkout: return "Running Workout"
        case .route: return "Route"
        case .challenge: return "Challenge"
        }
    }

    var systemImage: String {
        switch self {
        case .workout: return "dumbbell.fill"
        case .trainingPlan: return "calendar"
        case .runningWorkout: return "figure.run"
        case .route: return "map.fill"
        case .challenge: return "bolt.fill"
        }
    }
}

struct DirectConversationRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let userA: UUID
    let userB: UUID
    let createdAt: Date
    let updatedAt: Date
    let lastMessageAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userA = "user_a"
        case userB = "user_b"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
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

struct MessageShareDraft: Hashable {
    let kind: MessageShareKind
    let title: String
    let subtitle: String?
    let payload: String
    let sourceObjectID: UUID?
    let sourceOwnerID: UUID?
    let shareVersion: Int

    init<T: Encodable>(
        kind: MessageShareKind,
        title: String,
        subtitle: String? = nil,
        snapshot: T,
        sourceObjectID: UUID? = nil,
        sourceOwnerID: UUID? = nil,
        shareVersion: Int = 1
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
