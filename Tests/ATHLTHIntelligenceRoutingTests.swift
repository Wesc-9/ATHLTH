import XCTest
@testable import ATHLTH

final class ATHLTHIntelligenceRoutingTests: XCTestCase {
    func testExistingRoutesRemainUnchanged() {
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .dailyFormCalculation), .rules)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .trainingProgram), .groq)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .recoveryInsight), .groq)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .realtimeConversation), .openAIRealtime)
        XCTAssertFalse(ATHLTHIntelligenceRoutingPolicy.cloudEnabled)
    }

    func testLocalDiagnosticNeverFallsBackToRemote() {
        for admin in [false, true] {
            for enabled in [false, true] {
                for available in [false, true] {
                    XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .localDiagnostic,
                        adminPilotEnabled: enabled, isAdministrator: admin, localAvailable: available),
                        admin && enabled && available ? .appleLocal : nil)
                }
            }
        }
    }

    @MainActor
    func testDiagnosticRejectsInventedNumbersAndInvalidFormat() {
        XCTAssertTrue(ATHLTHIntelligenceEngine.validatesDiagnostic("Eksempeløkten var en gåtur på 30 minutter.", norwegian: true))
        XCTAssertTrue(ATHLTHIntelligenceEngine.validatesDiagnostic("The example was a 30-minute walk.", norwegian: false))
        XCTAssertFalse(ATHLTHIntelligenceEngine.validatesDiagnostic("En gåtur på 40 minutter.", norwegian: true))
        XCTAssertFalse(ATHLTHIntelligenceEngine.validatesDiagnostic("En gåtur på 30 minutter og 4 kilometer.", norwegian: true))
        XCTAssertFalse(ATHLTHIntelligenceEngine.validatesDiagnostic("30 minutter styrke.", norwegian: true))
        XCTAssertFalse(ATHLTHIntelligenceEngine.validatesDiagnostic("30 minute walk\nMore", norwegian: false))
    }
}
