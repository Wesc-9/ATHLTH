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

    func testSimplifiedMuscleRegionsCoverOriginalDetailedMuscles() {
        let keys = RecoveryCheckInMuscleRegion.allCases.flatMap(\.muscleKeys)
        XCTAssertEqual(keys.count, Set(keys).count, "Regions must not overlap")
        XCTAssertEqual(
            Set(keys).union(["Feet"]),
            Set(RecoverySorenessStore.muscleGroups),
            "Keep the canonical muscle keys used by historical recovery data"
        )
        XCTAssertEqual(RecoveryCheckInMuscleRegion.allCases.count, 8)
    }

    func testMuscleRegionSelectionCanBeClearedWithoutImpliedAnswers() {
        var ratings: [String: RecoverySorenessLevel] = [:]
        let region = RecoveryCheckInMuscleRegion.thighs
        XCTAssertNil(region.level(in: ratings))
        region.set(.moderate, in: &ratings)
        XCTAssertEqual(region.level(in: ratings), .moderate)
        XCTAssertEqual(ratings["Quads"], .moderate)
        XCTAssertEqual(ratings["Hamstrings"], .moderate)
        XCTAssertEqual(ratings["Adductors"], .moderate)
        region.set(nil, in: &ratings)
        XCTAssertNil(region.level(in: ratings))
        XCTAssertTrue(ratings.isEmpty)
    }

    func testBatchCheckInPersistsAllFieldsWhileKeepingPriorValues() {
        let defaults = UserDefaults(
            suiteName: "athlth.test.checkin.\(UUID().uuidString)")!
        let store = RecoverySorenessStore(defaults: defaults)
        store.setStress(2)

        var draft = RecoveryPartialCheckInDraft()
        draft.energy = 5
        draft.motivation = 4
        RecoveryCheckInMuscleRegion.back.set(.mild, in: &draft.muscles)
        draft.apply(to: store)

        XCTAssertEqual(store.todayEnergy, 5)
        XCTAssertEqual(store.todayStress, 2)
        XCTAssertEqual(store.todayMotivation, 4)
        XCTAssertNil(store.todayOverallSoreness)
        XCTAssertEqual(store.todayRatings["Back"], .mild)
        XCTAssertEqual(store.todayRatings["Lower Back"], .mild)
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
    func testSystemReminderSchedulesSevenAccountScopedDaysAndSkipsCompletedToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 28, hour: 7, minute: 30))!
        let account = UUID()
        let expected = ATHLTHDailyCheckInReminderScheduler.datesToSchedule(
            enabled: true, completedToday: false,
            accountID: account, now: now, calendar: calendar
        )
        XCTAssertEqual(expected.count, 7)
        XCTAssertEqual(calendar.component(.hour, from: expected[0].date), 9)
        XCTAssertTrue(expected.allSatisfy {
            $0.key.hasPrefix("insights.daily-check-in." + account.uuidString)
        })
        let done = ATHLTHDailyCheckInReminderScheduler.datesToSchedule(
            enabled: true, completedToday: true,
            accountID: account, now: now, calendar: calendar
        )
        XCTAssertEqual(done.count, 6)
        XCTAssertFalse(done.contains { $0.key == expected[0].key })
        XCTAssertEqual(done.first?.key, expected[1].key)
    }

    func testPastMorningReminderNotDeliveredLateAndDisabledMeansNone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 28, hour: 10))!
        let account = UUID()
        let future = ATHLTHDailyCheckInReminderScheduler.datesToSchedule(
            enabled: true, completedToday: false, accountID: account,
            now: now, calendar: calendar
        )
        XCTAssertEqual(future.count, 6)
        XCTAssertFalse(future.contains {
            calendar.isDate($0.date, inSameDayAs: now)
        })
        XCTAssertTrue(ATHLTHDailyCheckInReminderScheduler.datesToSchedule(
            enabled: false, completedToday: false, accountID: account,
            now: now, calendar: calendar
        ).isEmpty)
    }

    func testCheckInNotificationTapCannotOpenOtherAccountsData() {
        let account = UUID()
        let info: [AnyHashable: Any] = [
            "athlth_kind": "daily_check_in",
            "athlthCheckInAccountID": account.uuidString
        ]
        XCTAssertTrue(
            ATHLTHDailyCheckInReminderScheduler.isCurrentAccountCheckInTap(
                info, accountID: account
            )
        )
        XCTAssertFalse(
            ATHLTHDailyCheckInReminderScheduler.isCurrentAccountCheckInTap(
                info, accountID: UUID()
            )
        )
        XCTAssertFalse(
            ATHLTHDailyCheckInReminderScheduler.isCurrentAccountCheckInTap(
                ["athlth_kind": "challenge",
                 "athlthCheckInAccountID": account.uuidString],
                accountID: account
            )
        )
    }

}
