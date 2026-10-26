import ActivityKit
import Foundation

/// Experimental, foreground-only Dynamic Island experience.
/// The system may decline or suppress decorative Live Activities.
struct ATHLTHAliveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var expression: String
    }
    var openedAt: Date
}
