import Foundation

/// Only explicit, non-health training form choices. No messages, free text,
/// health measurements, identity, injury information or dates are retained.
struct ATHLTHCoachPreferences: Codable, Equatable {
    var planGoal: ATHLTHCoachChatPlanIntake.Goal?
    var workoutFocus: ATHLTHCoachChatWorkoutIntake.Focus?
    var place: ATHLTHCoachChatPlanIntake.Place?
    var experience: ATHLTHCoachChatPlanIntake.Experience?
    var weeks: Int?
    var sessionsPerWeek: Int?
    var minutes: Int?

    mutating func remember(_ intake: ATHLTHCoachChatPlanIntake) {
        planGoal = intake.goal
        place = intake.place
        experience = intake.experience
        weeks = intake.weeks
        sessionsPerWeek = intake.sessionsPerWeek
    }

    mutating func remember(_ intake: ATHLTHCoachChatWorkoutIntake) {
        workoutFocus = intake.focus
        place = intake.place
        experience = intake.experience
        minutes = intake.minutes
    }

    var description: String {
        var parts = [planGoal?.title, workoutFocus?.title, place?.title, experience?.title].compactMap { $0 }
        if let weeks { parts.append("\(weeks) " + ATHLTHLocalization.choose(english: "weeks", norwegian: "uker")) }
        if let sessionsPerWeek { parts.append("\(sessionsPerWeek) " + ATHLTHLocalization.choose(english: "workouts/week", norwegian: "økter/uke")) }
        if let minutes { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }
}
