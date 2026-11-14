import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutCatalogTileEqualityTests: XCTestCase {
    func testUnchangedRecipeDoesNotInvalidateOnParentStateUpdates() throws {
        let entry = try XCTUnwrap(ATHLTHCuratedStrengthWorkouts.entries.first)
        let a = ATHLTHWorkoutCatalogTile(
            entry: entry, catalogRevision: 2,
            compact: false, includePreview: true, history: nil
        )
        let b = ATHLTHWorkoutCatalogTile(
            entry: entry, catalogRevision: 2,
            compact: false, includePreview: true, history: nil
        )
        XCTAssertEqual(a, b)
    }

    func testCatalogRefreshOrHistoryChangeInvalidatesTile() throws {
        let entry = try XCTUnwrap(ATHLTHCuratedStrengthWorkouts.entries.first)
        let base = ATHLTHWorkoutCatalogTile(
            entry: entry, catalogRevision: 2,
            compact: false, includePreview: true, history: nil
        )
        let updated = ATHLTHWorkoutCatalogTile(
            entry: entry, catalogRevision: 3,
            compact: false, includePreview: true, history: nil
        )
        let grid = ATHLTHWorkoutCatalogTile(
            entry: entry, catalogRevision: 2,
            compact: true, includePreview: true, history: nil
        )
        let completed = ATHLTHWorkoutCatalogTile(
            entry: entry, catalogRevision: 2,
            compact: false, includePreview: true,
            history: ATHLTHLibraryWorkoutHistory.Summary(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                result: "Completed"
            )
        )
        XCTAssertNotEqual(base, updated)
        XCTAssertNotEqual(base, grid)
        XCTAssertNotEqual(base, completed)
    }
}
