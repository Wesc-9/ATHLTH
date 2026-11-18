import Foundation

/// Avoid redundant account writes from repeated owner-profile openings.
enum ATHLTHProfileRefreshPolicy {
    static func shouldSyncMostTrained(
        userID: UUID,
        local: [ATHLTHProfileHighlights.TrainedItem],
        previousUserID: UUID?,
        previousLocal: [ATHLTHProfileHighlights.TrainedItem],
        lastSyncedAt: Date?,
        now: Date = Date(),
        maxAge: TimeInterval = 180
    ) -> Bool {
        guard previousUserID == userID,
              previousLocal == local,
              let lastSyncedAt else { return true }
        return now.timeIntervalSince(lastSyncedAt) >= maxAge
    }
}
