import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHHomeWorkoutComposerRecoveryTests: XCTestCase {
    func testColdLaunchRecoversTheOriginalCalendarDayForSameAccount() {
        let userID = UUID()
        let otherID = UUID()
        let suite = "athlth.home.navigation.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Isolated defaults unavailable")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selectedDay = 710_000_000.0

        ATHLTHHomeWorkoutComposerRecoveryPolicy.save(
            accountID: userID, day: selectedDay, defaults: defaults, now: now
        )
        XCTAssertEqual(
            ATHLTHHomeWorkoutComposerRecoveryPolicy.load(
                for: userID, defaults: defaults, now: now
            )?.day, selectedDay
        )
        XCTAssertNil(ATHLTHHomeWorkoutComposerRecoveryPolicy.load(
            for: otherID, defaults: defaults, now: now
        ))
        ATHLTHHomeWorkoutComposerRecoveryPolicy.clear(
            for: otherID, defaults: defaults
        )
        XCTAssertNotNil(ATHLTHHomeWorkoutComposerRecoveryPolicy.load(
            for: userID, defaults: defaults, now: now
        ))
        ATHLTHHomeWorkoutComposerRecoveryPolicy.clear(
            for: userID, defaults: defaults
        )
        XCTAssertNil(ATHLTHHomeWorkoutComposerRecoveryPolicy.load(
            for: userID, defaults: defaults, now: now
        ))
    }

    func testExpiredOrMalformedComposerNeverAutoOpens() {
        let userID = UUID()
        let suite = "athlth.home.navigation.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Isolated defaults unavailable")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        ATHLTHHomeWorkoutComposerRecoveryPolicy.save(
            accountID: userID, day: 710_000_000,
            defaults: defaults, now: now
        )
        XCTAssertNil(ATHLTHHomeWorkoutComposerRecoveryPolicy.load(
            for: userID, defaults: defaults,
            now: now.addingTimeInterval(15 * 86_400)
        ))
        ATHLTHHomeWorkoutComposerRecoveryPolicy.clear(
            for: userID, defaults: defaults
        )
        ATHLTHHomeWorkoutComposerRecoveryPolicy.save(
            accountID: userID, day: .nan, defaults: defaults, now: now
        )
        XCTAssertNil(ATHLTHHomeWorkoutComposerRecoveryPolicy.load(
            for: userID, defaults: defaults, now: now
        ))
    }

    func testRestoresOnlySameAccountWithValidDate() {
        let id = UUID()
        XCTAssertTrue(ATHLTHHomeWorkoutComposerRecoveryPolicy.canRestore(
            account: id.uuidString, currentAccountID: id, day: 600_000_000
        ))
        XCTAssertFalse(ATHLTHHomeWorkoutComposerRecoveryPolicy.canRestore(
            account: UUID().uuidString, currentAccountID: id, day: 600_000_000
        ))
        for day in [0.0, -1.0, Double.infinity, Double.nan] {
            XCTAssertFalse(ATHLTHHomeWorkoutComposerRecoveryPolicy.canRestore(
                account: id.uuidString, currentAccountID: id, day: day
            ))
        }
    }
}
