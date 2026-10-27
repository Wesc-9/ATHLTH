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

    func testDiscoveredNorwegianAzureVoiceIdentifiers() {
        XCTAssertEqual(
            ATHLTHAzureCoachVoice.key("azure:nb-NO-NewVoiceNeural"),
            "nb-NO-NewVoiceNeural"
        )
        XCTAssertNil(ATHLTHAzureCoachVoice.key("azure:en-US-JennyNeural"))
        XCTAssertNil(ATHLTHAzureCoachVoice.key("azure:nb-NO-Bad<Voice>Neural"))
        XCTAssertNil(ATHLTHAzureCoachVoice.key("azure:nb-NO-OtherNeural?x=1"))
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
