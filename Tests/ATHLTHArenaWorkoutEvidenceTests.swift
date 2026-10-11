import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaWorkoutEvidenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let duration: TimeInterval = 1_500

    private func recordedRun(distance: Double, duration: Double = 1_500) -> SocialPublishableWorkout {
        let workout = PhoneWorkout(
            walking: false,
            start: start,
            end: start.addingTimeInterval(duration),
            accumulatedSeconds: duration,
            lastCheckpoint: start.addingTimeInterval(duration),
            distanceMeters: distance
        )
        return SocialPublishableWorkout(phoneWorkout: workout)
    }

    private func match(
        _ workout: SocialPublishableWorkout,
        as template: ATHLTHArenaRoundTemplate
    ) -> ATHLTHArenaEvidenceMatcher.Match? {
        ATHLTHArenaEvidenceMatcher.match(
            workout,
            template: template,
            startsAt: start.addingTimeInterval(-60),
            endsAt: start.addingTimeInterval(7_200)
        )
    }

    func testNearFiveKilometerFinishedRunSuggestsElapsedTime() {
        let matched = match(recordedRun(distance: 5_010), as: .fastest5K)
        XCTAssertEqual(matched?.metricType, "elapsed_seconds")
        XCTAssertEqual(matched?.metricValue, duration)
    }

    func testTenKilometerRunIsNotMisclassifiedAsFiveKilometerTime() {
        XCTAssertNil(match(recordedRun(distance: 10_000), as: .fastest5K))
    }

    func testFastestKilometerRequiresCorrectDistance() {
        let oneK = recordedRun(distance: 1_000, duration: 240)
        XCTAssertEqual(match(oneK, as: .fastest1K)?.metricValue, 240)
        XCTAssertNil(match(oneK, as: .fastest5K))
    }

    func testImpossibleFiveKilometerTimeIsNotSuggested() {
        XCTAssertNil(match(recordedRun(distance: 5_000, duration: 550), as: .fastest5K))
    }

    func testImpossibleOneKilometerTimeIsNotSuggested() {
        XCTAssertNil(match(recordedRun(distance: 1_000, duration: 90), as: .fastest1K))
    }

    func testImpossibleDistanceSpeedIsNotSuggested() {
        XCTAssertNil(match(recordedRun(distance: 10_000, duration: 600), as: .mostDistance))
    }

    func testUnsupportedExerciseSpecificRoundIsNotAutoMatched() {
        let workout = recordedRun(distance: 5_000)
        XCTAssertNil(match(workout, as: .mostRepetitions))
        XCTAssertNil(match(workout, as: .custom))
    }

    func testOutsideCompetitionWindowIsExcluded() {
        let workout = recordedRun(distance: 5_000)
        let result = ATHLTHArenaEvidenceMatcher.match(
            workout,
            template: .fastest5K,
            startsAt: start.addingTimeInterval(20),
            endsAt: start.addingTimeInterval(7_200)
        )
        XCTAssertNil(result)
    }

    func testOneWorkoutIsEligibleForDistanceSuggestion() {
        let result = match(recordedRun(distance: 5_000), as: .mostDistance)
        XCTAssertEqual(result?.metricType, "distance_meters")
        XCTAssertEqual(result?.metricValue, 5_000)
    }
}
