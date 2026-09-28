import XCTest
@testable import ATHLTH

final class WorkoutLaunchHardeningTests: XCTestCase {
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

}
