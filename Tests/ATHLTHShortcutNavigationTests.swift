import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHShortcutNavigationTests: XCTestCase {
    func testOnlyKnownFreshRoutesCanBeOpened() {
        let now = Date()
        for route in ATHLTHShortcutNavigation.allCases {
            let token = route.token(now: now)
            XCTAssertEqual(ATHLTHShortcutNavigation.route(from: token, now: now), route)
            XCTAssertNil(ATHLTHShortcutNavigation.route(from: token, now: now.addingTimeInterval(61)))
            XCTAssertNil(ATHLTHShortcutNavigation.route(from: token, now: now.addingTimeInterval(-1)))
        }
        XCTAssertNil(ATHLTHShortcutNavigation.route(from: "start|123|unknown", now: now))
    }

    @MainActor func testTokenIsConsumedOnlyOnce() {
        let key = ATHLTHShortcutNavigation.preferenceKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let token = ATHLTHShortcutNavigation.coach.token()
        UserDefaults.standard.set(token, forKey: key)
        XCTAssertEqual(ATHLTHShortcutNavigation.consume(token), .coach)
        XCTAssertNil(ATHLTHShortcutNavigation.consume(token))
    }
}
