import Foundation
import UserNotifications

/// Measurement goals follow recorded measurements, not a manually marked
/// milestone count. Privacy: no measurement or target is put in notifications.
enum ATHLTHBodyGoalCheckInPolicy {
    static func progress(
        _ goal: ATHLTHGoal, profile: ATHLTHTrainingProfile
    ) -> Double {
        guard let config = goal.bodyMeasurementGoal else { return goal.progress }
        guard config.target != config.baseline else { return 1 }
        guard let current = profile.readings(for: config.metric)
            .last(where: { $0.date >= goal.startDate })?.value else { return 0 }
        let ratio = (current - config.baseline) / (config.target - config.baseline)
        return min(1, max(0, ratio.isFinite ? ratio : 0))
    }

    static func feedback(
        _ goal: ATHLTHGoal, profile: ATHLTHTrainingProfile
    ) -> String {
        guard let config = goal.bodyMeasurementGoal else { return "" }
        func tr(_ en: String, _ no: String) -> String {
            ATHLTHLocalization.choose(english: en, norwegian: no)
        }
        let samples = profile.readings(for: config.metric)
            .filter { $0.date >= goal.startDate }
        guard let current = samples.last else {
            return tr("Add your first measurement to track this goal.",
                      "Registrer første måling for å følge utviklingen.")
        }
        if progress(goal, profile: profile) >= 1 {
            return tr("Your latest measurement has reached the target. Great progress!",
                      "Siste måling har nådd målet. Fin fremgang!")
        }
        guard samples.count > 1 else {
            return tr("Baseline recorded. Keep checking in for a meaningful trend.",
                      "Utgangspunktet er registrert. Fortsett å måle for å se trenden.")
        }
        guard let first = samples.first else { return "" }
        let change = current.value - first.value
        let towardTarget = (config.target - config.baseline) * change > 0
        if abs(change) < 0.2 {
            return tr("Stable measurement so far. Small fluctuations are normal.",
                      "Målet er stabilt foreløpig. Små variasjoner er normalt.")
        }
        if towardTarget {
            return tr("Your recorded measurements are moving toward your goal. Keep using consistent measuring conditions.",
                      "Målingene beveger seg mot målet. Fortsett å måle under like forhold.")
        }
        return tr("The latest measurements are moving away from the target. One reading is not a verdict; look at the trend over time.",
                  "Siste målinger går bort fra målet. Én måling avgjør ikke utviklingen – se på trenden over tid.")
    }

    static func dueDates(
        for goal: ATHLTHGoal, after now: Date,
        count: Int = 3, calendar: Calendar = .current
    ) -> [Date] {
        guard let config = goal.bodyMeasurementGoal, goal.status == .active,
              config.notificationsEnabled,
              (7...30).contains(config.checkInIntervalDays) else { return [] }
        let start = calendar.startOfDay(for: goal.startDate)
        var result: [Date] = []
        for index in 1...240 {
            guard let date = calendar.date(
                byAdding: .day, value: index * config.checkInIntervalDays,
                to: start
            ), let fire = calendar.date(
                bySettingHour: 9, minute: 0, second: 0, of: date
            ) else { continue }
            if let deadline = goal.deadline, date > deadline { break }
            if fire > now { result.append(fire) }
            if result.count >= count { break }
        }
        return result
    }

    static func completedPeriod(
        goal: ATHLTHGoal, due: Date,
        profile: ATHLTHTrainingProfile,
        calendar: Calendar = .current
    ) -> Bool {
        guard let config = goal.bodyMeasurementGoal,
              let prior = calendar.date(
                byAdding: .day, value: -config.checkInIntervalDays,
                to: calendar.startOfDay(for: due)
              ) else { return true }
        return profile.readings(for: config.metric).contains {
            $0.date > prior && $0.date <= Date()
        }
    }

    /// One in-app activity per actual measurement period, max 3 days late.
    /// A reading between two due dates counts as completing that period.
    static func dueUnmeasuredPeriod(
        goal: ATHLTHGoal, profile: ATHLTHTrainingProfile,
        now: Date = Date(), calendar: Calendar = .current
    ) -> Date? {
        // Activity check-ins remain available even without device-alert permission.
        guard let config = goal.bodyMeasurementGoal,
              goal.status == .active,
              (7...30).contains(config.checkInIntervalDays) else { return nil }
        if let deadline = goal.deadline,
           let followingDay = calendar.date(byAdding: .day, value: 1,
                                            to: calendar.startOfDay(for: deadline)),
           now > followingDay { return nil }
        let start = calendar.startOfDay(for: goal.startDate)
        for index in 1...240 {
            guard let due = calendar.date(
                byAdding: .day, value: index * config.checkInIntervalDays,
                to: start
            ) else { continue }
            let fire = calendar.date(
                bySettingHour: 9, minute: 0, second: 0, of: due
            ) ?? due
            if fire > now { break }
            if now.timeIntervalSince(fire) > 3 * 86_400 { continue }
            if !completedPeriod(goal: goal, due: due, profile: profile,
                                calendar: calendar) { return due }
        }
        return nil
    }

    static func eventKey(accountID: UUID, goalID: UUID, due: Date,
                         calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: due)
        return String(format: "body-goal-checkin.%@.%@.%04d-%02d-%02d",
                      accountID.uuidString, goalID.uuidString,
                      d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }
}

/// Device-local notification. No medical details, target values, or names on
/// the lock screen. The item is also reconciled into ATHLTH's Activity inbox.
@MainActor
enum ATHLTHBodyGoalReminderScheduler {
    private static let prefix = "athlth.bodyGoal."
    private static var generation = 0

    static func sync(
        goals: [ATHLTHGoal], profile: ATHLTHTrainingProfile,
        userID: UUID
    ) async {
        generation += 1
        let requestGeneration = generation
        let center = UNUserNotificationCenter.current()
        let pending: [UNNotificationRequest] = await withCheckedContinuation {
            continuation in
            center.getPendingNotificationRequests {
                continuation.resume(returning: $0)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers:
            pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional ||
                authorization == .ephemeral else { return }

        let now = Date()
        let active = goals.flatMap { goal -> [(Date, ATHLTHGoal)] in
            dueDatesForSchedule(goal, now: now).filter {
                !ATHLTHBodyGoalCheckInPolicy.completedPeriod(
                    goal: goal, due: $0, profile: profile
                )
            }.map { ($0, goal) }
        }.sorted { $0.0 < $1.0 }.prefix(40)
        for (date, goal) in active {
            guard generation == requestGeneration else { return }
            let content = UNMutableNotificationContent()
            content.title = ATHLTHLocalization.choose(
                english: "Time for a goal check-in",
                norwegian: "Tid for en målinnsjekk"
            )
            content.body = ATHLTHLocalization.choose(
                english: "Record a new measurement to see your progress in ATHLTH.",
                norwegian: "Registrer en ny måling for å følge utviklingen i ATHLTH."
            )
            content.sound = .default
            content.userInfo = [
                "athlth_body_goal_checkin_id": goal.id.uuidString,
                "athlth_body_goal_account_id": userID.uuidString
            ]
            let identifier = prefix + userID.uuidString + "." +
                goal.id.uuidString + "." + String(Int(date.timeIntervalSince1970))
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: date
                ), repeats: false
            )
            try? await center.add(UNNotificationRequest(
                identifier: identifier, content: content, trigger: trigger
            ))
        }
    }

    private static func dueDatesForSchedule(
        _ goal: ATHLTHGoal, now: Date
    ) -> [Date] {
        ATHLTHBodyGoalCheckInPolicy.dueDates(for: goal, after: now, count: 3)
    }
}
