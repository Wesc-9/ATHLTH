import Foundation

struct BackendProfile: Codable, Sendable {
    let id: UUID
    var username: String?
    var displayName: String?
    var bio: String?
    var avatarURL: String?
    var onboardingCompleted: Bool
    var onboardingCompletedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case onboardingCompleted = "onboarding_completed"
        case onboardingCompletedAt = "onboarding_completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BackendAccountRole: Codable, Sendable {
    let userID: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case role
    }
}

struct BackendSubscriptionEntitlement: Codable, Sendable {
    let userID: UUID
    let tier: String
    let status: String
    let source: String
    let trialStartedAt: Date?
    let trialEndsAt: Date?
    let appStoreProductID: String?
    let currentPeriodEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case tier
        case status
        case source
        case trialStartedAt = "trial_started_at"
        case trialEndsAt = "trial_ends_at"
        case appStoreProductID = "app_store_product_id"
        case currentPeriodEndsAt = "current_period_ends_at"
    }
}

struct BackendUserBootstrap: Sendable {
    let profile: BackendProfile
    let role: BackendAccountRole
    let entitlement: BackendSubscriptionEntitlement
}
