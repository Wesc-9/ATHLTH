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

    func testFullPersonalStepAndPauseSongsPersistWithoutEditingOriginal() throws {
        let suite = "athlth.full-step-user-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let original = steps()
        var edited = original
        edited[0].durationSeconds = 4 * 60
        edited[0].distanceMeters = nil
        edited[0].notes = "Hold jevn fart"
        edited[0].targetEffortRPE = 8
        edited[1].durationSeconds = 2 * 60
        edited[1].spotifyTrack = ATHLTHSpotifyIntervalTrack(
            id: String(repeating: "A", count: 22),
            title: "Recovery song", artist: "Artist",
            durationMilliseconds: 180_000
        )

        XCTAssertTrue(ATHLTHWorkoutUserTargetsStore.save(
            userID: "a", workoutID: id, original: original,
            customized: edited, defaults: defaults
        ))
        let loaded = try XCTUnwrap(ATHLTHWorkoutUserTargetsStore.load(
            userID: "a", workoutID: id, original: original, defaults: defaults
        ))
        XCTAssertEqual(loaded[0].durationSeconds, 240)
        XCTAssertNil(loaded[0].distanceMeters)
        XCTAssertEqual(loaded[0].notes, "Hold jevn fart")
        XCTAssertEqual(loaded[0].targetEffortRPE, 8)
        XCTAssertEqual(loaded[1].spotifyTrack?.title, "Recovery song")
        XCTAssertNil(original[1].spotifyTrack)
        XCTAssertNil(original[0].durationSeconds)
        XCTAssertNil(ATHLTHWorkoutUserTargetsStore.load(
            userID: "b", workoutID: id, original: original, defaults: defaults
        ))
    }

    func testPersonalOptionsStayWithinAccountAndWorkout() {
        let suite = "athlth.personal-options-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        var options = ATHLTHWorkoutPersonalOptions()
        options.spotifyAutoplayOnStart = true
        options.spotifyIntervalTrack = ATHLTHSpotifyIntervalTrack(
            id: String(repeating: "A", count: 22),
            title: "Interval", artist: "Artist", durationMilliseconds: 120_000
        )
        var coach = WatchAudioCoachConfiguration.disabled
        coach.enabled = true
        options.audioCoachConfiguration = coach
        ATHLTHWorkoutPersonalOptionsStore.save(
            options, userID: "a", workoutID: id, defaults: defaults
        )
        let stored = ATHLTHWorkoutPersonalOptionsStore.load(
            userID: "a", workoutID: id, defaults: defaults
        )
        XCTAssertEqual(stored, options)
        XCTAssertNil(ATHLTHWorkoutPersonalOptionsStore.load(
            userID: "b", workoutID: id, defaults: defaults
        ).spotifyIntervalTrack)
        XCTAssertNil(ATHLTHWorkoutPersonalOptionsStore.load(
            userID: "a", workoutID: UUID(), defaults: defaults
        ).audioCoachConfiguration)
    }

    func testSongSurvivesBlockCodingAndExecutionExpansion() throws {
        var step = steps()[0]
        step.spotifyTrack = ATHLTHSpotifyIntervalTrack(
            id: String(repeating: "B", count: 22),
            title: "Effort", artist: "Artist", durationMilliseconds: 240_000
        )
        let decoded = try JSONDecoder().decode(
            WorkoutTemplateBlock.self, from: JSONEncoder().encode(step)
        )
        XCTAssertEqual(decoded.spotifyTrack?.id, step.spotifyTrack?.id)
        XCTAssertEqual([step].expandedForExecution().first?.spotifyTrack?.title,
                       "Effort")
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
