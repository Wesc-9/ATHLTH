import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHFourByFourRecordsTests: XCTestCase {
    private func step(
        _ index: Int, phase: String, seconds: Double, distance: Double,
        reported: Bool = false
    ) -> ATHLTHRecordedRunningStep {
        ATHLTHRecordedRunningStep(
            index: index, title: phase, phase: phase,
            activeSeconds: seconds, distanceMeters: distance,
            isUserReported: reported
        )
    }

    private func standard() -> [ATHLTHRecordedRunningStep] {
        [
            step(0, phase: "warmup", seconds: 720, distance: 1000),
            step(1, phase: "work", seconds: 240, distance: 1000),
            step(2, phase: "recovery", seconds: 120, distance: 210),
            step(3, phase: "work", seconds: 240, distance: 1020),
            step(4, phase: "recovery", seconds: 120, distance: 230),
            step(5, phase: "work", seconds: 240, distance: 1010),
            step(6, phase: "recovery", seconds: 120, distance: 250),
            step(7, phase: "work", seconds: 240, distance: 1100),
            step(8, phase: "cooldown", seconds: 970, distance: 1200)
        ]
    }

    private func result(
        _ steps: [ATHLTHRecordedRunningStep]
    ) -> ATHLTHFourByFourRecords.Result? {
        ATHLTHFourByFourRecords.qualifyingResult(
            steps: steps, id: UUID(),
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func testExactlyFourEffortsAndThreeRestPeriodsCount() throws {
        let record = try XCTUnwrap(result(standard()))
        XCTAssertEqual(record.mainSeconds, 960, accuracy: 0.01)
        XCTAssertEqual(record.mainDistanceMeters, 4130, accuracy: 0.01)
        XCTAssertEqual(record.averageSpeedKmh, 15.4875, accuracy: 0.01)
        XCTAssertFalse(record.reported)
    }

    func testExtendedWarmupAndCoolDownNeverChangeMainPace() throws {
        var phases = standard()
        let original = try XCTUnwrap(result(phases))
        phases[0].activeSeconds += 400
        phases[8].activeSeconds += 250
        let later = try XCTUnwrap(result(phases))
        XCTAssertEqual(later.averagePaceSecondsPerKilometer,
                       original.averagePaceSecondsPerKilometer, accuracy: 0.01)
    }

    func testChangedRestMakesFourByFourIncomparable() {
        var phases = standard()
        phases[4].activeSeconds = 180
        XCTAssertNil(result(phases))
    }

    func testIncompleteMainPhaseDoesNotProduceARecord() {
        XCTAssertNil(result(Array(standard().dropLast(2))))
        var phases = standard()
        phases[5].activeSeconds = 170
        XCTAssertNil(result(phases))
    }

    func testManualTreadmillPaceRemainsExplicitlyReported() throws {
        var phases = standard()
        phases[1].isUserReported = true
        let item = try XCTUnwrap(result(phases))
        XCTAssertTrue(item.reported)
    }
}
