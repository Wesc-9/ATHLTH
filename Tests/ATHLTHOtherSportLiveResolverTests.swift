import XCTest
@testable import ATHLTH

final class ATHLTHOtherSportLiveResolverTests: XCTestCase {
    func testCyclingUsesVerifiedDistanceWhenMeasured() {
        XCTAssertEqual(
            ATHLTHOtherSportLiveResolver.resolve(
                kind: .cycling, distanceMeters: 5_200
            ), .measuredDistance
        )
    }

    func testCyclingWithoutDistanceShowsTimeInstead() {
        for meters in [Double.zero, -.infinity, .nan, -100] {
            XCTAssertEqual(
                ATHLTHOtherSportLiveResolver.resolve(
                    kind: .cycling, distanceMeters: meters
                ), .elapsed
            )
        }
    }

    func testOtherSportsNeverInventDistanceOrReps() {
        for kind: WatchWorkoutKind in [
            .hiit, .functional, .rowing, .stairClimbing, .yoga, .other
        ] {
            XCTAssertEqual(
                ATHLTHOtherSportLiveResolver.resolve(
                    kind: kind, distanceMeters: 1000
                ), .elapsed
            )
        }
    }
}
