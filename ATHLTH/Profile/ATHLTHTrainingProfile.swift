import Foundation

/// Personal, account-scoped training background. Never published in the
/// public profile or sent to Coach without a separate per-request decision.
struct ATHLTHTrainingProfile: Codable, Equatable {
    var trainingNotes: String = ""
    // Historical free-text stays readable after migrating to structured restrictions.
    var injuryAndLimitations: String = ""
    // Optional so existing saved profiles decode without a migration or data loss.
    var injuryRestrictions: [ATHLTHInjuryRestriction]? = nil
    var measurements: [ATHLTHBodyMeasurement] = []

    var coachLimitationsSummary: String {
        let structured = (injuryRestrictions ?? [])
            .map(\.coachInstruction)
            .joined(separator: "\n")
        let previous = injuryAndLimitations.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return [structured, previous].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    var updatedAt: Date = .now

    static func load(userID: UUID) -> Self {
        AccountLocalStorage.read(
            Self.self, name: "personalTrainingProfile", userID: userID
        ) ?? .init()
    }

    func save(userID: UUID) {
        AccountLocalStorage.write(
            self, name: "personalTrainingProfile", userID: userID
        )
    }

    mutating func record(
        metric: ATHLTHBodyMetric, value: Double, at date: Date
    ) -> Bool {
        guard metric.range.contains(value), value.isFinite else { return false }
        let calendar = Calendar.current
        // One reading per metric per local calendar day. Editing never
        // destroys another metric's history.
        if let index = measurements.firstIndex(where: {
            $0.metric == metric && calendar.isDate($0.date, inSameDayAs: date)
        }) {
            measurements[index].value = value
            measurements[index].date = date
        } else {
            measurements.append(.init(metric: metric, value: value, date: date))
        }
        updatedAt = .now
        return true
    }

    func readings(for metric: ATHLTHBodyMetric) -> [ATHLTHBodyMeasurement] {
        measurements.filter { $0.metric == metric }
            .sorted { $0.date < $1.date }
    }

    func latest(_ metric: ATHLTHBodyMetric) -> ATHLTHBodyMeasurement? {
        readings(for: metric).last
    }
}

enum ATHLTHBodyMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case weight
    case waist
    case hips
    case chest
    case upperArm
    case thigh
    case calf
    case neck

    var id: String { rawValue }
    var unit: String { self == .weight ? "kg" : "cm" }
    var range: ClosedRange<Double> {
        self == .weight ? 15...500 : 5...300
    }
    var name: String {
        let no = ATHLTHLocalization.isNorwegian
        switch self {
        case .weight: return no ? "Vekt" : "Body weight"
        case .waist: return no ? "Midje" : "Waist"
        case .hips: return no ? "Hofte" : "Hips"
        case .chest: return no ? "Bryst" : "Chest"
        case .upperArm: return no ? "Overarm" : "Upper arm"
        case .thigh: return no ? "Lår" : "Thigh"
        case .calf: return no ? "Legg" : "Calf"
        case .neck: return no ? "Hals" : "Neck"
        }
    }
}

struct ATHLTHBodyMeasurement: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var metric: ATHLTHBodyMetric
    var value: Double
    var date: Date
}
