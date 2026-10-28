import Foundation

/// The private training-profile notes must never be sent as Coach context
/// solely because they exist in local storage. Choosing the visible action
/// in the intake is required for each new plan request.
enum ATHLTHCoachProfileNotesPolicy {
    static func coachContext(
        profileNotes: String, selectedByAthlete: Bool
    ) -> String {
        guard selectedByAthlete else { return "" }
        return String(profileNotes.prefix(700))
    }
}
