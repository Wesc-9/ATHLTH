import Foundation

/// Same-account request notification. Never represents a grant of permission.
/// Only the recording iPhone may approve an *exact current session* locally.
struct ATHLTHLiveViewRequest: Codable, Equatable, Identifiable {
    let userID: UUID
    let requestID: UUID
    let requestedAt: Date
    let expiresAt: Date
    var status: String
    var respondedAt: Date?
    var approvedSessionID: UUID?

    var id: UUID { requestID }
    var isPending: Bool { status == "pending" && expiresAt > .now }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case requestID = "request_id"
        case requestedAt = "requested_at"
        case expiresAt = "expires_at"
        case status
        case respondedAt = "responded_at"
        case approvedSessionID = "approved_session_id"
    }
}

/// One short-lived request status, not a standing account permission.
enum ATHLTHLiveViewRequestState: String {
    case idle, sending, pending, denied, approved, expired, failed
}

struct ATHLTHLiveViewDecision: Encodable {
    let status: String
    let respondedAt: Date
    let approvedSessionID: UUID?

    enum CodingKeys: String, CodingKey {
        case status
        case respondedAt = "responded_at"
        case approvedSessionID = "approved_session_id"
    }
}
