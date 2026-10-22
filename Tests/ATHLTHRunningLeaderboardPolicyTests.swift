import XCTest
@testable import ATHLTH

final class ATHLTHRunningLeaderboardPolicyTests: XCTestCase {
    private func step(_ phase: String, seconds: Double) -> WatchRunningWorkoutStep {
        WatchRunningWorkoutStep(
            id: UUID(), title: phase, measure: .time,
            distanceMeters: nil, durationSeconds: seconds,
            intensityText: nil, phase: phase
        )
    }

    private func sample(_ index: Int, phase: String,
                        seconds: Double, meters: Double,
                        manual: Bool = false) -> ATHLTHRecordedRunningStep {
        ATHLTHRecordedRunningStep(
            index: index, title: phase, phase: phase,
            activeSeconds: seconds, distanceMeters: meters,
            isUserReported: manual
        )
    }

    private var canonical: WatchRunningWorkoutTransfer {
        WatchRunningWorkoutTransfer(
            title: "4 × 4",
            steps: [
                step("warmup", seconds: 600),
                step("work", seconds: 240),
                step("recovery", seconds: 120),
                step("work", seconds: 240),
                step("cooldown", seconds: 600)
            ]
        )
    }

    private var complete: [ATHLTHRecordedRunningStep] {
        [
            sample(0, phase: "warmup", seconds: 780, meters: 1200),
            sample(1, phase: "work", seconds: 240, meters: 900),
            sample(2, phase: "recovery", seconds: 120, meters: 150),
            sample(3, phase: "work", seconds: 240, meters: 950),
            sample(4, phase: "cooldown", seconds: 930, meters: 1300)
        ]
    }

    func testExtendedWarmupAndCooldownDoNotChangeMainScore() {
        let verdict = ATHLTHRunningLeaderboardPolicy.evaluate(
            planned: canonical, recorded: complete
        )
        XCTAssertTrue(verdict.eligible)
        XCTAssertEqual(verdict.mainActiveSeconds, 480, accuracy: 0.01)
        XCTAssertEqual(verdict.mainDistanceMeters, 1850, accuracy: 0.01)
        XCTAssertEqual(verdict.mainSpeedKilometersPerHour ?? 0, 13.875, accuracy: 0.001)
    }

    func testLongerRestDisqualifiesLeaderboardEntry() {
        var recorded = complete
        recorded[2].activeSeconds = 150
        XCTAssertFalse(ATHLTHRunningLeaderboardPolicy.evaluate(
            planned: canonical, recorded: recorded
        ).eligible)
    }

    func testManualDistanceAndEditedSessionNeverQualify() {
        var recorded = complete
        recorded[1].isUserReported = true
        XCTAssertFalse(ATHLTHRunningLeaderboardPolicy.evaluate(
            planned: canonical, recorded: recorded
        ).eligible)
        XCTAssertFalse(ATHLTHRunningLeaderboardPolicy.evaluate(
            planned: canonical, recorded: complete, modifiedDuringWorkout: true
        ).eligible)
    }

    func testEditedRestRecipeDisqualifiesEvenWhenAthleteFollowsEdit() {
        let original = canonical
        var edited = original
        edited.steps[2].durationSeconds = 150
        var followed = complete
        followed[2].activeSeconds = 150

        XCTAssertFalse(ATHLTHRunningLeaderboardPolicy.evaluate(
            canonical: original, executed: edited, recorded: followed
        ).eligible)
    }

    func testIndividualPaceTargetMayDifferWithoutChangingOfficialStructure() {
        let original = canonical
        var personalized = original
        personalized.steps[1].targetPaceMinSecondsPerKilometer = 230
        personalized.steps[3].targetPaceMinSecondsPerKilometer = 210
        XCTAssertTrue(ATHLTHRunningLeaderboardPolicy.evaluate(
            canonical: original, executed: personalized, recorded: complete
        ).eligible)
    }

    func testMissingOrUnfinishedPhasesNeverQualify() {
        XCTAssertFalse(ATHLTHRunningLeaderboardPolicy.evaluate(
            planned: canonical, recorded: Array(complete.dropLast())
        ).eligible)
        var recorded = complete
        recorded[3].activeSeconds = 190
        XCTAssertFalse(ATHLTHRunningLeaderboardPolicy.evaluate(
            planned: canonical, recorded: recorded
        ).eligible)
    }
}
