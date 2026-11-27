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
    @MainActor func testAlternativesUseOnlyAvailableDistinctLibraryIDs() {
        let entries = (1...5).map { number -> ExerciseLibraryEntry in
            let exercise = Exercise(id: UUID(), origin: .publicCatalog, ownerID: nil,
                name: "Back movement \(number)", instructions: [], primaryMuscles: ["Back"],
                secondaryMuscles: [], equipment: ["Dumbbell"], imageURL: nil,
                isVisibleOutsideOwnerLibrary: true)
            return ExerciseLibraryEntry(id: exercise.id, exercise: exercise,
                source: number == 1 ? .custom : .athlthCatalog, sourceIdentifier: nil,
                summary: nil, tips: [], category: "Strength", difficulty: nil,
                bodyPart: "Back", imageStartURL: nil, imagePeakURL: nil)
        }
        var intake = ATHLTHCoachChatWorkoutIntake()
        intake.focus = .back
        intake.alternatives = 3
        let drafts = ATHLTHCoachChatWorkoutFactory.makeDrafts(intake, library: entries)
        XCTAssertEqual(drafts.count, 3)
        let ids = drafts.map { Set($0.workout.resolvedWorkoutBlocks.compactMap(\.exerciseID)) }
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertTrue(ids.first?.contains(entries[0].id) == true)
        XCTAssertTrue(drafts.allSatisfy { ATHLTHCoachLibraryGate.hasOnlyLibraryReferences($0.workout, library: entries) })
        XCTAssertFalse(drafts.contains { ATHLTHCoachLibraryGate.hasOnlyLibraryReferences($0.workout, library: []) })
    }

    func testSubmittedIntakePersists() throws {
        var intake = ATHLTHCoachChatWorkoutIntake()
        intake.submitted = true
        let message = RecoveryCoachMessage(role: .assistant, text: "Form", workoutIntake: intake)
        let restored = try JSONDecoder().decode(RecoveryCoachMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored.workoutIntake, intake)
    }
}
