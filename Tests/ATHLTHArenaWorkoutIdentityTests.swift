import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaWorkoutIdentityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func workout(
        id: UUID = UUID(),
        startDelta: TimeInterval = 0,
        duration: TimeInterval = 1_600,
        distance: Double = 5_000,
        walking: Bool = false
    ) -> SocialPublishableWorkout {
        let started = start.addingTimeInterval(startDelta)
        let log = PhoneWorkout(
            id: id,
            walking: walking,
            start: started,
            end: started.addingTimeInterval(duration),
            accumulatedSeconds: duration,
            lastCheckpoint: started.addingTimeInterval(duration),
            distanceMeters: distance
        )
        return SocialPublishableWorkout(phoneWorkout: log)
    }

    private func entry(
        matching workout: SocialPublishableWorkout,
        user: UUID
    ) -> ATHLTHArenaWorkoutEvidence {
        ATHLTHArenaWorkoutEvidence(
            id: UUID(),
            seriesID: UUID(),
            roundID: UUID(),
            slotID: UUID(),
            userID: user,
            sourceWorkoutID: workout.id,
            source: "iphone",
            activityType: workout.activity == .walking ? "walking" : "running",
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            metricType: "distance_meters",
            metricValue: workout.distanceMeters ?? 0,
            reportedDistanceMeters: workout.distanceMeters,
            reportedRouteMatchPercent: nil,
            verificationLevel: "participant_reported"
        )
    }

    func testSameActivitySameIntervalDifferentUUIDsCountOnce() {
        let a = workout()
        let b = workout(id: UUID(), startDelta: 30, distance: 5_035)
        XCTAssertTrue(ATHLTHArenaWorkoutIdentity.samePhysicalWorkout(a, b))
        XCTAssertEqual(
            ATHLTHArenaWorkoutIdentity.distinct([a, b]).count, 1
        )
    }

    func testDifferentTimesAreDifferentWorkoutsEvenAtSameDistance() {
        let a = workout()
        let b = workout(startDelta: 2 * 3_600)
        XCTAssertFalse(ATHLTHArenaWorkoutIdentity.samePhysicalWorkout(a, b))
    }

    func testDifferentActivityDoesNotCollapse() {
        let a = workout()
        let b = workout(walking: true)
        XCTAssertFalse(ATHLTHArenaWorkoutIdentity.samePhysicalWorkout(a, b))
    }

    func testDifferentDistancesCannotBeTreatedAsMirrors() {
        let a = workout()
        let b = workout(distance: 10_000)
        XCTAssertFalse(ATHLTHArenaWorkoutIdentity.samePhysicalWorkout(a, b))
    }

    func testAlreadySharedMirroredUUIDBlocksSecondShare() {
        let athlete = UUID()
        let original = workout()
        let mirror = workout(startDelta: 30, distance: 5_035)
        XCTAssertTrue(ATHLTHArenaWorkoutIdentity.alreadyShared(
            mirror,
            entries: [entry(matching: original, user: athlete)],
            userID: athlete
        ))
    }

    func testAnotherAthleteHistoryDoesNotBlockOwnWorkout() {
        let athlete = UUID()
        let original = workout()
        XCTAssertFalse(ATHLTHArenaWorkoutIdentity.alreadyShared(
            original,
            entries: [entry(matching: original, user: UUID())],
            userID: athlete
        ))
    }
}
