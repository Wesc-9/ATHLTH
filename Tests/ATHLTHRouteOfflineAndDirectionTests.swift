import CoreLocation
import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRouteOfflineAndDirectionTests: XCTestCase {
    private func location(_ latitude: Double, _ longitude: Double) -> CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    func testOppositeDirectionsAreClassifiedSeparatelyOnLoop() {
        let course = [
            location(63.40, 10.40),
            location(63.4018, 10.40),
            location(63.4018, 10.404),
            location(63.40, 10.404),
            location(63.40, 10.40)
        ]
        XCTAssertEqual(
            ATHLTHRouteAttemptDirectionPolicy.classify(
                reference: course, actual: course
            ),
            .forward
        )
        XCTAssertEqual(
            ATHLTHRouteAttemptDirectionPolicy.classify(
                reference: course, actual: Array(course.reversed())
            ),
            .reverse
        )
    }

    func testOverlappingOutAndBackDoesNotInventDirection() {
        let course = [
            location(63.4, 10.4),
            location(63.402, 10.4),
            location(63.4, 10.4)
        ]
        XCTAssertEqual(
            ATHLTHRouteAttemptDirectionPolicy.classify(
                reference: course, actual: course
            ),
            .unknown
        )
    }

    func testPointToPointDirectionUsesBothEndpoints() {
        let course = [
            location(63.4, 10.4),
            location(63.405, 10.405),
            location(63.41, 10.41)
        ]
        XCTAssertEqual(
            ATHLTHRouteAttemptDirectionPolicy.classify(
                reference: course, actual: course
            ), .forward
        )
        XCTAssertEqual(
            ATHLTHRouteAttemptDirectionPolicy.classify(
                reference: course, actual: Array(course.reversed())
            ), .reverse
        )
    }

    private func attempt(
        userID: UUID,
        seconds: Double,
        direction: ATHLTHRouteAttemptDirection?,
        ageDays: Double = 0
    ) -> RouteAttemptRecord {
        RouteAttemptRecord(
            id: UUID(),
            routeID: UUID(),
            userID: userID,
            workoutID: UUID(),
            activityType: "running",
            startedAt: Date().addingTimeInterval(-ageDays * 86400),
            durationSeconds: seconds,
            distanceMeters: 5000,
            routeMatchPercent: 95,
            averageDeviationMeters: 8,
            maxDeviationMeters: 24,
            source: "apple_health",
            direction: direction,
            username: nil,
            displayName: nil,
            avatarURL: nil
        )
    }

    func testBestTimesAreNeverMixedAcrossDirectionsOrUnknownLegacyRows() {
        let user = UUID()
        let records = [
            attempt(userID: user, seconds: 1200, direction: .forward, ageDays: 2),
            attempt(userID: user, seconds: 1340, direction: .reverse, ageDays: 1),
            attempt(userID: user, seconds: 1020, direction: .unknown, ageDays: 3),
            attempt(userID: UUID(), seconds: 1050, direction: .reverse)
        ]
        let forward = ATHLTHRouteAttemptDirectionPolicy.bestByAthlete(
            records, direction: .forward
        )
        let reverse = ATHLTHRouteAttemptDirectionPolicy.bestByAthlete(
            records, direction: .reverse
        )
        XCTAssertEqual(forward.count, 1)
        XCTAssertEqual(forward[0].durationSeconds, 1200)
        XCTAssertEqual(reverse.count, 2)
        XCTAssertEqual(reverse[0].durationSeconds, 1050)
        XCTAssertFalse(reverse.contains { $0.durationSeconds == 1020 })
    }

    func testOwnAttemptProgressComparesOnlySameDirection() {
        let user = UUID()
        let attempts = [
            attempt(userID: user, seconds: 1500, direction: .forward, ageDays: 10),
            attempt(userID: user, seconds: 1390, direction: .forward, ageDays: 1),
            attempt(userID: user, seconds: 1100, direction: .reverse, ageDays: 0)
        ]
        let result = ATHLTHRouteAttemptDirectionPolicy.personalProgress(
            attempts, direction: .forward, userID: user
        )
        XCTAssertEqual(result.best?.durationSeconds, 1390)
        XCTAssertEqual(result.latest?.durationSeconds, 1390)
        XCTAssertEqual(result.gainSeconds, 110)
    }

    func testGPXExportPreservesMeasuredGeometryAndEscapesXML() throws {
        let route = TrainingRoute(
            id: UUID(),
            ownerID: UUID(),
            title: "Test & <løype>",
            visibility: .privateOnly,
            coordinates: [
                RouteCoordinate(latitude: 63.4, longitude: 10.4,
                                altitude: 12, sequence: 0),
                RouteCoordinate(latitude: 63.401, longitude: 10.401,
                                altitude: nil, sequence: 1)
            ],
            distanceKilometers: 0.2,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date()
        )
        let xml = try XCTUnwrap(String(
            data: ATHLTHRouteGPXExport.document(route),
            encoding: .utf8
        ))
        XCTAssertTrue(xml.contains("Test &amp; &lt;løype&gt;"))
        XCTAssertTrue(xml.contains("<ele>12.0000000</ele>"))
        XCTAssertEqual(xml.components(separatedBy: "<trkpt ").count - 1, 2)
        XCTAssertTrue(xml.contains("</gpx>"))
        XCTAssertFalse(xml.contains("<time>"))
    }

    func testGPXRejectsIncompleteRoute() {
        let route = TrainingRoute(
            id: UUID(),
            ownerID: UUID(),
            title: "Incomplete",
            visibility: .privateOnly,
            coordinates: [],
            distanceKilometers: 0,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date()
        )
        XCTAssertThrowsError(try ATHLTHRouteGPXExport.document(route))
    }
}
