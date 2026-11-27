import Foundation

/// One competition uses one scoring discipline regardless of whether the
/// competition is a duel, single event, league or knockout cup.
enum ATHLTHCompetitionDiscipline: String, Codable, CaseIterable, Identifiable {
    case sprint, workout, distance, duration, laps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sprint: return "Sprint"
        case .workout: return "Treningsøkt"
        case .distance: return "Distanse"
        case .duration: return "Tid"
        case .laps: return "Runder"
        }
    }
}

enum ATHLTHCompetitionSprintMode: String, Codable, CaseIterable, Identifiable {
    case massStart = "mass_start", relay, staggered
    var id: String { rawValue }
    var title: String {
        switch self {
        case .massStart: return "Fellesstart"
        case .relay: return "Lagsprint"
        case .staggered: return "Hver sin tur"
        }
    }
}

enum ATHLTHCompetitionSprintTarget: String, Codable, CaseIterable, Identifiable {
    case distance, duration, route
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: return "Distanse"
        case .duration: return "Tid"
        case .route: return "Rute"
        }
    }
}

/// Requirement is a rule, not a user-editable assertion of device provenance.
/// Recording origin must be checked against source-workout metadata on server.
enum ATHLTHCompetitionRecordingDevice: String, Codable, CaseIterable, Identifiable {
    case any, appleWatch = "apple_watch", iphone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: return "Alle godkjente registreringsenheter"
        case .appleWatch: return "Apple Watch er påkrevd"
        case .iphone: return "iPhone med ATHLTH"
        }
    }
}

enum ATHLTHCompetitionLapVerification: String, Codable, CaseIterable, Identifiable {
    case gps, supervised
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gps: return "Felles målpunkt · GPS-passering"
        case .supervised: return "Passering bekreftes av arrangør"
        }
    }
}

enum ATHLTHCompetitionScoringMode: String, Codable, CaseIterable, Identifiable {
    case ranking, winner, target, closest, completion
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ranking: "Poeng etter plassering"
        case .winner: "Poeng til vinneren"
        case .target: "Poeng for å nå målet"
        case .closest: "Nærmest målet"
        case .completion: "Poeng for gjennomføring"
        }
    }
    var detail: String {
        switch self {
        case .ranking: "Plasseringen avgjør poengene per øvelse."
        case .winner: "Beste måling får poeng. Ved likt resultat deler vinnerne poengene likt i betydningen samme poengsum."
        case .target: "Alle som når det avtalte målet får poeng."
        case .closest: "Målingen nærmest det avtalte målet får poeng."
        case .completion: "Alle godkjente gjennomføringer får poeng."
        }
    }
    var needsGoal: Bool { self == .target || self == .closest }
}

/// Shared definition of a configurable competition measurement. These are draft
/// entries until the result backend supports the same rules and evidence.
enum ATHLTHCompetitionMeasure: String, Codable, CaseIterable, Identifiable {
    case heaviest, heaviestForReps, mostReps, repsAtWeight, repsInTime, volume
    case relativeStrength, holdTime, fastestReps
    case fastestDistance, distanceInTime, continuousDistance, paceEndurance, speedEndurance
    case intervalDistance, mostLaps, elevationGain, closestPace, sprint
    case routeTime, routeSpeed, routeRepeats, routeClosestTime

    var id: String { rawValue }
    static var strength: [Self] {
        [.heaviest, .heaviestForReps, .mostReps, .repsAtWeight, .repsInTime, .volume,
         .relativeStrength, .holdTime, .fastestReps]
    }
    static var cardio: [Self] {
        [.fastestDistance, .distanceInTime, .continuousDistance, .paceEndurance,
         .speedEndurance, .intervalDistance, .mostLaps, .elevationGain, .closestPace, .sprint]
    }
    static var route: [Self] { [.routeTime, .routeSpeed, .routeRepeats, .routeClosestTime] }

