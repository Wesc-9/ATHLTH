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

    var trainingTypes: Set<TrainingFocus> = []
    var outcomes: Set<Outcome> = []
    var muscleGroups: Set<String> = []
    var experience: Experience?
    var durationWeeks: Int?
    var sessionsPerWeek: Int?
    var availableDays: Set<Int> = []
    var sessionDurationMinutes: Int?
    var locations: Set<Location> = []
    var equipment: Set<String> = []
    var otherEquipment = ""
    var injuryStatus: InjuryStatus?
    var injuryAreas: Set<String> = []
    var injurySeverity: InjurySeverity?
    var injuryRestriction: InjuryRestriction?
    var injuryNotes = ""
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
        if durationWeeks == nil { issues.append("durationWeeks") }
        if sessionsPerWeek == nil { issues.append("sessionsPerWeek") }
        if availableDays.isEmpty { issues.append("availableDays") }
        if let sessionsPerWeek, availableDays.count < sessionsPerWeek {
            issues.append("availableDayCount")
        }
        if sessionDurationMinutes == nil { issues.append("sessionDurationMinutes") }
        if locations.isEmpty { issues.append("locations") }
        if injuryStatus == nil { issues.append("injuryStatus") }
        if injuryStatus == .considerations {
            if injuryAreas.isEmpty { issues.append("injuryAreas") }
            if injurySeverity == nil { issues.append("injurySeverity") }
            if injuryRestriction == nil { issues.append("injuryRestriction") }
            if !healthSharingAuthorized { issues.append("healthSharingAuthorized") }
        }
        return issues
    }

    var isComplete: Bool {
        validationIssues.isEmpty
    }

    var coachContext: String {
        let types = trainingTypes.map(\.title).sorted().joined(separator: ", ")
        let outcomeText = outcomes.map(\.title).sorted().joined(separator: ", ")
        let muscles = muscleGroups.sorted().joined(separator: ", ")
        let locationText = locations.map(\.title).sorted().joined(separator: ", ")
        let equipmentText = equipment.sorted().joined(separator: ", ")
        let injuryText: String

        if injuryStatus == .considerations, healthSharingAuthorized {
            injuryText = """
            Affected areas: \(injuryAreas.sorted().joined(separator: ", ")).
            Severity: \(injurySeverity?.title ?? "Not specified").
            Required restriction: \(injuryRestriction?.title ?? "Not specified").
            Athlete notes: \(String(injuryNotes.prefix(500))).
            This restriction is mandatory. Never prescribe movement that loads an area the athlete said must not be loaded. If lower-body training is excluded, do not prescribe running, jumping, squats, lunges or other lower-body loading. For severe or very painful symptoms, keep the plan conservative and tell the athlete to seek qualified medical guidance before resuming affected movements.
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
        Available equipment: \(equipmentText.isEmpty ? "No equipment selected" : equipmentText).
        Other equipment: \(otherEquipment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : String(otherEquipment.prefix(300))).
        Injury and limitation instructions:
        \(injuryText)
        Use only the training types, locations and equipment the athlete explicitly selected. The linked main goal is optional and must not be invented.
        """
    }
}
