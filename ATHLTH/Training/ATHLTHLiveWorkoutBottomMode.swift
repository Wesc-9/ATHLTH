import Foundation

/// Phase 2: one actionable bottom control model for running and strength.
/// Recording is still owned by the existing session stores; this model
/// describes what the athlete can do next, never writes training results.
enum ATHLTHLiveWorkoutBottomMode: Equatable {
    case runningMain
    case runningInterval
    case runningNext
    case runningFree
    case strengthReady
    case strengthWorking
    case strengthRest
    case strengthExerciseRest
    case strengthNextExercise
    case strengthAddExercise
    case strengthFinish

    var phaseTitle: String {
        switch self {
        case .runningMain, .runningInterval, .runningNext:
            return ATHLTHLocalization.choose(
                english: "NEXT SECTION", norwegian: "NESTE DEL")
        case .runningFree:
            return ATHLTHLocalization.choose(
                english: "FREE RUN", norwegian: "FRI ØKT")
        case .strengthReady, .strengthWorking:
            return ATHLTHLocalization.choose(
                english: "CURRENT SET", norwegian: "AKTIVT SETT")
        case .strengthRest:
            return ATHLTHLocalization.choose(
                english: "REST", norwegian: "PAUSE")
        case .strengthExerciseRest:
            return ATHLTHLocalization.choose(
                english: "REST BEFORE NEXT EXERCISE",
                norwegian: "PAUSE FØR NESTE ØVELSE")
        case .strengthNextExercise:
            return ATHLTHLocalization.choose(
                english: "NEXT EXERCISE", norwegian: "NESTE ØVELSE")
        case .strengthAddExercise:
            return ATHLTHLocalization.choose(
                english: "FREE STRENGTH", norwegian: "FRI STYRKE")
        case .strengthFinish:
            return ATHLTHLocalization.choose(
                english: "WORKOUT COMPLETE", norwegian: "ØKT FULLFØRT")
        }
    }

    var primaryTitle: String {
        switch self {
        case .runningMain:
            return ATHLTHLocalization.choose(
                english: "Start main section", norwegian: "Start hoveddel")
        case .runningInterval:
            return ATHLTHLocalization.choose(
                english: "Start interval", norwegian: "Start intervall")
        case .runningNext:
            return ATHLTHLocalization.choose(
                english: "Next step", norwegian: "Neste steg")
        case .runningFree:
            return ATHLTHLocalization.choose(
                english: "Add an interval", norwegian: "Legg til intervall")
        case .strengthReady:
            return ATHLTHLocalization.choose(
                english: "Start set", norwegian: "Start sett")
        case .strengthWorking:
            return ATHLTHLocalization.choose(
                english: "Complete set", norwegian: "Fullfør sett")
        case .strengthRest:
            return ATHLTHLocalization.choose(
                english: "Start next set", norwegian: "Start neste sett")
        case .strengthNextExercise, .strengthExerciseRest:
            return ATHLTHLocalization.choose(
                english: "Next exercise", norwegian: "Neste øvelse")
        case .strengthAddExercise:
            return ATHLTHLocalization.choose(
                english: "Add exercise", norwegian: "Legg til øvelse")
        case .strengthFinish:
            return ATHLTHLocalization.choose(
                english: "Finish workout", norwegian: "Avslutt økten")
        }
    }

    var primarySymbol: String {
        switch self {
        case .runningFree, .strengthAddExercise:
            return "plus.circle.fill"
        case .runningMain, .runningInterval, .strengthReady, .strengthRest:
            return "play.fill"
        case .runningNext, .strengthNextExercise, .strengthExerciseRest:
            return "arrow.right.circle.fill"
        case .strengthWorking:
            return "checkmark.circle.fill"
        case .strengthFinish:
            return "stop.circle.fill"
        }
    }

    var secondaryTitle: String? {
        switch self {
        case .strengthRest, .strengthExerciseRest:
            return ATHLTHLocalization.choose(
                english: "+30 sec", norwegian: "+30 sek")
        case .strengthReady, .strengthWorking, .strengthNextExercise,
             .strengthFinish:
            return ATHLTHLocalization.choose(
                english: "Overview", norwegian: "Oversikt")
        case .runningMain, .runningInterval, .runningNext, .runningFree,
             .strengthAddExercise:
            return nil
        }
    }

    var secondarySymbol: String? {
        switch self {
        case .strengthRest, .strengthExerciseRest: "plus"
        case .strengthReady, .strengthWorking, .strengthNextExercise,
             .strengthFinish: "list.bullet"
        case .runningMain, .runningInterval, .runningNext, .runningFree,
             .strengthAddExercise: nil
        }
    }

    /// Progress cannot be recorded merely by showing a screen or by a timer
    /// reaching zero. Only a deliberate primary action drives the engine.
    var recordsCompletedSet: Bool {
        self == .strengthWorking
    }
}
