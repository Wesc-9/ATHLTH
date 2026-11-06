import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlannedGuidancePersistenceTests: XCTestCase {
    private func runBlock() -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1,
            kind: .run,
            title: "Outdoor run",
            exerciseSlug: nil,
            distanceMeters: 1_000,
            repetitions: nil,
            durationSeconds: nil,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil,
            phase: .main
        )
    }

    func testPlanBlueprintPreservesPerSessionCoachNavigationAndGhost() throws {
        let routeID = UUID()
        var blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Race preparation",
            kind: .running,
            durationMinutes: 30,
            routeID: routeID,
            blocks: [runBlock()]
        )
        var coach = WatchAudioCoachConfiguration.disabled
        coach.enabled = true
        coach.smartPrompts = ATHLTHAudioCoachSmartSettings()
        coach.smartPrompts?.motivationEnabled = true
        coach.smartPrompts?.announceCurrentHeartRateZone = true
        coach.smartPrompts?.maximumHeartRateBPM = 188
        blueprint.audioCoachConfiguration = coach
        blueprint.routeAlertConfiguration = .standard
        blueprint.ghostTargetDurationSeconds = 1_800
        var ghost = WatchGhostRaceAudioConfiguration.disabled
        ghost.enabled = true
        ghost.distanceIntervalMeters = 500
        blueprint.ghostUpdates = ghost

        XCTAssertTrue(blueprint.isValid)
        let decoded = try JSONDecoder().decode(
            ATHLTHPlanStructuredWorkoutBlueprint.self,
            from: JSONEncoder().encode(blueprint)
        )
        let saved = decoded.applying(to: nil)

        XCTAssertEqual(saved.routeID, routeID)
        XCTAssertTrue(saved.audioCoachConfiguration?.enabled == true)
        XCTAssertTrue(saved.audioCoachConfiguration?.smartPrompts?
            .motivationEnabled == true)
        XCTAssertEqual(saved.audioCoachConfiguration?.smartPrompts?
            .announceCurrentHeartRateZone, true)
        XCTAssertEqual(saved.audioCoachConfiguration?.smartPrompts?
            .maximumHeartRateBPM, 188)
        XCTAssertEqual(saved.routeAlertConfiguration?.deviationMeters, 80)
        XCTAssertEqual(saved.ghostTargetDurationSeconds, 1_800)
        XCTAssertEqual(saved.ghostUpdates?.distanceIntervalMeters, 500)
    }

    func testOldPlanBlueprintStillDecodesWithoutGuidanceKeys() throws {
        var blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Previous plan",
            kind: .running,
            durationMinutes: 30,
            routeID: nil,
            blocks: [runBlock()]
        )
        blueprint.spotifyAutoplayOnStart = true
        let encoded = try JSONEncoder().encode(blueprint)
        let decoded = try JSONDecoder().decode(
            ATHLTHPlanStructuredWorkoutBlueprint.self, from: encoded
        )
        XCTAssertNil(decoded.audioCoachConfiguration)
        XCTAssertNil(decoded.routeAlertConfiguration)
        XCTAssertNil(decoded.ghostTargetDurationSeconds)
        XCTAssertNil(decoded.ghostUpdates)
        XCTAssertEqual(decoded.spotifyAutoplayOnStart, true)
    }

    func testNoRouteSuppressesStaleNavigationAndGhost() {
        var blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Indoor run",
            kind: .running,
            durationMinutes: 30,
            routeID: nil,
            blocks: [runBlock()]
        )
        blueprint.routeAlertConfiguration = .standard
        blueprint.ghostTargetDurationSeconds = 1_500
        blueprint.ghostUpdates = .disabled
        let saved = blueprint.applying(to: nil)
        XCTAssertNil(saved.routeAlertConfiguration)
        XCTAssertNil(saved.ghostTargetDurationSeconds)
        XCTAssertNil(saved.ghostUpdates)
    }
}
