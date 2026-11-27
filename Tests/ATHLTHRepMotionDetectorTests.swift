import XCTest
@testable import ATHLTH

final class ATHLTHRepMotionDetectorTests: XCTestCase {
    func testCompleteSlowRotationCyclesCountButNoiseDoesNot() {
        var detector = ATHLTHRepMotionDetector()
        var t = 0.0
        detector.ingest(timestamp: t, x: 0, y: 0, z: 0)
        for _ in 0..<2 {
            for rate in Array(repeating: 1.0, count: 20) + Array(repeating: -1.0, count: 20) + Array(repeating: 0.0, count: 5) {
                t += 0.05
                detector.ingest(timestamp: t, x: rate, y: 0, z: 0)
            }
        }
        XCTAssertEqual(detector.count, 2)
        for _ in 0..<100 {
            t += 0.05
            detector.ingest(timestamp: t, x: 0.1, y: -0.1, z: 0.1)
        }
        XCTAssertEqual(detector.count, 2)
    }

    func testGapAndOneWayMotionCannotCompleteCycle() {
        var detector = ATHLTHRepMotionDetector()
        for i in 0..<25 {
            detector.ingest(timestamp: Double(i) * 0.05, x: 1, y: 0, z: 0)
        }
        XCTAssertEqual(detector.count, 0)
        for i in 0..<25 {
            detector.ingest(timestamp: 4 + Double(i) * 0.05, x: -1, y: 0, z: 0)
        }
        XCTAssertEqual(detector.count, 0)
        detector.reset()
        XCTAssertEqual(detector.count, 0)
    }
}
