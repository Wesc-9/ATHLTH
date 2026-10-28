import Foundation

/// Only direct instructions to change an *existing* plan are routed to
/// the plan-diff generator. "Make a training plan" is a creation request.
enum ATHLTHCoachPlanChatIntent {
    static func isAdjustmentRequest(_ source: String, hasActivePlan: Bool) -> Bool {
        guard hasActivePlan else { return false }
        let text = source.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "nb_NO")
        ).lowercased()
        let imperative = [
            "flytt ", "flytte ", "endre ", "endrer ", "juster ", "justere ",
            "bytt ", "bytte ", "hopp over ", "dropp ", "fjern ",
            "move ", "reschedule ", "skip ", "adjust ", "change ", "replace ",
            "remove ", "postpone ", "shift "
        ].contains { text.contains($0) }
        let existingContext = [
            "planen", "planlagte", "planlagt", "morgendagens", "økten", "økta",
            "intervallene", "ukens", "min plan", "treningsplanen", "på fredag",
            "til fredag", "til mandag", "til tirsdag", "til onsdag",
            "tomorrow", "friday", "monday", "tuesday", "wednesday",
            "thursday", "saturday", "sunday", "my plan", "the plan",
            "planned", "session", "workout", "intervals"
        ].contains { text.contains($0) }
        let creationOnly = [
            "lag en plan", "lag treningsplan", "create a plan",
            "build a new plan", "make me a plan"
        ].contains { text.contains($0) }
        return imperative && existingContext && !creationOnly
    }
}
