import Foundation

/// User-selected activity limitations, not a medical diagnosis. Saved privately
/// alongside the existing training history. Only sent to Coach after consent.
enum ATHLTHInjuryArea: String, Codable, CaseIterable, Identifiable {
    case foot, ankle, achilles, knee, thighFront, thighBack, calf, hip
    case glutes, lowerBack, upperBack, neck, shoulder, chest, elbow, wrist
    case hand, abdomen, other

    var id: String { rawValue }
    var title: String {
        let no = ATHLTHLocalization.isNorwegian
        switch self {
        case .foot: return no ? "Fot" : "Foot"
        case .ankle: return no ? "Ankel" : "Ankle"
        case .achilles: return no ? "Akillessene" : "Achilles tendon"
        case .knee: return no ? "Kne" : "Knee"
        case .thighFront: return no ? "Forside lår" : "Quadriceps"
        case .thighBack: return no ? "Bakside lår" : "Hamstrings"
        case .calf: return no ? "Legg" : "Calf"
        case .hip: return no ? "Hofte" : "Hip"
        case .glutes: return no ? "Setemuskler" : "Glutes"
        case .lowerBack: return no ? "Nedre rygg" : "Lower back"
        case .upperBack: return no ? "Øvre rygg" : "Upper back"
        case .neck: return no ? "Nakke" : "Neck"
        case .shoulder: return no ? "Skulder" : "Shoulder"
        case .chest: return no ? "Bryst" : "Chest"
        case .elbow: return no ? "Albue" : "Elbow"
        case .wrist: return no ? "Håndledd" : "Wrist"
        case .hand: return no ? "Hånd" : "Hand"
        case .abdomen: return no ? "Mage/kjerne" : "Abdominals/core"
        case .other: return no ? "Annet område" : "Other area"
        }
    }

    /// Stable English terms help the Coach interpret Norwegian UI selections.
    var instructionName: String {
        switch self {
        case .foot: return "foot"
        case .ankle: return "ankle"
        case .achilles: return "Achilles tendon"
        case .knee: return "knee"
        case .thighFront: return "quadriceps"
        case .thighBack: return "hamstrings"
        case .calf: return "calf"
        case .hip: return "hip"
        case .glutes: return "glutes"
        case .lowerBack: return "lower back"
        case .upperBack: return "upper back"
        case .neck: return "neck"
        case .shoulder: return "shoulder"
        case .chest: return "chest"
        case .elbow: return "elbow"
        case .wrist: return "wrist"
        case .hand: return "hand"
        case .abdomen: return "abdominals/core"
        case .other: return "other body area"
        }
    }
}

enum ATHLTHInjurySide: String, Codable, CaseIterable, Identifiable {
    case unspecified, left, right, both
    var id: String { rawValue }
    var title: String {
        let no = ATHLTHLocalization.isNorwegian
        switch self {
        case .unspecified: return no ? "Ikke spesifisert" : "Not specified"
        case .left: return no ? "Venstre" : "Left"
        case .right: return no ? "Høyre" : "Right"
        case .both: return no ? "Begge sider" : "Both sides"
        }
    }
    var instruction: String {
        switch self {
        case .unspecified: return ""
        case .left: return "left "
        case .right: return "right "
        case .both: return "both sides of "
        }
    }
}

enum ATHLTHInjuryRestrictionLevel: String, Codable, CaseIterable, Identifiable {
    case avoid, major, moderate, mild
    var id: String { rawValue }

    var title: String {
        let no = ATHLTHLocalization.isNorwegian
        switch self {
        case .avoid: return no ? "Kan ikke trene / belaste" : "Cannot train or load"
        case .major: return no ? "Store begrensninger" : "Major limitations"
        case .moderate: return no ? "Noen begrensninger" : "Some limitations"
        case .mild: return no ? "Ta ekstra hensyn" : "Use extra caution"
        }
    }

    var instruction: String {
        switch self {
        case .avoid:
            return "DO NOT prescribe exercises that train or load this area. Ask the athlete for clarification rather than substituting a potentially aggravating exercise."
        case .major:
            return "Significant restrictions: avoid heavy loads and potentially aggravating movements. Ask about safe alternatives before proposing exercises."
        case .moderate:
            return "Some limitations: use only athlete-accepted movements and conservative intensity, and ask about movements to avoid."
        case .mild:
            return "Mild concerns: suggest comfortable ranges and self-adjusted loading, without assuming the area is pain-free."
        }
    }
}

struct ATHLTHInjuryRestriction: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var area: ATHLTHInjuryArea = .knee
    var side: ATHLTHInjurySide = .unspecified
    var level: ATHLTHInjuryRestrictionLevel = .moderate
    var notes: String = ""

    var coachInstruction: String {
        let clean = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Athlete-reported restriction: \(side.instruction)\(area.instructionName). \(level.instruction)" +
            (clean.isEmpty ? "" : " Athlete's notes: \(String(clean.prefix(500))).")
    }
}
