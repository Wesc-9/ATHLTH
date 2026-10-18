import CoreLocation
import XCTest
@testable import ATHLTH

final class HomeActivityCenterSafetyTests: XCTestCase {
    func testStrengthWithoutMuscleGroupsShowsPhotographicFallback() {
        XCTAssertTrue(
            HomeStrengthArtworkPolicy.usesFallbackPhoto(.empty)
        )
    }

    func testStrengthWithRecordedMuscleGroupsKeepsTheAnatomyMap() {
        let profile = StrengthMuscleProfile(
            activations: [
                StrengthMuscleActivation(region: .quads, score: 1)
            ]
        )
        XCTAssertFalse(
            HomeStrengthArtworkPolicy.usesFallbackPhoto(profile)
        )
    }

    func testPhotoCardHasNumbersOnlyWhenActuallyRecorded() {
        XCTAssertNil(HomeStrengthRecentCardMetrics.durationText(0))
        XCTAssertNil(HomeStrengthRecentCardMetrics.durationText(.nan))
        XCTAssertEqual(HomeStrengthRecentCardMetrics.durationText(19 * 60), "19 min")
        XCTAssertNil(HomeStrengthRecentCardMetrics.detailText(
            exerciseCount: nil, completedSetCount: nil
        ))
        XCTAssertNil(HomeStrengthRecentCardMetrics.detailText(
            exerciseCount: 0, completedSetCount: 0
        ))
        XCTAssertEqual(HomeStrengthRecentCardMetrics.detailText(
            exerciseCount: 5, completedSetCount: nil
        ), ATHLTHLocalization.choose(
            english: "5 exercises", norwegian: "5 øvelser"
        ))
        XCTAssertEqual(HomeStrengthRecentCardMetrics.detailText(
            exerciseCount: 5, completedSetCount: 14
        ), ATHLTHLocalization.choose(
            english: "5 exercises · 14 sets",
            norwegian: "5 øvelser · 14 sett"
        ))
    }

    func testNewPhotoCardRequiresNoMuscleActivations() {
        XCTAssertTrue(HomeStrengthRecentCardMetrics.showsPhoto(for: .empty))
        let workoutWithMuscles = StrengthMuscleProfile(
            activations: [
                StrengthMuscleActivation(region: .chest, score: 3),
                StrengthMuscleActivation(region: .biceps, score: 2)
            ]
        )
        XCTAssertFalse(HomeStrengthRecentCardMetrics.showsPhoto(
            for: workoutWithMuscles
        ))
    }

    func testInvalidCoordinatesAreRemovedBeforeMapKit() {
        let locations = [
            CLLocation(
                latitude: 63.4305,
                longitude: 10.3951
            ),
            CLLocation(
                latitude: .nan,
                longitude: 10.40
            ),
            CLLocation(
                latitude: 63.44,
                longitude: .infinity
            ),
            CLLocation(
                latitude: 91,
                longitude: 10
            ),
            CLLocation(
                latitude: 63.45,
                longitude: 10.41
            )
        ]

        let valid =
            HomeActivityRouteSanitizer
                .validLocations(locations)

        XCTAssertEqual(valid.count, 2)
        XCTAssertTrue(
            valid.allSatisfy {
                CLLocationCoordinate2DIsValid(
                    $0.coordinate
                )
            }
        )
    }

    func testRouteSamplingIsBoundedAndKeepsEndpoints() {
        let coordinates =
            (0..<250).map {
                index in

                CLLocationCoordinate2D(
                    latitude:
                        63.40 +
                        Double(index) * 0.0001,
                    longitude:
                        10.30 +
                        Double(index) * 0.0001
                )
            }

        let sampled =
            HomeActivityRouteSanitizer.sampled(
                coordinates,
                maximumCount: 96
            )

        XCTAssertEqual(sampled.count, 96)
        XCTAssertEqual(
            sampled.first?.latitude,
            coordinates.first?.latitude
        )
        XCTAssertEqual(
            sampled.last?.latitude,
            coordinates.last?.latitude
        )
    }
}
