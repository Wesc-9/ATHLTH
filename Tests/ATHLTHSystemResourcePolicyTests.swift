import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHSystemResourcePolicyTests: XCTestCase {
    func testNormalAndFairThermalStatesPreserveOptionalWork() {
        XCTAssertEqual(ATHLTHSystemResourcePolicy.resolve(lowPower: false, thermal: .nominal), .normal)
        XCTAssertEqual(ATHLTHSystemResourcePolicy.resolve(lowPower: false, thermal: .fair), .normal)
        XCTAssertTrue(ATHLTHSystemResourcePolicy.normal.allowsOptionalPreparation)
    }

    func testLowPowerAndSeriousThermalStateDeferOptionalWork() {
        XCTAssertEqual(ATHLTHSystemResourcePolicy.resolve(lowPower: true, thermal: .nominal), .constrained)
        XCTAssertEqual(ATHLTHSystemResourcePolicy.resolve(lowPower: false, thermal: .serious), .constrained)
        XCTAssertFalse(ATHLTHSystemResourcePolicy.constrained.allowsOptionalPreparation)
    }

    func testCriticalTemperatureWinsOverPowerMode() {
        for lowPower in [false, true] {
            XCTAssertEqual(ATHLTHSystemResourcePolicy.resolve(lowPower: lowPower, thermal: .critical), .critical)
        }
        XCTAssertFalse(ATHLTHSystemResourcePolicy.critical.allowsOptionalPreparation)
    }

    func testConstrainedCacheBudgetsAreBounded() {
        XCTAssertLessThan(ATHLTHSystemResourcePolicy.constrained.storageImageBudget,
                          ATHLTHSystemResourcePolicy.normal.storageImageBudget)
        XCTAssertLessThan(ATHLTHSystemResourcePolicy.constrained.exerciseThumbnailBudget,
                          ATHLTHSystemResourcePolicy.normal.exerciseThumbnailBudget)
        XCTAssertGreaterThan(ATHLTHSystemResourcePolicy.critical.storageImageBudget, 0)
    }
}
