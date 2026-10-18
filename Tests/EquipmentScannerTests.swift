import XCTest
@testable import ATHLTH

final class EquipmentScannerTests: XCTestCase {
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
