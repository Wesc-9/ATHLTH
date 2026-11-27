import XCTest
@testable import ATHLTH

final class ATHLTHCoachPreferencesTests: XCTestCase {
    func testRememberedChoicesNeverOverrideExplicitRequest() {
        var memory = ATHLTHCoachPreferences()
        var earlier = ATHLTHCoachChatWorkoutIntake()
        earlier.focus = .back
        earlier.place = .gym
        earlier.minutes = 45
        memory.remember(earlier)
        let next = ATHLTHCoachChatWorkoutIntake.prefilled(from: "Lag en økt for meg", preferences: memory)
        XCTAssertEqual(next.focus, .back)
        XCTAssertEqual(next.minutes, 45)
        let explicit = ATHLTHCoachChatWorkoutIntake.prefilled(from: "Lag en løpeøkt ute på 30 minutter", preferences: memory)
        XCTAssertEqual(explicit.focus, .running)
        XCTAssertEqual(explicit.place, .outdoors)
        XCTAssertEqual(explicit.minutes, 30)
    }

    func testOlderTrainingProfileStillDecodes() throws {
        let old = #"{"trainingNotes":"","injuryAndLimitations":"","measurements":[],"updatedAt":0}"#
        let profile = try JSONDecoder().decode(ATHLTHTrainingProfile.self, from: Data(old.utf8))
        XCTAssertNil(profile.coachPreferences)
    }
}
