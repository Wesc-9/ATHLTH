import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRunningWorkoutDisplayDeduplicationTests: XCTestCase {
    private func builtIn4x4() -> RunningWorkoutTemplate {
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000051")!,
            title: "4 × 4 intervaller",
            type: .intervals,
            summary: "10 min warmup · 4 × 4 min efforts · 2 min recovery.",
            blocks: [],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func savedCopy(
        of original: RunningWorkoutTemplate,
        title: String? = nil,
        summary: String? = nil,
        sourceID: UUID? = nil
    ) -> RunningWorkoutTemplate {
        var copy = RunningWorkoutTemplate(
            id: UUID(),
            title: title ?? original.title,
            type: original.type,
            summary: summary ?? original.summary,
            blocks: original.blocks,
            routeID: original.routeID,
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        copy.sharedSourceWorkoutID = sourceID
        return copy
    }

    func testBuiltIn4x4AndItsSavedCopyAppearOnlyOnce() throws {
        let builtIn = builtIn4x4()
        let saved = savedCopy(of: builtIn, sourceID: builtIn.id)
        let displayed = ATHLTHRunningWorkoutDisplayDeduplication.visible([
            builtIn, saved
        ])
        XCTAssertEqual(displayed.map(\.id), [saved.id])
    }

    func testLegacyCopyWithSameSummaryAndTitleIsDeduplicated() throws {
        let builtIn = builtIn4x4()
        let saved = savedCopy(of: builtIn)
        let displayed = ATHLTHRunningWorkoutDisplayDeduplication.visible([
            builtIn, saved
        ])
        XCTAssertEqual(displayed.map(\.id), [saved.id])
    }

    func testDistinctWorkoutsWithSameTitleAreNotDeletedOrHidden() throws {
        let builtIn = builtIn4x4()
        let other = savedCopy(
            of: builtIn,
            summary: "Different four by four training prescription."
        )
        XCTAssertEqual(
            ATHLTHRunningWorkoutDisplayDeduplication.visible([builtIn, other]).count,
            2
        )
    }

    func testOriginalRemainsWhenSavedCopyIsExcludedByFavoritesFilter() throws {
        let builtIn = builtIn4x4()
        // The filter executes before deduplication: if only the original
        // is starred, its source ID remains a valid favorite target.
        XCTAssertEqual(
            ATHLTHRunningWorkoutDisplayDeduplication.visible([builtIn]).map(\.id),
            [builtIn.id]
        )
    }

    func testPersonalCopyAloneRemainsSelectableUnderMineFilter() throws {
        let builtIn = builtIn4x4()
        let saved = savedCopy(of: builtIn, sourceID: builtIn.id)
        XCTAssertEqual(
            ATHLTHRunningWorkoutDisplayDeduplication.visible([saved]).map(\.id),
            [saved.id]
        )
    }
}
