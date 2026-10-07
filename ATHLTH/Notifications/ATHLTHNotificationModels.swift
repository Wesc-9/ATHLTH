import Foundation

enum ATHLTHNotificationKind: String, Codable, Hashable {
    case workoutCompleted
    case milestoneReached
    case goalCompleted
    case personalRecord
    case achievement
    case challenge
    case social
    case system

    var title: String {
        switch self {
        case .workoutCompleted: return ATHLTHLocalization.string( "Workout completed")
        case .milestoneReached: return ATHLTHLocalization.string( "Milestone reached")
        case .goalCompleted: return ATHLTHLocalization.string( "Goal completed")
        case .personalRecord: return ATHLTHLocalization.string( "Personal record")
        case .achievement: return ATHLTHLocalization.string( "Achievement")
        case .challenge: return ATHLTHLocalization.string( "Challenge")
        case .social: return ATHLTHLocalization.string( "Social")
        case .system: return ATHLTHLocalization.string( "ATHLTH")
        }
    }

    var systemImage: String {
        switch self {
        case .workoutCompleted: return "checkmark.circle.fill"
        case .milestoneReached: return "flag.fill"
        case .goalCompleted: return "target"
        case .personalRecord: return "trophy.fill"
        case .achievement: return "medal.fill"
        case .challenge: return "trophy.fill"
        case .social: return "person.2.fill"
        case .system: return "bell.fill"
        }
    }
}

struct ATHLTHNotificationItem: Identifiable, Codable, Hashable {
    let id: UUID
    let eventKey: String
    var kind: ATHLTHNotificationKind
    var title: String
    var message: String
    var createdAt: Date
    var readAt: Date?
    var goalID: UUID?
    var workoutID: UUID?
    var challengeID: UUID?
    var backendEventID: UUID?
    var socialEventKind: String?
    var socialEntityType: String?
    var socialEntityID: UUID?
    var groupID: UUID?

    init(
        id: UUID = UUID(),
        eventKey: String,
        kind: ATHLTHNotificationKind,
        title: String,
        message: String,
        createdAt: Date = Date(),
        readAt: Date? = nil,
        goalID: UUID? = nil,
        workoutID: UUID? = nil,
        challengeID: UUID? = nil,
        backendEventID: UUID? = nil,
        socialEventKind: String? = nil,
        socialEntityType: String? = nil,
        socialEntityID: UUID? = nil,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.eventKey = eventKey
        self.kind = kind
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.readAt = readAt
        self.goalID = goalID
        self.workoutID = workoutID
        self.challengeID = challengeID
        self.backendEventID = backendEventID
        self.socialEventKind = socialEventKind
        self.socialEntityType = socialEntityType
        self.socialEntityID = socialEntityID
        self.groupID = groupID
    }

    var isUnread: Bool { readAt == nil }
}

struct ATHLTHNotificationDraft: Hashable {
    let eventKey: String
    let kind: ATHLTHNotificationKind
    let title: String
    let message: String
    let createdAt: Date
    let readAt: Date?
    let goalID: UUID?
    let workoutID: UUID?
    let challengeID: UUID?
    let backendEventID: UUID?
    let socialEventKind: String?
    let socialEntityType: String?
    let socialEntityID: UUID?
    let groupID: UUID?

    init(
        eventKey: String,
        kind: ATHLTHNotificationKind,
        title: String,
        message: String,
        createdAt: Date = Date(),
        readAt: Date? = nil,
        goalID: UUID? = nil,
        workoutID: UUID? = nil,
        challengeID: UUID? = nil,
        backendEventID: UUID? = nil,
        socialEventKind: String? = nil,
        socialEntityType: String? = nil,
        socialEntityID: UUID? = nil,
        groupID: UUID? = nil
    ) {
        self.eventKey = eventKey
        self.kind = kind
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.readAt = readAt
        self.goalID = goalID
        self.workoutID = workoutID
        self.challengeID = challengeID
        self.backendEventID = backendEventID
        self.socialEventKind = socialEventKind
        self.socialEntityType = socialEntityType
        self.socialEntityID = socialEntityID
        self.groupID = groupID
    }
}
