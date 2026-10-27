import Foundation

/// Bundled, attributed import of Zoned's MIT-licensed training content.
/// All active sessions use the app's standard five HRmax zones.
/// The original six-zone content stays in the attributed source JSON snapshot.
/// Running pace examples from Zoned are NOT individualized pace prescriptions.
enum ATHLTHZonedPlanLibrary {
    struct Plan: Decodable, Sendable {
        let id: String
        let nameEn: String
        let descriptionEn: String
        let difficulty: String
        let sessionsPerWeek: Int
        let totalWeeks: Int
        let raceDistance: String?
        let tags: [String]
        let weeks: [Week]
    }

    struct Week: Decodable, Sendable {
        let weekNumber: Int
        let phase: String
        let isRecoveryWeek: Bool
        let volumePercent: Double?
        let targetKm: Double?
        let targetLongRunKm: Double?
        let weeklyLoadScore: Double?
        let sessions: [Session]
    }

    struct PaceNote: Decodable, Sendable {
        let zone: String
        let paceMinKm: Double?
        let paceMaxKm: Double?
        let descriptionEn: String?
    }

    struct Session: Decodable, Sendable {
        let dayOfWeek: Int
        let workoutId: String
        let sessionType: String
        let isKeySession: Bool
        let isSuggestion: Bool?
        let estimatedDurationMin: Int?
        let targetDurationMin: Int?
        let targetDistanceKm: Double?
        let loadScore: Double?
        let scaledRepetitions: Int?
        let notesEn: String?
        let paceNotes: [PaceNote]?
    }

    struct Step: Decodable, Sendable {
        let kind: String
        let descriptionEn: String?
        let durationSec: Double?
        let distanceM: Double?
        let distanceKm: Double?
        let zone: String?
        let vmaPercent: Double?
        let intensityType: String?
        let role: String?
        let elevationGainM: Double?
        let gradientPercent: Double?
        let terrainType: String?
        let count: Int?
        let steps: [Step]?
        let between: [Step]?
    }

    struct Duration: Decodable, Sendable {
        let min: Int
        let max: Int
    }

    struct Environment: Decodable, Sendable {
        let requiresHills: Bool?
        let requiresTrack: Bool?
        let prefersFlat: Bool?
        let prefersSoft: Bool?
    }

    struct Workout: Decodable, Sendable {
        let id: String
        let discipline: String?
        let nameEn: String
        let descriptionEn: String
        let category: String
        let sessionType: String
        let targetSystem: String?
        let difficulty: String
        let typicalDuration: Duration?
        let environment: Environment?
        let warmupStructure: [Step]?
        let mainSetStructure: [Step]?
        let cooldownStructure: [Step]?
        let coachingTipsEn: [String]?
        let commonMistakesEn: [String]?
    }

    private static func load<T: Decodable>(_ type: T.Type, files: [String]) -> [T] {
        let decoder = JSONDecoder()
        return files.flatMap { name -> [T] in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let result = try? decoder.decode([T].self, from: data) else {
                return []
            }
            return result
        }
    }

