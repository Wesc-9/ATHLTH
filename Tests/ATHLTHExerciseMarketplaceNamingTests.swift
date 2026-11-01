import XCTest
@testable import ATHLTH

final class ATHLTHExerciseMarketplaceNamingTests: XCTestCase {
    func testDistinctCustomExercisesMayShareSameName() {
        XCTAssertEqual(
            ATHLTHExerciseNamePolicy.key("  My   Home  Exercise "),
            ATHLTHExerciseNamePolicy.key("my home exercise")
        )
        // No unique global index for custom exercise names.
        XCTAssertEqual(
            ATHLTHExerciseNamePolicy.key("Creative Exercise"),
            ATHLTHExerciseNamePolicy.key("Creative Exercise")
        )
    }

    @MainActor
    func testOnlyBuiltInCatalogNamesAreReserved() {
        let library = ExerciseLibraryStore()
        let builtIn = library.allExercises.first(where: { $0.source != .custom })
        XCTAssertNotNil(builtIn)
        guard let builtIn else { return }
        XCTAssertTrue(ATHLTHExerciseNamePolicy.collidesWithCatalog(
            builtIn.canonicalName.uppercased(), library: library
        ))
        XCTAssertFalse(ATHLTHExerciseNamePolicy.collidesWithCatalog(
            "Brand New Custom Drill 9F301", library: library
        ))
    }
}
