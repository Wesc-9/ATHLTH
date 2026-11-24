import XCTest
@testable import ATHLTH

final class ATHLTHAliveExpressionTests: XCTestCase {
    func testExpressionsRoundTripWithoutChangingActivityStateSchema() throws {
        for face in ATHLTHAliveExpression.allCases {
            let state = ATHLTHAliveActivityAttributes.ContentState(expression: face.rawValue)
            let decoded = try JSONDecoder().decode(
                ATHLTHAliveActivityAttributes.ContentState.self,
                from: JSONEncoder().encode(state)
            )
            XCTAssertEqual(decoded.face, face)
        }
    }

    func testLegacyAndUnknownExpressionUseNeutralSmile() {
        XCTAssertEqual(ATHLTHAliveExpression(storedValue: "awake"), .awake)
        XCTAssertEqual(ATHLTHAliveExpression(storedValue: "unknown"), .awake)
    }
}
