import XCTest
@testable import ATHLTH

final class HomeCalendarRecommendationDisplayPolicyTests: XCTestCase {
    func testRecommendationShowsOnlyWhenCalendarHasAtMostOneActivity() {
        XCTAssertTrue(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 0,
            personalEventCount: 0,
            clubEventCount: 0,
            tournamentCount: 0
        ))
        XCTAssertTrue(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 1,
            personalEventCount: 0,
            clubEventCount: 0,
            tournamentCount: 0
        ))
        XCTAssertFalse(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 2,
            personalEventCount: 0,
            clubEventCount: 0,
            tournamentCount: 0
        ))
    }

    func testDifferentCalendarSourcesAlsoHideRecommendationWhenCombined() {
        XCTAssertFalse(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 1,
            personalEventCount: 0,
            clubEventCount: 1,
            tournamentCount: 0
        ))
        XCTAssertFalse(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 0,
            personalEventCount: 1,
            clubEventCount: 0,
            tournamentCount: 1
        ))
    }

    func testHomeQuickStartDefaultsAndRanksByExistingTrainSelections() {
        XCTAssertEqual(ATHLTHQuickActivityUsage.favorites(counts: [:]), [.running, .strength])
        XCTAssertEqual(ATHLTHQuickActivityUsage.favorites(counts: ["walking": 9]), [.walking, .running])
        XCTAssertEqual(ATHLTHQuickActivityUsage.favorites(counts: ["sports": 8, "freeTraining": 7, "cycling": 999]), [.sports, .freeTraining])
        XCTAssertEqual(ATHLTHQuickActivityUsage.favorites(counts: ["strength": 3, "running": 3]), [.running, .strength])
    }

    func testQuickStartUsesExistingAccountScopedTapHistory() {
        let suite = "athlth-quick-start-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID()
        let other = UUID()
        defaults.set(["walking": 4], forKey: ATHLTHQuickActivityUsage.storageKey(for: owner))
        XCTAssertEqual(ATHLTHQuickActivityUsage.record(.walking, for: owner, defaults: defaults)["walking"], 5)
        XCTAssertEqual(ATHLTHQuickActivityUsage.counts(for: other, defaults: defaults), [:])
        XCTAssertNil(ATHLTHQuickActivityUsage.record(.cycling, for: owner, defaults: defaults)["cycling"])
    }

    func testHomeBasicQuickChoosesVerifiedWatchOrPhone() {
        XCTAssertEqual(ATHLTHHomeQuickCaptureChoice.automatic.resolve(watchAvailable: true), .appleWatch)
        XCTAssertEqual(ATHLTHHomeQuickCaptureChoice.automatic.resolve(watchAvailable: false), .iPhone)
        XCTAssertEqual(ATHLTHHomeQuickCaptureChoice.iPhone.resolve(watchAvailable: true), .iPhone)
        XCTAssertEqual(ATHLTHHomeQuickCaptureChoice.appleWatch.resolve(watchAvailable: true), .appleWatch)
        XCTAssertNil(ATHLTHHomeQuickCaptureChoice.appleWatch.resolve(watchAvailable: false))
    }

    func testHomeQuickDevicePickerUsesConfigurationNotReachability() {
        let automatic = ATHLTHHomeQuickCaptureChoice.automatic
        XCTAssertEqual(automatic.displayedChoice(watchConfigured: true), .appleWatch)
        XCTAssertEqual(automatic.displayedChoice(watchConfigured: false), .iPhone)
        let phone = automatic.toggled(watchConfigured: true)
        XCTAssertEqual(phone, .iPhone)
        XCTAssertEqual(phone.displayedChoice(watchConfigured: true), .iPhone)
        let watch = phone.toggled(watchConfigured: true)
        XCTAssertEqual(watch, .appleWatch)
        XCTAssertEqual(watch.displayedChoice(watchConfigured: false), .iPhone)
        XCTAssertEqual(watch.displayedChoice(watchConfigured: true), .appleWatch)
        XCTAssertEqual(phone.toggled(watchConfigured: false), .iPhone)
        XCTAssertNil(ATHLTHHomeQuickCaptureChoice.appleWatch.resolve(watchAvailable: false))
    }

    func testTemporaryUnknownPairingDoesNotSwitchTheSelectedDevice() {
        XCTAssertTrue(ATHLTHHomeQuickCaptureChoice.configuredWatch(paired: nil, installed: nil, previous: true))
        XCTAssertFalse(ATHLTHHomeQuickCaptureChoice.configuredWatch(paired: nil, installed: nil, previous: false))
        XCTAssertTrue(ATHLTHHomeQuickCaptureChoice.configuredWatch(paired: true, installed: true, previous: false))
        XCTAssertFalse(ATHLTHHomeQuickCaptureChoice.configuredWatch(paired: false, installed: nil, previous: true))
        XCTAssertFalse(ATHLTHHomeQuickCaptureChoice.configuredWatch(paired: true, installed: false, previous: true))
    }

    func testGarminSyncDoesNotBecomeAnUnsupportedLiveLaunch() {
        XCTAssertEqual(ATHLTHHomeQuickCaptureChoice.automatic.displayedChoice(watchConfigured: true, preferredWatch: .garmin), .iPhone)
        XCTAssertEqual(ATHLTHHomeQuickCaptureChoice.appleWatch.displayedChoice(watchConfigured: true, preferredWatch: .garmin), .appleWatch)
    }
}
