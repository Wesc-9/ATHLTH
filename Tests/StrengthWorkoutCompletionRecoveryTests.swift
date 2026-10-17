import Foundation
import XCTest
@testable import ATHLTH

final class StrengthWorkoutCompletionRecoveryTests: XCTestCase {
    @MainActor
    func testFinishedStrengthWorkoutIsRestoredAfterHistoryWriteIsLost() throws {
        let userID = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: userID)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: userID)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: userID)
            )
        }

        let store = StrengthWorkoutStore()
        store.switchAccount(userID)
        let plan = PlannedSession(
            id: UUID(), title: "Recovery test", kind: .strength,
            scheduledStart: nil, durationMinutes: 20,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
        store.start(
            session: plan, watchSessionID: nil,
            trackingMode: .advanced, captureDevice: .iPhone
        )
        let activeID = try XCTUnwrap(store.activeWorkout?.id)
        XCTAssertThrowsError(
            try StrengthWorkoutCompletionJournal.save(
                try XCTUnwrap(store.activeWorkout), userID: userID
            )
        )

        XCTAssertTrue(store.finish())
        XCTAssertNil(store.activeWorkout)
        XCTAssertNil(store.completionSaveError)
        XCTAssertEqual(store.workoutHistory.filter { $0.id == activeID }.count, 1)
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: userID)?.id, activeID)

        // Simulate UserDefaults history not surviving a process exit while
        // the atomic journal did. The active checkpoint may still exist.
        try AccountLocalStorage.writeChecked(
            [StrengthWorkoutLog](), name: "strengthHistory", userID: userID
        )
        let restored = StrengthWorkoutStore()
        restored.switchAccount(userID)
        XCTAssertNil(restored.activeWorkout)
        XCTAssertEqual(restored.workoutHistory.filter { $0.id == activeID }.count, 1)

        // Repeated launches must not generate duplicate sessions.
        let secondRead = StrengthWorkoutStore()
        secondRead.switchAccount(userID)
        XCTAssertEqual(secondRead.workoutHistory.filter { $0.id == activeID }.count, 1)

        secondRead.removeWorkoutFromHistory(matching: [activeID])
        XCTAssertNil(StrengthWorkoutCompletionJournal.read(userID: userID))
    }
}
