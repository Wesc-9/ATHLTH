import Foundation
import XCTest
@testable import ATHLTH

/// Read-only history separates unresolved rounds without claiming that a
/// completed series has independently verified GPS or newly awarded points.
final class ATHLTHArenaArchivePresentationTests: XCTestCase {
    private func series(
        status: String = "completed",
        completionReason: String? = nil,
        date: Date? = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> ATHLTHArenaRemoteSeries {
        ATHLTHArenaRemoteSeries(
            id: UUID(),
            ownerID: UUID(),
            clubID: nil,
            title: "Arena route",
            scope: .duel,
            scoring: .winner,
            durationDays: 7,
            status: status,
            startsAt: nil,
            endsAt: date,
            completedAt: date,
            completionReason: completionReason
        )
    }

    func testDeadlineUnresolvedShowsAsUnresolvedNotCompletedScore() {
        let unresolved = series(completionReason: "deadline_unresolved")
        XCTAssertTrue(ATHLTHArenaArchivePresentation.isUnresolved(unresolved))
        XCTAssertEqual(
            ATHLTHArenaArchivePresentation.visible(
                [unresolved], filter: .unresolved
            ).map(\.id), [unresolved.id]
        )
        XCTAssertTrue(ATHLTHArenaArchivePresentation.visible(
            [unresolved], filter: .completed
        ).isEmpty)
    }

    func testOtherCompletedReasonsStayVisibleWithoutInferringApprovedPoints() {
        let ended = series(completionReason: "all_results_approved")
        let unknown = series(completionReason: nil)
        XCTAssertFalse(ATHLTHArenaArchivePresentation.isUnresolved(ended))
        XCTAssertFalse(ATHLTHArenaArchivePresentation.isUnresolved(unknown))
        XCTAssertEqual(
            ATHLTHArenaArchivePresentation.visible(
                [ended, unknown], filter: .completed
            ).count, 2
        )
    }

    func testLiveAndDraftCompetitionsNeverAppearInArchive() {
        let active = series(status: "active")
        let draft = series(status: "draft")
        let completed = series()
        for filter in ATHLTHArenaArchivePresentation.Filter.allCases {
            let rows = ATHLTHArenaArchivePresentation.visible(
                [active, draft, completed], filter: filter
            )
            XCTAssertFalse(rows.contains { $0.id == active.id })
            XCTAssertFalse(rows.contains { $0.id == draft.id })
        }
    }

    func testUnresolvedCompletionReasonCannotMakeActiveRaceHistorical() {
        let active = series(
            status: "active", completionReason: "deadline_unresolved"
        )
        XCTAssertFalse(ATHLTHArenaArchivePresentation.isUnresolved(active))
        XCTAssertTrue(ATHLTHArenaArchivePresentation.visible(
            [active], filter: .all
        ).isEmpty)
    }

    func testArchiveNeverDisplaysRowsFetchedForAnotherAccount() {
        let originalUser = UUID()
        let nextUser = UUID()
        XCTAssertTrue(ATHLTHArenaArchiveAccountScope.mayDisplay(
            loadedForUserID: originalUser,
            currentUserID: originalUser
        ))
        XCTAssertFalse(ATHLTHArenaArchiveAccountScope.mayDisplay(
            loadedForUserID: originalUser,
            currentUserID: nextUser
        ))
    }

    func testArchiveFailsClosedBeforeFirstLoadAndAfterLogout() {
        let userID = UUID()
        XCTAssertFalse(ATHLTHArenaArchiveAccountScope.mayDisplay(
            loadedForUserID: nil,
            currentUserID: userID
        ))
        XCTAssertFalse(ATHLTHArenaArchiveAccountScope.mayDisplay(
            loadedForUserID: userID,
            currentUserID: UUID()
        ))
    }

    func testArchiveFilterPreservesNewestFirstSourceOrdering() {
        let newer = series(completionReason: "deadline_unresolved")
        let older = series(completionReason: "deadline_unresolved")
        let normal = series()
        let ordered = [newer, normal, older]
        XCTAssertEqual(
            ATHLTHArenaArchivePresentation.visible(
                ordered, filter: .unresolved
            ).map(\.id), [newer.id, older.id]
        )
        XCTAssertEqual(
            ATHLTHArenaArchivePresentation.visible(
                ordered, filter: .all
            ).map(\.id), [newer.id, normal.id, older.id]
        )
    }
}
