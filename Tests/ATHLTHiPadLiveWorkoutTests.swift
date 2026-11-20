import Foundation
import XCTest
@testable import ATHLTH

/// The iPad live companion is a spectator, never a second workout recorder.
/// Missing metrics stay unknown and counters do not run on after sync stalls.
final class ATHLTHiPadLiveWorkoutTests: XCTestCase {
    private func snapshot(
        paused: Bool? = false,
        elapsed: TimeInterval = 540,
        capturedAt: Date? = Date(timeIntervalSince1970: 1_000),
        stepRemaining: TimeInterval? = 70,
        completedSets: Int? = nil,
        totalSets: Int? = nil
    ) -> ATHLTHCrossDeviceWorkoutSnapshot {
        ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: UUID(),
            kind: "running",
            title: "4 × 4",
            startedAt: Date(timeIntervalSince1970: 460),
            elapsedSeconds: elapsed,
            distanceMeters: 1_400,
            currentStep: "Effort 2",
            nextStep: "Recovery",
            completedSets: completedSets,
            totalSets: totalSets,
            paused: paused,
            runningIntervalOrdinal: 2,
            runningIntervalTotal: 4,
            runningInRecovery: false,
            runningStepRemainingSeconds: stepRemaining,
            capturedAt: capturedAt
        )
    }

    func testTimerExtrapolatesOnlyBrieflyAndNeverPastSourceTTL() {
        let now = Date(timeIntervalSince1970: 1_020)
        let remote = snapshot()
        XCTAssertEqual(ATHLTHiPadLiveMetrics.elapsed(remote, at: now), 548)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.remaining(remote, at: now), 62)
        XCTAssertTrue(ATHLTHiPadLiveMetrics.isDelayed(remote, at: now))
        XCTAssertEqual(ATHLTHiPadLiveMetrics.duration(548), "09:08")
    }

    func testPausePreservesRecordedElapsedAndCountdown() {
        let now = Date(timeIntervalSince1970: 1_030)
        let paused = snapshot(paused: true)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.elapsed(paused, at: now), 540)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.remaining(paused, at: now), 70)
    }

    func testMissingSensorDataDoesNotInventNumbers() {
        XCTAssertEqual(ATHLTHiPadLiveMetrics.heartRate(nil), "—")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.pace(nil), "—")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.calories(nil), "—")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.distance(nil), "—")
        XCTAssertNil(ATHLTHiPadLiveMetrics.normalized(Double.nan))
        XCTAssertNil(ATHLTHiPadLiveMetrics.normalized(5))
    }

    func testAveragePaceUsesActualDistanceAndElapsed() {
        let workout = snapshot(elapsed: 600)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.averagePace(workout), "7:09")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.pace(300), "5:00")
    }

    func testOlderPrivateSnapshotDecodesWithoutNewOptionalTelemetry() throws {
        let original = snapshot()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ATHLTHCrossDeviceWorkoutSnapshot.self, from: encoded
        )
        XCTAssertNil(decoded.sourceDevice)
        XCTAssertNil(decoded.heartRateBPM)
        XCTAssertNil(decoded.currentPaceSecondsPerKilometer)
        XCTAssertEqual(decoded.elapsedSeconds, 540)
        XCTAssertEqual(decoded.runningIntervalOrdinal, 2)
    }

    @MainActor
    func testIpadReceivesExplicitStrengthLoadBasisOnlyWhenKnown() throws {
        var workout = snapshot()
        workout.strengthLoadBasisRaw = "kilogramsPerHand"
        workout.strengthWeightKilograms = 18
        // Only strength workouts should carry a strength-specific weight
        // interpretation into the spectator payload.
        let running = ATHLTHCrossDeviceWorkoutStore.boundedSpectatorSnapshot(
            workout
        )
        XCTAssertNil(running.strengthLoadBasisRaw)

        let data = try JSONEncoder().encode(workout)
        var decoded = try JSONDecoder().decode(
            ATHLTHCrossDeviceWorkoutSnapshot.self, from: data
        )
        decoded = ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: decoded.sessionID,
            kind: "strength",
            title: decoded.title,
            startedAt: decoded.startedAt,
            elapsedSeconds: decoded.elapsedSeconds,
            distanceMeters: nil,
            currentStep: "Shoulder press",
            nextStep: nil,
            completedSets: 1,
            totalSets: 3,
            strengthWeightKilograms: 18,
            strengthLoadBasisRaw: "kilogramsPerHand"
        )
        let bounded = ATHLTHCrossDeviceWorkoutStore.boundedSpectatorSnapshot(
            decoded
        )
        XCTAssertEqual(bounded.strengthLoadBasisRaw, "kilogramsPerHand")
        XCTAssertEqual(
            bounded.strengthLoadBasisRaw.flatMap(
                ATHLTHStrengthLoadBasis.init(rawValue:)
            ),
            .kilogramsPerHand
        )
    }

    @MainActor
    func testIpadRejectsUnknownOrInventedWeightBasis() {
        var workout = ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: UUID(),
            kind: "strength",
            title: "Strength",
            startedAt: Date(),
            elapsedSeconds: 90,
            distanceMeters: nil,
            currentStep: "Press",
            nextStep: nil,
            completedSets: 0,
            totalSets: 3
        )
        XCTAssertNil(workout.strengthLoadBasisRaw)
        workout.strengthLoadBasisRaw = "unsupported"
        XCTAssertNil(ATHLTHCrossDeviceWorkoutStore.boundedSpectatorSnapshot(
            workout
        ).strengthLoadBasisRaw)
        workout.strengthLoadBasisRaw = "totalKilograms"
        XCTAssertEqual(ATHLTHCrossDeviceWorkoutStore.boundedSpectatorSnapshot(
            workout
        ).strengthLoadBasisRaw, "totalKilograms")
    }

    @MainActor
    func testPrivateIpadStrengthSyncPreservesWeightBasisWithoutGuessingLegacy() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        var exercise = Exercise(
            id: UUID(), origin: .custom, ownerID: UUID(),
            name: "Dumbbell Press", instructions: [],
            primaryMuscles: ["shoulders"], secondaryMuscles: [],
            equipment: ["dumbbells"], imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        exercise.coachLoadBasis = .kilogramsPerHand
        store.appendExercise(
            exercise, sets: 2, reps: 8,
            targetWeightKilograms: 20, restSeconds: 0
        )
        let snapshot = try XCTUnwrap(
            ATHLTHPrivateLiveStrengthSnapshot.make(from: store)
        )
        XCTAssertEqual(snapshot.plannedLoadBasisRaw, "kilogramsPerHand")
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(
            ATHLTHPrivateLiveStrengthSnapshot.self, from: encoded
        )
        XCTAssertEqual(decoded.plannedLoadBasisRaw, "kilogramsPerHand")

        // A previous app version has no such field; nil is intentional.
        var dictionary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        dictionary.removeValue(forKey: "plannedLoadBasisRaw")
        let legacy = try JSONDecoder().decode(
            ATHLTHPrivateLiveStrengthSnapshot.self,
            from: JSONSerialization.data(withJSONObject: dictionary)
        )
        XCTAssertNil(legacy.plannedLoadBasisRaw)
        XCTAssertEqual(legacy.plannedWeightKilograms, 20)
    }

    func testStrengthSetsAreReadOnlyAndNeverExceedTotal() {
        let workout = snapshot(completedSets: 12, totalSets: 10)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.sets(workout), "10 / 10")
    }

    func testLiveViewPermissionCannotTransferFromPreviousWorkout() {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let owner = UUID()
        var request = ATHLTHLiveViewRequest(
            userID: owner, requestID: UUID(),
            requestedAt: now.addingTimeInterval(-20),
            expiresAt: now.addingTimeInterval(90),
            status: "pending", respondedAt: nil, approvedSessionID: nil
        )
        XCTAssertTrue(ATHLTHLiveViewSessionRequestPolicy.mayPromptOwner(
            request, accountID: owner,
            sourceStartedAt: now.addingTimeInterval(-50), at: now
        ))
        XCTAssertFalse(ATHLTHLiveViewSessionRequestPolicy.mayPromptOwner(
            request, accountID: owner,
            sourceStartedAt: now.addingTimeInterval(-5), at: now
        ))
        XCTAssertFalse(ATHLTHLiveViewSessionRequestPolicy.mayPromptOwner(
            request, accountID: UUID(),
            sourceStartedAt: now.addingTimeInterval(-50), at: now
        ))
        request.status = "denied"
        XCTAssertFalse(ATHLTHLiveViewSessionRequestPolicy.mayPromptOwner(
            request, accountID: owner,
            sourceStartedAt: now.addingTimeInterval(-50), at: now
        ))
    }


    @MainActor
    func testPrivateStrengthMirrorCountsSkippedEMOMOnlyOnce() throws {
        let id = UUID()
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: "squat", distanceMeters: nil,
            repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: 20, loadNote: nil,
            notes: nil, phase: .main
        )
        block.groupID = id
        block.groupKind = .emom
        block.groupRounds = 1
        block.groupClockSeconds = 60
        var plan = PlannedSession(
            id: UUID(), title: "iPad mirror", kind: .strength,
            scheduledStart: nil, durationMinutes: 5,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        plan.workoutBlocks = [block]
        let store = StrengthWorkoutStore()
        store.start(session: plan, watchSessionID: nil, trackingMode: .advanced, captureDevice: .iPhone)
        XCTAssertTrue(store.skipCurrentSet())
        let snapshot = try XCTUnwrap(
            ATHLTHPrivateLiveStrengthSnapshot.make(from: store)
        )
        XCTAssertEqual(snapshot.totalPlannedSets, 1)
        XCTAssertEqual(snapshot.skippedSets, 1)
        XCTAssertEqual(snapshot.exercises.first?.plannedSets, 1)
        XCTAssertEqual(snapshot.exercises.first?.skippedSets, 1)
        XCTAssertEqual(snapshot.completedSets, 0)
    }


    func testIpadReconnectAcceptsOnlyFreshOwnerApprovedTelemetry() {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        var remote = ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: UUID(), kind: "strength", title: "Strength",
            startedAt: now.addingTimeInterval(-600), elapsedSeconds: 600,
            distanceMeters: nil, currentStep: "Squat", nextStep: nil,
            completedSets: 2, totalSets: 6
        )
        remote.capturedAt = now.addingTimeInterval(-3)
        XCTAssertTrue(ATHLTHCrossDeviceLiveReadPolicy.accepts(
            remote,
            updatedAt: now.addingTimeInterval(-2),
            expiresAt: now.addingTimeInterval(28),
            at: now
        ))
        remote.capturedAt = now.addingTimeInterval(-80)
        XCTAssertFalse(ATHLTHCrossDeviceLiveReadPolicy.accepts(
            remote,
            updatedAt: now.addingTimeInterval(-1),
            expiresAt: now.addingTimeInterval(28),
            at: now
        ), "A relay heartbeat must not revive an old Watch sensor snapshot.")
        remote.capturedAt = now.addingTimeInterval(-2)
        XCTAssertFalse(ATHLTHCrossDeviceLiveReadPolicy.accepts(
            remote,
            updatedAt: now.addingTimeInterval(-40),
            expiresAt: now.addingTimeInterval(28),
            at: now
        ))
        XCTAssertFalse(ATHLTHCrossDeviceLiveReadPolicy.accepts(
            remote,
            updatedAt: now.addingTimeInterval(-1),
            expiresAt: now.addingTimeInterval(-1),
            at: now
        ))
    }

    func testLegacyIpadSnapshotWithoutCaptureDateUsesOnlyFreshHeartbeat() {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let old = ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: UUID(), kind: "running", title: "Run",
            startedAt: now.addingTimeInterval(-120),
            elapsedSeconds: 120, distanceMeters: 500,
            currentStep: nil, nextStep: nil,
            completedSets: nil, totalSets: nil
        )
        XCTAssertNil(old.capturedAt)
        XCTAssertTrue(ATHLTHCrossDeviceLiveReadPolicy.accepts(
            old, updatedAt: now.addingTimeInterval(-5),
            expiresAt: now.addingTimeInterval(25), at: now
        ))
        XCTAssertFalse(ATHLTHCrossDeviceLiveReadPolicy.accepts(
            old, updatedAt: now.addingTimeInterval(-50),
            expiresAt: now.addingTimeInterval(25), at: now
        ))
        var invalid = old
        invalid.elapsedSeconds = .infinity
        XCTAssertFalse(ATHLTHCrossDeviceLiveReadPolicy.accepts(
            invalid, updatedAt: now.addingTimeInterval(-1),
            expiresAt: now.addingTimeInterval(25), at: now
        ))
    }


    func testWatchSpectatorKeepsOneSessionIDAfterReconnect() throws {
        let owner = UUID()
        let workoutID = UUID()
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var mirror = WatchWorkoutLiveSnapshot(
            kind: .cycling, state: .running,
            startedAt: start, capturedAt: start.addingTimeInterval(60),
            elapsedTime: 45, heartRate: 120,
            activeCalories: 30, distanceMeters: 100,
            averageHeartRate: nil, maxHeartRate: nil,
            routePointCount: 0
        )
        mirror.accountOwnerID = owner
        mirror.universalWorkoutID = workoutID
        XCTAssertTrue(ATHLTHWatchSpectatorSessionPolicy.canRelay(
            mirror, to: owner
        ))
        XCTAssertEqual(
            ATHLTHWatchSpectatorSessionPolicy.verifiedID(mirror), workoutID
        )
        mirror.state = .paused
        mirror.capturedAt = start.addingTimeInterval(120)
        XCTAssertEqual(
            ATHLTHWatchSpectatorSessionPolicy.verifiedID(mirror), workoutID
        )
        XCTAssertFalse(ATHLTHWatchSpectatorSessionPolicy.canRelay(
            mirror, to: UUID()
        ))
        XCTAssertFalse(ATHLTHWatchSpectatorSessionPolicy.canRelay(
            mirror, to: nil
        ))
        mirror.accountOwnerID = nil
        XCTAssertFalse(ATHLTHWatchSpectatorSessionPolicy.canRelay(
            mirror, to: owner
        ))
    }

    func testWatchSpectatorRejectsConflictingStrengthIDs() {
        var mirror = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .running,
            startedAt: Date(), capturedAt: Date(),
            elapsedTime: 10, heartRate: 100, activeCalories: 5,
            distanceMeters: 0, averageHeartRate: nil,
            maxHeartRate: nil, routePointCount: 0
        )
        mirror.strengthWorkoutID = UUID()
        mirror.universalWorkoutID = UUID()
        XCTAssertTrue(
            ATHLTHWatchSpectatorSessionPolicy.hasContradictoryIdentity(mirror)
        )
        XCTAssertNil(ATHLTHWatchSpectatorSessionPolicy.verifiedID(mirror))
        mirror.universalWorkoutID = mirror.strengthWorkoutID
        XCTAssertFalse(
            ATHLTHWatchSpectatorSessionPolicy.hasContradictoryIdentity(mirror)
        )
        XCTAssertEqual(
            ATHLTHWatchSpectatorSessionPolicy.verifiedID(mirror),
            mirror.strengthWorkoutID
        )
    }



    @MainActor
    func testManualAndStructuredSpectatorsCannotPublishFakeSensors() {
        for evidence in ["manualTimer", "structuredManual"] {
            var source = snapshot()
            source.captureEvidence = evidence
            source.heartRateBPM = 155
            source.activeCalories = 160
            source.currentPaceSecondsPerKilometer = 270
            source.liveLatitude = 63.4
            source.liveLongitude = 10.4
            source.livePositionAt = .now
            let result = ATHLTHCrossDeviceWorkoutStore.boundedSpectatorSnapshot(
                source
            )
            XCTAssertEqual(result.sessionID, source.sessionID)
            XCTAssertEqual(result.elapsedSeconds, source.elapsedSeconds)
            XCTAssertNil(result.distanceMeters)
            XCTAssertNil(result.heartRateBPM)
            XCTAssertNil(result.activeCalories)
            XCTAssertNil(result.currentPaceSecondsPerKilometer)
            XCTAssertNil(result.liveLatitude)
            XCTAssertNil(result.liveLongitude)
            XCTAssertNil(result.livePositionAt)
        }
    }

    @MainActor
    func testSportsCannotAccidentallyInheritRunningPaceInIpadRelay() {
        for sport in ["cycling", "rowing", "hiit", "functional", "yoga", "strength"] {
            var source = ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: UUID(), kind: sport, title: sport,
                startedAt: Date(), elapsedSeconds: 1200,
                distanceMeters: 4000,
                currentStep: nil, nextStep: nil,
                completedSets: nil, totalSets: nil
            )
            source.captureEvidence = "watchHealthKit"
            source.currentPaceSecondsPerKilometer = 280
            source.targetPaceSecondsPerKilometer = 300
            let result = ATHLTHCrossDeviceWorkoutStore.boundedSpectatorSnapshot(source)
            XCTAssertNil(result.currentPaceSecondsPerKilometer, sport)
            XCTAssertNil(result.targetPaceSecondsPerKilometer, sport)
            if !ATHLTHSpectatorSportMetricPolicy.supportsDistance(sport) {
                XCTAssertNil(result.distanceMeters, sport)
            }
        }
        XCTAssertTrue(ATHLTHSpectatorSportMetricPolicy.supportsDistance("cycling"))
        XCTAssertTrue(ATHLTHSpectatorSportMetricPolicy.supportsDistance("rowing"))
        XCTAssertFalse(ATHLTHSpectatorSportMetricPolicy.supportsRunningPace("cycling"))
        XCTAssertFalse(ATHLTHSpectatorSportMetricPolicy.supportsDistance("yoga"))
    }

    func testOptionalEvidenceSurvivesOldSnapshotDecoding() throws {
        let old = try JSONEncoder().encode(snapshot())
        let read = try JSONDecoder().decode(ATHLTHCrossDeviceWorkoutSnapshot.self, from: old)
        XCTAssertNil(read.captureEvidence)
    }


    @MainActor
    func testIpadCyclingAndRowingUseSportSpecificAverageUnits() {
        func sensorSport(_ category: String, meters: Double, elapsed: Double)
            -> ATHLTHCrossDeviceWorkoutSnapshot {
            var s = ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: UUID(), kind: category, title: category,
                startedAt: Date(), elapsedSeconds: elapsed,
                distanceMeters: meters, currentStep: nil, nextStep: nil,
                completedSets: nil, totalSets: nil
            )
            s.captureEvidence = "watchHealthKit"
            return ATHLTHCrossDeviceWorkoutStore.boundedSpectatorSnapshot(s)
        }
        let cycling = sensorSport("cycling", meters: 30_000, elapsed: 3_600)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.averageSpeed(cycling), "30.0")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.averageRowingSplit(cycling), "—")
        let rowing = sensorSport("rowing", meters: 5_000, elapsed: 1_200)
        XCTAssertEqual(ATHLTHiPadLiveMetrics.averageRowingSplit(rowing), "2:00")
        XCTAssertEqual(ATHLTHiPadLiveMetrics.averageSpeed(rowing), "—")
    }

    func testIpadManualSpectatorNeverInfersSportSpeedOrRowingSplit() {
        for category in ["cycling", "rowing"] {
            var s = ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: UUID(), kind: category, title: category,
                startedAt: Date(), elapsedSeconds: 500,
                distanceMeters: 3_000, currentStep: nil,
                nextStep: nil, completedSets: nil, totalSets: nil
            )
            s.captureEvidence = "manualTimer"
            XCTAssertEqual(ATHLTHiPadLiveMetrics.averageSpeed(s), "—")
            XCTAssertEqual(ATHLTHiPadLiveMetrics.averageRowingSplit(s), "—")
        }
    }

}
