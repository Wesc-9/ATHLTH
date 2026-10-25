import XCTest
@testable import ATHLTH

final class ATHLTHRunningTargetEditingTests: XCTestCase {
    func testChangingDurationKeepsPaceRangeZoneRPEAndIncline() {
        let intensity = RunningIntensityTarget(
            kind: .pace, paceMinSecondsPerKilometer: 245,
            paceMaxSecondsPerKilometer: 255, heartRateZone: 4, rpe: 7)
        var original = RunningStepTarget.time(45, intensity: intensity)
        original.treadmillInclinePercent = 2
        var edit = original
        edit.durationSeconds = 47
        edit.intensity.paceMaxSecondsPerKilometer = 245
        edit.intensity.rpe = nil
        let result = ATHLTHRunningTargetEditing.preservingAdditionalTargets(from: original, in: edit)
        XCTAssertEqual(result.durationSeconds, 47)
        XCTAssertEqual(result.intensity.paceMaxSecondsPerKilometer, 255)
        XCTAssertEqual(result.intensity.heartRateZone, 4)
        XCTAssertEqual(result.intensity.rpe, 7)
        XCTAssertEqual(result.treadmillInclinePercent, 2)
    }

    func testExplicitPaceChangeOrRemovalDoesNotRestoreOldPaceRange() {
        var original = RunningStepTarget.time(45)
        original.intensity = .init(kind: .pace, paceMinSecondsPerKilometer: 245,
                                   paceMaxSecondsPerKilometer: 255, heartRateZone: nil, rpe: nil)
        var edited = original
        edited.intensity.paceMinSecondsPerKilometer = 230
        edited.intensity.paceMaxSecondsPerKilometer = 230
        XCTAssertEqual(ATHLTHRunningTargetEditing.preservingAdditionalTargets(
            from: original, in: edited).intensity.paceMaxSecondsPerKilometer, 230)
        edited.intensity = .easy
        XCTAssertNil(ATHLTHRunningTargetEditing.preservingAdditionalTargets(
            from: original, in: edited).intensity.paceMaxSecondsPerKilometer)
    }
}
