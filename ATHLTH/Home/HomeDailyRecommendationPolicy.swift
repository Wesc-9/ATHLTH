import Foundation

/// Small, conservative daily suggestions. No AI inference or invented sensor
/// values: recommendations are derived only from known plan and recovery data.
enum HomeDailyRecommendationPolicy {
    enum Readiness {
        case ready, balanced, takeItEasy, recover, unavailable
    }

    enum Destination {
        case insights, training
    }

    struct Advice {
        let title: String
        let detail: String
        let source: String
        let symbol: String
        let destination: Destination
    }

    static func recommendation(
        readiness: Readiness,
        hasWorkoutToday: Bool,
        trainingLoadRatio: Double?
    ) -> Advice {
        func tr(_ en: String, _ no: String) -> String {
            ATHLTHLocalization.choose(english: en, norwegian: no)
        }

        switch readiness {
        case .recover:
            return Advice(
                title: hasWorkoutToday
                    ? tr("Consider an easier session", "Vurder en lettere økt")
                    : tr("Prioritize recovery", "Prioriter hvile"),
                detail: hasWorkoutToday
                    ? tr("Recovery is low. Consider reducing today's workload.",
                         "Dagsformen er lav. Vurder mindre belastning i dag.")
                    : tr("Your recovery signals suggest a gentler day.",
                         "Restitusjonssignalene tilsier en roligere dag."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "leaf",
                destination: .insights
            )
        case .takeItEasy:
            return Advice(
                title: hasWorkoutToday
                    ? tr("Ease into the session", "Ta økten roligere")
                    : tr("A gentle day", "En rolig dag"),
                detail: hasWorkoutToday
                    ? tr("Consider lowering intensity or duration today.",
                         "Vurder lavere intensitet eller kortere varighet.")
                    : tr("Easy movement may be a better fit today.",
                         "Lett aktivitet kan passe bedre i dag."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "heart",
                destination: .insights
            )
        case .ready, .balanced, .unavailable:
            break
        }

        if let ratio = trainingLoadRatio, ratio.isFinite, ratio >= 1.5 {
            return Advice(
                title: tr("Mind your training load", "Vurder belastningen"),
                detail: hasWorkoutToday
                    ? tr("Recent load is high. Adjust today's workout if needed.",
                         "Belastningen er høy. Tilpass økten ved behov.")
                    : tr("Recent load is high. Consider a lighter day.",
                         "Belastningen er høy. Vurder en roligere dag."),
                source: tr("Based on recent training", "Basert på treningsbelastning"),
                symbol: "chart.bar.xaxis",
                destination: .insights
            )
        }

        switch readiness {
        case .ready:
            return Advice(
                title: hasWorkoutToday
                    ? tr("Ready for today's session", "Klar for dagens økt")
                    : tr("Ready to move", "Klar for aktivitet"),
                detail: hasWorkoutToday
                    ? tr("Readiness looks good. Check how you feel as you start.",
                         "Dagsformen er god. Kjenn etter når du starter.")
                    : tr("Readiness looks good. Choose a suitable activity.",
                         "Dagsformen er god. Velg en aktivitet som passer."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "sparkles",
                destination: .insights
            )
        case .balanced:
            return Advice(
                title: hasWorkoutToday
                    ? tr("Follow your plan", "Følg planen")
                    : tr("Keep moving", "Hold deg i gang"),
                detail: hasWorkoutToday
                    ? tr("Readiness is balanced. Adjust to how you feel.",
                         "Dagsformen er balansert. Tilpass etter behov.")
                    : tr("A session at a comfortable intensity could suit today.",
                         "En økt med behagelig intensitet kan passe i dag."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "figure.walk",
                destination: .insights
            )
        case .unavailable:
            if hasWorkoutToday {
                return Advice(
                    title: tr("Listen to your body", "Kjenn etter i dag"),
                    detail: tr("A workout is planned. Adjust it to how you feel.",
                               "Du har en økt planlagt. Tilpass etter dagsformen."),
                    source: tr("Based on your plan", "Basert på planen"),
                    symbol: "calendar",
                    destination: .training
                )
            }
            return Advice(
                title: tr("Make time to move", "Finn litt bevegelse"),
                detail: tr("A short walk or an easy session could be a good start.",
                           "En kort tur eller rolig økt kan være en fin start."),
                source: tr("General suggestion", "Generelt forslag"),
                symbol: "figure.walk",
                destination: .training
            )
        case .recover, .takeItEasy:
            // Both cases return above. This fallback keeps the switch
            // exhaustive if the policy's priority order changes.
            return Advice(
                title: tr("Take it easy", "Ta det rolig"),
                detail: tr("Adjust activity to how you feel.",
                           "Tilpass aktiviteten etter dagsformen."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "leaf",
                destination: .insights
            )
        }
    }
}
