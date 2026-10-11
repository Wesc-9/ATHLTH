import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaLocalEvidenceCheckTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_790_000_000)

    private func run(
        id: UUID = UUID(),
        distance: Double = 5_000,
        duration: Double = 1_600,
        finished: Bool = true
    ) -> PhoneWorkout {
        PhoneWorkout(
            id: id,
            walking: false,
            start: started,
            end: finished ? started.addingTimeInterval(duration) : nil,
            accumulatedSeconds: duration,
            lastCheckpoint: started.addingTimeInterval(duration),
            distanceMeters: distance
        )
    }

    func testFinishedAthlthPhoneWorkoutMatchesLocalHistory() {
        let original = run()
        let presented = SocialPublishableWorkout(phoneWorkout: original)
        XCTAssertEqual(
            ATHLTHArenaLocalEvidenceCheck.verify(
                presented, health: [], phone: [original], strength: []
            ),
            .athlthRecording
        )
    }

    func testWorkoutMissingFromHistoryCannotBeShared() {
        let published = SocialPublishableWorkout(phoneWorkout: run())
        XCTAssertEqual(
            ATHLTHArenaLocalEvidenceCheck.verify(
                published, health: [], phone: [], strength: []
            ),
            .missingRecord
        )
    }

    func testAlteredDistanceConflictsWithOriginalLog() {
        var original = run()
        let published = SocialPublishableWorkout(phoneWorkout: original)
        original.distanceMeters = 8_500
        XCTAssertEqual(
            ATHLTHArenaLocalEvidenceCheck.verify(
                published, health: [], phone: [original], strength: []
            ),
            .conflictingRecord
        )
    }

    func testDeletedAndUnfinishedLogDoesNotQualify() {
        var recorded = run()
        let published = SocialPublishableWorkout(phoneWorkout: recorded)
        recorded.end = nil
        XCTAssertEqual(
            ATHLTHArenaLocalEvidenceCheck.verify(
                published, health: [], phone: [recorded], strength: []
            ),
            .missingRecord
        )
    }

    func testDifferentWorkoutUUIDNeverQualifiesEvenWithSameStats() {
        let presented = SocialPublishableWorkout(phoneWorkout: run())
        let otherWorkout = run()
        XCTAssertEqual(
            ATHLTHArenaLocalEvidenceCheck.verify(
                presented, health: [], phone: [otherWorkout], strength: []
            ),
            .missingRecord
        )
    }
}
