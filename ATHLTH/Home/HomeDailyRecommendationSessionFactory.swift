import Foundation

/// Builds executable, time-bounded recommendations for the existing
/// iPhone and Apple Watch workout engines, without editing saved plans.
enum HomeDailyRecommendationSessionFactory {
    static func make(
        advice: HomeDailyRecommendationPolicy.Advice
    ) -> PlannedSession? {
        guard let kind = advice.suggestedWorkout.kind,
              let minutes = advice.suggestedWorkout.durationMinutes,
              minutes > 0
        else { return nil }

        let walking = kind == .walking
        var workout = PlannedSession(
            id: UUID(),
            title: advice.suggestedTitle,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: minutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: [advice.dayDescription, advice.suggestedDetail]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        )

        func tr(_ en: String, _ no: String) -> String {
            ATHLTHLocalization.choose(english: en, norwegian: no)
        }

        typealias Step = (
            phase: WorkoutPhaseKind,
            title: String,
            minutes: Int,
            effort: Int,
            notes: String
        )
        let steps: [Step]

        switch advice.suggestedWorkout {
        case .progressiveRun:
            // Moderate progression, not a hidden interval workout.
            steps = [
                (.warmup, tr("Easy warm-up", "Rolig oppvarming"), 8, 3,
                 tr("Relaxed conversational pace.", "Lett pratefart.")),
                (.main, tr("Steady build", "Jevn progresjon"), 17, 5,
                 tr("Gradually lift the pace, RPE 5/10. Not an all-out effort.",
                    "Øk tempoet gradvis til RPE 5/10. Ikke maks innsats.")),
                (.cooldown, tr("Easy cool-down", "Rolig nedjogg"), 5, 2,
                 tr("Slow down and recover.", "Senk farten og ro ned."))
            ]

        case .tempoRun:
            // 35 minutes: 8 easy + 3 x 5 tempo / 2 easy between + 8 easy.
            // Effort is subjective; never assume known pace or max HR.
            steps = [
                (.warmup, tr("Easy warm-up", "Rolig oppvarming"), 8, 3,
                 tr("Start comfortably.", "Start i behagelig tempo.")),
                (.main, tr("Tempo 1 of 3", "Tempo 1 av 3"), 5, 6,
                 tr("Controlled tempo, RPE 6/10.", "Kontrollert tempo, RPE 6/10.")),
                (.recovery, tr("Easy running", "Rolig løping"), 2, 3,
                 tr("Recover between efforts.", "Hent deg inn mellom dragene.")),
                (.main, tr("Tempo 2 of 3", "Tempo 2 av 3"), 5, 6,
                 tr("Even effort, RPE 6/10.", "Jevn innsats, RPE 6/10.")),
                (.recovery, tr("Easy running", "Rolig løping"), 2, 3,
                 tr("Recover between efforts.", "Hent deg inn mellom dragene.")),
                (.main, tr("Tempo 3 of 3", "Tempo 3 av 3"), 5, 6,
                 tr("Finish in control, RPE 6/10.", "Avslutt kontrollert, RPE 6/10.")),
                (.cooldown, tr("Easy cool-down", "Rolig nedjogg"), 8, 2,
                 tr("Slow down gradually.", "Senk farten gradvis."))
            ]

        case .easyWalk, .easyRun:
            steps = [
                (.main, advice.suggestedTitle, minutes, 3, advice.suggestedDetail)
            ]

        case .planned:
            return nil
        }

        workout.workoutBlocks = steps.enumerated().map { index, step in
            var block = WorkoutTemplateBlock(
                sequence: index + 1,
                kind: .run,
                title: step.title,
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: Double(step.minutes * 60),
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: step.notes,
                phase: step.phase,
                targetHeartRateZone: nil,
                cardioActivity: walking ? .walking : .running
            )
            block.targetEffortRPE = step.effort
            return block
        }
        workout.workoutCategory = walking ? "walking" : "running"
        return workout
    }
}
