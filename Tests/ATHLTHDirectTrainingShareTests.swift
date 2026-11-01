import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHDirectTrainingShareTests: XCTestCase {
    @MainActor
    func testExerciseIsValidMessagingKind() throws {
        XCTAssertEqual(MessageShareKind.exercise.rawValue, "exercise")
        let exercise = ExerciseSnapshot(
            name: "Custom Row",
            instructions: ["Use a steady tempo."],
            primaryMuscles: ["Back"],
            secondaryMuscles: ["Biceps"],
            equipment: ["Cable"],
            imageURL: nil
        )
        let attachment = ATHLTHSharedExerciseAttachment(
            name: exercise.name,
            sourceID: UUID(), sourceIdentifier: nil,
            snapshot: exercise
        )
        let draft = try MessageShareDraft(
            kind: .exercise, title: exercise.name, snapshot: attachment
        )
        let received = try XCTUnwrap(JSONDecoder().decode(
            ATHLTHSharedExerciseAttachment.self,
            from: Data(draft.payload.utf8)
        ))
        XCTAssertEqual(received.snapshot?.instructions, exercise.instructions)
        XCTAssertEqual(received.previewBlock.exerciseSnapshot, exercise)
        XCTAssertEqual(received.previewBlock.kind, .exercise)
        XCTAssertNil(received.previewBlock.exerciseSlug)
    }

    @MainActor
    func testOnlyOwnerCreatedExercisesAppearInSharePicker() throws {
        let ownerID = UUID()
        let library = ExerciseLibraryStore()
        library.switchAccount(ownerID)
        let mine = library.createCustomExercise(
            ownerID: ownerID, name: "My Cable Drill",
            instructions: ["Keep steady"],
            primaryMuscles: ["Back"], secondaryMuscles: [],
            equipment: ["Cable"], isVisibleOutsideOwnerLibrary: true
        )
        XCTAssertTrue(ATHLTHPersonalExerciseSharing.isEligible(
            mine, ownerID: ownerID
        ))
        XCTAssertFalse(ATHLTHPersonalExerciseSharing.isEligible(
            mine, ownerID: UUID()
        ))
        let builtIn = try XCTUnwrap(library.allExercises.first {
            $0.source != .custom
        })
        XCTAssertFalse(ATHLTHPersonalExerciseSharing.isEligible(
            builtIn, ownerID: ownerID
        ))
        XCTAssertThrowsError(try ATHLTHShareDraftFactory.exercise(
            builtIn, ownerID: ownerID
        ))
        let draft = try ATHLTHShareDraftFactory.exercise(mine, ownerID: ownerID)
        XCTAssertEqual(draft.kind, .exercise)
        XCTAssertEqual(draft.sourceObjectID, mine.id)
    }

    @MainActor
    func testImportedExerciseRetainsSmallSenderLabelThroughLocalStorage() throws {
        let ownerID = UUID()
        let library = ExerciseLibraryStore()
        library.switchAccount(ownerID)
        let snapshot = ExerciseSnapshot(
            name: "Shared Row", instructions: ["Keep steady"],
            primaryMuscles: ["Back"], secondaryMuscles: [],
            equipment: ["Cable"], imageURL: nil
        )
        let imported = try XCTUnwrap(library.importSharedExercise(
            snapshot,
            ownerID: ownerID,
            sourceExerciseID: UUID(),
            sharedByUsername: "sender_athlete"
        ))
        XCTAssertNil(imported.exercise.sharedAttributionText)
        let reloaded = ExerciseLibraryStore()
        reloaded.switchAccount(ownerID)
        XCTAssertEqual(
            reloaded.customExercises.first(where: { $0.id == imported.id })?
                .exercise.sharedByUsername,
            "sender_athlete"
        )
    }

    @MainActor
    func testForwardedExerciseKeepsOriginalCreator() throws {
        let receiver = UUID()
        let creator = UUID()
        let library = ExerciseLibraryStore()
        library.switchAccount(receiver)
        let snapshot = ExerciseSnapshot(
            name: "Unique Shoulder Series",
            instructions: ["Steady movement"], primaryMuscles: ["Shoulders"],
            secondaryMuscles: [], equipment: ["Band"], imageURL: nil
        )
        let sourceID = UUID()
        let imported = try XCTUnwrap(library.importSharedExercise(
            snapshot, ownerID: receiver, sourceExerciseID: sourceID,
            sharedByUsername: "middleman",
            originalCreatorID: creator,
            originalCreatorUsername: "originalauthor",
            originalExerciseID: sourceID
        ))
        XCTAssertTrue(imported.exercise.sharedAttributionText?.contains(
            "@originalauthor"
        ) == true)
        var shareable = imported.exercise
        shareable.isVisibleOutsideOwnerLibrary = true
        library.updateCustomExercise(shareable)
        let local = try XCTUnwrap(library.customExercises.first {
            $0.id == imported.id
        })
        let forward = try ATHLTHShareDraftFactory.exercise(
            local, ownerID: receiver, creatorUsername: "middleman"
        )
        let payload = try JSONDecoder().decode(
            ATHLTHSharedExerciseAttachment.self,
            from: Data(forward.payload.utf8)
        )
        XCTAssertEqual(payload.originalCreatorID, creator)
        XCTAssertEqual(payload.originalCreatorUsername, "originalauthor")
        XCTAssertEqual(payload.originalExerciseID, sourceID)
        XCTAssertEqual(forward.sourceOwnerID, creator)
    }

    @MainActor
    func testSharedWorkoutStripsPrivateCalendarAndInvitationData() throws {
        let owner = UUID()
        var workout = PlannedSession(
            id: UUID(), title: "Back Workout", kind: .strength,
            scheduledStart: Date(timeIntervalSince1970: 1800000000),
            durationMinutes: 45, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: UUID(), exercises: [], notes: "Controlled rows"
        )
        workout.invitedPartnerID = UUID()
        workout.reminderMinutesBefore = 30
        workout.recoveryAdjustedAt = Date()
        workout.gearIDs = [UUID()]
        let draft = try ATHLTHShareDraftFactory.workout(
            workout, library: [], ownerID: owner
        )
        let saved = try JSONDecoder().decode(
            PlannedSession.self, from: Data(draft.payload.utf8)
        )
        XCTAssertNil(saved.scheduledStart)
        XCTAssertNil(saved.routeID)
        XCTAssertNil(saved.invitedPartnerID)
        XCTAssertNil(saved.reminderMinutesBefore)
        XCTAssertNil(saved.gearIDs)
        XCTAssertNil(saved.recoveryAdjustedAt)
        XCTAssertEqual(saved.title, workout.title)
        XCTAssertEqual(saved.durationMinutes, workout.durationMinutes)
        XCTAssertEqual(draft.sourceObjectID, workout.id)
        XCTAssertEqual(draft.sourceOwnerID, owner)
    }

    @MainActor
    func testSharedPlanStripsProfileAndDatesWithoutDroppingSessions() throws {
        let owner = UUID()
        let workout = PlannedSession(
            id: UUID(), title: "Strength", kind: .strength,
            scheduledStart: Date(),
            durationMinutes: 40, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        let day = TrainingPlanDay(
            id: UUID(), dayIndex: 1, title: "Monday", sessions: [workout]
        )
        let week = TrainingPlanWeek(
            id: UUID(), weekNumber: 1, title: "Week 1", days: [day]
        )
        var plan = TrainingPlan(
            id: UUID(), ownerID: owner, title: "Shared Plan",
            summary: "Full body", visibility: .privateOnly,
            version: 1, weeks: [week], tags: ["strength"],
            createdAt: Date(), updatedAt: Date()
        )
        plan.startDate = Date()
        plan.endDate = Date()
        let draft = try ATHLTHShareDraftFactory.plan(
            plan, library: [], ownerID: owner
        )
        let copy = try JSONDecoder().decode(
            TrainingPlan.self, from: Data(draft.payload.utf8)
        )
        XCTAssertNil(copy.startDate)
        XCTAssertNil(copy.endDate)
        XCTAssertNil(copy.builderProfile)
        XCTAssertEqual(copy.visibility, .privateOnly)
        XCTAssertEqual(copy.weeks.count, 1)
        XCTAssertEqual(copy.weeks[0].days[0].sessions.count, 1)
        XCTAssertNil(copy.weeks[0].days[0].sessions[0].scheduledStart)
        XCTAssertEqual(copy.weeks[0].days[0].sessions[0].title, "Strength")
    }
}
