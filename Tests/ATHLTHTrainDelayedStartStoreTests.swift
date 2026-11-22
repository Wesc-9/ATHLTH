import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainDelayedStartStoreTests: XCTestCase {
    func testRestoreKeepsOriginalPlannedWorkoutAndExactTime() {
        let name = "athlth.train.delay.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let userID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let checkpoint = ATHLTHTrainDelayedStartStore.Checkpoint(
            planID: UUID(), workoutID: UUID(), startsAt: now.addingTimeInterval(300)
        )
        ATHLTHTrainDelayedStartStore.save(checkpoint, for: userID, defaults: defaults)
        XCTAssertEqual(ATHLTHTrainDelayedStartStore.load(
            for: userID, now: now, defaults: defaults
        ), checkpoint)
        XCTAssertNil(ATHLTHTrainDelayedStartStore.load(
            for: UUID(), now: now, defaults: defaults
        ))
    }

    func testExpiredOrCancelledCheckpointCannotRestart() {
        let name = "athlth.train.delay.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let userID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let checkpoint = ATHLTHTrainDelayedStartStore.Checkpoint(
            planID: UUID(), workoutID: UUID(), startsAt: now.addingTimeInterval(-2_000)
        )
        ATHLTHTrainDelayedStartStore.save(checkpoint, for: userID, defaults: defaults)
        XCTAssertNil(ATHLTHTrainDelayedStartStore.load(
            for: userID, now: now, defaults: defaults
        ))
        ATHLTHTrainDelayedStartStore.save(
            .init(planID: UUID(), workoutID: UUID(), startsAt: now.addingTimeInterval(60)),
            for: userID, defaults: defaults
        )
        ATHLTHTrainDelayedStartStore.remove(for: userID, defaults: defaults)
        XCTAssertNil(ATHLTHTrainDelayedStartStore.load(
            for: userID, now: now, defaults: defaults
        ))
    }
}