    static let plans: [Plan] = load(Plan.self, files: ["ZonedPlansA", "ZonedPlansB"])
    static let workouts: [Workout] = load(Workout.self, files: ["ZonedWorkoutsA", "ZonedWorkoutsB"])
    private static let workoutsByID: [String: Workout] =
        Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })

    static func plan(for catalogSlug: String) -> Plan? {
        guard catalogSlug.hasPrefix("zoned-") else { return nil }
        let sourceID = String(catalogSlug.dropFirst("zoned-".count))
        return plans.first { $0.id == sourceID }
    }

    static var catalogEntries: [TrainingPlanCatalogEntry] {
        plans.enumerated().map { index, source in
            let pattern = (source.weeks.first?.sessions ?? [])
                .filter { $0.isSuggestion != true }
                .sorted { weekday($0.dayOfWeek) < weekday($1.dayOfWeek) }
                .map { blueprint($0.sessionType) }
            let level: String
            switch source.difficulty {
            case "beginner": level = ATHLTHLocalization.choose(english: "Beginner", norwegian: "Nybegynner")
            case "advanced", "elite": level = ATHLTHLocalization.choose(english: "Advanced", norwegian: "Avansert")
            default: level = ATHLTHLocalization.choose(english: "Intermediate", norwegian: "Middels")
            }
            let title = ATHLTHZonedLocalization.planTitle(source.id, english: source.nameEn)
            let goal = source.raceDistance.map { "Run \($0)" } ??
                ATHLTHLocalization.choose(english: "Build running fitness", norwegian: "Bygg løpeform")
            return TrainingPlanCatalogEntry(
                id: UUID(uuidString: String(format: "B3000000-0000-0000-0000-%012d", index + 1))!,
                slug: "zoned-\(source.id)",
                title: title,
                summary: ATHLTHZonedLocalization.planSummary(source.id, english: source.descriptionEn),
                category: "running",
                goal: goal,
                level: level,
                durationWeeks: source.totalWeeks,
                sessionsPerWeek: source.sessionsPerWeek,
                workoutPattern: pattern,
                tags: source.tags + ["zoned", "source:Zoned", "six-zone-prescription", "running"],
                sortOrder: 65 + index,
                catalogVersion: 1
            )
        }
    }

    static var workoutCatalogEntries: [WorkoutTemplateCatalogEntry] {
        workouts.enumerated().compactMap { index, workout in
            guard workout.discipline != "swimming" else { return nil }
            let blocks = blocks(for: workout)
            guard !blocks.isEmpty else { return nil }
            let activity = workout.discipline ?? "running"
            return WorkoutTemplateCatalogEntry(
                id: UUID(uuidString: String(format: "B4000000-0000-0000-0000-%012d", index + 1))!,
                slug: "zoned-\(workout.id.lowercased())",
                title: ATHLTHZonedLocalization.text(workout.nameEn),
                summary: ATHLTHZonedLocalization.workoutSummary(workout.category, english: workout.descriptionEn),
                category: activity,
                difficulty: workout.difficulty,
                estimatedDurationMinutes: workout.typicalDuration.map { ($0.min + $0.max) / 2 },
                tags: ["zoned", workout.category, workout.sessionType, workout.targetSystem ?? ""].filter { !$0.isEmpty },
                sourceLabel: "Zoned · MIT",
                sourceURL: "https://github.com/alarboulletmarin/zoned",
                blocks: blocks,
                sortOrder: 500 + index
            )
        }
    }

    static func weekday(_ source: Int) -> Int {
        // Zoned uses JavaScript weekdays (Sunday=0). ATHLTH uses Monday=1..Sunday=7.
        source == 0 ? 7 : min(max(source, 1), 7)
    }

    static func orderedRequiredSessions(in week: Week) -> [Session] {
        week.sessions.filter { $0.isSuggestion != true }
            .sorted { weekday($0.dayOfWeek) < weekday($1.dayOfWeek) }
    }

    static func plannedSession(
        _ source: Session,
        week: Week,
        sourcePlan: Plan
    ) -> PlannedSession? {
        if source.workoutId == "__race_day__" {
            return raceDaySession(source, week: week, sourcePlan: sourcePlan)
        }
        guard let workout = workoutsByID[source.workoutId] else { return nil }
        var blocks = blocks(for: workout)
        guard !blocks.isEmpty else { return nil }
        // Plan-specific scaling wins over the generic catalogue interval count
        // only where the original session explicitly prescribes repetitions.
        // We retain the underlying interval structure rather than guessing a
        // replacement if the generic workout has nested sets.
        if let scaled = source.scaledRepetitions, scaled > 0 {
            let text = ATHLTHLocalization.choose(
                english: "Plan prescribes \(scaled) repetitions; review the interval set when personalizing.",
                norwegian: "Planen angir \(scaled) repetisjoner. Kontroller intervallene ved tilpasning."
            )
            if !blocks.isEmpty {
                blocks[0].notes = [blocks[0].notes, text].compactMap { $0 }.joined(separator: "\n")
            }
        }
        let isCycle = workout.discipline == "cycling"
        let kind: WorkoutKind = isCycle ? .custom : .running
        let plannedMinutes = source.targetDurationMin ?? source.estimatedDurationMin ??
            workout.typicalDuration.map { ($0.min + $0.max) / 2 } ?? 30

        let optionalStrength = week.sessions.filter { $0.isSuggestion == true }
            .map(\.workoutId).joined(separator: ", ")
        var detail: [String] = [
            ATHLTHZonedLocalization.workoutSummary(workout.category, english: workout.descriptionEn),
            ATHLTHLocalization.choose(
                english: "Zoned · \(sourcePlan.nameEn) · week \(week.weekNumber) (\(week.phase))",
                norwegian: "Zoned · \(ATHLTHZonedLocalization.planTitle(sourcePlan.id, english: sourcePlan.nameEn)) · uke \(week.weekNumber) (\(ATHLTHZonedLocalization.phase(week.phase)))"
            ),
            ATHLTHLocalization.choose(english: "Zoned session: \(source.workoutId)", norwegian: "Zoned-økt: \(source.workoutId)"),
        ]
        if week.isRecoveryWeek { detail.append(ATHLTHLocalization.choose(english: "Recovery week", norwegian: "Restitusjonsuke")) }
        if source.isKeySession { detail.append(ATHLTHLocalization.choose(english: "Key session", norwegian: "Nøkkeløkt")) }
        if let km = week.targetKm { detail.append(ATHLTHLocalization.choose(english: "Weekly running target: \(km) km", norwegian: "Ukemål løping: \(km) km")) }
        if let km = week.targetLongRunKm { detail.append(ATHLTHLocalization.choose(english: "Weekly long-run target: \(km) km", norwegian: "Ukemål langtur: \(km) km")) }
        if let load = week.weeklyLoadScore { detail.append(ATHLTHLocalization.choose(english: "Zoned weekly load score: \(load)", norwegian: "Zoned-belastning for uken: \(load)")) }
        if let load = source.loadScore { detail.append(ATHLTHLocalization.choose(english: "Zoned session load score: \(load)", norwegian: "Zoned-belastning for økten: \(load)")) }
        if let km = source.targetDistanceKm { detail.append(ATHLTHLocalization.choose(english: "Planned distance: \(km) km", norwegian: "Planlagt distanse: \(km) km")) }
        if let notes = source.notesEn, !notes.isEmpty {
            detail.append(ATHLTHLocalization.choose(english: "Source pace example (not personalized): \(notes)", norwegian: "Fartseksempel fra kilden (ikke personlig): \(ATHLTHZonedLocalization.text(notes))"))
        }
        if let examples = source.paceNotes, !examples.isEmpty {
            detail.append(ATHLTHLocalization.choose(english: "Zoned example pace zones: ", norwegian: "Zoned-eksempler på fartssoner: ") + examples.map {
                "\($0.zone): \($0.paceMinKm.map(String.init(describing:)) ?? "?")–\($0.paceMaxKm.map(String.init(describing:)) ?? "?") min/km"
            }.joined(separator: "; "))
        }
        if !optionalStrength.isEmpty {
            detail.append(ATHLTHLocalization.choose(english: "Optional strength recommendations, not automatically scheduled: \(optionalStrength)", norwegian: "Valgfrie styrkeøkter, ikke lagt til automatisk: \(optionalStrength)"))
        }
        if let tips = workout.coachingTipsEn, !tips.isEmpty {
            detail.append(ATHLTHLocalization.isNorwegian ? "Tips: Følg planlagt intensitet og tilpass treningen til dagsformen." : "Coach tips: " + tips.prefix(3).joined(separator: " · "))
        }
        if let mistakes = workout.commonMistakesEn, !mistakes.isEmpty {
            detail.append(ATHLTHLocalization.isNorwegian ? "Unngå: Å øke intensiteten utover det økten foreskriver." : "Avoid: " + mistakes.prefix(2).joined(separator: " · "))
        }
        if workout.environment?.requiresHills == true { detail.append(ATHLTHLocalization.choose(english: "Requires hills", norwegian: "Krever bakker")) }
        if workout.environment?.requiresTrack == true { detail.append(ATHLTHLocalization.choose(english: "Requires track", norwegian: "Krever løpebane")) }
        detail.append("Source: Zoned (MIT), github.com/alarboulletmarin/zoned")
        if sourcePlan.id == "retour-blessure" {
            detail.append(ATHLTHLocalization.choose(english: "General fitness content only; not medical rehabilitation advice.", norwegian: "Generell trening, ikke medisinsk rehabilitering."))
        }
        var session = PlannedSession(
            id: UUID(),
            title: ATHLTHZonedLocalization.text(workout.nameEn),
            kind: kind,
            scheduledStart: nil,
            durationMinutes: max(5, plannedMinutes),
            targetDistanceKilometers: source.targetDistanceKm,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: detail.joined(separator: "\n")
        )
        session.workoutBlocks = blocks
        session.workoutCategory = isCycle ? "cycling" : "running"
        return session
    }

    /// Zoned marks race days by a sentinel rather than a normal workout ID.
    /// Preserve those days as executable events without inventing pace or HR.
    private static func raceDaySession(
        _ source: Session, week: Week, sourcePlan: Plan
    ) -> PlannedSession {
        let distance: Double?
        switch sourcePlan.raceDistance?.uppercased() {
        case "5K": distance = 5
        case "10K": distance = 10
        case "HALF", "HALF_MARATHON", "SEMI": distance = 21.0975
        case "MARATHON": distance = 42.195
        default: distance = source.targetDistanceKm
        }
        let notes = [
            ATHLTHLocalization.choose(english: "Zoned race day", norwegian: "Zoned konkurransedag") + " · \(ATHLTHZonedLocalization.planTitle(sourcePlan.id, english: sourcePlan.nameEn))",
            ATHLTHLocalization.choose(english: "Week \(week.weekNumber)", norwegian: "Uke \(week.weekNumber)") + " · \(ATHLTHZonedLocalization.phase(week.phase))",
            ATHLTHZonedLocalization.text(source.notesEn ?? "Personalize competition preparation."),
            ATHLTHLocalization.choose(english: "Choose safe, individual pace and heart-rate goals.", norwegian: "Velg trygge, individuelt tilpassede farts- og pulsmål."),
            "Source: Zoned (MIT), github.com/alarboulletmarin/zoned"
        ].joined(separator: "\n")
        var event = PlannedSession(
            id: UUID(), title: ATHLTHLocalization.choose(english: "Race day", norwegian: "Konkurransedag"),
            kind: .running, scheduledStart: nil,
            durationMinutes: source.targetDurationMin ?? source.estimatedDurationMin,
            targetDistanceKilometers: distance,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: notes
        )
        event.workoutCategory = "running"
        event.workoutBlocks = [WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: ATHLTHLocalization.choose(english: "Race", norwegian: "Konkurranse"),
            exerciseSlug: nil,
            distanceMeters: distance.map { $0 * 1_000 },
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil,
            notes: ATHLTHLocalization.choose(english: "Choose an individual effort target.", norwegian: "Velg et individuelt intensitetsmål."),
            phase: .main, cardioActivity: .running
        )]
        return event
    }

    static func blocks(for workout: Workout) -> [WorkoutTemplateBlock] {
        var result: [WorkoutTemplateBlock] = []
        let isCycling = workout.discipline == "cycling"
        let isSwimming = workout.discipline == "swimming"
        append(workout.warmupStructure ?? [], phase: .warmup, sport: workout.discipline, depth: 0, to: &result)
        append(workout.mainSetStructure ?? [], phase: .main, sport: workout.discipline, depth: 0, to: &result)
        append(workout.cooldownStructure ?? [], phase: .cooldown, sport: workout.discipline, depth: 0, to: &result)
        // A timed cycling segment uses a non-running block in ATHLTH.
        // Swimming stays in the source bundle but is not published as a workout
        // until a swimming engine is available.
        if isSwimming { return [] }
        if isCycling { return result.filter { $0.activityTag == "cycling" || $0.kind == .rest } }
        return result
    }

    private static func append(
        _ steps: [Step],
        phase: WorkoutPhaseKind,
        sport: String?,
        depth: Int,
        to result: inout [WorkoutTemplateBlock]
    ) {
        guard depth < 9 else { return }
        for step in steps where result.count < 900 {
            if step.kind == "repeat" {
                let repeats = min(max(step.count ?? 1, 1), 50)
                for index in 0..<repeats where result.count < 900 {
                    append(step.steps ?? [], phase: phase, sport: sport, depth: depth + 1, to: &result)
                    if index < repeats - 1 {
                        append(step.between ?? [], phase: .recovery, sport: sport, depth: depth + 1, to: &result)
                    }
                }
                continue
            }
            guard step.kind == "segment" else { continue }
            let recovery = step.role == "recovery"
            let blockPhase: WorkoutPhaseKind = recovery ? .recovery : phase
            let isCycling = sport == "cycling"
            let description = (step.descriptionEn ?? "").lowercased()
            let isActiveRecovery = ["jog", "run", "spin", "ride", "pedal", "walk", "cycle"]
                .contains { description.contains($0) }
            let passiveRest = blockPhase == .recovery && !isActiveRecovery
            let notes: [String] = [
                step.vmaPercent.map { ATHLTHLocalization.choose(english: "VMA target: \($0) %", norwegian: "VMA-mål: \($0) %") },
                step.intensityType.map { ATHLTHLocalization.choose(english: "Pace intensity: \($0)", norwegian: "Fartsintensitet: \($0)") },
                step.elevationGainM.map { ATHLTHLocalization.choose(english: "Elevation gain: \($0) m", norwegian: "Høydemeter: \($0) m") },
                step.gradientPercent.map { ATHLTHLocalization.choose(english: "Gradient: \($0) %", norwegian: "Stigning: \($0) %") },
                step.terrainType.map { ATHLTHLocalization.choose(english: "Terrain: \($0)", norwegian: "Terreng: \(ATHLTHZonedLocalization.text($0))") }
            ].compactMap { $0 }
            let zone = step.zone.flatMap(zonePrescription)
            var block = WorkoutTemplateBlock(
                sequence: result.count + 1,
                kind: passiveRest ? .rest : (isCycling ? .note : .run),
                title: ATHLTHZonedLocalization.text(step.descriptionEn ?? (recovery ? "Recovery" : "Effort")),
                exerciseSlug: nil,
                distanceMeters: step.distanceM ?? step.distanceKm.map { $0 * 1_000 },
                repetitions: nil,
                durationSeconds: step.durationSec,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: notes.isEmpty ? nil : notes.joined(separator: " · "),
                phase: blockPhase,
                targetHeartRateZone: zone?.athlthZone,
                cardioActivity: isCycling ? nil : .running
            )
            block.activityTag = isCycling ? "cycling" : nil
            block.sourceIntensityZoneLabel = zone?.label
            block.targetHeartRatePercentMin = zone?.minimum
            block.targetHeartRatePercentMax = zone?.maximum
            result.append(block)
        }
    }

    struct ZonePrescription: Equatable, Sendable {
        let minimum: Double
        let maximum: Double
        let athlthZone: Int?
        let label: String
    }

    /// One coherent five-zone ATHLTH scheme for every imported session:
    /// Z1 50-60, Z2 60-70, Z3 70-80, Z4 80-90, Z5 90-100% HRmax.
    /// Zoned's source Z5 (90-95) and Z6 (95-100) both map to Z5.
    /// A range like Z4-Z6 becomes Z4-Z5 rather than a fabricated Z6.
    static func zonePrescription(_ source: String) -> ZonePrescription? {
        let values = source.uppercased()
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard !values.isEmpty, values.allSatisfy({ (1...6).contains($0) }),
              let low = values.min(), let high = values.max() else { return nil }
        let first = min(low, 5)
        let last = source.contains("+") ? 5 : min(high, 5)
        let bounds: [Double] = [50, 60, 70, 80, 90, 100]
        return ZonePrescription(
            minimum: bounds[first - 1],
            maximum: bounds[last],
            athlthZone: first == last ? first : nil,
            label: first == last ? "Z\(first)" : "Z\(first)-Z\(last)"
        )
    }

    private static func blueprint(_ type: String) -> String {
        switch type {
        case "endurance", "recovery": return "easy_run"
        case "long_run": return "long_run"
        case "tempo", "threshold", "race_specific": return "tempo_run"
        case "hills": return "hill_run"
        default: return "interval_run"
        }
    }
}
