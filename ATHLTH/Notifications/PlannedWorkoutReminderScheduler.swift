import Foundation
import UserNotifications

/// Device-local training reminders. No workout or location data is uploaded.
enum PlannedWorkoutReminderScheduler {
    private static func identifier(for workoutID: UUID) -> String {
        "athlth.plannedWorkout.reminder.\(workoutID.uuidString)"
    }

    static func cancel(_ workoutID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: workoutID)]
        )
    }

    static func sync(_ workout: PlannedSession) {
        cancel(workout.id)
        guard let date = workout.scheduledStart,
              let minutes = workout.reminderMinutesBefore,
              minutes > 0
        else { return }

        let fireDate = date.addingTimeInterval(-TimeInterval(minutes * 60))
        guard fireDate > Date() else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var authorized = settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral
            if settings.authorizationStatus == .notDetermined {
                authorized = (try? await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )) ?? false
            }
            guard authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = ATHLTHLocalization.choose(
                english: "Your workout starts soon",
                norwegian: "Treningsøkten starter snart"
            )
            content.body = workout.title
            content.sound = .default
            content.userInfo = ["planned_workout_id": workout.id.uuidString]
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: identifier(for: workout.id),
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components, repeats: false
                )
            )
            try? await center.add(request)
        }
    }
}
