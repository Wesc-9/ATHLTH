import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWalkingRouteIntegrationTests: XCTestCase {
    private func sampleRoute() -> TrainingRoute {
        TrainingRoute(
            id: UUID(), ownerID: UUID(), title: "Søndagstur",
            visibility: .privateOnly,
            coordinates: [
                RouteCoordinate(latitude: 63.40, longitude: 10.40,
                                altitude: nil, sequence: 0),
                RouteCoordinate(latitude: 63.41, longitude: 10.41,
                                altitude: nil, sequence: 1)
            ],
            distanceKilometers: 5.0,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            routeSource: nil
        )
    }

    private func configuration() -> WalkQuickStartConfiguration {
        WalkQuickStartConfiguration(
            captureDevice: .iPhone,
            audioCoach: .disabled,
            autoPauseEnabled: true,
            spotifyPlaylist: nil,
            spotifyAutoplay: false,
            friends: [],
            socialMode: .physical,
            gearIDs: []
        )
    }

    func testSelectedWalkingRouteIsPreservedInLaunchAndInvitePayload() {
        let route = sampleRoute()
        var walking = configuration()
        walking.route = route
        let payload = walking.trainTogetherInvitePayload

        XCTAssertEqual(payload.workout.kind, .walking)
        XCTAssertEqual(payload.workout.routeID, route.id)
        XCTAssertEqual(payload.route?.id, route.id)
        XCTAssertEqual(payload.workout.title, route.title)
        XCTAssertEqual(payload.workout.targetDistanceKilometers, 5.0)
        XCTAssertEqual(walking.route?.coordinates.count, 2)
    }

    func testFreeWalkStillHasNoRoute() {
        let payload = configuration().trainTogetherInvitePayload
        XCTAssertEqual(payload.workout.kind, .walking)
        XCTAssertNil(payload.workout.routeID)
        XCTAssertNil(payload.route)
        XCTAssertNil(payload.workout.targetDistanceKilometers)
    }
}
