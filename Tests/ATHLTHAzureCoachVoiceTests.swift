import XCTest
@testable import ATHLTH

final class ATHLTHAzureCoachVoiceTests: XCTestCase {
    func testSupportedNorwegianAzureChoices() {
        XCTAssertEqual(
            ATHLTHAzureCoachVoice.supported,
            ["finn", "iselin", "pernille"]
        )
        for voice in ATHLTHAzureCoachVoice.supported {
            XCTAssertEqual(
                ATHLTHAzureCoachVoice.key("azure:" + voice),
                voice
            )
        }
    }

    func testUnavailableOrTamperedVoiceFallsBackToApple() {
        XCTAssertNil(ATHLTHAzureCoachVoice.key(nil))
        XCTAssertNil(ATHLTHAzureCoachVoice.key(""))
        XCTAssertNil(ATHLTHAzureCoachVoice.key("nb-NO-FinnNeural"))
        XCTAssertNil(ATHLTHAzureCoachVoice.key("azure:unknown"))
        XCTAssertNil(ATHLTHAzureCoachVoice.key("azure:finnevil"))
        XCTAssertNil(ATHLTHAzureCoachVoice.key("azure:"))
    }
}
