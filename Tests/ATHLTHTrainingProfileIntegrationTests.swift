import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainingProfileIntegrationTests: XCTestCase {
    func testProfileDailyCheckInReusesExistingStoredValues() throws {
        let suite = "athlth.profile-checkin-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let insightsStore = RecoverySorenessStore(defaults: defaults)
        let profileStore = RecoverySorenessStore(defaults: defaults)
        XCTAssertFalse(profileStore.hasTodayCheckIn)

        insightsStore.setEnergy(4)
        insightsStore.setStress(2)
        profileStore.reloadFromStorage()

        XCTAssertTrue(profileStore.hasTodayCheckIn)
        XCTAssertEqual(profileStore.todayEnergy, 4)
        XCTAssertEqual(profileStore.todayStress, 2)

        profileStore.setMotivation(5)
        insightsStore.reloadFromStorage()
        XCTAssertEqual(insightsStore.todayMotivation, 5)
        XCTAssertEqual(insightsStore.todayEnergy, 4)
    }

    func testTrainingProfileBodyMeasurementsRemainSingleSharedSource() {
        var profile = ATHLTHTrainingProfile()
        let initial = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(profile.record(metric: .weight, value: 78.5, at: initial))
        XCTAssertTrue(profile.record(metric: .waist, value: 84.0, at: initial))
        XCTAssertEqual(profile.readings(for: .weight).count, 1)
        XCTAssertEqual(profile.readings(for: .waist).count, 1)
        XCTAssertEqual(profile.latest(.weight)?.value, 78.5)
    }

    @MainActor
    func testGoalsKeepExistingPrimaryAndStatusSemantics() {
        let store = GoalStore()
        let first = ATHLTHGoal(title: "Run 10 km", category: .endurance,
                               dataSource: .manual, isPrimary: true)
        let second = ATHLTHGoal(title: "Build strength", category: .strength,
                                dataSource: .manual)
        store.add(first)
        store.add(second)
        XCTAssertEqual(store.primaryGoal?.id, first.id)
        store.setStatus(.paused, for: first.id)
        XCTAssertNil(store.primaryGoal)
        XCTAssertEqual(store.goals.filter { $0.status == .active }.count, 1)
    }
}
