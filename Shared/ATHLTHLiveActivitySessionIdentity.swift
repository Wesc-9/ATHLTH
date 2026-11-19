import Foundation

/// Session identity is intentionally independent of Live Activity's mutable
/// display title. The Watch may rename the route, but an existing activity
/// must not be attached to the next workout of the same sport.
struct ATHLTHLiveActivitySessionIdentity: Equatable {
    var systemImage: String
    var startedAt: Date?
    var fallbackTitle: String

    /// Reject a delayed update for the same Live Activity without
    /// rejecting an explicitly new workout. ActivityKit presentation only.
    static func acceptsCapturedAt(
        currentIdentity: Self?,
        incomingIdentity: Self,
        currentCapturedAt: Date?,
        incomingCapturedAt: Date
    ) -> Bool {
        guard incomingCapturedAt.timeIntervalSince1970.isFinite else {
            return false
        }
        guard let currentIdentity,
              currentIdentity.matches(incomingIdentity),
              let currentCapturedAt else { return true }
        return incomingCapturedAt >= currentCapturedAt
    }

    func matches(_ other: Self) -> Bool {
        guard systemImage == other.systemImage else { return false }
        switch (startedAt, other.startedAt) {
        case let (lhs?, rhs?):
            return abs(lhs.timeIntervalSince(rhs)) < 2
        case (nil, nil):
            return fallbackTitle == other.fallbackTitle
        default:
            return false
        }
    }
}
