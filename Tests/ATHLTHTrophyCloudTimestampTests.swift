import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrophyCloudTimestampTests: XCTestCase {
    func testEdgeFunctionReceivesRFC3339InsteadOfFoundationEpoch() throws {
        let expected = Date(timeIntervalSince1970: 1_794_744_000.125)
        let sent = ATHLTHTrophyCloudTimestamp.encode(expected)
        XCTAssertTrue(sent.contains("T"))
        XCTAssertTrue(sent.hasSuffix("Z"))
        XCTAssertTrue(sent.contains("."))
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let decoded = try XCTUnwrap(parser.date(from: sent))
        XCTAssertEqual(decoded.timeIntervalSince1970,
                       expected.timeIntervalSince1970, accuracy: 0.001)
    }
}
