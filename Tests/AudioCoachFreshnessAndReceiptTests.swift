import XCTest
@testable import ATHLTH

final class AudioCoachFreshnessAndReceiptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testHeartRateNeedsRecentPlausibleMeasurement() {
        XCTAssertTrue(
            ATHLTHCoachSensorFreshness.validHeartRate(
                142,
                sampledAt: now.addingTimeInterval(-8),
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validHeartRate(
                142,
                sampledAt: now.addingTimeInterval(-20),
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validHeartRate(
                0,
                sampledAt: now,
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validHeartRate(
                .nan,
                sampledAt: now,
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validHeartRate(
                142,
                sampledAt: nil,
                now: now
            )
        )
    }

    func testPaceRejectsOldImpossibleAndMissingGps() {
        XCTAssertTrue(
            ATHLTHCoachSensorFreshness.validPace(
                320,
                sampledAt: now.addingTimeInterval(-5),
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validPace(
                320,
                sampledAt: now.addingTimeInterval(-12),
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validPace(
                40,
                sampledAt: now,
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validPace(
                .infinity,
                sampledAt: now,
                now: now
            )
        )
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.validPace(
                nil,
                sampledAt: now,
                now: now
            )
        )
    }

    func testFutureSensorTimestampsCannotTriggerCoachAlerts() {
        XCTAssertFalse(
            ATHLTHCoachSensorFreshness.isFresh(
                sampledAt: now.addingTimeInterval(8),
                maximumAge: 12,
                now: now
            )
        )
    }

    func testReceiptIsSessionBoundAndShortLived() {
        let started = now.addingTimeInterval(-180)
        let receipt = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: started,
            eventKind: .routineMilestone,
            eventKey: "d1000",
            sentAt: now
        )
        XCTAssertTrue(receipt.isValid(for: started, now: now))
        XCTAssertFalse(
            receipt.isValid(
                for: started.addingTimeInterval(40),
                now: now
            )
        )
        XCTAssertFalse(
            receipt.isValid(
                for: started,
                now: now.addingTimeInterval(15)
            )
        )
        XCTAssertEqual(receipt.deliveryID, "routineMilestone:d1000")
    }

    func testReceiptRejectsUntrustedKindsAndLargeIds() {
        let started = now.addingTimeInterval(-20)
        let ghost = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: started,
            eventKind: .ghostUpdate,
            eventKey: "sensitive",
            sentAt: now
        )
        XCTAssertFalse(ghost.isValid(for: started, now: now))
        let oversized = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: started,
            eventKind: .runningStep,
            eventKey: String(repeating: "a", count: 90),
            sentAt: now
        )
        XCTAssertFalse(oversized.isValid(for: started, now: now))
    }

    func testCompanionReceiptSuppressesOnlyTheSameEvent() throws {
        let started = now.addingTimeInterval(-60)
        let receipt = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: started,
            eventKind: .runningStep,
            eventKey: "3",
            sentAt: now
        )
        let decoded = try JSONDecoder().decode(
            ATHLTHCoachDeliveryReceipt.self,
            from: JSONEncoder().encode(receipt)
        )
        var ledger = ATHLTHCoachEventLedger()
        XCTAssertTrue(decoded.isValid(for: started, now: now))
        ledger.noteCompanionDelivery(id: decoded.deliveryID)

        let alreadySpoken = ATHLTHCoachEvent(
            kind: .runningStep,
            key: "3",
            priority: .structuredStep,
            createdAt: now,
            validFor: 12
        )
        XCTAssertFalse(ledger.canDeliver(alreadySpoken, now: now))
        let nextStep = ATHLTHCoachEvent(
            kind: .runningStep,
            key: "4",
            priority: .structuredStep,
            createdAt: now,
            validFor: 12
        )
        XCTAssertTrue(ledger.canDeliver(nextStep, now: now))
    }

    func testCompanionReceiptsAreBoundedAndResetPerWorkout() {
        var ledger = ATHLTHCoachEventLedger()
        for index in 0..<(ATHLTHCoachEventLedger.maxEntries + 15) {
            ledger.noteCompanionDelivery(id: "runningStep:\(index)")
        }
        XCTAssertEqual(ledger.deliveredIDs.count, ATHLTHCoachEventLedger.maxEntries)
        ledger.reset()
        XCTAssertTrue(ledger.deliveredIDs.isEmpty)
    }

    func testNewSnapshotTimestampsRemainOptionalForOldWatchBuilds() throws {
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .running,
            state: .running,
            startedAt: now.addingTimeInterval(-10),
            capturedAt: now,
            elapsedTime: 10,
            heartRate: 150,
            activeCalories: 10,
            distanceMeters: 20,
            averageHeartRate: nil,
            maxHeartRate: nil,
            routePointCount: 1
        )
        let old = try JSONDecoder().decode(
            WatchWorkoutLiveSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertNil(old.coachHeartRateSampleAt)
        XCTAssertNil(old.coachPaceSampleAt)

        snapshot.coachHeartRateSampleAt = now
        snapshot.coachPaceSampleAt = now
        let updated = try JSONDecoder().decode(
            WatchWorkoutLiveSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(updated.coachHeartRateSampleAt, now)
        XCTAssertEqual(updated.coachPaceSampleAt, now)
    }
}
