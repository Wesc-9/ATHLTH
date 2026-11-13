import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHHomeWorkoutComposerRecoveryTests: XCTestCase {
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
