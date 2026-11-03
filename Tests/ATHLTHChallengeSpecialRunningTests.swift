import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHChallengeSpecialRunningTests: XCTestCase {
    private func result(
        sourceID: UUID,
        fullyCompleted: Bool = true,
        workUserReported: Bool = false
    ) -> WatchWorkoutResult {
        let now = Date()
        var output = WatchWorkoutResult(
            id: UUID(),
            kind: .running,
            healthKitWorkoutUUID: nil,
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now,
            duration: 1_200,
            activeCalories: 110,
            distanceMeters: 3_000,
            averageHeartRate: 145,
            maxHeartRate: 175,
            routePointCount: 40
        )
        output.structuredWorkoutFullyCompleted = fullyCompleted
        output.structuredWorkoutSourceID = sourceID
        output.recordedRunningSteps = [
            .init(index: 0, title: "Warmup", phase: "warmup",
                  activeSeconds: 250, distanceMeters: 900),
            .init(index: 1, title: "Up hill", phase: "work",
                  activeSeconds: 70, distanceMeters: 220,
                  isUserReported: workUserReported),
            .init(index: 2, title: "Downhill", phase: "recovery",
                  activeSeconds: 110, distanceMeters: 220),
            .init(index: 3, title: "Up hill 2", phase: "work",
                  activeSeconds: 65, distanceMeters: 210),
            .init(index: 4, title: "Cooldown", phase: "cooldown",
                  activeSeconds: 240, distanceMeters: 600)
        ]
        return output
    }

    func testOnlyWorkIntervalsContributeToChallengeScore() {
        let source = UUID()
        let measured = ATHLTHChallengeRunningWorkPolicy.measuredWork(
            from: result(sourceID: source),
            expectedTemplateID: source,
            minimumRepetitions: 2
        )
        XCTAssertEqual(measured?.count, 2)
        XCTAssertEqual(measured?.seconds, 135)
        XCTAssertEqual(measured?.meters, 430)
        // 900 m warmup, 220 m downhill and 600 m cooldown are excluded.
    }

    func testWorkIsRejectedWhenWorkoutNotCompleted() {
        let source = UUID()
        XCTAssertNil(ATHLTHChallengeRunningWorkPolicy.measuredWork(
            from: result(sourceID: source, fullyCompleted: false),
            expectedTemplateID: source,
            minimumRepetitions: 2
        ))
    }

    func testWorkRejectsWrongWorkoutOrInsufficientRepetitions() {
        let source = UUID()
        XCTAssertNil(ATHLTHChallengeRunningWorkPolicy.measuredWork(
            from: result(sourceID: source),
            expectedTemplateID: UUID(),
            minimumRepetitions: 2
        ))
        XCTAssertNil(ATHLTHChallengeRunningWorkPolicy.measuredWork(
            from: result(sourceID: source),
            expectedTemplateID: source,
            minimumRepetitions: 3
        ))
    }

    func testManuallyReportedTreadmillDataDoesNotQualifyAsVerified() {
        let source = UUID()
        XCTAssertNil(ATHLTHChallengeRunningWorkPolicy.measuredWork(
            from: result(sourceID: source, workUserReported: true),
            expectedTemplateID: source,
            minimumRepetitions: 2
        ))
    }

    func testChallengeAutomaticTitleLeavesNamesToParticipantCaption() {
        XCTAssertEqual(
            ChallengeCreationPolicy.resolvedTitle(
                "", sport: .running, scoring: .fastestDistance,
                creatorName: "Stian", invitedNames: ["Malin"],
                scoringTitle: "Løping • Lengst distanse i drag"
            ),
            "Løping • Lengst distanse i drag"
        )
    }

    func testRunningVenueCanRepresentAllThreeLocations() {
        XCTAssertEqual(ATHLTHChallengeRunningVenue.outdoor.rawValue, "outdoor")
        XCTAssertEqual(ATHLTHChallengeRunningVenue.indoor.rawValue, "indoor")
        XCTAssertEqual(ATHLTHChallengeRunningVenue.treadmill.rawValue, "treadmill")
    }

    func testIntervalComposerDraftPreservesSelectedTemplateAndVenue() throws {
        let templateID = UUID()
        let original = ATHLTHChallengeCreationDraft(
            title: "", summary: "",
            sport: .running, scoring: .farthestInTime,
            runningFocus: .intervals, runningComparison: .mostWorkDistance,
            runningTemplateID: templateID, runningVenue: .treadmill,
            invited: [], startsAt: Date(), endsAt: Date(),
            hasEnd: true, coverArtwork: "GoalRunning",
            allowMultipleAttempts: false
        )
        let restored = try JSONDecoder().decode(
            ATHLTHChallengeCreationDraft.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(restored.runningTemplateID, templateID)
        XCTAssertEqual(restored.runningFocus, .intervals)
        XCTAssertEqual(restored.runningComparison, .mostWorkDistance)
        XCTAssertEqual(restored.runningVenue, .treadmill)
    }

    func testCustomTitleIsNeverOverridden() {
        XCTAssertEqual(
            ChallengeCreationPolicy.resolvedTitle(
                "Min intervallutfordring",
                sport: .running, scoring: .fastestDistance,
                creatorName: "Stian", invitedNames: ["Malin"]
            ),
            "Min intervallutfordring"
        )
    }
}
