import Foundation

/// Personalized, conservative suggestions derived from known plan + Health
/// signals only. Never rewrites a user's plan or infers injury/medical status.
enum HomeDailyRecommendationPolicy {
    enum Readiness: Equatable {
        case ready, balanced, takeItEasy, recover, unavailable
    }

    enum Destination: Equatable {
        case insights, training
    }

    enum PlannedActivity: Equatable {
        case running, strength, other
    }

    struct Advice {
        let title: String
        let detail: String
        let source: String
        let symbol: String
        let destination: Destination
        /// Real comparison, omitted if the baseline is absent.
        let evidence: String?

        init(title: String, detail: String, source: String,
             symbol: String, destination: Destination,
             evidence: String? = nil) {
            self.title = title
            self.detail = detail
            self.source = source
            self.symbol = symbol
            self.destination = destination
            self.evidence = evidence
        }
    }

    static func recommendation(
        readiness: Readiness,
        hasWorkoutToday: Bool,
        trainingLoadRatio: Double?,
        plannedActivity: PlannedActivity? = nil
    ) -> Advice {
        func tr(_ en: String, _ no: String) -> String {
            ATHLTHLocalization.choose(english: en, norwegian: no)
        }

        // A load *ratio* means recent minutes relative to a personal baseline.
        // Never use the raw ratio as a clinical fatigue or injury indicator.
        let ratio = trainingLoadRatio.flatMap { value in
            value.isFinite && value >= 0 && value <= 20 ? value : nil
        }
        let loadEvidence: String? = ratio.map { value in
            let change = Int(((value - 1) * 100).rounded())
            return tr(
                "Training minutes \(change >= 0 ? "+" : "")\(change)% vs 4-week average",
                "Treningsminutter \(change >= 0 ? "+" : "")\(change) % mot 4-ukers snitt"
            )
        }

        func lighterSessionTitle() -> String {
            switch plannedActivity {
            case .running:
                return tr("Choose an easy run", "Velg en rolig løpetur")
            case .strength:
                return tr("Reduce strength volume", "Reduser styrkevolumet")
            case .other, .none:
                return hasWorkoutToday
                    ? tr("Adjust today's workout", "Tilpass dagens økt")
                    : tr("Take an active recovery day", "Velg aktiv restitusjon")
            }
        }

        func lighterSessionDetail() -> String {
            switch plannedActivity {
            case .running:
                return tr("Consider 20–30 min at conversational pace. Skip hard efforts.",
                          "Vurder 20–30 min i pratefart. Dropp harde drag.")
            case .strength:
                return tr("Consider 1–2 fewer sets and lighter weights today.",
                          "Vurder 1–2 færre sett og lettere vekter i dag.")
            case .other:
                return tr("Keep the planned workout short and comfortable.",
                          "Hold den planlagte økten kort og behagelig.")
            case .none:
                return tr("Try a gentle 20–30 min walk if it feels right.",
                          "Prøv en rolig gåtur på 20–30 min hvis det passer.")
            }
        }

        // Low readiness takes priority over a seemingly normal training load.
        if readiness == .recover || readiness == .takeItEasy {
            return Advice(
                title: lighterSessionTitle(),
                detail: lighterSessionDetail(),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "leaf",
                destination: .insights,
                evidence: (ratio ?? 0) >= 1.5 ? loadEvidence : nil
            )
        }

        if let ratio, ratio >= 1.5 {
            return Advice(
                title: lighterSessionTitle(),
                detail: lighterSessionDetail(),
                source: tr("Based on recent training", "Basert på treningsbelastning"),
                symbol: plannedActivity == .strength ? "dumbbell" : "chart.bar.xaxis",
                destination: .insights,
                evidence: loadEvidence
            )
        }

        switch readiness {
        case .ready:
            return Advice(
                title: hasWorkoutToday
                    ? tr("Your planned session fits", "Dagens økt kan passe")
                    : tr("Good day for activity", "Fin dag for aktivitet"),
                detail: hasWorkoutToday
                    ? tr("Start as planned. Check how you feel during the warm-up.",
                         "Start som planlagt. Kjenn etter under oppvarmingen.")
                    : tr("Try 20–30 min walking or a comfortable run.",
                         "Prøv 20–30 min gange eller rolig løping."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "sparkles",
                destination: .training
            )
        case .balanced:
            return Advice(
                title: hasWorkoutToday
                    ? tr("Keep today's intensity steady", "Hold jevn intensitet")
                    : tr("Build a steady habit", "Bygg en jevn vane"),
                detail: hasWorkoutToday
                    ? tr("Warm up gently, then follow the plan at a comfortable effort.",
                         "Varm rolig opp og følg planen med behagelig innsats.")
                    : tr("Try 20–30 min easy activity today.",
                         "Prøv 20–30 min rolig aktivitet i dag."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "figure.walk",
                destination: .training
            )
        case .unavailable:
            return Advice(
                title: hasWorkoutToday
                    ? tr("Start with a gentle warm-up", "Start med rolig oppvarming")
                    : tr("Try a short walk", "Prøv en kort gåtur"),
                detail: hasWorkoutToday
                    ? tr("No reliable readiness data. Use the warm-up to adjust today's plan.",
                         "Mangler sikre dagsformdata. Tilpass økten under oppvarmingen.")
                    : tr("Try 15–20 min easy walking. No readiness estimate is available.",
                         "Prøv 15–20 min rolig gange. Dagsformdata mangler."),
                source: hasWorkoutToday
                    ? tr("Based on your plan", "Basert på planen")
                    : tr("General suggestion", "Generelt forslag"),
                symbol: hasWorkoutToday ? "calendar" : "figure.walk",
                destination: .training
            )
        case .recover, .takeItEasy:
            // Already handled above.
            return Advice(
                title: lighterSessionTitle(),
                detail: lighterSessionDetail(),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "leaf",
                destination: .insights
            )
        }
    }
}
