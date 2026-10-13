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
        XCTAssertEqual(scan.matchedExercises(in: []), [])
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
}
