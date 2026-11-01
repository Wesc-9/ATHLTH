import Foundation

/// Explicit answers collected before ATHLTH Coach may generate a standalone plan.
/// Empty values are intentional: Coach must not choose goals, experience, schedule,
/// equipment or injury restrictions on the athlete's behalf.
struct ATHLTHAIProgramIntake: Equatable {
    enum Experience: String, CaseIterable, Identifiable {
        case beginner
        case regular
        case experienced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .beginner:
                ATHLTHLocalization.choose(english: "Beginner", norwegian: "Nybegynner")
            case .regular:
                ATHLTHLocalization.choose(english: "Regular", norwegian: "Normal")
            case .experienced:
                ATHLTHLocalization.choose(english: "Experienced", norwegian: "Erfaren")
            }
        }
    }

    enum Outcome: String, CaseIterable, Identifiable {
        case stronger
        case betterFitness
        case buildMuscle
        case endurance
        case weightManagement
        case mobility
        case wellbeing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stronger:
                ATHLTHLocalization.choose(english: "Get stronger", norwegian: "Bli sterkere")
            case .betterFitness:
                ATHLTHLocalization.choose(english: "Better fitness", norwegian: "Bedre form")
            case .buildMuscle:
                ATHLTHLocalization.choose(english: "Build muscle", norwegian: "Bygge muskler")
            case .endurance:
                ATHLTHLocalization.choose(english: "More endurance", norwegian: "Bedre utholdenhet")
            case .weightManagement:
                ATHLTHLocalization.choose(english: "Weight management", norwegian: "Vektkontroll")
            case .mobility:
                ATHLTHLocalization.choose(english: "More mobility", norwegian: "Bedre bevegelighet")
            case .wellbeing:
                ATHLTHLocalization.choose(english: "Feel better", norwegian: "Få mer overskudd")
            }
        }
    }

    enum Location: String, CaseIterable, Identifiable {
        case gym
        case home
        case outdoors

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gym:
                ATHLTHLocalization.choose(english: "Gym", norwegian: "Treningssenter")
            case .home:
                ATHLTHLocalization.choose(english: "Home", norwegian: "Hjemme")
            case .outdoors:
                ATHLTHLocalization.choose(english: "Outdoors", norwegian: "Utendørs")
            }
        }
    }

    enum InjuryStatus: String, CaseIterable, Identifiable {
        case none
        case considerations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none:
                ATHLTHLocalization.choose(
                    english: "No injuries or limitations",
                    norwegian: "Ingen skader eller begrensninger"
                )
            case .considerations:
                ATHLTHLocalization.choose(
                    english: "I have an injury or limitation",
                    norwegian: "Jeg har en skade eller begrensning"
                )
            }
        }
    }

    enum InjurySeverity: String, CaseIterable, Identifiable {
        case mild
        case moderate
        case severe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mild:
                ATHLTHLocalization.choose(english: "Mild", norwegian: "Lett")
            case .moderate:
                ATHLTHLocalization.choose(english: "Moderate", norwegian: "Moderat")
            case .severe:
                ATHLTHLocalization.choose(english: "Severe / very painful", norwegian: "Alvorlig / svært vondt")
            }
        }
    }

    enum InjuryRestriction: String, CaseIterable, Identifiable {
        case adapt
        case avoidAffectedArea
        case avoidLowerBody

        var id: String { rawValue }

        var title: String {
            switch self {
            case .adapt:
                ATHLTHLocalization.choose(
                    english: "Adapt exercises and load",
                    norwegian: "Tilpass øvelser og belastning"
                )
            case .avoidAffectedArea:
                ATHLTHLocalization.choose(
                    english: "Do not load the affected area",
                    norwegian: "Ikke belast det skadde området"
                )
            case .avoidLowerBody:
                ATHLTHLocalization.choose(
                    english: "No lower-body training",
                    norwegian: "Ingen trening av underkropp"
                )
            }
        }
    }

    enum InjuryCondition: String, CaseIterable, Identifiable {
        case trainLightly
        case someLimitations
        case avoidLoading

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trainLightly:
                ATHLTHLocalization.choose(
                    english: "Can train lightly", norwegian: "Kan trene lett"
                )
            case .someLimitations:
                ATHLTHLocalization.choose(
                    english: "Some limitations", norwegian: "Noen begrensninger"
                )
            case .avoidLoading:
                ATHLTHLocalization.choose(
                    english: "Do not train affected area",
                    norwegian: "Ikke tren området"
                )
            }
        }

        var severity: InjurySeverity {
            switch self {
            case .trainLightly: .mild
            case .someLimitations: .moderate
            case .avoidLoading: .severe
            }
        }

        var instruction: String {
            switch self {
            case .trainLightly:
                "Only gentle, low-load movements if they do not increase symptoms."
            case .someLimitations:
                "Adapt exercises, intensity and loading. Avoid aggravating movements."
            case .avoidLoading:
                "Do not prescribe loading or exercise involving this affected area."
            }
        }
    }

    struct InjuryEntry: Identifiable, Equatable {
        var id = UUID()
        var area: String?
        var condition: InjuryCondition?
    }

    var trainingTypes: Set<TrainingFocus> = []
    var outcomes: Set<Outcome> = []
    var muscleGroups: Set<String> = []
    var experience: Experience?
    var durationWeeks: Int?
    var sessionsPerWeek: Int?
    var availableDays: Set<Int> = []
    var sessionDurationMinutes: Int?
    var locations: Set<Location> = []
    /// Required only when both gym and outdoor training are selected.
    /// Nil means the athlete has not chosen a balance yet.
    var outdoorSharePercent: Int?
    var equipment: Set<String> = []
    var otherEquipment = ""
    var injuryStatus: InjuryStatus?
    /// Each injury independently identifies a body area and limitation.
    var injuries: [InjuryEntry] = []
    /// Compatibility for legacy and older callers; new intake uses injuries.
    var injuryAreas: Set<String> = []
    var injurySeverity: InjurySeverity?
    var injuryRestriction: InjuryRestriction?
    var injuryNotes = ""
    /// Exact exercise names/movements the athlete must never be prescribed.
    /// One name per line, comma or semicolon; this is always enforced locally.
    var excludedMovements = ""
    var healthSharingAuthorized = false

    var resolvedTrainingFocus: TrainingFocus? {
        if trainingTypes.contains(.running) && trainingTypes.contains(.strength) {
            return .hybrid
        }
        return TrainingFocus.allCases.first { trainingTypes.contains($0) }
    }

    var validationIssues: [String] {
        var issues: [String] = []
        if trainingTypes.isEmpty { issues.append("trainingTypes") }
        if outcomes.isEmpty { issues.append("outcomes") }
        if trainingTypes.contains(.strength) && muscleGroups.isEmpty {
            issues.append("muscleGroups")
        }
        if experience == nil { issues.append("experience") }
        if durationWeeks == nil || !(1...52).contains(durationWeeks ?? 0) {
            issues.append("durationWeeks")
        }
        if sessionsPerWeek == nil { issues.append("sessionsPerWeek") }
        if availableDays.isEmpty { issues.append("availableDays") }
        if let sessionsPerWeek, availableDays.count < sessionsPerWeek {
            issues.append("availableDayCount")
        }
        if sessionDurationMinutes == nil ||
           !(10...180).contains(sessionDurationMinutes ?? 0) {
            issues.append("sessionDurationMinutes")
        }
        if locations.isEmpty { issues.append("locations") }
        if equipment.isEmpty { issues.append("equipment") }
        if locations.contains(.gym) && locations.contains(.outdoors) &&
            outdoorSharePercent == nil {
            issues.append("locationBalance")
        }
        if injuryStatus == nil { issues.append("injuryStatus") }
        if injuryStatus == .considerations {
            if !injuries.isEmpty {
                // A row is an independent selection: never apply one global
                // severity to another injury or silently fill an empty row.
                if injuries.contains(where: { $0.area == nil || $0.condition == nil }) {
                    issues.append("injuryEntries")
                }
            } else if healthSharingAuthorized {
                // Preserve explicit consent validation for older callers.
                if injuryAreas.isEmpty { issues.append("injuryAreas") }
                if injurySeverity == nil { issues.append("injurySeverity") }
                if injuryRestriction == nil { issues.append("injuryRestriction") }
            }
        }
        return issues
    }

    var isComplete: Bool {
        validationIssues.isEmpty
    }

    var excludedExerciseNames: [String] {
        let candidates = excludedMovements
            .components(separatedBy: CharacterSet(charactersIn: "\n,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        return Array(Set(candidates)).sorted().prefix(40).map { String($0.prefix(100)) }
    }

    /// A blocked lower-body region must not produce leg workouts even when
    /// the rest of the generated plan looks plausible.
    var avoidLowerBodyTraining: Bool {
        let lowerBodyAreas: Set<String> = ["Knees", "Feet / ankles", "Hips"]
        return injuries.contains {
            $0.area.map(lowerBodyAreas.contains) == true &&
            $0.condition == .avoidLoading
        } || (injuries.isEmpty && injuryRestriction == .avoidLowerBody)
    }

    /// Explicitly consented data only; pass separately from generic notes
    /// so request truncation can never silently remove safety restrictions.
    var sharedInjurySafetyNotes: String? {
        guard injuryStatus == .considerations, healthSharingAuthorized else { return nil }
        let detailedEntries = injuries.compactMap { injury -> String? in
            guard let area = injury.area, let condition = injury.condition else {
                return nil
            }
            return "\(area): \(condition.title). \(condition.instruction)"
        }
        let summary: String
        if !detailedEntries.isEmpty {
            summary = detailedEntries.joined(separator: "\n")
        } else {
            summary = """
            Affected areas: \(injuryAreas.sorted().joined(separator: ", ")).
            Severity: \(injurySeverity?.title ?? "Not specified").
            Mandatory restriction: \(injuryRestriction?.title ?? "Not specified").
            """
        }
        return """
        Athlete-provided injuries / training limitations (use only for exercise avoidance):
        \(summary)
        Athlete description: \(String(injuryNotes.prefix(1_200))).
        Exercises or movements that must NOT be prescribed: \(excludedExerciseNames.joined(separator: "; ")).
        Do not include exercises, variations or intensity that violate these restrictions.
        If the restriction cannot be honored safely, provide a rest/recovery option
        instead and explain that a qualified professional should be consulted.
        This is training guidance, not a diagnosis or medical clearance.
        """
    }

    var coachContext: String {
        let types = trainingTypes.map(\.title).sorted().joined(separator: ", ")
        let outcomeText = outcomes.map(\.title).sorted().joined(separator: ", ")
        let muscles = muscleGroups.sorted().joined(separator: ", ")
        let locationText = locations.map(\.title).sorted().joined(separator: ", ")
        let equipmentText = equipment.sorted().joined(separator: ", ")
        let locationBalance: String
        if locations.contains(.gym) && locations.contains(.outdoors),
           let outdoorSharePercent {
            locationBalance = "\(outdoorSharePercent)% outdoors / \(100 - outdoorSharePercent)% gym"
        } else {
            locationBalance = "Not applicable"
        }
        let injuryText: String

        if injuryStatus == .considerations, healthSharingAuthorized {
            injuryText = "Injury details and excluded movements are supplied in the separate, explicit-consent safety field. Follow them strictly."
        } else if injuryStatus == .considerations {
            injuryText = """
            The athlete has not authorized sharing the details of their limitations.
            No affected areas, symptoms or notes are shared. Recommend a generic
            conservative low-impact starting point, avoid high-intensity and
            heavy loading, and ask them to consult a qualified professional
            before attempting potentially aggravating exercise. Never infer
            undisclosed injuries or present the plan as individually safe.
            """
        } else {
            injuryText = "The athlete explicitly reported no injuries or training limitations."
        }

        return """
        Explicit standalone Coach intake:
        Training types: \(types).
        Desired outcomes: \(outcomeText).
        Strength muscle focus: \(muscles.isEmpty ? "Not applicable" : muscles).
        Experience: \(experience?.title ?? "Not specified").
        Plan duration: \(durationWeeks ?? 0) weeks.
        Requested sessions per week: \(sessionsPerWeek ?? 0).
        Available weekday indexes: \(availableDays.sorted()).
        Approximate session duration: \(sessionDurationMinutes ?? 0) minutes.
        Training locations: \(locationText).
        Gym/outdoor plan balance: \(locationBalance).
        Available equipment: \(equipmentText.isEmpty ? "No equipment selected" : equipmentText).
        Other equipment: \(otherEquipment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : String(otherEquipment.prefix(300))).
        Injury and limitation instructions:
        \(injuryText)
        Use only the training types, locations and equipment the athlete explicitly selected. The linked main goal is optional and must not be invented.
        """
    }
}


/// Defensive post-generation screen. AI instructions are not a guarantee;
/// reject clearly forbidden exercises before preview or persistence. A
/// heuristic does not replace clinical review or justify an "all safe" badge.
enum ATHLTHAIInjurySafetyValidator {
    private static let aliases: [[String]] = [
        ["knebøy", "squat", "squats"],
        ["utfall", "lunge", "lunges"],
        ["markløft", "deadlift", "deadlifts"],
        ["beinpress", "benpress", "leg press"],
        ["løping", "løp", "running", "run", "jogging"],
        ["gange", "gåtur", "gåing", "walking", "walk"],
        ["hopping", "hopp", "jump", "jumping", "jumps"],
        ["sykling", "sykkel", "cycling", "bike", "biking"],
        ["tåhev", "calf raise", "calf raises"],
        ["step up", "step-ups", "step ups"],
        ["burpee", "burpees"]
    ]

    private static func norm(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "nb_NO"))
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ text: String, forbidden: String) -> Bool {
        let normalized = " " + norm(text) + " "
        let blocked = norm(forbidden)
        guard blocked.count >= 2 else { return false }
        let names = aliases.first(where: { group in
            group.contains { norm($0) == blocked }
        }) ?? [blocked]
        return names.contains { alias in
            let phrase = norm(alias)
            guard !phrase.isEmpty else { return false }
            // Treat whole words/phrases, not a substring of an unrelated word.
            return normalized.contains(" " + phrase + " ") ||
                normalized.contains(" " + phrase + "s ") ||
                normalized.contains(" " + phrase + ",") ||
                normalized.contains(" " + phrase + ".")
        }
    }

    static func violations(
        in draft: AIProgramDraft,
        excludedMovements: [String],
        avoidLowerBody: Bool
    ) -> [String] {
        let noLowerBody = [
            "knebøy", "utfall", "markløft", "beinpress", "løping",
            "gåtur", "hopping", "sykling", "tåhev", "step up", "burpee"
        ]
        let blocked = excludedMovements + (avoidLowerBody ? noLowerBody : [])
        guard !blocked.isEmpty else { return [] }

        var rejected = Set<String>()
        for week in draft.weeks {
            for day in week.days {
                for session in day.sessions {
                    let kindWords: String
                    switch session.kind {
                    case "running": kindWords = "running"
                    case "walking": kindWords = "walking"
                    case "cycling": kindWords = "cycling"
                    default: kindWords = ""
                    }
                    let candidates: [String] =
                        [session.title, kindWords] +
                        session.exercises.map(\.name) +
                        (session.blocks ?? []).map(\.title)
                    for item in candidates {
                        if blocked.contains(where: { matches(item, forbidden: $0) }) {
                            rejected.insert(item)
                        }
                    }
                }
            }
        }
        return rejected.sorted()
    }
}
