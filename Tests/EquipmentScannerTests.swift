import Supabase
import UIKit
import XCTest
@testable import ATHLTH

final class EquipmentScannerTests: XCTestCase {
    func testEquipmentFeedbackPreservesOriginalGuessAndCorrection() {
        let report = ATHLTHEquipmentFeedbackDraft(
            outcome: .match("Cable machine"), selectedEquipment: "Rowing machine",
            publicExerciseNames: ["Seated row"], privateExerciseCount: 2,
            hasExerciseResults: true, appVersion: "3.0.6", osVersion: "27.3"
        )
        XCTAssertTrue(report.message.contains("Vision suggestion: Cable machine"))
        XCTAssertTrue(report.message.contains("Selected equipment: Rowing machine"))
        XCTAssertTrue(report.message.contains("Library suggestions (public): Seated row"))
        XCTAssertTrue(report.message.contains("Private exercise suggestions omitted: 2"))
        XCTAssertTrue(report.message.contains("App: 3.0.6"))
    }

    func testEquipmentFeedbackDistinguishesNoMatchAndManualSelection() {
        let noMatch = ATHLTHEquipmentFeedbackDraft(
            outcome: .noMatch, selectedEquipment: "", publicExerciseNames: [],
            privateExerciseCount: 0, hasExerciseResults: false,
            appVersion: "", osVersion: ""
        )
        XCTAssertTrue(noMatch.message.contains("Vision suggestion: No reliable match"))
        XCTAssertTrue(noMatch.message.contains("Library suggestions (public): Not requested"))
        XCTAssertEqual(ATHLTHEquipmentVisionOutcome.unavailable.reportValue, "Recognition unavailable")
        let manual = ATHLTHEquipmentFeedbackDraft(
            outcome: nil, selectedEquipment: "Dumbbell", publicExerciseNames: [],
            privateExerciseCount: 0, hasExerciseResults: true,
            appVersion: "", osVersion: ""
        )
        XCTAssertTrue(manual.message.contains("Vision suggestion: Not scanned (manual selection)"))
        XCTAssertTrue(manual.message.contains("Library suggestions (public): None"))
    }

    func testEquipmentFeedbackFitsSupportLimit() {
        let longName = String(repeating: "x", count: 500)
        let report = ATHLTHEquipmentFeedbackDraft(
            outcome: .match(longName), selectedEquipment: longName,
            publicExerciseNames: Array(repeating: longName, count: 100),
            privateExerciseCount: 3, hasExerciseResults: true,
            appVersion: longName, osVersion: longName
        )
        XCTAssertLessThanOrEqual(report.message.utf16.count, 5000)
        XCTAssertLessThanOrEqual(report.subject.count, 120)
    }

