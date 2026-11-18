import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHRouteHomePrivacyPolicyTests: XCTestCase {
    private func route(
        hideStart: Bool,
        hideEnd: Bool,
        visibility: ProfileVisibility = .friends,
        count: Int = 11,
        step: Double = 0.001
    ) -> TrainingRoute {
        let points = (0..<count).map {
            RouteCoordinate(
                latitude: 63.4 + Double($0) * step,
                longitude: 10.4,
                altitude: nil,
                sequence: $0
            )
        }
        return TrainingRoute(
            id: UUID(), ownerID: UUID(),
            title: "Hjem → Parken",
            visibility: visibility,
            coordinates: points,
            distanceKilometers: Double(count - 1) * 0.111,
            elevationGainMeters: 24,
            importedFilename: nil,
            createdAt: Date(),
            startName: "Hjem", endName: "Parken",
            hideSharedStartNearHome: hideStart,
            hideSharedEndNearHome: hideEnd
        )
    }

    func testStartAtHomeIsCroppedWithoutChangingOwnedRoute() {
        let original = route(hideStart: true, hideEnd: false)
        let publicCopy = ATHLTHRouteHomePrivacyPolicy.sharedVersion(of: original)
        XCTAssertNotNil(publicCopy)
        XCTAssertEqual(original.coordinates.count, 11)
        XCTAssertGreaterThan(publicCopy!.coordinates.first!.latitude, 63.402)
        XCTAssertEqual(publicCopy!.coordinates.last, original.coordinates.last)
        XCTAssertEqual(publicCopy!.startName, "Skjult start")
        XCTAssertFalse(publicCopy!.title.contains("Hjem"))
        XCTAssertNil(publicCopy!.hideSharedStartNearHome)
        XCTAssertNil(publicCopy!.elevationGainMeters)
    }

    func testOnlyFinishAtHomeHidesFinish() {
        let original = route(hideStart: false, hideEnd: true)
        let shared = ATHLTHRouteHomePrivacyPolicy.sharedVersion(of: original)!
        XCTAssertEqual(shared.coordinates.first, original.coordinates.first)
        XCTAssertLessThan(shared.coordinates.last!.latitude, 63.408)
        XCTAssertEqual(shared.endName, "Skjult slutt")
    }

    func testBothHomeEndpointsAreCropped() {
        let original = route(hideStart: true, hideEnd: true)
        let shared = ATHLTHRouteHomePrivacyPolicy.sharedVersion(of: original)!
        XCTAssertGreaterThan(shared.coordinates.first!.latitude, 63.402)
        XCTAssertLessThan(shared.coordinates.last!.latitude, 63.408)
        XCTAssertLessThan(shared.coordinates.count, original.coordinates.count)
    }

    func testShortRouteNeverFallsBackToPublishingFullTrack() {
        let original = route(
            hideStart: true, hideEnd: false, count: 3, step: 0.0004
        )
        XCTAssertNil(ATHLTHRouteHomePrivacyPolicy.sharedVersion(of: original))
    }

    func testPrivateOrNonHomeRoutesRemainUnchanged() {
        let privateRoute = route(
            hideStart: true, hideEnd: true, visibility: .privateOnly
        )
        XCTAssertEqual(
            ATHLTHRouteHomePrivacyPolicy.sharedVersion(of: privateRoute),
            privateRoute
        )
        let unchanged = route(hideStart: false, hideEnd: false)
        XCTAssertEqual(
            ATHLTHRouteHomePrivacyPolicy.sharedVersion(of: unchanged),
            unchanged
        )
    }
}