    var title: String {
        switch self {
        case .heaviest: "Høyeste vekt (1 rep)"
        case .heaviestForReps: "Høyeste vekt ved X reps"
        case .mostReps: "Flest sammenhengende reps"
        case .repsAtWeight: "Flest reps ved bestemt vekt"
        case .repsInTime: "Flest reps innen en tid"
        case .volume: "Høyest treningsvolum"
        case .relativeStrength: "Relativ styrke"
        case .holdTime: "Lengst holdetid"
        case .fastestReps: "Raskeste gjennomføring av X reps"
        case .fastestDistance: "Raskeste distanse"
        case .distanceInTime: "Lengst distanse innen en tid"
        case .continuousDistance: "Lengst sammenhengende distanse"
        case .paceEndurance: "Hold bestemt pace lengst mulig"
        case .speedEndurance: "Hold bestemt hastighet lengst mulig"
        case .intervalDistance: "Lengst samlet intervalldistanse"
        case .mostLaps: "Flest runder innen en tid"
        case .elevationGain: "Flest høydemeter innen en tid"
        case .closestPace: "Nærmest avtalt pace"
        case .sprint: "Raskeste sprint"
        case .routeTime: "Raskeste tid"
        case .routeSpeed: "Beste gjennomsnittsfart"
        case .routeRepeats: "Flest gjennomføringer"
        case .routeClosestTime: "Nærmest avtalt sluttid"
        }
    }
    /// Closest-target measures return absolute deviation, not the raw pace/time.
    var lowerIsBetter: Bool {
        [.fastestDistance, .fastestReps, .sprint, .routeTime, .closestPace, .routeClosestTime].contains(self)
    }
    var needsReps: Bool { [.heaviestForReps, .fastestReps].contains(self) }
    var needsWeight: Bool { self == .repsAtWeight }
    var needsDistance: Bool { [.fastestDistance, .closestPace, .sprint].contains(self) }
    var needsDuration: Bool { [.repsInTime, .distanceInTime, .mostLaps, .elevationGain, .routeRepeats, .routeClosestTime].contains(self) }
    var needsPace: Bool { [.paceEndurance, .closestPace].contains(self) }
    var needsSpeed: Bool { self == .speedEndurance }
}

/// The identifier belongs to the competition entry, not a fictitious catalog
/// exercise. Several entries can reference the same real library exercise.
struct ATHLTHCompetitionMeasureDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    var activity: ATHLTHTournamentActivity
    var measure: ATHLTHCompetitionMeasure
    var libraryID: UUID? = nil
    var libraryName: String? = nil
    var routeID: UUID? = nil
    var routeName: String? = nil
    var repetitions = 10
    var kilograms = 60.0
    var distanceMeters = 5_000
    var durationSeconds = 1_800
    var paceSecondsPerKM = 300
    var speedKMH = 12.0
    var intervals = 4
    var workSeconds = 240
    var restSeconds = 180
    var paceToleranceSeconds = 10
    var speedToleranceKMH = 0.5
    var attempts = 1
    var pointsWeight = 1

    var isValid: Bool {
        guard activity.isAvailableForCreation, (1...10).contains(attempts),
              (1...5).contains(pointsWeight),
              (1...1_000).contains(repetitions),
              kilograms.isFinite, (0.1...1_000).contains(kilograms),
              (50...500_000).contains(distanceMeters),
              (1...86_400).contains(durationSeconds),
              (60...3_600).contains(paceSecondsPerKM),
              speedKMH.isFinite, (0.5...60).contains(speedKMH),
              (1...100).contains(intervals), (1...3_600).contains(workSeconds),
              (0...3_600).contains(restSeconds),
              (1...120).contains(paceToleranceSeconds),
              speedToleranceKMH.isFinite, (0.1...5).contains(speedToleranceKMH)
        else { return false }
        if ATHLTHCompetitionMeasure.strength.contains(measure) {
            return activity == .strength && libraryID != nil && routeID == nil &&
                !(libraryName ?? "").isEmpty && (libraryName ?? "").count <= 240
        }
        if ATHLTHCompetitionMeasure.route.contains(measure) {
            return (activity == .running || activity == .walking) && routeID != nil && libraryID == nil &&
                !(routeName ?? "").isEmpty && (routeName ?? "").count <= 120
        }
        return (activity == .running || activity == .walking) && libraryID == nil && routeID == nil &&
            ATHLTHCompetitionMeasure.cardio.contains(measure) &&
            (activity == .running || measure != .sprint)
    }
}

