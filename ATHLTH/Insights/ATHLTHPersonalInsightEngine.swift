import Foundation

/// Correlations and simple contrasts based on observations already authorized
/// in ATHLTH. No score is a diagnosis, forecast or inferred cause.
struct ATHLTHPersonalInsight: Identifiable, Equatable {
    enum Kind: String {
        case combinedSignals
        case sleepAndEnergy
        case stressAndEnergy
        case everydayMovement
        case weekdayEnergy
        case sleepConsistency
    }

    struct Evidence: Equatable {
        let labelNO: String
        let labelEN: String
        let value: String

        var label: String {
            ATHLTHLocalization.choose(english: labelEN, norwegian: labelNO)
        }
    }

    let kind: Kind
    let sampleCount: Int
    let evidence: [Evidence]
    let explanationNO: String
    let explanationEN: String
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .combinedSignals:
            return ATHLTHLocalization.choose(
                english: "Several body signals changed together",
                norwegian: "Flere kroppssignaler har endret seg"
            )
        case .sleepAndEnergy:
            return ATHLTHLocalization.choose(
                english: "Sleep and reported energy",
                norwegian: "Søvn og opplevd energi"
            )
        case .stressAndEnergy:
            return ATHLTHLocalization.choose(
                english: "Stress and daily energy",
                norwegian: "Stress og energi i hverdagen"
            )
        case .everydayMovement:
            return ATHLTHLocalization.choose(
                english: "Movement beyond workouts",
                norwegian: "Bevegelse utenom treningsøktene"
            )
        case .weekdayEnergy:
            return ATHLTHLocalization.choose(
                english: "Your weekday patterns",
                norwegian: "Dine mønstre gjennom uken"
            )
        case .sleepConsistency:
            return ATHLTHLocalization.choose(
                english: "Your sleep varies across nights",
                norwegian: "Søvnen varierer mellom nettene"
            )
        }
    }

    var explanation: String {
        ATHLTHLocalization.choose(
            english: explanationEN, norwegian: explanationNO
        )
    }

    var icon: String {
        switch kind {
        case .combinedSignals: return "waveform.path.ecg"
        case .sleepAndEnergy: return "moon.stars"
        case .stressAndEnergy: return "brain.head.profile"
        case .everydayMovement: return "figure.walk"
        case .weekdayEnergy: return "calendar"
        case .sleepConsistency: return "moon.zzz"
        }
    }

    var caution: String {
        ATHLTHLocalization.choose(
            english: "An observed pattern, not proof of cause or a medical assessment. Measurements and self-reports can be incomplete.",
            norwegian: "Et observert mønster, ikke bevis for årsak eller en medisinsk vurdering. Målinger og egenrapportering kan være ufullstendige."
        )
    }
}

/// Pure and deterministic analysis of local data; no networking, AI upload
/// or additional HealthKit permissions. Unpaired days never become zeros.
enum ATHLTHPersonalInsightEngine {
    private struct Pair {
        let first: Double
        let second: Double
    }

    static func findings(
        days: [RecoveryTrendDay],
        checkIns: [RecoverySorenessEntry],
        stepsChangePercent: Double? = nil,
        trainingChangePercent: Double? = nil,
        averageDailySteps: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ATHLTHPersonalInsight] {
        let start = calendar.date(byAdding: .day, value: -27,
                                  to: calendar.startOfDay(for: now)) ?? now
        // Use one observation per calendar day and ignore future dates.
        let observations = days.filter {
            $0.date >= start && $0.date <= now
        }.sorted { $0.date < $1.date }
        var byDay: [Date: RecoveryTrendDay] = [:]
        for day in observations {
            byDay[calendar.startOfDay(for: day.date)] = day
        }
        var selfReports: [Date: RecoverySorenessEntry] = [:]
        for entry in checkIns.sorted(by: { $0.date < $1.date }) {
            guard entry.date >= start, entry.date <= now else { continue }
            selfReports[calendar.startOfDay(for: entry.date)] = entry
        }

        var output: [ATHLTHPersonalInsight] = []
        if let finding = combinedSignalFinding(observations) {
            output.append(finding)
        }
        if let finding = sleepEnergyFinding(
            days: byDay, checkIns: selfReports
        ) {
            output.append(finding)
        }
        if let finding = stressEnergyFinding(selfReports) {
            output.append(finding)
        }
        if let finding = movementFinding(
            steps: stepsChangePercent,
            training: trainingChangePercent,
            averageSteps: averageDailySteps
        ) {
            output.append(finding)
        }
        if let finding = weekdayEnergyFinding(
            selfReports, calendar: calendar
        ) {
            output.append(finding)
        }
        if let finding = sleepConsistencyFinding(observations),
           !output.contains(where: { $0.kind == .sleepAndEnergy }) {
            output.append(finding)
        }
        return output
    }

    private static func mean(_ values: [Double]) -> Double? {
        let finite = values.filter { $0.isFinite }
        guard !finite.isEmpty else { return nil }
        return finite.reduce(0, +) / Double(finite.count)
    }

    private static func number(_ value: Double, places: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }

    private static func evidence(
        _ labelNO: String, _ labelEN: String, _ value: String
    ) -> ATHLTHPersonalInsight.Evidence {
        .init(labelNO: labelNO, labelEN: labelEN, value: value)
    }

    private static func combinedSignalFinding(
        _ days: [RecoveryTrendDay]
    ) -> ATHLTHPersonalInsight? {
        guard days.count >= 12 else { return nil }
        let baseline = Array(days.dropLast(3))
        let recent = Array(days.suffix(3))

        let sources: [(String, String, (RecoveryTrendDay) -> Double?, Double)] = [
            ("HRV", "HRV", { $0.hrvMilliseconds }, 0.15),
            ("Hvilepuls", "Resting HR", { $0.restingHeartRate }, 0.08),
            ("Respirasjon", "Breathing", { $0.respiratoryRate }, 0.08)
        ]
        var changes: [ATHLTHPersonalInsight.Evidence] = []
        var minimumObservations = Int.max
        for (labelNO, labelEN, value, threshold) in sources {
            let past = baseline.compactMap(value).filter {
                $0.isFinite && $0 > 0
            }
            let latest = recent.compactMap(value).filter {
                $0.isFinite && $0 > 0
            }
            guard past.count >= 8, latest.count >= 2,
                  let before = mean(past), let after = mean(latest),
                  before > 0 else { continue }
            let change = (after - before) / before
            guard abs(change) >= threshold,
                  abs(change) <= 0.65 else { continue }
            let signed = change > 0 ? "+" : ""
            changes.append(evidence(
                labelNO, labelEN,
                signed + number(change * 100) + " %"
            ))
            minimumObservations = min(minimumObservations,
                                      past.count + latest.count)
        }
        guard changes.count >= 2 else { return nil }
        return .init(
            kind: .combinedSignals,
            sampleCount: minimumObservations,
            evidence: changes,
            explanationNO: "Minst to målte signaler har beveget seg fra ditt tidligere nivå de siste tre dagene. Dette viser endring, ikke hva som har forårsaket den.",
            explanationEN: "At least two measured signals moved away from your earlier baseline over the past three days. This shows a change, not what caused it."
        )
    }

    private static func sleepEnergyFinding(
        days: [Date: RecoveryTrendDay],
        checkIns: [Date: RecoverySorenessEntry]
    ) -> ATHLTHPersonalInsight? {
        let pairs: [Pair] = checkIns.compactMap { date, entry in
            guard let energy = entry.energy, (1...5).contains(energy),
                  let seconds = days[date]?.sleepDuration,
                  seconds.isFinite, (2 * 3_600...14 * 3_600).contains(seconds)
            else { return nil }
            return Pair(first: seconds / 3_600, second: Double(energy))
        }
        guard pairs.count >= 8 else { return nil }
        let sorted = pairs.sorted { $0.first < $1.first }
        // Deliberately compare distinct low/high thirds to avoid
        // describing tiny nightly differences as a meaningful pattern.
        let size = pairs.count / 3
        guard size >= 3,
              let lowSleep = mean(Array(sorted.prefix(size)).map(\.first)),
              let highSleep = mean(Array(sorted.suffix(size)).map(\.first)),
              highSleep - lowSleep >= 0.75,
              let lowEnergy = mean(Array(sorted.prefix(size)).map(\.second)),
              let highEnergy = mean(Array(sorted.suffix(size)).map(\.second)),
              abs(highEnergy - lowEnergy) >= 0.6 else { return nil }

        let higherAfterLonger = highEnergy > lowEnergy
        return .init(
            kind: .sleepAndEnergy,
            sampleCount: pairs.count,
            evidence: [
                evidence("Kortere netter", "Shorter nights",
                         number(lowEnergy, places: 1) + "/5"),
                evidence("Lengre netter", "Longer nights",
                         number(highEnergy, places: 1) + "/5")
            ],
            explanationNO: higherAfterLonger
                ? "På dagene med lengre registrert søvn har du i snitt rapportert mer energi enn etter kortere netter. Andre forhold kan også påvirke dette."
                : "På dagene med lengre registrert søvn har du i snitt rapportert mindre energi enn etter kortere netter. Dette er en sammenheng, ikke bevis på årsak.",
            explanationEN: higherAfterLonger
                ? "On days after longer recorded sleep you reported higher average energy than after shorter nights. Other factors may contribute."
                : "On days after longer recorded sleep you reported lower average energy than after shorter nights. This is an association, not proof of cause."
        )
    }