    func testLocalEquipmentRequiresSpecificUnambiguousLabel() {
        XCTAssertEqual(ATHLTHLocalEquipmentRecognition.suggestion(observations: [("dumbbell", 0.9)], options: ["Dumbbell"]), "Dumbbell")
        XCTAssertNil(ATHLTHLocalEquipmentRecognition.suggestion(observations: [("gym", 0.9)], options: ["Dumbbell"]))
        XCTAssertNil(ATHLTHLocalEquipmentRecognition.suggestion(observations: [("dumbbell", 0.9), ("barbell", 0.8)], options: ["Dumbbell", "Barbell"]))
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .equipmentRecognition), .appleVision)
        XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .equipmentRecognition))
    }

    @MainActor
    func testOnlyKnownExerciseIDsCanBeSuggested() throws {
        let library = ExerciseLibraryStore()
        let candidate = try XCTUnwrap(library.search(query: "").first)
        let unknown = UUID().uuidString

        let payload = """
        {
          "equipmentName":"Cable machine",
          "confidence":"high",
          "explanation":"Possible cable exercise station",
          "exerciseIDs":["\(unknown)","\(candidate.id.uuidString)","\(candidate.id.uuidString)"]
        }
        """
        let scan = try JSONDecoder().decode(
            ATHLTHEquipmentScanResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(scan.matchedExercises(in: [candidate]).map(\.id), [candidate.id])
        XCTAssertTrue(scan.matchedExercises(in: []).isEmpty)
    }

    @MainActor
    func testLowConfidenceNeverSuggestsExercises() throws {
        let library = ExerciseLibraryStore()
        let candidate = try XCTUnwrap(library.search(query: "").first)
        let payload = """
        {
          "equipmentName":"Unknown",
          "confidence":"low",
          "explanation":"Machine cannot be identified reliably",
          "exerciseIDs":["\(candidate.id.uuidString)"]
        }
        """
        let scan = try JSONDecoder().decode(
            ATHLTHEquipmentScanResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertTrue(scan.matchedExercises(in: [candidate]).isEmpty)
    }
    @MainActor
    func testScanResultsStayRestrictedToRecognizedExerciseIDs() throws {
        let library = ExerciseLibraryStore()
        let candidates = Array(library.search(query: "").prefix(3))
        XCTAssertEqual(candidates.count, 3)
        let payload = """
        {
          "equipmentName":"Weight machine",
          "confidence":"medium",
          "explanation":"Possible matching station",
          "exerciseIDs":["\(candidates[2].id.uuidString)","\(candidates[0].id.uuidString)"]
        }
        """
        let analysis = try JSONDecoder().decode(
            ATHLTHEquipmentScanResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(
            analysis.matchedExercises(in: candidates).map(\.id),
            [candidates[2].id, candidates[0].id]
        )
        XCTAssertFalse(
            analysis.matchedExercises(in: candidates)
                .contains(where: { $0.id == candidates[1].id })
        )
    }

    @MainActor
    func testScannerJPEGHasPredictablePixelDimensionsAndRequestSize() throws {
        // On a 3x iPhone, an 800pt renderer must NOT become 2400 pixels.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 1600, height: 1200), format: format
        ).image { context in
            UIColor.systemGray4.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 150, y: 250, width: 600, height: 180))
            UIColor.black.setFill()
            context.fill(CGRect(x: 500, y: 200, width: 65, height: 900))
        }

        let data = try ATHLTHEquipmentPhotoEncoder.jpegData(for: source)
        XCTAssertLessThanOrEqual(
            data.count, ATHLTHEquipmentPhotoEncoder.maximumJPEGBytes
        )
        let pixelImage = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertLessThanOrEqual(max(pixelImage.width, pixelImage.height), 800)
        XCTAssertGreaterThan(min(pixelImage.width, pixelImage.height), 0)
        // Includes base64 overhead, leaving room for exercise candidates.
        XCTAssertLessThan(data.base64EncodedString().count, 330_000)
    }

    @MainActor
    func testScanProvider413ReturnsSpecificFailureNotGenericPhotoError() {
        let payload = Data(
            #"{"error":"Payload too large","code":"VISION_PAYLOAD_TOO_LARGE"}"#.utf8
        )
        let error = FunctionsError.httpError(code: 413, data: payload)
        XCTAssertEqual(
            ATHLTHEquipmentScannerError.from(error),
            .providerPayloadTooLarge
        )
    }

    @MainActor
    func testEquipmentCandidatesAreBoundedAndDeterministic() {
        let library = ExerciseLibraryStore()
        let candidates = library.search(query: "")
        let first = ATHLTHEquipmentScanCandidateSelector.select(
            from: candidates
        )
        let second = ATHLTHEquipmentScanCandidateSelector.select(
            from: candidates
        )

        XCTAssertLessThanOrEqual(first.count, 100)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        XCTAssertTrue(first.allSatisfy { $0.source != .custom })
        XCTAssertTrue(
            ATHLTHEquipmentScanCandidateSelector.select(
                from: candidates,
                limit: 0
            ).isEmpty
        )
    }

}
