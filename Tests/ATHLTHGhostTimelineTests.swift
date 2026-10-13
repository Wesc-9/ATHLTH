import XCTest
@testable import ATHLTH

final class ATHLTHGhostTimelineTests: XCTestCase {
    private let times: [Double] = [0, 100, 200, 300]
    private let distances: [Double] = [0, 150, 500, 1_000]

    func testGhostDistanceMovesSmoothlyBetweenSamples() {
        let value = ATHLTHGhostTimeline.interpolate(
            at: 150, count: times.count,
            position: { times[$0] },
            value: { distances[$0] }
        )
        XCTAssertEqual(value ?? -1, 325, accuracy: 0.001)
    }

    func testTimeAtDistanceIsInverseOfSameTimeline() {
        let value = ATHLTHGhostTimeline.interpolate(
            at: 325, count: distances.count,
            position: { distances[$0] },
            value: { times[$0] }
        )
        XCTAssertEqual(value ?? -1, 150, accuracy: 0.001)
    }

    func testStartAndFinishAreExactWithoutExtrapolating() {
        let early = ATHLTHGhostTimeline.interpolate(
            at: -30, count: times.count,
            position: { times[$0] }, value: { distances[$0] }
        )
        let late = ATHLTHGhostTimeline.interpolate(
            at: 500, count: times.count,
            position: { times[$0] }, value: { distances[$0] }
        )
        XCTAssertEqual(early, 0)
        XCTAssertEqual(late, 1_000)
    }

    func testRepeatedDistancesRemainFinite() {
        let distance: [Double] = [0, 200, 200, 400]
        let time: [Double] = [0, 60, 75, 150]
        let value = ATHLTHGhostTimeline.interpolate(
            at: 300, count: distance.count,
            position: { distance[$0] }, value: { time[$0] }
        )
        XCTAssertEqual(value ?? -1, 112.5, accuracy: 0.001)
    }

    func testNonFiniteInputCannotCreatePhantomLead() {
        let value = ATHLTHGhostTimeline.interpolate(
            at: .nan, count: times.count,
            position: { times[$0] }, value: { distances[$0] }
        )
        XCTAssertNil(value)
    }

    func testEmptySamplesAreNotMatched() {
        XCTAssertNil(ATHLTHGhostTimeline.bracket(
            at: 10, count: 0, position: { _ in 0 }
        ))
    }
}