    private static func stressEnergyFinding(
        _ entries: [Date: RecoverySorenessEntry]
    ) -> ATHLTHPersonalInsight? {
        let pairs = entries.values.compactMap { entry -> Pair? in
            guard let stress = entry.stress, let energy = entry.energy,
                  (1...5).contains(stress), (1...5).contains(energy)
            else { return nil }
            return Pair(first: Double(stress), second: Double(energy))
        }
        guard pairs.count >= 8 else { return nil }
        let low = pairs.filter { $0.first <= 2 }.map(\.second)
        let high = pairs.filter { $0.first >= 4 }.map(\.second)
        guard low.count >= 3, high.count >= 3,
              let lowEnergy = mean(low), let highEnergy = mean(high),
              abs(lowEnergy - highEnergy) >= 0.7 else { return nil }
        let lowerWhenStressed = highEnergy < lowEnergy
        return .init(
            kind: .stressAndEnergy,
            sampleCount: pairs.count,
            evidence: [
                evidence("Lavt stress", "Lower reported stress",
                         number(lowEnergy, places: 1) + "/5"),
                evidence("Høyt stress", "Higher reported stress",
                         number(highEnergy, places: 1) + "/5")
            ],
            explanationNO: lowerWhenStressed
                ? "Du har oftere rapportert mindre energi på dager med høyt opplevd stress enn på dager med lavt stress."
                : "Du har rapportert mer energi på dager med høyt opplevd stress enn på dager med lavt stress. Se dette i sammenheng med dine egne rutiner.",
            explanationEN: lowerWhenStressed
                ? "You reported lower average energy on high-stress days than on low-stress days."
                : "You reported higher average energy on high-stress days than on low-stress days. Interpret this in the context of your own routines."
        )
    }

    private static func movementFinding(
        steps: Double?, training: Double?, averageSteps: Double?
    ) -> ATHLTHPersonalInsight? {
        guard let steps, let training, let averageSteps,
              steps.isFinite, training.isFinite,
              averageSteps.isFinite, averageSteps >= 0,
              abs(steps) <= 300, abs(training) <= 300
        else { return nil }
        let diverged = (steps >= 15 && training <= -15) ||
            (steps <= -15 && training >= 15)
        guard diverged else { return nil }
        return .init(
            kind: .everydayMovement,
            sampleCount: 28,
            evidence: [
                evidence("Daglige steg", "Daily steps",
                         (steps > 0 ? "+" : "") + number(steps) + " %"),
                evidence("Treningstid", "Workout time",
                         (training > 0 ? "+" : "") + number(training) + " %")
            ],
            explanationNO: "Endringen i skritt og registrert treningstid går i hver sin retning sammenlignet med forrige 28-dagersperiode. Skritt beskriver også vanlig hverdagsbevegelse.",
            explanationEN: "Steps and recorded workout duration changed in opposite directions compared with the previous 28-day period. Steps also reflect everyday movement."
        )
    }

    private static func weekdayEnergyFinding(
        _ entries: [Date: RecoverySorenessEntry],
        calendar: Calendar
    ) -> ATHLTHPersonalInsight? {
        let samples: [(Date, Double)] = entries.compactMap { date, entry in
            guard let value = entry.energy, (1...5).contains(value) else {
                return nil
            }
            return (date, Double(value))
        }
        guard samples.count >= 12 else { return nil }
        let weekend = samples.filter {
            calendar.isDateInWeekend($0.0)
        }.map(\.1)
        let weekday = samples.filter {
            !calendar.isDateInWeekend($0.0)
        }.map(\.1)
        guard weekend.count >= 4, weekday.count >= 6,
              let w = mean(weekend), let d = mean(weekday),
              abs(w - d) >= 0.8 else { return nil }
        return .init(
            kind: .weekdayEnergy,
            sampleCount: samples.count,
            evidence: [
                evidence("Hverdager", "Weekdays", number(d, places: 1) + "/5"),
                evidence("Helg", "Weekends", number(w, places: 1) + "/5")
            ],
            explanationNO: "Dine rapporterte energinivåer er forskjellige på hverdager og i helger. Dette er et mønster fra innsjekkene dine, ikke en forklaring på hvorfor.",
            explanationEN: "Your reported energy differs between weekdays and weekends. This is a pattern in your check-ins, not an explanation of why."
        )
    }

    private static func sleepConsistencyFinding(
        _ days: [RecoveryTrendDay]
    ) -> ATHLTHPersonalInsight? {
        let hours = days.compactMap { day -> Double? in
            guard let time = day.sleepDuration,
                  time.isFinite,
                  (2 * 3_600...14 * 3_600).contains(time)
            else { return nil }
            return time / 3_600
        }
        guard hours.count >= 12, let average = mean(hours) else {
            return nil
        }
        let variance = hours.reduce(0.0) {
            $0 + pow($1 - average, 2)
        } / Double(hours.count)
        let standardDeviation = sqrt(variance)
        guard standardDeviation >= 1.25 else { return nil }
        return .init(
            kind: .sleepConsistency,
            sampleCount: hours.count,
            evidence: [
                evidence("Gjennomsnitt", "Average",
                         number(average, places: 1) + " t"),
                evidence("Typisk variasjon", "Typical variation",
                         number(standardDeviation, places: 1) + " t")
            ],
            explanationNO: "Registrert søvnlengde har variert betydelig mellom nettene. Dette sier ikke noe sikkert om søvnkvaliteten eller årsaken til variasjonen.",
            explanationEN: "Recorded sleep duration varied considerably from night to night. This does not establish sleep quality or explain the variation."
        )
    }
}
