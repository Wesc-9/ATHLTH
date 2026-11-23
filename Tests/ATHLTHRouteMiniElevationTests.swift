import CoreLocation
import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHRouteMiniElevationTests: XCTestCase {
    private func point(_ altitude: Double?, _ sequence: Int) -> RouteCoordinate {
        RouteCoordinate(
            latitude: 63.40 + Double(sequence) * 0.00001,
            longitude: 10.40,
            altitude: altitude,
            sequence: sequence
        )
    }

    private func route(
        _ coordinates: [RouteCoordinate],
        recordedGain: Double? = nil
    ) -> TrainingRoute {
        TrainingRoute(
            id: UUID(),
            ownerID: UUID(),
            title: "Elevation test route",
            visibility: .privateOnly,
            coordinates: coordinates,
            distanceKilometers: 4,
            elevationGainMeters: recordedGain,
            importedFilename: nil,
            createdAt: Date()
        )
    }

    func testMissingElevationDoesNotInventAProfileOrDifficulty() {
        let r = route([point(nil, 0), point(nil, 1), point(nil, 2)])
        let summary = ATHLTHRouteMiniElevationPolicy.summary(for: r)
        XCTAssertTrue(summary.profile.isEmpty)
        XCTAssertNil(summary.ascentMeters)
        XCTAssertNil(summary.descentMeters)
        XCTAssertNil(summary.difficulty)
        XCTAssertFalse(summary.hasContent)
    }

    func testProfileIsSortedByOriginalRouteSequenceAndKeepsAscentAndDescent() {
        let r = route([
            point(170, 2),
            point(100, 0),
            point(140, 1),
            point(150, 3)
        ])
        let summary = ATHLTHRouteMiniElevationPolicy.summary(for: r)
        XCTAssertEqual(summary.profile, [100, 140, 170, 150])
        XCTAssertEqual(summary.ascentMeters, 70)
        XCTAssertEqual(summary.descentMeters, 20)
        XCTAssertNil(summary.difficulty)
        XCTAssertTrue(summary.hasContent)
    }

    func testKnownRecordedClimbShowsWithoutFabricatingUnknownDescent() {
        let r = route([
            point(nil, 0), point(nil, 1), point(nil, 2)
        ], recordedGain: 92)
        let summary = ATHLTHRouteMiniElevationPolicy.summary(for: r)
        XCTAssertEqual(summary.ascentMeters, 92)
        XCTAssertNil(summary.descentMeters)
        XCTAssertTrue(summary.profile.isEmpty)
        XCTAssertTrue(summary.hasContent)
    }

    func testIncompleteGPSAltitudeSeriesDoesNotBecomeAnInventedHillCurve() {
        let coords = (0..<10).map { index in
            point(index == 0 ? 100 : (index == 9 ? 200 : nil), index)
        }
        let summary = ATHLTHRouteMiniElevationPolicy.summary(
            for: route(coords)
        )
        XCTAssertTrue(summary.profile.isEmpty)
        XCTAssertNil(summary.ascentMeters)
        XCTAssertNil(summary.descentMeters)
        XCTAssertFalse(summary.hasContent)
    }

    func testPublishedProfileAndRealDifficultyOverrideGPSDerivedValues() {
        let r = route([
            point(100, 0), point(120, 1), point(105, 2)
        ], recordedGain: 20)
        let published = PublicTrailRecord(
            id: r.id,
            osmRelationID: 123,
            name: r.title,
            routeKind: "hiking",
            network: nil,
            reference: nil,
            operatorName: nil,
            symbol: nil,
            coordinates: r.coordinates,
            distanceKilometers: 4,
            centerLatitude: 63.40,
            centerLongitude: 10.40,
            leaderboardEnabled: false,
            athlthVerified: false,
            source: "openstreetmap",
            difficulty: "  Moderate  ",
            elevationGainMeters: 49,
            elevationLossMeters: 26,
            elevationProfile: [130, 165, 145]
        )
        let summary = ATHLTHRouteMiniElevationPolicy.summary(
            for: r, published: published
        )
        XCTAssertEqual(summary.profile, [130, 165, 145])
        XCTAssertEqual(summary.ascentMeters, 49)
        XCTAssertEqual(summary.descentMeters, 26)
        XCTAssertEqual(summary.difficulty, "Moderate")
    }

    func testLargeGPSTraceIsCappedForRenderingButTotalsUseFullAltitude() {
        let coords = (0..<1_200).map { index in
            point(100 + Double(index) * 4, index)
        }
        let summary = ATHLTHRouteMiniElevationPolicy.summary(
            for: route(coords)
        )
        XCTAssertEqual(summary.profile.count, 72)
        XCTAssertEqual(summary.profile.first, 100)
        XCTAssertEqual(summary.profile.last, 4896)
        XCTAssertEqual(summary.ascentMeters, 4796)
        XCTAssertEqual(summary.descentMeters, 0)
    }
}
