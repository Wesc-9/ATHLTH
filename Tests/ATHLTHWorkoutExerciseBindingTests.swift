import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutExerciseBindingTests: XCTestCase {
    private func workout(
        _ title: String = "Strength",
        blocks: [WorkoutTemplateBlock] = [],
        exercises: [PlannedExercise] = []
    ) -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(), title: title, kind: .strength,
            scheduledStart: nil, durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: exercises, notes: nil
        )
        workout.workoutBlocks = blocks
        return workout
    }

    private func strengthBlock(
        title: String = "Skulderpress",
        slug: String? = "athlth-native-overhead-press"
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise,
            title: title, exerciseSlug: slug,
            distanceMeters: nil, repetitions: 3,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: "Last set AMRAP",
            phase: .main, targetEffortRPE: 9,
            setCount: 5, restBetweenSetsSeconds: 180
        )
        block.targetRepsInReserve = 1
        return block
    }

    func testRetiredRowErgMigratesToIllustratedRowingMachineWithoutChangingTargets() throws {
        let store = ExerciseLibraryStore()
        let library = store.allExercises
        let rower = try XCTUnwrap(ATHLTHExerciseReferenceResolver.rowingMachine(in: library))
        let legacyID = ATHLTHExerciseReferenceResolver.retiredRowingID
        XCTAssertFalse(store.selectableExercises.contains { $0.id == legacyID })
        XCTAssertTrue(store.selectableExercises.contains { $0.id == rower.id })
        var old = strengthBlock(title: "Row", slug: "rowing-erg")
        old.exerciseID = legacyID
        old.distanceMeters = 1_000
        old.durationSeconds = 240
        var foreign = strengthBlock(title: "Roing", slug: nil)
        foreign.exerciseID = UUID()
        let resistance = strengthBlock(title: "Seated Cable Row", slug: nil)
        let original = workout(blocks: [old, foreign, resistance])
        let migrated = ATHLTHWorkoutExerciseBinding.migrateRowing(original, to: rower)
        let blocks = try XCTUnwrap(migrated.workoutBlocks)
        XCTAssertEqual(blocks[0].exerciseID, rower.id)
        XCTAssertEqual(blocks[0].exerciseSlug, rower.sourceIdentifier)
        XCTAssertEqual(blocks[0].exerciseSnapshot?.name, rower.canonicalName)
        XCTAssertEqual(blocks[0].distanceMeters, old.distanceMeters)
        XCTAssertEqual(blocks[0].durationSeconds, old.durationSeconds)
        XCTAssertEqual(blocks[0].restBetweenSetsSeconds, old.restBetweenSetsSeconds)
        XCTAssertEqual(blocks[0].setCount, old.setCount)
        XCTAssertEqual(blocks[0].notes, old.notes)
        XCTAssertEqual(blocks[1], foreign)
        XCTAssertEqual(blocks[2], resistance)
        XCTAssertEqual(ATHLTHWorkoutExerciseBinding.migrateRowing(migrated, to: rower), migrated)
        XCTAssertEqual(ATHLTHExerciseReferenceResolver.resolve(old, in: library)?.id, rower.id)
        XCTAssertEqual(ATHLTHExerciseReferenceResolver.resolvePublicName("Roing", in: library)?.id, rower.id)
    }

    func testReviewedStationAndNativeDuplicatesUseCanonicalRepDBIdentity() throws {
        let store = ExerciseLibraryStore()
        let library = store.allExercises
        let native = try XCTUnwrap(library.first { $0.sourceIdentifier == "athlth-native-cable-curl" })
        let repDB = try XCTUnwrap(library.first { $0.source == .repDB && $0.sourceIdentifier == "cable-curl" })
        XCTAssertEqual(ATHLTHExerciseReferenceResolver.canonicalReviewedID(native.id), repDB.id)
        XCTAssertFalse(store.selectableExercises.contains { $0.id == native.id })
        XCTAssertTrue(store.selectableExercises.contains { $0.id == repDB.id })
        var block = strengthBlock(title: "Cable Curl", slug: native.sourceIdentifier)
        block.exerciseID = native.id
        let foreign = UUID()
        var custom = block
        custom.exerciseID = foreign
        let session = workout(blocks: [block, custom, strengthBlock(title: "SkiErg", slug: "athlth:skierg")])
        let index = ATHLTHWorkoutExerciseBinding.DuplicateIndex(library: library)
        let migrated = index.migrate(session)
        let blocks = try XCTUnwrap(migrated.workoutBlocks)
        XCTAssertEqual(blocks[0].exerciseID, repDB.id)
        XCTAssertEqual(blocks[0].setCount, block.setCount)
        XCTAssertEqual(blocks[0].restBetweenSetsSeconds, block.restBetweenSetsSeconds)
        XCTAssertEqual(blocks[1].exerciseID, foreign)
        XCTAssertEqual(blocks[2].exerciseSlug, "ski-erg")
        XCTAssertEqual(index.migrate(migrated), migrated)
        XCTAssertEqual(ATHLTHWorkoutExerciseBinding.DuplicateIndex(library: []).migrate(session), session)
    }

    func testPlanWideLookupCachesRepeatedMovementWithoutReplacingForeignUUID() throws {
        let suite = "CatalogLookupCache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Repeated strength", summary: "", weekCount: 2,
            startDate: Date()
        ))
        var first = strengthBlock()
        let firstSession = workout("First", blocks: [first])
        first.setCount = 3
        first.repetitions = 8
        let secondSession = workout("Second", blocks: [first])
        let foreignID = UUID()
        var foreign = strengthBlock()
        foreign.exerciseID = foreignID
        let foreignSession = workout("Foreign", blocks: [foreign])
        store.addSession(
            firstSession, toDay: plan.weeks[0].days[0].id, inPlan: plan.id
        )
        store.addSession(
            secondSession, toDay: plan.weeks[1].days[0].id, inPlan: plan.id
        )
        store.addSession(
            foreignSession, toDay: plan.weeks[1].days[1].id, inPlan: plan.id
        )
        var edited = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &edited, library: ExerciseLibraryStore().allExercises
        )
        XCTAssertEqual(report.linked, 2)
        XCTAssertEqual(report.unresolved, ["Skulderpress"])
        let steps = edited.weeks.flatMap(\.days).flatMap(\.sessions)
            .flatMap { $0.workoutBlocks ?? [] }
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps[0].exerciseID, steps[1].exerciseID)
        XCTAssertEqual(steps[0].setCount, 5)
        XCTAssertEqual(steps[1].setCount, 3)
        XCTAssertEqual(steps[1].repetitions, 8)
        XCTAssertEqual(steps[2].exerciseID, foreignID)
    }

    func testPlanExerciseIdentityLinksWithoutChangingPrescription() throws {
        let library = ExerciseLibraryStore().allExercises
        var session = workout(blocks: [strengthBlock()])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.linked, 1)
        let block = try XCTUnwrap(session.workoutBlocks?.first)
        let matched = try XCTUnwrap(library.first {
            $0.sourceIdentifier == "athlth-native-overhead-press"
        })
        let visible = ATHLTHExerciseReferenceResolver.visibleEquivalent(
            of: matched, in: library
        )
        XCTAssertEqual(block.exerciseID, visible.id)
        XCTAssertEqual(block.exerciseSlug, visible.sourceIdentifier)
        XCTAssertEqual(block.exerciseSnapshot?.name, visible.canonicalName)
        XCTAssertFalse(block.exerciseSnapshot?.instructions.isEmpty ?? true)
        XCTAssertEqual(block.setCount, 5)
        XCTAssertEqual(block.repetitions, 3)
        XCTAssertEqual(block.restBetweenSetsSeconds, 180)
        XCTAssertEqual(block.targetRepsInReserve, 1)
        XCTAssertEqual(block.targetEffortRPE, 9)
        XCTAssertEqual(block.notes, "Last set AMRAP")
        // The live strength engine must forward the library identity into
        // completed logs so "Last trained" and progression see this movement.
        let queue = StrengthWorkoutStore.strengthExerciseLogsFromBlocks([block])
        XCTAssertEqual(queue.first?.plannedExerciseID, visible.id)
        XCTAssertEqual(queue.first?.sets.count, 5)
    }

    func testEveryBundledGymCoachBlockCanBindBeforePlanActivation() {
        let library = ExerciseLibraryStore().allExercises
        for program in ATHLTHGymCoachStrengthLibrary.programs {
            for source in program.program.workouts {
                var session = ATHLTHGymCoachStrengthLibrary.plannedSession(
                    source, program: program, week: 1
                )
                let report = ATHLTHWorkoutExerciseBinding.bind(
                    &session, library: library
                )
                XCTAssertTrue(
                    report.isReady,
                    "Unlinked movement in \(program.slug): \(report.unresolved)"
                )
                XCTAssertTrue(session.workoutBlocks?.filter {
                    $0.kind == .exercise
                }.allSatisfy { $0.exerciseID != nil } == true)
            }
        }
    }

    func testLegacyFullBodyExerciseNamesBindWithoutChangingSets() throws {
        let library = ExerciseLibraryStore().allExercises
        var squat = strengthBlock(title: "Bodyweight squats", slug: nil)
        squat.setCount = 3
        let lunges = strengthBlock(title: "Lunges (each leg)", slug: nil)
        let pushUps = strengthBlock(title: "Push-ups", slug: nil)
        var warmup = strengthBlock(title: "Dynamic warm-up", slug: nil)
        warmup.phase = .warmup
        warmup.setCount = nil
        warmup.repetitions = nil
        warmup.durationSeconds = 300
        warmup.restBetweenSetsSeconds = nil
        var session = workout(blocks: [warmup, squat, lunges, pushUps])
        let report = ATHLTHWorkoutExerciseBinding.bind(&session, library: library)
        XCTAssertTrue(report.isReady, "\(report.unresolved)")
        let blocks = try XCTUnwrap(session.workoutBlocks)
        XCTAssertEqual(blocks[0].kind, .note)
        XCTAssertEqual(blocks[0].durationSeconds, 300)
        XCTAssertEqual(blocks[0].resolvedPhase, .warmup)
        XCTAssertTrue(blocks.dropFirst().allSatisfy { $0.exerciseID != nil })
        XCTAssertEqual(blocks[1].setCount, 3)
        XCTAssertEqual(blocks[2].repetitions, lunges.repetitions)
    }

    func testNamedForeignWarmupIsNeverConvertedToInstruction() {
        var block = strengthBlock(title: "Dynamic warm-up", slug: nil)
        block.exerciseID = UUID()
        block.phase = .warmup
        block.setCount = nil
        block.repetitions = nil
        block.durationSeconds = 300
        var session = workout(blocks: [block])
        let report = ATHLTHWorkoutExerciseBinding.bind(&session, library: [])
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(session.workoutBlocks?.first?.exerciseID, block.exerciseID)
        XCTAssertEqual(session.workoutBlocks?.first?.kind, .exercise)
    }

    func testLegacyUnidentifiedTextIsRetainedButNotAcceptedAsExecutable() {
        let library = ExerciseLibraryStore().allExercises
        var block = strengthBlock(
            title: "My Unique Movement", slug: nil
        )
        block.exerciseSnapshot = ExerciseSnapshot(
            name: "My Unique Movement", instructions: [],
            primaryMuscles: [], equipment: [], imageURL: nil
        )
        var session = workout(blocks: [block])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.unresolved, ["My Unique Movement"])
        XCTAssertEqual(session.workoutBlocks?.first?.title,
                       "My Unique Movement")
        XCTAssertNil(session.workoutBlocks?.first?.exerciseID)
        XCTAssertEqual(session.workoutBlocks?.first?.repetitions, 3)
    }

    func testOriginalOwnerIdentityNeverReplacedBySameNamedStockExercise() {
        let library = ExerciseLibraryStore().allExercises
        var step = strengthBlock(title: "Skulderpress")
        step.exerciseID = UUID() // The source UUID no longer exists here.
        var session = workout(blocks: [step])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(session.workoutBlocks?.first?.exerciseID,
                       step.exerciseID)
    }

    func testLegacyPlannedExerciseGetsCanonicalLibraryIdentity() throws {
        let library = ExerciseLibraryStore().allExercises
        let planned = PlannedExercise(
            id: UUID(), exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Overhead Press", instructions: [],
                primaryMuscles: [], equipment: [], imageURL: nil
            ),
            sets: 5, reps: 3,
            targetWeightKilograms: nil, targetRPE: 9,
            restSeconds: 180, notes: nil
        )
        var session = workout(exercises: [planned])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertTrue(report.isReady)
        let native = try XCTUnwrap(library.first {
            $0.sourceIdentifier == "athlth-native-overhead-press"
        })
        XCTAssertEqual(
            session.exercises.first?.exerciseID,
            ATHLTHExerciseReferenceResolver.visibleEquivalent(
                of: native, in: library
            ).id
        )
        XCTAssertEqual(session.exercises.first?.id, planned.id)
        XCTAssertEqual(session.exercises.first?.sets, 5)
        XCTAssertEqual(session.exercises.first?.reps, 3)
        XCTAssertEqual(session.exercises.first?.restSeconds, 180)
    }

    func testLegacyNorwegianMarkloftCanBindToExistingLibraryExercise() throws {
        let library = ExerciseLibraryStore().allExercises
        let planned = PlannedExercise(
            id: UUID(), exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Markløft", instructions: [],
                primaryMuscles: [], equipment: [], imageURL: nil
            ),
            sets: 3, reps: 1,
            targetWeightKilograms: nil, targetRPE: 9,
            restSeconds: 240, notes: "Last set AMRAP"
        )
        var session = workout(exercises: [planned])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        let expected = try XCTUnwrap(
            ATHLTHExerciseReferenceResolver.resolvePublicName(
                "Markløft", in: library
            )
        )
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(session.exercises.first?.exerciseID, expected.id)
        XCTAssertEqual(session.exercises.first?.sets, 3)
        XCTAssertEqual(session.exercises.first?.reps, 1)
        XCTAssertEqual(session.exercises.first?.restSeconds, 240)
        XCTAssertEqual(session.exercises.first?.notes, "Last set AMRAP")
    }

    func testCardioTypedLibraryExerciseKeepsCanonicalIDAcrossPlanBinding() throws {
        let library = ExerciseLibraryStore().allExercises
        var source = strengthBlock()
        source.kind = .run
        source.durationSeconds = 240
        var session = workout("Mixed", blocks: [source])
        let result = ATHLTHWorkoutExerciseBinding.bind(&session, library: library)
        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.linked, 1)
        let bound = try XCTUnwrap(session.workoutBlocks?.first)
        XCTAssertEqual(bound.kind, .run)
        XCTAssertEqual(bound.durationSeconds, 240)
        XCTAssertNotNil(bound.exerciseID)
    }

    func testUnreferencedCardioBlockIsNotFalselyLinked() {
        var run = strengthBlock(title: "Running", slug: nil)
        run.kind = .run
        run.exerciseID = nil
        var session = workout("Mixed", blocks: [run])
        let result = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: ExerciseLibraryStore().allExercises
        )
        XCTAssertTrue(result.isReady)
        XCTAssertNil(session.workoutBlocks?.first?.exerciseID)
    }

    func testCardioAndNotesDoNotRequireStrengthExerciseIdentity() {
        var session = workout(blocks: [
            WorkoutTemplateBlock(
                sequence: 1, kind: .note,
                title: "Warm up", exerciseSlug: nil,
                distanceMeters: nil, repetitions: nil,
                durationSeconds: 300, targetWeightKilograms: nil,
                loadNote: nil, notes: nil
            )
        ])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: []
        )
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.linked, 0)
    }
}
