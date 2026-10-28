import XCTest
@testable import ATHLTH

final class ATHLTHCoachProfileNotesPolicyTests: XCTestCase {
    func testPrivateProfileNotesDoNotBecomeCoachContextWithoutSelection() {
        XCTAssertEqual(
            ATHLTHCoachProfileNotesPolicy.coachContext(
                profileNotes: "My private training notes", selectedByAthlete: false
            ), ""
        )
    }

    func testExplicitSelectionCanUseEditedProfilePreferences() {
        XCTAssertEqual(
            ATHLTHCoachProfileNotesPolicy.coachContext(
                profileNotes: "Preferred interval schedule", selectedByAthlete: true
            ), "Preferred interval schedule"
        )
    }

    func testCoachContextHasBoundedLength() {
        XCTAssertEqual(
            ATHLTHCoachProfileNotesPolicy.coachContext(
                profileNotes: String(repeating: "A", count: 900), selectedByAthlete: true
            ).count, 700
        )
    }
}
