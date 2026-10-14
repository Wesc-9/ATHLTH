import XCTest
@testable import ATHLTH

final class WorkoutLaunchHardeningTests: XCTestCase {
    func testCompletedResultReleasesOldWatchLockAndRejectsDelayedActiveMessage() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let old = WatchWorkoutActivityState(isActive: true, title: "Run", updatedAt: end.addingTimeInterval(-30))
        let resolved = WatchWorkoutActivityState.afterCompletion(current: old, endedAt: end)
        XCTAssertFalse(resolved.isActive)
        XCTAssertNil(resolved.title)
        XCTAssertGreaterThan(resolved.updatedAt, old.updatedAt)
    }

    func testDelayedCompletionDoesNotReleaseNewerWatchWorkout() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = WatchWorkoutActivityState(isActive: true, title: "New run", updatedAt: end.addingTimeInterval(5))
        XCTAssertEqual(WatchWorkoutActivityState.afterCompletion(current: newer, endedAt: end), newer)
        XCTAssertFalse(WatchWorkoutActivityState.afterCompletion(current: nil, endedAt: end).isActive)
    }

    @MainActor
    func testAIHealthConsentIsAccountScopedAndPersists() {
        let suite =
            "ATHLTHTests.\(UUID().uuidString)"
        let defaults =
            UserDefaults(suiteName: suite)!

        defer {
            defaults.removePersistentDomain(
                forName: suite
            )
        }

        let first = UUID()
        let second = UUID()
        let store =
            AppSessionStore(defaults: defaults)

        store.applyBackendBootstrap(
            bootstrap(first)
        )
        XCTAssertFalse(
            store.aiHealthDataSharingEnabled
        )

        store.setAIHealthDataSharingEnabled(true)
        XCTAssertTrue(
            store.aiHealthDataSharingEnabled
        )

        store.clearAfterSignOut()
        store.applyBackendBootstrap(
            bootstrap(second)
        )
        XCTAssertFalse(
            store.aiHealthDataSharingEnabled
        )

        store.clearAfterSignOut()
        store.applyBackendBootstrap(
            bootstrap(first)
        )
        XCTAssertTrue(
            store.aiHealthDataSharingEnabled
        )

        store.clearAfterAccountDeletion()
        store.applyBackendBootstrap(
            bootstrap(first)
        )
        XCTAssertFalse(
            store.aiHealthDataSharingEnabled
        )
    }

    @MainActor
    func testWatchLaunchSeesActiveIPhoneWorkoutLock() {
        let connection = AppleWatchConnectionStore()
        XCTAssertFalse(connection.hasActiveIPhoneWorkout)

        connection.updateLocalWorkoutActivity(
            isActive: true,
            title: "Local run"
        )
        XCTAssertTrue(connection.hasActiveIPhoneWorkout)

        connection.updateLocalWorkoutActivity(
            isActive: false,
            title: nil
        )
        XCTAssertFalse(connection.hasActiveIPhoneWorkout)
    }

    func testWatchActivityQueryUsesExplicitTransportAndCurrentSnapshot() throws {
        XCTAssertEqual(
            WatchTransferKind.workoutActivityQuery.rawValue,
            "workoutActivityQuery"
        )
        let finished = WatchWorkoutActivityState(
            isActive: false,
            title: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let restored = try JSONDecoder().decode(
            WatchWorkoutActivityState.self,
            from: JSONEncoder().encode(finished)
        )
        XCTAssertFalse(restored.isActive)
        XCTAssertNil(restored.title)
        XCTAssertEqual(restored.updatedAt, finished.updatedAt)
    }

    func testWatchActiveSnapshotRemainsActiveAfterLongWorkout() throws {
        let active = WatchWorkoutActivityState(
            isActive: true,
            title: "Long run",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let decoded = try JSONDecoder().decode(
            WatchWorkoutActivityState.self,
            from: JSONEncoder().encode(active)
        )
        XCTAssertTrue(decoded.isActive)
        XCTAssertEqual(decoded.title, "Long run")
    }

    func testWorkoutKindMappingIsCentralized() {
        XCTAssertEqual(
            PlannedWorkoutWatchBuilder.watchKind(
                for: .running
            ),
            .running
        )
        XCTAssertEqual(
            PlannedWorkoutWatchBuilder.watchKind(
                for: .walking
            ),
            .walking
        )
        XCTAssertEqual(
            PlannedWorkoutWatchBuilder.watchKind(
                for: .strength
            ),
            .strength
        )
        XCTAssertNil(
            PlannedWorkoutWatchBuilder.watchKind(
                for: .recovery
            )
        )
    }

    func testPlannedWorkoutResolvesRouteAndCoachDistance() throws {
        let owner = UUID()
        let routeID = UUID()

        let route = TrainingRoute(
            id: routeID,
            ownerID: owner,
            title: "Morning Loop",
            visibility: .privateOnly,
            coordinates: [],
            distanceKilometers: 7.25,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date()
        )

        var workout = PlannedSession(
            id: UUID(),
            title: "Run",
            kind: .running,
            exercises: []
        )
        workout.routeID = routeID
        workout.targetDistanceKilometers = 10

        let selected =
            PlannedWorkoutWatchBuilder.route(
                for: workout,
                routes: [route]
            )

        XCTAssertEqual(selected?.id, routeID)

        var defaults =
            WatchAudioCoachConfiguration.disabled
        defaults.enabled = true
        defaults.announceDistance = true

        let configuration =
            PlannedWorkoutWatchBuilder
                .audioCoachConfiguration(
                    for: workout,
                    selectedRoute: selected,
                    defaultConfiguration: defaults
                )

        XCTAssertTrue(configuration.enabled)
        XCTAssertEqual(
            try XCTUnwrap(
                configuration.routeDistanceMeters
            ),
            7_250,
            accuracy: 0.001
        )
    }

    func testPlannedRunningFallbackTransferUsesDistance() throws {
        var workout = PlannedSession(
            id: UUID(),
            title: "5K",
            kind: .running,
            exercises: []
        )
        workout.targetDistanceKilometers = 5
        workout.targetPaceSecondsPerKilometer = 300

        let transfer =
            PlannedWorkoutWatchBuilder
                .runningTransfer(
                    from: workout,
                    routeAlerts: .standard
                )

        XCTAssertEqual(transfer.title, "5K")
        XCTAssertEqual(transfer.steps.count, 1)
        XCTAssertEqual(
            transfer.steps.first?.measure,
            .distance
        )
        XCTAssertEqual(
            try XCTUnwrap(
                transfer.steps.first?.distanceMeters
            ),
            5_000,
            accuracy: 0.001
        )
        XCTAssertEqual(
            transfer.steps.first?
                .targetPaceMinSecondsPerKilometer,
            300
        )
        XCTAssertEqual(
            transfer.steps.first?
                .targetPaceMaxSecondsPerKilometer,
            300
        )
    }

    private func bootstrap(
        _ id: UUID
    ) -> BackendUserBootstrap {
        BackendUserBootstrap(
            profile: BackendProfile(
                id: id,
                onboardingCompleted: true,
                createdAt: Date(),
                updatedAt: Date()
            ),
            role: BackendAccountRole(
                userID: id,
                role: "user"
            ),
            entitlement:
                BackendSubscriptionEntitlement(
                    userID: id,
                    tier: "free",
                    status: "inactive",
                    source: "none",
                    trialStartedAt: nil,
                    trialEndsAt: nil,
                    appStoreProductID: nil,
                    currentPeriodEndsAt: nil
                )
        )
    }


    func testAudioCoachDuckingDefaultsOnForLegacyPayloads() throws {
        let legacyJSON = """
        {
          "enabled": true,
          "language": "system",
          "distanceIntervalMeters": 1000,
          "timeIntervalSeconds": null,
          "announceDistance": true,
          "announceElapsedTime": true,
          "announceAveragePace": true,
          "announceClockTime": false,
          "announceHeartRate": false,
          "announceRemainingRouteDistance": false,
          "announceEstimatedRemainingRouteTime": false,
          "routeDistanceMeters": null,
          "announceCurrentWorkoutStep": false,
          "announceRemainingStepTime": false,
          "announceRemainingStepDistance": false
        }
        """

        let decoded = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertNil(decoded.duckOtherAudio)
        XCTAssertTrue(decoded.shouldDuckOtherAudio)
    }

    func testAudioCoachDuckingSurvivesWatchTransferEncoding() throws {
        var configuration =
            WatchAudioCoachConfiguration.disabled
        configuration.enabled = true
        configuration.duckOtherAudio = false

        let data =
            try JSONEncoder().encode(
                configuration
            )
        let decoded =
            try JSONDecoder().decode(
                WatchAudioCoachConfiguration.self,
                from: data
            )

        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(
            decoded.duckOtherAudio,
            false
        )
        XCTAssertFalse(
            decoded.shouldDuckOtherAudio
        )
    }

}
