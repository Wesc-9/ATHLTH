import Foundation

enum ATHLTHNotificationKind: String, Codable, Hashable {
    case workoutCompleted
    case milestoneReached
    case goalCompleted
    case personalRecord
    case achievement
    case social
    case system

    var title: String {
        switch self {
        case .workoutCompleted: return "Workout completed"
        case .milestoneReached: return "Milestone reached"
        case .goalCompleted: return "Goal completed"
        case .personalRecord: return "Personal record"
        case .achievement: return "Achievement"
        case .social: return "Social"
        case .system: return "ATHLTH"
        }
    }

    var systemImage: String {
        switch self {
        case .workoutCompleted: return "checkmark.circle.fill"
        case .milestoneReached: return "flag.fill"
        case .goalCompleted: return "target"
        case .personalRecord: return "trophy.fill"
        case .achievement: return "medal.fill"
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
        challengeID: UUID? = nil
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
    }

    var isUnread: Bool { readAt == nil }
}

struct ATHLTHNotificationDraft: Hashable {
    let eventKey: String
    let kind: ATHLTHNotificationKind
    let title: String
    let message: String
    let createdAt: Date
    let goalID: UUID?
    let workoutID: UUID?
    let challengeID: UUID?

    init(
        eventKey: String,
        kind: ATHLTHNotificationKind,
        title: String,
        message: String,
        createdAt: Date = Date(),
        goalID: UUID? = nil,
        workoutID: UUID? = nil,
        challengeID: UUID? = nil
    ) {
        self.eventKey = eventKey
        self.kind = kind
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.goalID = goalID
        self.workoutID = workoutID
        self.challengeID = challengeID
    }
}
