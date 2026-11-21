import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutUserTargetsStoreTests: XCTestCase {
    private func steps() -> [WorkoutTemplateBlock] {
        var work = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "500m drag",
            exerciseSlug: nil, distanceMeters: 500,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: .main
        )
        work.targetHeartRateZone = 5
        var recovery = WorkoutTemplateBlock(
            sequence: 2, kind: .run, title: "Aktiv pause",
            exerciseSlug: nil, distanceMeters: 200,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: .recovery
        )
        recovery.cardioActivity = .running
        return [work, recovery]
    }

    func testOnlyAccountOwnsSavedTargetsAndOriginalNeverChanges() {
        let suite = "athlth.user-targets-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let original = steps()
        var personalized = original
        personalized[0].targetPaceSecondsPerKilometer = 285
        personalized[0].targetHeartRateZone = 4
        XCTAssertTrue(ATHLTHWorkoutUserTargetsStore.save(
            userID: "a", workoutID: id, original: original,
            customized: personalized, defaults: defaults
        ))
        let restored = ATHLTHWorkoutUserTargetsStore.load(
            userID: "a", workoutID: id, original: original, defaults: defaults
        )
        XCTAssertEqual(restored?[0].targetPaceSecondsPerKilometer, 285)
        XCTAssertEqual(restored?[0].targetHeartRateZone, 4)
        XCTAssertEqual(restored?[1].distanceMeters, 200)
        XCTAssertEqual(original[0].targetHeartRateZone, 5)
        XCTAssertNil(original[0].targetPaceSecondsPerKilometer)
        XCTAssertNil(ATHLTHWorkoutUserTargetsStore.load(
            userID: "b", workoutID: id, original: original, defaults: defaults
        ))
    }

    func testResetRestoresAuthoredIntensityWithoutErasingPrescription() {
        let suite = "athlth.user-targets-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let original = steps()
        var personalized = original
        personalized[0].targetPaceSecondsPerKilometer = 300
        XCTAssertTrue(ATHLTHWorkoutUserTargetsStore.save(
            userID: "a", workoutID: id, original: original,
            customized: personalized, defaults: defaults
        ))
        ATHLTHWorkoutUserTargetsStore.reset(
            userID: "a", workoutID: id, defaults: defaults
        )
        XCTAssertNil(ATHLTHWorkoutUserTargetsStore.load(
            userID: "a", workoutID: id, original: original, defaults: defaults
        ))
        XCTAssertEqual(original[0].targetHeartRateZone, 5)
    }

    func testChangedTemplateDoesNotInheritTargetsByIndex() {
        let suite = "athlth.user-targets-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let original = steps()
        var personalized = original
        personalized[0].targetPaceSecondsPerKilometer = 320
        XCTAssertTrue(ATHLTHWorkoutUserTargetsStore.save(
            userID: "a", workoutID: id, original: original,
            customized: personalized, defaults: defaults
        ))
        var changed = original
        changed[0].title = "New workout step"
        XCTAssertNil(ATHLTHWorkoutUserTargetsStore.load(
            userID: "a", workoutID: id, original: changed, defaults: defaults
        ))
    }
}
