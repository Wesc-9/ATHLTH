import XCTest
@testable import ATHLTH

final class ATHLTHHeadMotionLabTests: XCTestCase {
    func testRejectsDuplicateAndInvalidSamples() {
        var value = ATHLTHHeadMotionLabAccumulator()
        value.ingest(timestamp: 1, pitch: 0, accelerationMagnitude: 0.1, rotationMagnitude: 0.2)
        value.ingest(timestamp: 1, pitch: 0.5, accelerationMagnitude: 0.1, rotationMagnitude: 0.2)
        value.ingest(timestamp: 2, pitch: .nan, accelerationMagnitude: 0.1, rotationMagnitude: 0.2)
        XCTAssertEqual(value.count, 1)
        XCTAssertEqual(value.accelerationRMS ?? 0, 0.1, accuracy: 0.0001)
        XCTAssertEqual(value.candidateNods, 0)
    }
    func testSingleDeliberateExcursionAndCooldown() {
        var value = ATHLTHHeadMotionLabAccumulator()
        for (time, pitch) in [(1.0, 0.0), (1.2, 0.4), (1.4, 0.0), (1.6, 0.4), (1.8, 0.0)] {
            value.ingest(timestamp: time, pitch: pitch, accelerationMagnitude: 0.2, rotationMagnitude: 0.3)
        }
        XCTAssertEqual(value.candidateNods, 1)
    }
}