/// Pure strength measurement primitives. The caller must supply completed,
/// consecutive sets from the exact library exercise; no planned values or
/// incomplete attempts may be substituted for recorded measurements.
/// This does not establish server verification or submit a competition score.
enum ATHLTHCompetitionMeasureCalculator {
    struct CompletedSet: Equatable {
        let repetitions: Int
        let kilograms: Double?
        let holdSeconds: Double?

        var isValid: Bool {
            (0...100_000).contains(repetitions) &&
                (kilograms.map { $0.isFinite && (0...1_000).contains($0) } ?? true) &&
                (holdSeconds.map { $0.isFinite && (0...86_400).contains($0) } ?? true)
        }
    }

    static func strength(_ rule: ATHLTHCompetitionMeasureDraft, libraryID: UUID,
                         sets: [CompletedSet], bodyMassKG: Double? = nil) -> Double? {
        guard rule.isValid, rule.libraryID == libraryID, !sets.isEmpty,
              sets.allSatisfy(\.isValid) else { return nil }
        let performed = sets.filter { $0.repetitions > 0 }
        let result: Double?
        switch rule.measure {
        case .heaviest, .heaviestForReps:
            let required = rule.measure == .heaviest ? 1 : rule.repetitions
            result = performed.filter { $0.repetitions >= required }.compactMap(\.kilograms).max()
        case .mostReps:
            result = performed.map { Double($0.repetitions) }.max()
        case .repsAtWeight:
            result = performed.filter { set in
                guard let weight = set.kilograms else { return false }
                return abs(weight - rule.kilograms) <= 0.000_001
            }.map { Double($0.repetitions) }.max()
        case .volume:
            guard !performed.isEmpty, performed.allSatisfy({ $0.kilograms != nil }) else { return nil }
            result = performed.reduce(0) { $0 + Double($1.repetitions) * ($1.kilograms ?? 0) }
        case .relativeStrength:
            guard let mass = bodyMassKG, mass.isFinite, (20...500).contains(mass),
                  let weight = performed.compactMap(\.kilograms).max() else { return nil }
            result = weight / mass
        case .holdTime:
            result = sets.compactMap(\.holdSeconds).max()
        default:
            // Timed rep challenges require timestamped evidence, not aggregate sets.
            return nil
        }
        guard let result, result.isFinite, result > 0 else { return nil }
        return result
    }

    /// Chooses from independently valid measured attempts only. Missing
    /// measurements are not treated as zero or as an automatic win.
    static func bestAttempt(_ rule: ATHLTHCompetitionMeasureDraft, values: [Double]) -> Double? {
        guard rule.isValid, !values.isEmpty, values.count <= rule.attempts,
              values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return rule.measure.lowerIsBetter ? values.min() : values.max()
    }
}

struct ATHLTHCompetitionRaceRules: Codable, Hashable {
    /// Local/template-only until server-side measurement validation is available.
    var measureDrafts: [ATHLTHCompetitionMeasureDraft]? = nil
    var plannedMeasures: [ATHLTHCompetitionMeasureDraft] { measureDrafts ?? [] }

