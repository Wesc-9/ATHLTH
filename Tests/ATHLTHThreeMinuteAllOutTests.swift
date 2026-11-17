import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHThreeMinuteAllOutTests: XCTestCase {
    func testCriticalSpeedAndDPrimeFromMeasuredDistances() throws {
        // Measured 900 m total, 120 m during the final 30 seconds.
        // CS = 120/30 = 4 m/s; D′ = 900 − 4×180 = 180 m.
        let result = try XCTUnwrap(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: 900, finalThirtySecondsMeters: 120
        ))
        XCTAssertEqual(result.criticalSpeedMetersPerSecond, 4, accuracy: 0.00001)
        XCTAssertEqual(result.criticalSpeedKilometersPerHour, 14.4, accuracy: 0.00001)
        XCTAssertEqual(result.criticalPaceSecondsPerKilometer, 250, accuracy: 0.00001)
        XCTAssertEqual(result.distanceAboveCriticalSpeedMeters, 180, accuracy: 0.00001)
        XCTAssertEqual(ATHLTHThreeMinuteAllOut.paceText(
            secondsPerKilometer: result.criticalPaceSecondsPerKilometer
        ), "4:10")
    }

    func testRejectsImpossibleAndPacedResults() {
        XCTAssertNil(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: 0, finalThirtySecondsMeters: 100
        ))
        XCTAssertNil(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: 600, finalThirtySecondsMeters: 120
        )) // Constant speed -> D′ = 0, not a plausible all-out decline.
        XCTAssertNil(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: 600, finalThirtySecondsMeters: 130
        )) // Faster at the end: D′ would be negative.
        XCTAssertNil(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: 800, finalThirtySecondsMeters: 370
        ))
        XCTAssertNil(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: .nan, finalThirtySecondsMeters: 100
        ))
        XCTAssertNil(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: .infinity, finalThirtySecondsMeters: 100
        ))
        XCTAssertNil(ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: 800, finalThirtySecondsMeters: -1
        ))
    }

    @MainActor
    func testRunningAssessmentIsRecognizedButOrdinaryThreeMinuteIntervalsAreNot() throws {
        let threeMinute = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "ASS-009" }
        )
        let steps = ATHLTHZonedPlanLibrary.blocks(for: threeMinute)
        XCTAssertTrue(ATHLTHThreeMinuteAllOut.isRunningTest(
            title: "3-Minute All-Out Test", blocks: steps
        ))
        XCTAssertTrue(ATHLTHThreeMinuteAllOut.isRunningTest(
            title: "3 min maksimaltest", blocks: steps
        ))
        XCTAssertFalse(ATHLTHThreeMinuteAllOut.isRunningTest(
            title: "4×4-intervaller", blocks: steps
        ))
        let other = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "ASS-005" }
        )
        XCTAssertFalse(ATHLTHThreeMinuteAllOut.isRunningTest(
            title: "3MT", blocks: ATHLTHZonedPlanLibrary.blocks(for: other)
        ))
    }

    @MainActor
    func testThreeMinuteProtocolUsesThreeTenSecondStridesAndPreservesSourceTime() throws {
        let previousLanguage = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")
        let workout = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "ASS-009" }
        )
        let blocks = ATHLTHZonedPlanLibrary.blocks(for: workout)
        let warmup = blocks.filter { $0.resolvedPhase == .warmup }
        let strides = warmup.filter { $0.title.contains("/3") }
        XCTAssertEqual(strides.count, 3)
        XCTAssertTrue(strides.allSatisfy { $0.durationSeconds == 10 })
        XCTAssertEqual(warmup.compactMap(\.durationSeconds).reduce(0, +), 900)
        XCTAssertEqual(blocks.compactMap(\.durationSeconds).reduce(0, +), 1_680)
        let test = try XCTUnwrap(
            blocks.first {
                $0.resolvedPhase == .main && $0.title == "3 min maksimaltest"
            }
        )
        XCTAssertEqual(test.durationSeconds, 180)
        XCTAssertTrue(test.notes?.contains("første sekund") == true)
        XCTAssertTrue(test.notes?.contains("2:30 og 3:00") == true)
        XCTAssertNil(test.targetPaceSecondsPerKilometer)
    }
}
