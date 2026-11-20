import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutCaptureAdmissionTests: XCTestCase {
    private func block(_ kind: WorkoutTemplateBlockKind,
                       sequence: Int = 1) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence, kind: kind, title: "Step",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 300, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
    }

    private func session(_ kind: WorkoutKind,
                         blocks: [WorkoutTemplateBlock] = [],
                         category: String? = nil) -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(), title: "Session", kind: kind,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        workout.workoutBlocks = blocks.isEmpty ? nil : blocks
        workout.workoutCategory = category
        return workout
    }

    func testSupportedStrengthAndRunStrengthHybridRemainAdmissible() {
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.strength, blocks: [block(.exercise)])
            ))
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.custom, blocks: [
                    block(.run), block(.exercise, sequence: 2)
                ])
            ))
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.strength, blocks: [
                    block(.exercise), block(.rest, sequence: 2),
                    block(.note, sequence: 3)
                ])
            ))
    }

    func testCyclingStrengthCannotBecomeFakeStrengthRecording() {
        var cycle = block(.note)
        cycle.activityTag = "cycling"
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.strength, blocks: [
                    cycle, block(.exercise, sequence: 2)
                ])
            ))
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.custom, category: "cycling")
            ))
    }

    func testYogaAndMeditationCannotBecomeStrengthRecording() {
        var yoga = block(.note)
        yoga.wellnessKind = .yoga
        var meditation = block(.note)
        meditation.wellnessKind = .meditation
        for wellness in [yoga, meditation] {
            XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
                .requireSupportedStrengthCapture(
                    for: session(.strength, blocks: [
                        block(.exercise), wellness
                    ])
                ))
        }
    }

    func testOtherActivityWithoutStrengthIsNotAccepted() {
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.running, blocks: [block(.run)])
            ))
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.custom, category: "hybrid")
            ))
        XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(
                for: session(.mobility)
            ))
    }

    func testFreeStrengthWithoutStructuredBlocksStillSupported() {
        XCTAssertNoThrow(try ATHLTHWorkoutCaptureAdmission
            .requireSupportedStrengthCapture(for: session(.strength)))
    }

    func testEveryOtherTaggedSportCannotBecomeFakeStrengthCapture() {
        for tag in [
            "cycling", "rowing", "stairClimber", "HIIT",
            "circuit", "functional", "sports", "mobility", "yoga", "other"
        ] {
            var activity = block(.note)
            activity.activityTag = tag
            XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
                .requireSupportedStrengthCapture(
                    for: session(.strength, blocks: [
                        block(.exercise), activity
                    ])
                ), "Tagged sport \(tag) cannot be recorded as strength")
            XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
                .requireSupportedStrengthCapture(
                    for: session(.strength, blocks: [activity])
                ))
        }
    }

    func testLegacyStrengthKindCannotOverrideExplicitOtherSportCategory() {
        for category in ["rowing", "stairclimber", "hiit", "functional",
                         "cycling", "yoga", "meditation"] {
            XCTAssertThrowsError(try ATHLTHWorkoutCaptureAdmission
                .requireSupportedStrengthCapture(
                    for: session(.strength, category: category)
                ))
        }
    }


    func testSimplePlannedSportsUseRealMatchingWatchActivity() {
        for (category, kind) in [
            ("cycling", WatchWorkoutKind.cycling),
            ("rowing", .rowing), ("stairclimber", .stairClimbing),
            ("hiit", .hiit), ("circuit", .functional),
            ("functional", .functional), ("sports", .other),
            ("other", .other), ("yoga", .yoga), ("mobility", .other)
        ] {
            let plan = session(.custom, category: category)
            XCTAssertEqual(
                ATHLTHWorkoutCaptureAdmission.watchKind(for: plan),
                kind, "Wrong Apple Watch HealthKit activity for \(category)"
            )
        }
        XCTAssertEqual(
            ATHLTHWorkoutCaptureAdmission.watchKind(for: session(.running)),
            .running
        )
        XCTAssertEqual(
            ATHLTHWorkoutCaptureAdmission.watchKind(for: session(.walking)),
            .walking
        )
        XCTAssertEqual(
            ATHLTHWorkoutCaptureAdmission.watchKind(for: session(.strength)),
            .strength
        )
    }

    func testUnsupportedOrMixedPlansCannotBeFlattenedIntoWatchSport() {
        XCTAssertNil(ATHLTHWorkoutCaptureAdmission.watchKind(
            for: session(.custom, category: "meditation")
        ))
        XCTAssertNil(ATHLTHWorkoutCaptureAdmission.watchKind(
            for: session(.custom, category: "custom")
        ))
        XCTAssertNil(ATHLTHWorkoutCaptureAdmission.watchKind(
            for: session(.strength, category: "cycling")
        ))
        var cycle = block(.note)
        cycle.activityTag = "cycling"
        XCTAssertNil(ATHLTHWorkoutCaptureAdmission.watchKind(
            for: session(.custom, blocks: [cycle])
        ), "Structured single-sport steps cannot be dropped on transfer")
        XCTAssertNil(ATHLTHWorkoutCaptureAdmission.watchKind(
            for: session(.strength, blocks: [
                block(.exercise), cycle
            ])
        ), "Mixed strength+cycling cannot masquerade as strength")
        var yoga = block(.note)
        yoga.wellnessKind = .yoga
        XCTAssertNil(ATHLTHWorkoutCaptureAdmission.watchKind(
            for: session(.running, blocks: [block(.run), yoga])
        ))
    }


    func testWatchCompletionCorrelatesOnlyWithActualSupportedSport() {
        for (category, expected) in [
            ("cycling", WatchWorkoutKind.cycling),
            ("rowing", .rowing), ("hiit", .hiit),
            ("stairclimber", .stairClimbing), ("yoga", .yoga)
        ] {
            let planned = session(.custom, category: category)
            XCTAssertTrue(ATHLTHWorkoutCaptureAdmission
                .matchesCompletedWatchKind(planned, actual: expected))
            XCTAssertFalse(ATHLTHWorkoutCaptureAdmission
                .matchesCompletedWatchKind(planned, actual: .strength))
            XCTAssertFalse(ATHLTHWorkoutCaptureAdmission
                .matchesCompletedWatchKind(planned, actual: .running))
        }
        let unsupported = session(.custom, category: "meditation")
        XCTAssertFalse(ATHLTHWorkoutCaptureAdmission
            .matchesCompletedWatchKind(unsupported, actual: .yoga))
    }


    func testOneCaptureRoutePreservesMixedRunAndYogaOnPhone() {
        var source = session(.running, blocks: [block(.run)])
        var yoga = block(.note, sequence: 2)
        yoga.wellnessKind = .yoga
        source.workoutBlocks = [block(.run), yoga]
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                source, device: .iPhone
            ), .phoneStructuredManual
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                source, device: .appleWatch
            ), .unavailable
        )
    }

    func testOneRouteForEverySimpleSportAndBothCaptureDevices() {
        let sports: [(String, WatchWorkoutKind)] = [
            ("cycling", .cycling), ("rowing", .rowing),
            ("stairclimber", .stairClimbing), ("hiit", .hiit),
            ("circuit", .functional), ("functional", .functional),
            ("yoga", .yoga), ("mobility", .other)
        ]
        for (category, watchKind) in sports {
            let plan = session(.custom, category: category)
            XCTAssertEqual(
                ATHLTHPlannedWorkoutCaptureRoute.resolve(
                    plan, device: .iPhone
                ), .phoneStructuredManual
            )
            XCTAssertEqual(
                ATHLTHPlannedWorkoutCaptureRoute.resolve(
                    plan, device: .appleWatch
                ), .watchSport(watchKind)
            )
        }
    }

    func testStructuredStrengthWatchKeepsOneRealRecorder() {
        let plan = session(.strength, blocks: [
            block(.exercise), block(.rest, sequence: 2)
        ])
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                plan, device: .iPhone
            ), .phoneStructuredManual
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                plan, device: .appleWatch
            ), .watchStrength
        )
    }

    func testUnavailableCustomWorkoutsDoNotGetFakeCapture() {
        var unconfigured = session(.custom, category: "custom")
        unconfigured.durationMinutes = nil
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                unconfigured, device: .iPhone
            ), .unavailable
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                unconfigured, device: .appleWatch
            ), .unavailable
        )
    }


    func testWatchTodayNeverOffersAnIncompletePreparedRecipe() {
        let cycling = session(.custom, category: "cycling")
        XCTAssertTrue(ATHLTHPlannedWorkoutCaptureRoute.resolve(
            cycling, device: .appleWatch
        ).canUsePreparedWatchTransfer)
        var savedRouteSport = cycling
        savedRouteSport.routeID = UUID()
        XCTAssertFalse(ATHLTHPlannedWorkoutCaptureRoute.resolve(
            savedRouteSport, device: .appleWatch
        ).canUsePreparedWatchTransfer)
        var mixed = session(.running, blocks: [block(.run)])
        var yoga = block(.note, sequence: 2)
        yoga.wellnessKind = .yoga
        mixed.workoutBlocks = [block(.run), yoga]
        XCTAssertFalse(ATHLTHPlannedWorkoutCaptureRoute.resolve(
            mixed, device: .appleWatch
        ).canUsePreparedWatchTransfer)
        XCTAssertTrue(ATHLTHPlannedWorkoutCaptureRoute.resolve(
            session(.running), device: .appleWatch
        ).canUsePreparedWatchTransfer)
    }


    func testInstructionStagesAreNotDroppedByEnduranceCapture() {
        var instructions = block(.note, sequence: 2)
        instructions.notes = "Run technique and posture"
        let planned = session(.running, blocks: [
            block(.run), instructions
        ])
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                planned, device: .iPhone
            ), .phoneStructuredManual
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                planned, device: .appleWatch
            ), .unavailable
        )
        XCTAssertNil(ATHLTHWorkoutCaptureAdmission.watchKind(for: planned))
    }

    func testStrengthAndInstructionsRetainOriginalStepsInsteadOfFalseWatchRecipe() {
        let planned = session(.strength, blocks: [
            block(.exercise), block(.note, sequence: 2)
        ])
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                planned, device: .iPhone
            ), .phoneStructuredManual
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                planned, device: .appleWatch
            ), .unavailable
        )
        XCTAssertFalse(ATHLTHPlannedWorkoutCaptureRoute.resolve(
            planned, device: .appleWatch
        ).canUsePreparedWatchTransfer)
    }

    func testPureStructuredWorkoutRetainsMeasuredRoute() {
        let running = session(.running, blocks: [
            block(.run), block(.rest, sequence: 2),
            block(.run, sequence: 3)
        ])
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                running, device: .iPhone
            ), .phoneEndurance
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutCaptureRoute.resolve(
                running, device: .appleWatch
            ), .watchEndurance
        )
    }


    func testPlannedQuickEnduranceCannotSilentlyDiscardOtherActivities() throws {
        for kind in [WorkoutKind.running, .walking] {
            let simple = session(kind)
            XCTAssertNoThrow(
                try ATHLTHWorkoutCaptureAdmission.requireSupportedEnduranceCapture(
                    for: simple, expectedKind: kind, device: .iPhone
                )
            )
            XCTAssertNoThrow(
                try ATHLTHWorkoutCaptureAdmission.requireSupportedEnduranceCapture(
                    for: simple, expectedKind: kind, device: .appleWatch
                )
            )
        }
        var runWithNotes = session(.running, blocks: [block(.run)])
        var note = block(.note, sequence: 2)
        note.notes = "Technique"
        runWithNotes.workoutBlocks = [block(.run), note]
        for device in [WorkoutCaptureDevice.iPhone, .appleWatch] {
            XCTAssertThrowsError(
                try ATHLTHWorkoutCaptureAdmission.requireSupportedEnduranceCapture(
                    for: runWithNotes, expectedKind: .running, device: device
                )
            )
            XCTAssertThrowsError(
                try ATHLTHWorkoutCaptureAdmission.requireSupportedEnduranceCapture(
                    for: session(.strength),
                    expectedKind: .running, device: device
                )
            )
        }
    }

    func testPlannedQuickEnduranceRejectsHybridAndPreservesPlanIdentity() {
        var mixed = session(.running, blocks: [block(.run)])
        var yoga = block(.note, sequence: 2)
        yoga.wellnessKind = .yoga
        mixed.workoutBlocks = [block(.run), yoga]
        let sourceID = mixed.id
        XCTAssertThrowsError(
            try ATHLTHWorkoutCaptureAdmission.requireSupportedEnduranceCapture(
                for: mixed, expectedKind: .running, device: .iPhone
            )
        )
        XCTAssertEqual(mixed.id, sourceID)
        XCTAssertEqual(mixed.resolvedWorkoutBlocks.count, 2)
    }


    func testUniversalPlannedLaunchRequiresWholeOriginalPlanLink() {
        let planID = UUID()
        let sessionID = UUID()
        XCTAssertTrue(ATHLTHPlannedLaunchIdentityPolicy.hasCompleteLink(
            planID: nil, sessionID: nil
        ))
        XCTAssertTrue(ATHLTHPlannedLaunchIdentityPolicy.hasCompleteLink(
            planID: planID, sessionID: sessionID
        ))
        XCTAssertFalse(ATHLTHPlannedLaunchIdentityPolicy.hasCompleteLink(
            planID: planID, sessionID: nil
        ))
        XCTAssertFalse(ATHLTHPlannedLaunchIdentityPolicy.hasCompleteLink(
            planID: nil, sessionID: sessionID
        ))
    }

}
