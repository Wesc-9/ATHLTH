import Foundation

/// Activity attached to an athlete-owned exercise. It is not inferred from
/// muscle groups or exercise names: those cannot reliably distinguish sport.
enum ATHLTHExerciseActivity: String, Codable, CaseIterable, Identifiable, Hashable {
    case running
    case walking
    case strength
    case cycling
    case hiking
    case yoga
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .cycling: return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
        case .hiking: return ATHLTHLocalization.choose(english: "Hiking", norwegian: "Tur")
        case .yoga: return ATHLTHLocalization.choose(english: "Yoga", norwegian: "Yoga")
        case .other: return ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell"
        case .cycling: return "bicycle"
        case .hiking: return "mountain.2"
        case .yoga: return "figure.yoga"
        case .other: return "square.grid.2x2"
        }
    }
}