    var scoringMode: ATHLTHCompetitionScoringMode? = nil
    var pointsPerExercise: Int? = nil
    var reviewHours: Int? = nil
    var scoringGoals: [String: Double]? = nil
    var exerciseWeights: [String: Int]? = nil
    var handicapPercentages: [String: Int]? = nil
    var effectiveScoringMode: ATHLTHCompetitionScoringMode { scoringMode ?? .ranking }
    var scoringSummary: String {
        effectiveScoringMode.title + " · " + String(pointsPerExercise ?? 1) + " grunnpoeng"
    }
    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
    func handicap(for id: UUID) -> Int { handicapPercentages?[Self.key(id)] ?? 0 }
    func goal(for id: UUID) -> Double? { scoringGoals?[Self.key(id)] }
    func weight(for id: UUID) -> Int { exerciseWeights?[Self.key(id)] ?? 1 }
    /// Illustrative points only. The server remains authoritative for real results.
    /// "distance" means elapsed seconds over a fixed distance; "duration"
    /// means meters in a fixed time, and "time" means hold duration in seconds.
    static func previewPoints(mode: ATHLTHCompetitionScoringMode, metric: String,
                              values: [Double], handicaps: [Int],
                              basePoints: Int, weight: Int, goal: Double?) -> [Int]? {
        guard ["distance", "duration", "time", "repetitions"].contains(metric),
              !values.isEmpty, values.count == handicaps.count, values.count <= 21,
              values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100_000_000 }),
              handicaps.allSatisfy({ (0...30).contains($0) }),
              (1...10).contains(basePoints), (1...5).contains(weight) else { return nil }
        if mode.needsGoal {
            guard let goal, goal.isFinite, goal > 0, goal <= 100_000_000 else { return nil }
        }
        let lowerIsBetter = metric == "distance"
        let adjusted = zip(values, handicaps).map { value, handicap in
            let factor = 1 + (lowerIsBetter ? -1.0 : 1.0) * Double(handicap) / 100
            return (value * factor * 1_000_000).rounded() / 1_000_000
        }
        let order = adjusted.map { value -> Double in
            if mode == .closest, let goal { return abs(value - goal) }
            return lowerIsBetter ? value : -value
        }
        return adjusted.indices.map { i in
            let rank = 1 + order.filter { $0 < order[i] }.count
            let multiplier: Int
            switch mode {
            case .ranking: multiplier = max(0, values.count - rank + 1)
            case .winner, .closest: multiplier = rank == 1 ? 1 : 0
            case .target:
                multiplier = goal.map { lowerIsBetter ? adjusted[i] <= $0 : adjusted[i] >= $0 } == true ? 1 : 0
            case .completion: multiplier = 1
            }
            return multiplier * basePoints * weight
        }
    }

    var discipline: ATHLTHCompetitionDiscipline = .workout
    // Absent in legacy events: only new exercise-scored events opt in.
    var exerciseScoringVersion: Int? = nil
    var duelMode: Bool? = nil
    var previousCompetitionID: UUID? = nil
    var seasonNumber: Int? = nil
    var competitionEndsAt: String? = nil
    var endDate: Date? { competitionEndsAt.flatMap { ISO8601DateFormatter().date(from: $0) } }
    var sprintMode: ATHLTHCompetitionSprintMode = .massStart
    var sprintTarget: ATHLTHCompetitionSprintTarget = .distance
    var routeID: UUID? = nil
    var routeName: String = ""
    var recordingDevice: ATHLTHCompetitionRecordingDevice = .any
    var targetDistanceMeters: Int = 100
    var targetDurationSeconds: Int = 60
    var lapCount: Int = 3
    /// A lap can be used without knowing its length. All athletes must run
    /// the same course. It does not imply a measured distance.
    var lapVerification: ATHLTHCompetitionLapVerification = .supervised
    var lapCourseName: String = ""
    var lapCourseLatitude: Double? = nil
    var lapCourseLongitude: Double? = nil
    var countdownSeconds: Int = 10
    var allowOptInLiveLocation: Bool = false
    /// Explicitly listed permitted equipment, e.g. shoes or gym apparatus.
    /// This does not substitute for device-source verification.
    var equipmentRules: String = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case discipline, sprintMode, sprintTarget, routeID, routeName,
             recordingDevice, targetDistanceMeters, targetDurationSeconds,
             lapCount, lapVerification, lapCourseName, lapCourseLatitude,
             lapCourseLongitude, countdownSeconds, allowOptInLiveLocation,
             equipmentRules, exerciseScoringVersion, duelMode, competitionEndsAt, previousCompetitionID, seasonNumber,
             scoringMode, pointsPerExercise, reviewHours, scoringGoals, exerciseWeights, handicapPercentages, measureDrafts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        measureDrafts = try c.decodeIfPresent([ATHLTHCompetitionMeasureDraft].self, forKey: .measureDrafts)
        scoringMode = try c.decodeIfPresent(ATHLTHCompetitionScoringMode.self, forKey: .scoringMode)
        pointsPerExercise = try c.decodeIfPresent(Int.self, forKey: .pointsPerExercise)
        reviewHours = try c.decodeIfPresent(Int.self, forKey: .reviewHours)
        scoringGoals = try c.decodeIfPresent([String: Double].self, forKey: .scoringGoals)
        exerciseWeights = try c.decodeIfPresent([String: Int].self, forKey: .exerciseWeights)
        handicapPercentages = try c.decodeIfPresent([String: Int].self, forKey: .handicapPercentages)
        exerciseScoringVersion = try c.decodeIfPresent(Int.self, forKey: .exerciseScoringVersion)
        duelMode = try c.decodeIfPresent(Bool.self, forKey: .duelMode)
        previousCompetitionID = try c.decodeIfPresent(UUID.self, forKey: .previousCompetitionID)
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        competitionEndsAt = try c.decodeIfPresent(String.self, forKey: .competitionEndsAt)
        discipline = try c.decodeIfPresent(ATHLTHCompetitionDiscipline.self,
                         forKey: .discipline) ?? .workout
        sprintMode = try c.decodeIfPresent(ATHLTHCompetitionSprintMode.self,
                         forKey: .sprintMode) ?? .massStart
        sprintTarget = try c.decodeIfPresent(ATHLTHCompetitionSprintTarget.self,
                         forKey: .sprintTarget) ?? .distance
        routeID = try c.decodeIfPresent(UUID.self, forKey: .routeID)
        routeName = try c.decodeIfPresent(String.self, forKey: .routeName) ?? ""
        recordingDevice = try c.decodeIfPresent(
            ATHLTHCompetitionRecordingDevice.self,
            forKey: .recordingDevice) ?? .any
        targetDistanceMeters = try c.decodeIfPresent(Int.self,
                                 forKey: .targetDistanceMeters) ?? 100
        targetDurationSeconds = try c.decodeIfPresent(Int.self,
                                 forKey: .targetDurationSeconds) ?? 60
        lapCount = try c.decodeIfPresent(Int.self, forKey: .lapCount) ?? 3
        lapVerification = try c.decodeIfPresent(
            ATHLTHCompetitionLapVerification.self,
            forKey: .lapVerification) ?? .supervised
        lapCourseName = try c.decodeIfPresent(String.self,
                         forKey: .lapCourseName) ?? ""
        lapCourseLatitude = try c.decodeIfPresent(Double.self,
                              forKey: .lapCourseLatitude)
        lapCourseLongitude = try c.decodeIfPresent(Double.self,
                              forKey: .lapCourseLongitude)
        countdownSeconds = try c.decodeIfPresent(Int.self,
                             forKey: .countdownSeconds) ?? 10
        allowOptInLiveLocation = try c.decodeIfPresent(Bool.self,
                                 forKey: .allowOptInLiveLocation) ?? false
        equipmentRules = try c.decodeIfPresent(String.self,
                         forKey: .equipmentRules) ?? ""
    }

    /// Unsupported capture origins and synchronized formats can be saved
    /// as private drafts, but must never be published as working competitions.
    var isOperational: Bool {
        if !plannedMeasures.isEmpty { return false }
        if recordingDevice != .any { return false }
        if discipline == .sprint {
            return sprintMode == .massStart && sprintTarget != .route
        }
        if discipline == .laps && lapVerification == .gps { return false }
        return true
    }

    var isValid: Bool {
        guard plannedMeasures.count <= 12,
              Set(plannedMeasures.map(\.id)).count == plannedMeasures.count,
              plannedMeasures.allSatisfy(\.isValid),
              (12...168).contains(reviewHours ?? 48),
              (1...10).contains(pointsPerExercise ?? 1),
              (scoringGoals ?? [:]).values.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000_000 }),
              (exerciseWeights ?? [:]).values.allSatisfy({ (1...5).contains($0) }),
              (handicapPercentages ?? [:]).values.allSatisfy({ (0...30).contains($0) }),
              (100...100_000).contains(targetDistanceMeters),
              (10...86_400).contains(targetDurationSeconds),
              (1...500).contains(lapCount),
              (5...30).contains(countdownSeconds),
              lapCourseName.count <= 120,
              routeName.count <= 120,
              equipmentRules.count <= 350,
              (lapCourseLatitude == nil && lapCourseLongitude == nil) ||
              (lapCourseLatitude.map { (-90...90).contains($0) } == true &&
               lapCourseLongitude.map { (-180...180).contains($0) } == true)
        else { return false }
        if discipline == .sprint && sprintTarget == .route && routeID == nil {
            return false
        }
        return discipline != .laps ||
            !lapCourseName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
