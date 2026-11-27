import Foundation

/// Private, read-only observations derived from recorded aggregates.
/// The model can choose approved wording but cannot change the underlying facts.
@MainActor
enum ATHLTHPrivateHealthInsights {
    private static func tr(_ norwegian: Bool, _ en: String, _ no: String) -> String {
        norwegian ? no : en
    }

    static func recovery(_ context: RecoveryAIContext, norwegian: Bool) async throws -> RecoveryAIInsight {
        let state = context.recoveryState.lowercased()
        let cautious = state.contains("recover") || state.contains("easy") ||
            state.contains("rest") || state.contains("rolig") || state.contains("restit")
        let summary: String
        if let score = context.recoveryScore, (0...100).contains(score) {
            summary = tr(norwegian, "ATHLTH's recorded recovery score is \(score)/100. It is a training signal, not a medical assessment.",
                         "ATHLTHs registrerte formscore er \(score)/100. Den er et treningssignal, ikke en medisinsk vurdering.")
        } else {
            summary = tr(norwegian, "There is no valid recovery score available. Missing data is not a sign of poor recovery.",
                         "Ingen gyldig formscore er tilgjengelig. Manglende data betyr ikke dårlig restitusjon.")
        }
        let selected = try await ATHLTHIntelligenceEngine.privateWording(feature: .recoveryInsight,
            options: [summary, summary + " " + tr(norwegian, "Consider how you feel as well.", "Ta også hensyn til hvordan du føler deg.")])
        var factors: [RecoveryAIFactor] = []
        if let sleep = context.sleepSeconds, sleep.isFinite, sleep > 0, sleep < 172800 {
            let minutes = Int(sleep / 60)
            factors.append(RecoveryAIFactor(title: tr(norwegian, "Sleep", "Søvn"),
                detail: "\(minutes / 60)t \(minutes % 60)m", impact: "neutral"))
        }
        if let hrv = context.hrvMilliseconds, hrv.isFinite, hrv > 0, hrv < 1000 {
            factors.append(RecoveryAIFactor(title: "HRV", detail: String(format: "%.0f ms", hrv), impact: "neutral"))
        }
        if let bpm = context.restingHeartRate, bpm.isFinite, (20...250).contains(bpm) {
            factors.append(RecoveryAIFactor(title: tr(norwegian, "Resting heart rate", "Hvilepuls"),
                detail: String(format: "%.0f bpm", bpm), impact: "neutral"))
        }
        return RecoveryAIInsight(
            headline: tr(norwegian, "Your recovery signals", "Dine restitusjonssignaler"),
            summary: selected, factors: factors,
            suggestion: RecoveryAISuggestion(
                title: cautious ? tr(norwegian, "Consider an easier day", "Vurder en roligere dag") : tr(norwegian, "Adjust to how you feel", "Tilpass etter dagsformen"),
                subtitle: tr(norwegian, "Training guidance", "Treningsveiledning"),
                reason: tr(norwegian, "The score alone cannot determine whether a workout is appropriate. Do not train through concerning symptoms.",
                    "Scoren alene avgjør ikke om en økt passer. Ikke tren gjennom bekymringsfulle symptomer.")),
            quickQuestions: [])
    }

    static func workout(_ context: WorkoutAIInsightContext, norwegian: Bool) async throws -> WorkoutAIInsight {
        let duration = ATHLTHWorkoutSummaryEngine.durationText(context.durationSeconds)
        var observations = [tr(norwegian, "Recorded duration: ", "Registrert varighet: ") + duration + "."]
        if let meters = context.distanceMeters, meters.isFinite, meters > 0 {
            observations.append(tr(norwegian, "Distance: ", "Distanse: ") + ATHLTHWorkoutSummaryEngine.distanceText(meters) + ".")
        }
        if let hr = context.averageHeartRateBPM, hr.isFinite, (20...250).contains(hr) {
            observations.append(tr(norwegian, "Average heart rate: ", "Snittpuls: ") + ATHLTHWorkoutSummaryEngine.pulseText(hr) + ".")
        }
        if let sets = context.strengthTotalSets, sets > 0 {
            observations.append(tr(norwegian, "Completed sets: ", "Fullførte sett: ") + String(sets) + ".")
        }
        let strength = context.activity.lowercased().contains("strength")
        let summary = observations.joined(separator: " ")
        let selected = try await ATHLTHIntelligenceEngine.privateWording(feature: .workoutInsight,
            options: [summary, observations.reversed().joined(separator: " ")])
        // Use the same wire schema the existing renderer already decodes.
        let payload: [String: Any] = [
            "headline": tr(norwegian, "Your recorded workout", "Din registrerte økt"),
            "summary": selected,
            "visualRecipe": [
                "palette": "amber", "scene": strength ? "studio" : "track",
                "light": "daylight", "motif": strength ? "pulse" : "steps",
                "energy": "steady", "variant": 1
            ]
        ]
        return try JSONDecoder().decode(WorkoutAIInsight.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static func coach(question: String, context: RecoveryAIContext?, norwegian: Bool) async throws -> RecoveryCoachReply {
        let general = tr(norwegian,
            "For training decisions, use your existing plan, recent workload and how you feel. I cannot verify a medical condition or prescribe a new plan in this private mode.",
            "Bruk treningsplanen, nylig belastning og hvordan du føler deg når du tar treningsvalg. Jeg kan ikke vurdere en medisinsk tilstand eller lage en ny plan i denne private modusen.")
        let alternate = tr(norwegian,
            "For questions about symptoms, pain or illness, seek qualified healthcare advice. For exercise planning, use ATHLTH's plan tools and adjust intensity to how you feel.",
            "Ved spørsmål om symptomer, smerter eller sykdom, søk råd fra kvalifisert helsepersonell. Bruk planverktøyene i ATHLTH til treningsplanlegging og tilpass intensiteten etter dagsformen.")
        var answer = try await ATHLTHIntelligenceEngine.privateWording(feature: .coachQuestion,
            options: [general, alternate], question: question)
        if let context, let score = context.recoveryScore, (0...100).contains(score) {
            answer += " " + tr(norwegian, "Your recorded recovery score is \(score)/100; it is not a diagnosis.",
                                "Din registrerte formscore er \(score)/100. Det er ikke en diagnose.")
        }
        return RecoveryCoachReply(answer: answer, quickQuestions: [], proposal: nil)
    }
}
