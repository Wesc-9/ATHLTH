import Foundation
import XCTest
@testable import ATHLTH

final class RecoveryDailyCheckInTests: XCTestCase {
    func testDailyReminderIsDisabledWhenSwitchedOffOrCompleted() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 21, hour: 9))!
        XCTAssertTrue(ATHLTHDailyCheckInReminderPolicy.shouldShow(
            enabled: true, completed: false, issuedToday: false,
            now: date, calendar: calendar))
        XCTAssertFalse(ATHLTHDailyCheckInReminderPolicy.shouldShow(
            enabled: false, completed: false, issuedToday: false,
            now: date, calendar: calendar))
        XCTAssertFalse(ATHLTHDailyCheckInReminderPolicy.shouldShow(
            enabled: true, completed: true, issuedToday: false,
            now: date, calendar: calendar))
        XCTAssertFalse(ATHLTHDailyCheckInReminderPolicy.shouldShow(
            enabled: true, completed: false, issuedToday: true,
            now: date, calendar: calendar))
    }

    func testReminderDoesNotAppearAtMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 21, hour: 0))!
        XCTAssertFalse(ATHLTHDailyCheckInReminderPolicy.shouldShow(
            enabled: true, completed: false, issuedToday: false,
            now: date, calendar: calendar))
    }

    func testNewCheckInHasNoPreselectedFields() {
        let draft = RecoveryPartialCheckInDraft()
        XCTAssertNil(draft.energy)
        XCTAssertNil(draft.stress)
        XCTAssertNil(draft.overallSoreness)
        XCTAssertNil(draft.motivation)
        XCTAssertTrue(draft.muscles.isEmpty)
        XCTAssertFalse(draft.hasAnswers)
    }

    func testSavingOnlyEnergyDoesNotFabricateStressOrSoreness() {
        let defaults = UserDefaults(
            suiteName: "athlth.test.checkin.\(UUID().uuidString)")!
        let store = RecoverySorenessStore(defaults: defaults)
        var draft = RecoveryPartialCheckInDraft()
        draft.energy = 2
        draft.apply(to: store)
        XCTAssertTrue(store.hasTodayCheckIn)
        XCTAssertEqual(store.todayEnergy, 2)
        XCTAssertNil(store.todayStress)
        XCTAssertNil(store.todayOverallSoreness)
        XCTAssertNil(store.todayMotivation)
        XCTAssertTrue(store.todayRatings.isEmpty)
    }

    func testLaterPartialAnswerPreservesEarlierValues() {
        let defaults = UserDefaults(
            suiteName: "athlth.test.checkin.\(UUID().uuidString)")!
        let store = RecoverySorenessStore(defaults: defaults)
        store.setEnergy(4)
        var followUp = RecoveryPartialCheckInDraft()
        followUp.stress = 3
        followUp.apply(to: store)
        XCTAssertEqual(store.todayEnergy, 4)
        XCTAssertEqual(store.todayStress, 3)
        XCTAssertNil(store.todayMotivation)
    }

    func testSorenessOnlyCheckInWithoutEnergyIsValid() {
        let defaults = UserDefaults(
            suiteName: "athlth.test.checkin.\(UUID().uuidString)")!
        let store = RecoverySorenessStore(defaults: defaults)
        var draft = RecoveryPartialCheckInDraft()
        draft.muscles["Quads"] = .moderate
        XCTAssertTrue(draft.hasAnswers)
        draft.apply(to: store)
        XCTAssertNil(store.todayEnergy)
        XCTAssertEqual(store.todayRatings["Quads"], .moderate)
    }
}
