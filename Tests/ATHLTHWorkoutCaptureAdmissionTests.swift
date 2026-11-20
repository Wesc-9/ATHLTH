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

}
