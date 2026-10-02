import Foundation

enum CampaignAudience: String, Codable, Hashable, CaseIterable, Identifiable {
    case freeUsers
    case paidUsers
    case allUsers
    case personalizedSegment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeUsers: return "Free users"
        case .paidUsers: return "ATHLTH+ users"
        case .allUsers: return "All users"
        case .personalizedSegment: return "Personalized segment"
        }
    }
}

enum CampaignChannel: String, Codable, Hashable, CaseIterable, Identifiable {
    case inApp
    case push
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inApp: return "In-app"
        case .push: return "Push"
        case .email: return "Email"
        }
    }

    var systemImage: String {
        switch self {
        case .inApp: return "rectangle.on.rectangle"
        case .push: return "bell.fill"
        case .email: return "envelope.fill"
        }
    }
}

enum CampaignDeliveryStatus: String, Codable, Hashable {
    case draft
    case scheduled
    case sent
    case cancelled
    case blocked

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .scheduled: return "Scheduled"
        case .sent: return "Sent"
        case .cancelled: return "Cancelled"
        case .blocked: return "Blocked"
        }
    }
}

struct CampaignRecipientSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID
    var username: String
    var deliveredAt: Date?
    var openedAt: Date?
    var convertedAt: Date?
}

struct CampaignHistoryRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var message: String
    var audience: CampaignAudience
    var channels: Set<CampaignChannel>
    var status: CampaignDeliveryStatus
    var createdByUsername: String
    var createdAt: Date
    var sentAt: Date?
    var audienceCount: Int
    var deliveredCount: Int
    var openedCount: Int
    var convertedCount: Int
    var recipients: [CampaignRecipientSnapshot]
}

struct UserCampaignEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var campaignID: UUID
    var campaignTitle: String
    var channels: Set<CampaignChannel>
    var status: CampaignDeliveryStatus
    var sentAt: Date?
    var openedAt: Date?
    var convertedAt: Date?
}
