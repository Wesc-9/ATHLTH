import XCTest
@testable import ATHLTH

final class ATHLTHCoachReflectionTests: XCTestCase {
    func testCloudPromptExcludesExactHealthMetrics() {
        let data = ATHLTHCoachReflection(activity: "running", completed: false, elapsedSeconds: 633,
            distanceMeters: 2438, paceSecondsPerKilometer: 301, heartRateBPM: 147, planned: true)
        XCTAssertFalse(data.modelPrompt.contains("2438"))
        XCTAssertFalse(data.modelPrompt.contains("147"))
        XCTAssertFalse(data.modelPrompt.contains("301"))
        XCTAssertTrue(data.modelPrompt.contains("Approximate minutes: 10"))
        XCTAssertEqual(data.validatedChoice("pacing"), .pacing)
        XCTAssertNil(data.validatedChoice("increase speed"))
        XCTAssertNil(data.validatedChoice("strength"))
    }

    func testInvalidMeasurementsAreAbsentAndCompletedFallbackIsConservative() {
        let data = ATHLTHCoachReflection(activity: "unknown identifier", completed: true, elapsedSeconds: .nan,
            distanceMeters: -1, paceSecondsPerKilometer: .infinity, heartRateBPM: 0, completedSets: -1)
        XCTAssertEqual(data.activity, "other")
        XCTAssertTrue(data.facts(norwegian: true).isEmpty)
        XCTAssertEqual(data.fallback, .recovery)
        XCTAssertNil(data.validatedChoice("pacing"))
    }
}
