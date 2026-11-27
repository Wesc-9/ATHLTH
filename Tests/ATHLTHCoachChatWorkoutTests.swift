import XCTest
@testable import ATHLTH

final class ATHLTHCoachChatWorkoutTests: XCTestCase {
    func testRequestAndPrefill() {
        let request = "Gi meg tre alternative økter for å trene rygg om en uke"
        XCTAssertTrue(ATHLTHCoachChatWorkoutIntake.isRequest(request))
        let now = Date()
        let intake = ATHLTHCoachChatWorkoutIntake.prefilled(from: request, now: now)
        XCTAssertEqual(intake.focus, .back)
        XCTAssertEqual(intake.alternatives, 3)
        XCTAssertEqual(intake.date, Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: now)))
        XCTAssertFalse(ATHLTHCoachChatWorkoutIntake.isRequest("Utsett økten min"))
    }
    @MainActor func testEmptyLibraryCannotInventStrengthExercises() {
        var intake = ATHLTHCoachChatWorkoutIntake()
        intake.focus = .back
        intake.alternatives = 3
        XCTAssertTrue(ATHLTHCoachChatWorkoutFactory.makeDrafts(intake, library: []).isEmpty)
    }
    func testSubmittedIntakePersists() throws {
        var intake = ATHLTHCoachChatWorkoutIntake()
        intake.submitted = true
        let message = RecoveryCoachMessage(role: .assistant, text: "Form", workoutIntake: intake)
        let restored = try JSONDecoder().decode(RecoveryCoachMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored.workoutIntake, intake)
    }
}
