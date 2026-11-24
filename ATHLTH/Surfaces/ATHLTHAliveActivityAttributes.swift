import ActivityKit
import Foundation

/// Expressions are encoded as strings for compatibility with installed widgets.
enum ATHLTHAliveExpression: String, CaseIterable, Sendable {
    case awake, hello, wink, excited

    init(storedValue: String) {
        self = Self(rawValue: storedValue) ?? .awake
    }
}

/// Foreground Dynamic Island and Smart Stack experience.
/// The system may decline or suppress decorative Live Activities.
struct ATHLTHAliveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var expression: String
        var face: ATHLTHAliveExpression { .init(storedValue: expression) }
    }
    var openedAt: Date
}
