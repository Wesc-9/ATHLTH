import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHLibraryWorkoutHistoryTests: XCTestCase {
    private func completion(
        workoutID: UUID, templateID: UUID?, date: Date,
        planID: UUID? = nil
    ) -> StructuredWorkoutCompletion {
        StructuredWorkoutCompletion(
            id: UUID(),
            workoutTemplateID: templateID,
            sourceWorkoutID: workoutID,
            title: "4x4 intervaller",
            category: "running",
            startedAt: date.addingTimeInterval(-1_800),
            endedAt: date,
            completedBlockCount: 7,
            totalBlockCount: 7,
            sourcePlanID: planID
        )
    }

    func testLibraryOriginalNeverInheritsCompletedPersonalCopy() {
        let originalID = UUID()
        let personalID = UUID()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(86_400)
        let completions = [
            completion(workoutID: personalID, templateID: originalID, date: newer)
        ]
        XCTAssertNil(ATHLTHLibraryWorkoutHistory.catalogOriginal(
            id: originalID, completions: completions))
        XCTAssertEqual(ATHLTHLibraryWorkoutHistory.savedWorkout(
            id: personalID, completions: completions)?.date, newer)

        let both = completions + [
            completion(workoutID: originalID, templateID: originalID, date: older)
        ]
        XCTAssertEqual(ATHLTHLibraryWorkoutHistory.catalogOriginal(
            id: originalID, completions: both)?.date, older)
        XCTAssertEqual(ATHLTHLibraryWorkoutHistory.savedWorkout(
            id: personalID, completions: both)?.date, newer)
    }

    func testCatalogOriginalExcludesPlannedCopiesEvenIfSourceIDMatches() {
        let originalID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(ATHLTHLibraryWorkoutHistory.catalogOriginal(
            id: originalID, completions: [
                completion(workoutID: originalID, templateID: originalID,
                           date: date, planID: UUID())
            ]))
    }

    func testMostRecentExactCompletionWinsNotArrayOrdering() {
        let workoutID = UUID()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = earlier.addingTimeInterval(60 * 60)
        let history = [
            completion(workoutID: workoutID, templateID: workoutID, date: earlier),
            completion(workoutID: workoutID, templateID: workoutID, date: later),
            completion(workoutID: UUID(), templateID: workoutID,
                       date: later.addingTimeInterval(20_000))
        ]
        XCTAssertEqual(ATHLTHLibraryWorkoutHistory.catalogOriginal(
            id: workoutID, completions: history)?.date, later)
    }

    func testPublicWorkoutUsesStableIdentityPersonalCopyGetsDifferentID() throws {
        let template = try XCTUnwrap(WorkoutTemplateCatalogEntry.fallbackCatalog.first)
        XCTAssertEqual(template.plannedSession(useOriginalID: true).id, template.id)
        XCTAssertNotEqual(template.plannedSession().id, template.id)
    }

    func testNoHistoryMeansNoSummary() {
        XCTAssertNil(ATHLTHLibraryWorkoutHistory.catalogOriginal(
            id: UUID(), completions: []))
        XCTAssertNil(ATHLTHLibraryWorkoutHistory.running(id: UUID(), records: []))
        XCTAssertNil(ATHLTHLibraryWorkoutHistory.strengthExercise(
            id: UUID(), canonicalName: "Bench press", isCustom: true, workouts: []))
    }
}
