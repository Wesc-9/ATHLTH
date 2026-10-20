import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHHomePlannedDayReconciliationTests: XCTestCase {
    private func workout(_ id: UUID = UUID(), title: String = "Økt") -> PlannedSession {
        PlannedSession(
            id: id, title: title, kind: .strength,
            scheduledStart: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [], notes: nil
        )
    }

    func testRemovedStandaloneDoesNotReturnFromCalendarSnapshot() {
        let deleted = workout()
        let shown = ATHLTHHomePlannedDayReconciliation.current(
            selection: [deleted], originalPlanIDs: [],
            persistedPlan: [], standalone: []
        )
        XCTAssertTrue(shown.isEmpty)
    }

    func testRemovedPlanWorkoutDoesNotReturnFromCalendarSnapshot() {
        let deleted = workout()
        let shown = ATHLTHHomePlannedDayReconciliation.current(
            selection: [deleted], originalPlanIDs: [deleted.id],
            persistedPlan: [], standalone: []
        )
        XCTAssertTrue(shown.isEmpty)
    }

    func testPlanRevisionAppearsWithoutClosingSheet() {
        let original = workout()
        let revised = workout(original.id, title: "Oppdatert økt")
        let shown = ATHLTHHomePlannedDayReconciliation.current(
            selection: [original], originalPlanIDs: [original.id],
            persistedPlan: [revised], standalone: []
        )
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.title, "Oppdatert økt")
    }

    func testNewStandaloneAppearsWithoutClosingSheet() {
        let source = workout()
        let newlyAdded = workout()
        let shown = ATHLTHHomePlannedDayReconciliation.current(
            selection: [source], originalPlanIDs: [],
            persistedPlan: [], standalone: [source, newlyAdded]
        )
        XCTAssertEqual(Set(shown.map(\.id)), Set([source.id, newlyAdded.id]))
        XCTAssertEqual(shown.count, 2)
    }

    func testSameIDCannotAppearInPlanAndStandaloneAtOnce() {
        let source = workout()
        let shown = ATHLTHHomePlannedDayReconciliation.current(
            selection: [source], originalPlanIDs: [source.id],
            persistedPlan: [source], standalone: [source]
        )
        XCTAssertEqual(shown.map(\.id), [source.id])
    }
}
