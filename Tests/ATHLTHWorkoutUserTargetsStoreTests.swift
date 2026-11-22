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

    func testOwnSpeedOrPaceCanBeEnteredWithoutFixedDefault() {
        XCTAssertEqual(
            ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
                input: "14", unit: .kilometersPerHour
            ), 14
        )
        XCTAssertEqual(
            ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
                input: "9,5", unit: .kilometersPerHour
            ), 9.5
        )
        XCTAssertEqual(
            ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
                input: "5:00", unit: .minutesPerKilometer
            ), 12
        )
        XCTAssertEqual(
            ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
                input: "5.00", unit: .minutesPerKilometer
            ), 12
        )
        XCTAssertEqual(
            ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
                input: "5,30", unit: .minutesPerKilometer
            ) ?? 0, 3600.0 / 330.0, accuracy: 0.0001
        )
        XCTAssertNil(ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
            input: "", unit: .kilometersPerHour
        ))
        XCTAssertNil(ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
            input: "5:99", unit: .minutesPerKilometer
        ))
        XCTAssertNil(ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
            input: "5.3", unit: .minutesPerKilometer
        ))
        XCTAssertEqual(
            ATHLTHPersonalWorkoutSpeedPolicy.display(
                kilometersPerHour: 12, unit: .minutesPerKilometer
            ), "5:00"
        )
    }

    func testApplyingCustomSpeedOnlyChangesFourEfforts() {
        let recoveryIndices: Set<Int> = [2, 4, 6]
        let steps: [WorkoutTemplateBlock] = (0..<9).map { index in
            WorkoutTemplateBlock(
                sequence: index + 1,
                kind: .run,
                title: "Part \(index + 1)",
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: index == 0 || index == 8 ? 600 : 240,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil,
                phase: index == 0 ? .warmup :
                    (index == 8 ? .cooldown :
                        (recoveryIndices.contains(index) ? .recovery : .main))
            )
        }
        XCTAssertEqual(
            ATHLTHPersonalWorkoutSpeedPolicy.workIndices(in: steps),
            [1, 3, 5, 7]
        )
        let updated = ATHLTHPersonalWorkoutSpeedPolicy.applying(
            kilometersPerHour: 9.5, to: steps
        )
        for index in [1, 3, 5, 7] {
            XCTAssertEqual(
                updated[index].targetPaceSecondsPerKilometer ?? 0,
                3600 / 9.5, accuracy: 0.0001
            )
        }
        for index in [0, 2, 4, 6, 8] {
            XCTAssertNil(updated[index].targetPaceSecondsPerKilometer)
        }
        XCTAssertTrue(steps.allSatisfy { $0.targetPaceSecondsPerKilometer == nil })
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

    func testFourByFourSpeedAppliesToFourEffortsNotActiveRecoveries() {
        let warmup = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Oppvarming",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 600, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .warmup
        )
        var entries: [WorkoutTemplateBlock] = [warmup]
        for rep in 1...4 {
            var effort = WorkoutTemplateBlock(
                sequence: entries.count + 1, kind: .run,
                title: "4x4 intervall drag \(rep)/4", exerciseSlug: nil,
                distanceMeters: nil, repetitions: nil,
                durationSeconds: 240, targetWeightKilograms: nil,
                loadNote: nil, notes: nil, phase: .main
            )
            effort.targetHeartRateZone = 4
            entries.append(effort)
            if rep < 4 {
                var recovery = WorkoutTemplateBlock(
                    sequence: entries.count + 1, kind: .run,
                    title: "Aktiv pause", exerciseSlug: nil,
                    distanceMeters: nil, repetitions: nil,
                    durationSeconds: 120, targetWeightKilograms: nil,
                    loadNote: nil, notes: nil, phase: .recovery
                )
                recovery.targetHeartRateZone = 2
                entries.append(recovery)
            }
        }
        let cooldown = WorkoutTemplateBlock(
            sequence: entries.count + 1, kind: .run, title: "Nedjogging",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 600, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .cooldown
        )
        entries.append(cooldown)

        let updated = ATHLTHPersonalWorkoutSpeedPolicy.applying(
            kilometersPerHour: 14, to: entries
        )
        XCTAssertEqual(updated.count, 9)
        XCTAssertEqual(ATHLTHPersonalWorkoutSpeedPolicy.workIndices(
            in: entries
        ), [1, 3, 5, 7])
        for index in [1, 3, 5, 7] {
            XCTAssertEqual(updated[index].targetPaceSecondsPerKilometer ?? 0,
                           3600 / 14, accuracy: 0.0001)
            XCTAssertEqual(updated[index].targetHeartRateZone, 4)
        }
        for index in [0, 2, 4, 6, 8] {
            XCTAssertNil(updated[index].targetPaceSecondsPerKilometer)
        }
        XCTAssertEqual(entries, ATHLTHPersonalWorkoutSpeedPolicy.applying(
            kilometersPerHour: 100, to: entries
        ))
        XCTAssertTrue(entries.allSatisfy {
            $0.targetPaceSecondsPerKilometer == nil
        })
    }

    func testPersonalWorkoutOptionsResetClearsOnlyThatOwnersWorkout() {
        let suite = "athlth.personal-options-reset-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let otherID = UUID()
        var mine = ATHLTHWorkoutPersonalOptions()
        mine.spotifyAutoplayOnStart = true
        ATHLTHWorkoutPersonalOptionsStore.save(
            mine, userID: "a", workoutID: id, defaults: defaults
        )
        ATHLTHWorkoutPersonalOptionsStore.save(
            mine, userID: "b", workoutID: id, defaults: defaults
        )
        ATHLTHWorkoutPersonalOptionsStore.save(
            mine, userID: "a", workoutID: otherID, defaults: defaults
        )
        ATHLTHWorkoutPersonalOptionsStore.reset(
            userID: "a", workoutID: id, defaults: defaults
        )
        XCTAssertEqual(
            ATHLTHWorkoutPersonalOptionsStore.load(
                userID: "a", workoutID: id, defaults: defaults
            ),
            ATHLTHWorkoutPersonalOptions()
        )
        XCTAssertEqual(
            ATHLTHWorkoutPersonalOptionsStore.load(
                userID: "b", workoutID: id, defaults: defaults
            ), mine
        )
        XCTAssertEqual(
            ATHLTHWorkoutPersonalOptionsStore.load(
                userID: "a", workoutID: otherID, defaults: defaults
            ), mine
        )
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
