import XCTest
@testable import ATHLTH

final class ATHLTHIntelligenceRoutingTests: XCTestCase {
    func testExistingRoutesRemainUnchanged() {
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .dailyFormCalculation), .rules)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .trainingProgram), .groq)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .recoveryInsight), .rules)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .recoveryInsight, localAvailable: true), .appleLocal)
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

    func testExistingCloudEndpointsAndLocalOnlySeparation() throws {
        XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .workoutInsight))
        XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .recoveryInsight))
        XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .coachQuestion))
        XCTAssertEqual(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .trainingProgram), "generate-training-program")
        XCTAssertEqual(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .planAdaptation), "generate-plan-adaptation")
        XCTAssertEqual(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .strengthSession), "generate-strength-session")
        XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .localDiagnostic))
        XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .dailyRecommendationExplanation))
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .dailyRecommendationExplanation), .rules)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .dailyRecommendationExplanation,
            adminPilotEnabled: true, isAdministrator: true, localAvailable: true), .appleLocal)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .dailyRecommendationExplanation,
            adminPilotEnabled: true, isAdministrator: false, localAvailable: true), .rules)
    }

    func testHealthFeaturesNeverSelectExternalProvider() {
        for feature: ATHLTHIntelligenceFeature in [.workoutInsight, .recoveryInsight, .coachQuestion] {
            XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: feature, localAvailable: true), .appleLocal)
            XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: feature, localAvailable: false), .rules)
            XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: feature))
        }
    }

    @MainActor
    func testOnlyApprovedLocalWordingCanBeReturned() {
        let options = ["Original", "Alternative"]
        XCTAssertEqual(ATHLTHIntelligenceEngine.approvedChoice("A", options: options), "Original")
        XCTAssertEqual(ATHLTHIntelligenceEngine.approvedChoice(" B\n", options: options), "Alternative")
        XCTAssertNil(ATHLTHIntelligenceEngine.approvedChoice("B. Extra advice", options: options))
        XCTAssertNil(ATHLTHIntelligenceEngine.approvedChoice("A", options: []))
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
