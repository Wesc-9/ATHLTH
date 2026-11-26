import Foundation

/// Training advice, not a medical assessment or a replacement for wearable
/// recovery. Missing responses remain unknown and cannot justify progression.
enum ATHLTHDailyFormPolicy {
    enum Recommendation: String, Equatable {
        case unavailable, normal, lighter, rest

        var title: String {
            switch self {
            case .unavailable: return ATHLTHLocalization.choose(english: "Not enough information", norwegian: "For lite informasjon")
            case .normal: return ATHLTHLocalization.choose(english: "Consider the planned session", norwegian: "Vurder planlagt økt")
            case .lighter: return ATHLTHLocalization.choose(english: "Consider a lighter session", norwegian: "Vurder en roligere økt")
            case .rest: return ATHLTHLocalization.choose(english: "Prioritize recovery", norwegian: "Prioriter restitusjon")
            }
        }
    }

    struct Assessment: Equatable {
        let measuredScore: Int?
        let subjectiveScore: Int?
        let contextualScore: Int?
        let recommendation: Recommendation
        let reasons: [String]
        let illnessReported: Bool
        let answeredCount: Int

        var explanation: String {
            reasons.isEmpty
                ? ATHLTHLocalization.choose(english: "Answer a daily check-in to personalize your advice.", norwegian: "Registrer dagsformen for å tilpasse treningsrådene.")
                : reasons.joined(separator: " ")
        }
    }

    static func assess(entry: RecoverySorenessEntry?, measuredScore: Int?,
                       now: Date = Date(), calendar: Calendar = .current) -> Assessment {
        let entry = entry.flatMap { $0.date <= now && calendar.isDate($0.date, inSameDayAs: now) ? $0 : nil }
        let measured = measuredScore.flatMap { (0...100).contains($0) ? $0 : nil }
        func valid(_ value: Int?) -> Int? { value.flatMap { (1...5).contains($0) ? $0 : nil } }
        let energy = valid(entry?.energy), stress = valid(entry?.stress)
        let soreness = valid(entry?.overallSoreness), motivation = valid(entry?.motivation)
        let sleep = valid(entry?.sleepQuality)
        let values = [energy, stress.map { 6 - $0 }, soreness.map { 6 - $0 }, motivation, sleep].compactMap { $0 }
        // At least three answers are required to show a subjective score.
        let subjective = values.count >= 3 ? Int((Double(values.reduce(0, +) - values.count) * 25 / Double(values.count)).rounded()) : nil
        let contextual: Int? = {
            guard let measured, let subjective else { return nil }
            // Self-report may lower the contextual result, never raise the
            // objective wearable score or override a warning.
            return min(measured, Int((0.7 * Double(measured) + 0.3 * Double(subjective)).rounded()))
        }()
        let unwell = entry?.feelsUnwell == true
        var reasons: [String] = []
        if unwell {
            reasons.append(ATHLTHLocalization.choose(english: "You reported feeling ill. Consider resting; seek medical advice if symptoms are concerning or persistent.", norwegian: "Du har oppgitt sykdomsfølelse. Vurder hvile, og kontakt helsepersonell ved bekymringsfulle eller vedvarende symptomer."))
        }
        if energy.map({ $0 <= 2 }) == true { reasons.append(ATHLTHLocalization.choose(english: "Low reported energy.", norwegian: "Lav opplevd energi.")) }
        if stress.map({ $0 >= 4 }) == true { reasons.append(ATHLTHLocalization.choose(english: "High reported stress.", norwegian: "Høyt opplevd stress.")) }
        if soreness.map({ $0 >= 4 }) == true || entry?.ratings.values.contains(where: { $0.rawValue >= 2 }) == true {
            reasons.append(ATHLTHLocalization.choose(english: "Reported muscle soreness.", norwegian: "Rapportert muskelømhet."))
        }
        if sleep.map({ $0 <= 2 }) == true { reasons.append(ATHLTHLocalization.choose(english: "Poor reported sleep quality.", norwegian: "Lav opplevd søvnkvalitet.")) }
        if motivation.map({ $0 <= 2 }) == true { reasons.append(ATHLTHLocalization.choose(english: "Low motivation; a shorter session may be easier to complete.", norwegian: "Lav motivasjon; en kortere økt kan være enklere å gjennomføre.")) }
        if measured.map({ $0 < 60 }) == true { reasons.append(ATHLTHLocalization.choose(english: "Lower measured recovery score.", norwegian: "Lavere målt restitusjonsscore.")) }
        let recommendation: Recommendation
        if unwell { recommendation = .rest }
        else if !reasons.isEmpty || contextual.map({ $0 < 60 }) == true { recommendation = .lighter }
        else if measured != nil || !values.isEmpty { recommendation = .normal }
        else { recommendation = .unavailable }
        if reasons.isEmpty, recommendation == .normal {
            reasons.append(ATHLTHLocalization.choose(english: "No clear warning in the available signals. Follow how you feel; progression is not guaranteed.", norwegian: "Ingen tydelige varselsignaler i tilgjengelige data. Kjenn etter underveis; dette er ikke en garanti for økt kapasitet."))
        }
        return Assessment(measuredScore: measured, subjectiveScore: subjective, contextualScore: contextual,
                          recommendation: recommendation, reasons: reasons, illnessReported: unwell,
                          answeredCount: values.count + (entry?.feelsUnwell == nil ? 0 : 1))
    }

    /// Keep original measured readiness when a report does not call for
    /// reduced load. Never promote low readiness on the basis of self-report.
    static func recommendationReadiness(_ original: HomeDailyRecommendationPolicy.Readiness,
                                        entry: RecoverySorenessEntry?, now: Date = Date()) -> HomeDailyRecommendationPolicy.Readiness {
        let result = assess(entry: entry, measuredScore: nil, now: now)
        switch result.recommendation {
        case .rest: return .recover
        case .lighter: return original == .recover ? .recover : .takeItEasy
        default: return original
        }
    }

    struct Day: Identifiable {
        let date: Date
        let energy: Int?
        let stress: Int?
        let soreness: Int?
        let motivation: Int?
        let sleep: Int?
        var id: Date { date }
    }

    static func history(_ entries: [RecoverySorenessEntry], days: Int = 7, now: Date = Date(),
                        calendar: Calendar = .current) -> [Day] {
        let length = min(max(days, 1), 90)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 1 - length, to: today) ?? today
        var byDay: [Date: RecoverySorenessEntry] = [:]
        for entry in entries.sorted(by: { $0.date < $1.date }) where entry.date >= start && entry.date <= now {
            byDay[calendar.startOfDay(for: entry.date)] = entry
        }
        return (0..<length).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
            let entry = byDay[date]
            return Day(date: date, energy: entry?.energy, stress: entry?.stress, soreness: entry?.overallSoreness,
                       motivation: entry?.motivation, sleep: entry?.sleepQuality)
        }
    }
}
