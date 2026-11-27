import Foundation

/// Private chat intake. The fields are explicit athlete choices and never
/// uploaded to a language-model service by this flow.
struct ATHLTHCoachChatPlanIntake: Codable, Hashable {
    enum Goal: String, CaseIterable, Codable {
        case strength, legs, running, walking, hybrid
        var title: String {
            switch self {
            case .strength: return ATHLTHLocalization.choose(english: "General strength", norwegian: "Generell styrke")
            case .legs: return ATHLTHLocalization.choose(english: "Leg strength", norwegian: "Styrke i lår og bein")
            case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
            case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
            case .hybrid: return ATHLTHLocalization.choose(english: "Running and strength", norwegian: "Løping og styrke")
            }
        }
    }
    enum Place: String, CaseIterable, Codable {
        case gym, outdoors, home, seasonal
        var title: String {
            switch self {
            case .gym: return ATHLTHLocalization.choose(english: "Gym", norwegian: "Treningssenter")
            case .outdoors: return ATHLTHLocalization.choose(english: "Outdoors", norwegian: "Utendørs")
            case .home: return ATHLTHLocalization.choose(english: "Home (no equipment)", norwegian: "Hjemme (uten utstyr)")
            case .seasonal: return ATHLTHLocalization.choose(english: "Summer outdoors / winter gym", norwegian: "Sommer ute / vinter på senter")
            }
        }
    }
    enum Experience: String, CaseIterable, Codable {
        case beginner, regular
        var title: String { self == .beginner
            ? ATHLTHLocalization.choose(english: "Beginner / returning", norwegian: "Nybegynner / tilbake etter pause")
            : ATHLTHLocalization.choose(english: "Regular training", norwegian: "Trener regelmessig") }
    }
    enum MuscleFocus: String, CaseIterable, Codable, Hashable {
        case chest, back, shoulders, arms, legs, glutes, core
        var title: String {
            switch self {
            case .chest: return ATHLTHLocalization.choose(english: "Chest", norwegian: "Bryst")
            case .back: return ATHLTHLocalization.choose(english: "Back", norwegian: "Rygg")
            case .shoulders: return ATHLTHLocalization.choose(english: "Shoulders", norwegian: "Skuldre")
            case .arms: return ATHLTHLocalization.choose(english: "Arms", norwegian: "Armer")
            case .legs: return ATHLTHLocalization.choose(english: "Legs", norwegian: "Bein")
            case .glutes: return ATHLTHLocalization.choose(english: "Glutes", norwegian: "Sete")
            case .core: return ATHLTHLocalization.choose(english: "Core", norwegian: "Kjerne")
            }
        }

        private var aliases: Set<String> {
            switch self {
            case .chest: return ["chest", "pectorals", "pecs"]
            case .back: return ["back", "lats", "upper back", "lower back", "traps", "latissimus dorsi", "rhomboids"]
            case .shoulders: return ["shoulders", "deltoids", "front delts", "rear delts", "side delts"]
            case .arms: return ["arms", "biceps", "triceps", "forearms", "upper arms", "lower arms"]
            case .legs: return ["legs", "quadriceps", "quads", "hamstrings", "calves", "adductors", "abductors", "upper legs", "lower legs"]
            case .glutes: return ["glutes", "gluteus", "gluteus maximus", "gluteus medius", "gluteus minimus"]
            case .core: return ["core", "abs", "abdominals", "obliques", "waist"]
            }
        }

        func matches(_ entry: ExerciseLibraryEntry) -> Bool {
            let targets = Set(aliases.map(ATHLTHExerciseReferenceResolver.key))
            let muscles = entry.exercise.primaryMuscles
            return muscles.contains { targets.contains(ATHLTHExerciseReferenceResolver.key($0)) }
        }
    }

    // Optional for old saved conversations; nil or empty means general training.
    var muscleFocus: Set<MuscleFocus>? = nil
    var supportsMuscleFocus: Bool { goal == .strength || goal == .legs || goal == .hybrid }
    var activeMuscleFocus: [MuscleFocus] {
        guard supportsMuscleFocus else { return [] }
        return MuscleFocus.allCases.filter { muscleFocus?.contains($0) == true }
    }
    var muscleFocusTitle: String {
        activeMuscleFocus.isEmpty
            ? ATHLTHLocalization.choose(english: "General / full body", norwegian: "Generelt / hele kroppen")
            : activeMuscleFocus.map(\.title).joined(separator: ", ")
    }
    var goal: Goal = .strength
    var place: Place = .gym
    var experience: Experience = .beginner
    var startDate = Calendar.current.startOfDay(for: Date())
    var weeks = 8
    var sessionsPerWeek = 3
    var submitted = false
    var rememberPreferences: Bool? = nil

    static func isCreationRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        let plan = ["treningsplan", "treningsprogram", "training plan", "training program", "workout plan"].contains { text.contains($0) }
        let creation = ["lag ", "lage ", "lager ", "opprett", "sett opp", "sette opp", "create", "make", "build", "generate", "ønsker", "vil ha", "trenger"].contains { text.contains($0) }
        let adjustment = ["endre ", "juster ", "flytt ", "utsett ", "change ", "adjust ", "move "].contains { text.contains($0) }
        return plan && creation && !adjustment
    }

    static func prefilled(from source: String, preferences: ATHLTHCoachPreferences? = nil) -> Self {
        var result = Self()
        result.goal = preferences?.planGoal ?? result.goal
        result.muscleFocus = preferences?.planMuscleFocus
        result.place = preferences?.place ?? result.place
        result.experience = preferences?.experience ?? result.experience
        if let weeks = preferences?.weeks, (2...12).contains(weeks) { result.weeks = weeks }
        if let count = preferences?.sessionsPerWeek, (2...4).contains(count) { result.sessionsPerWeek = count }
        let text = source.lowercased()
        if ["lår", "bein", "benstyrke", "quadriceps", "leg strength", "thigh"].contains(where: { text.contains($0) }) {
            result.goal = .legs
        } else if text.contains("løp") && text.contains("styrke") || text.contains("running") && text.contains("strength") {
            result.goal = .hybrid
        } else if text.contains("løp") || text.contains("running") { result.goal = .running }
        else if text.contains("gåtur") || text.contains("walking") { result.goal = .walking }
        else if text.contains("styrke") || text.contains("strength") { result.goal = .strength }
        let muscleWords: [(MuscleFocus, [String])] = [
            (.chest, ["bryst", "chest"]), (.back, ["rygg", "back"]),
            (.shoulders, ["skuldre", "shoulders"]), (.arms, ["armer", "biceps", "triceps"]),
            (.legs, ["lår", "bein", "legs", "quadriceps"]), (.glutes, ["sete", "glutes"]),
            (.core, ["kjerne", "mage", "core"])
        ]
        let mentioned = Set(muscleWords.compactMap { group, words in
            words.contains { word in
                text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b",
                           options: .regularExpression) != nil
            } ? group : nil
        })
        if !mentioned.isEmpty { result.muscleFocus = mentioned }
        if ["helkropp", "hele kroppen", "full body", "generell styrke"].contains(where: { text.contains($0) }) {
            result.muscleFocus = nil
        }
        if (text.contains("sommer") && text.contains("vinter")) || (text.contains("summer") && text.contains("winter")) {
            result.place = .seasonal
        } else if text.contains("utendørs") || text.contains(" ute") || text.contains("outdoors") {
            result.place = .outdoors
        } else if text.contains("hjemme") || text.contains("at home") { result.place = .home }
        else if text.contains("treningssenter") || text.contains("gym") { result.place = .gym }
        if text.contains("regelmessig") || text.contains("experienced") { result.experience = .regular }
        else if text.contains("nybegynner") || text.contains("beginner") { result.experience = .beginner }
        if let range = text.range(of: #"[2-4](?:\s*[-–]\s*[2-4])?\s*(?:ganger|økter|times|sessions)"#, options: .regularExpression),
           let number = text[range].first?.wholeNumberValue { result.sessionsPerWeek = number }
        if let range = text.range(of: #"\b(?:[2-9]|1[0-2])\s*(?:uker|weeks)\b"#, options: .regularExpression),
           let number = Int(text[range].prefix(while: { $0.isNumber })) { result.weeks = number }
        return result
    }

    var isValid: Bool { (2...4).contains(sessionsPerWeek) && (2...12).contains(weeks) }
}

struct ATHLTHCoachChatPlanDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    let intake: ATHLTHCoachChatPlanIntake
    let program: AIProgramDraft
    var used = false
}

/// Build with existing curated executable workouts, never model-invented
/// exercise identifiers. No plan is saved until the existing store accepts it.
enum ATHLTHCoachChatPlanFactory {
    static func makeDraft(_ intake: ATHLTHCoachChatPlanIntake, calendar: Calendar = .current, library: [ExerciseLibraryEntry]? = nil) -> ATHLTHCoachChatPlanDraft? {
        guard intake.isValid else { return nil }
        let slug: String
        switch intake.goal {
        case .legs: slug = "focus-quadriceps"
        case .strength: slug = "strength-upper-lower-foundation"
        case .running: slug = "race-5k-speed"
        case .walking: slug = "walking-strength-foundation"
        case .hybrid: slug = "hybrid-three-day"
        }
        guard let entry = ATHLTHCuratedTrainingPlans.entries.first(where: { $0.slug == slug }),
              let homeEntry = ATHLTHCuratedTrainingPlans.entries.first(where: { $0.slug == "home-bodyweight-8w" }) else { return nil }
        let weekdays = intake.sessionsPerWeek == 2 ? [1, 4] : intake.sessionsPerWeek == 3 ? [1, 3, 5] : [1, 3, 5, 7]
        let allowedIDs = library.map { Set($0.map(\.id)) }
        let custom = library?.filter { $0.source == .custom } ?? []
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let norwegian = ["Mandag", "Tirsdag", "Onsdag", "Torsdag", "Fredag", "Lørdag", "Søndag"]
        var weeks: [AIProgramDraftWeek] = []
        for week in 1...intake.weeks {
            var days: [AIProgramDraftDay] = []
            for weekday in 1...7 {
                var workouts: [AIProgramDraftSession] = []
                if let slot = weekdays.firstIndex(of: weekday) {
                    let offset = ATHLTHTrainingPlanSchedule.relativeDayIndex(forCalendarWeekday: weekday, planStart: intake.startDate) - 1
                    let date = calendar.date(byAdding: .day, value: (week - 1) * 7 + offset, to: intake.startDate) ?? intake.startDate
                    let month = calendar.component(.month, from: date)
                    let outside = intake.place == .outdoors || intake.place == .home ||
                        (intake.place == .seasonal && (5...9).contains(month))
                    let blueprint: TrainingPlanCatalogSessionBlueprint
                    switch intake.goal {
                    case .legs:
                        blueprint = slot < 2 ? (outside ? .home : (slot == 0 ? .quads : .legs)) : (outside ? .walking : .upperBody)
                    case .strength:
                        blueprint = outside ? .home : (slot % 2 == 0 ? .upperBody : .lowerBody)
                    case .running:
                        blueprint = .easyRun
                    case .walking:
                        blueprint = .walking
                    case .hybrid:
                        blueprint = slot % 2 == 0 ? .easyRun : (outside ? .home : .fullBodyA)
                    }
                    let source = blueprint == .home ? homeEntry : entry
                    var workout = ATHLTHCatalogPlanSessionFactory.session(entry: source, blueprint: blueprint, week: week)
                    if workout.kind == .strength && !intake.activeMuscleFocus.isEmpty {
                        guard let library, let focused = focusedStrengthSession(
                            intake, library: library, bodyweight: outside, variation: (week - 1) * intake.sessionsPerWeek + slot
                        ) else { return nil }
                        workout = focused
                    }
                    if intake.activeMuscleFocus.isEmpty, workout.kind == .strength, var blocks = workout.workoutBlocks {
                        if intake.activeMuscleFocus.isEmpty && intake.goal == .legs && outside {
                            let names = ["Bodyweight Squat", "Glute Bridge", "Bodyweight Reverse Lunge"]
                            blocks = blocks.filter { $0.kind != .exercise || names.contains($0.title) }
                            workout.title = ATHLTHLocalization.choose(english: "Bodyweight leg strength", norwegian: "Beinstyrke uten utstyr")
                        }
                        if intake.experience == .beginner {
                            for index in blocks.indices where blocks[index].kind == .exercise {
                                if let sets = blocks[index].setCount { blocks[index].setCount = min(sets, 2) }
                            }
                        }
                        workout.workoutBlocks = ATHLTHCatalogPlanSessionFactory.resequencedBlocks(blocks)
                    }
                    if intake.activeMuscleFocus.isEmpty && intake.goal == .legs && outside {
                        workout.notes = (workout.notes ?? "") + "\n" + ATHLTHLocalization.choose(
                            english: "Bodyweight session; focus on controlled lower-body movements.",
                            norwegian: "Kroppsvektøkt; fokuser på kontrollerte beinøvelser.")
                    }
                    if let library, let allowedIDs {
                        guard ATHLTHWorkoutExerciseBinding.bind(&workout, library: library).isReady else { return nil }
                        // A custom movement can replace a matching catalog movement
                        // only when its primary-muscle and equipment metadata agree.
                        // Preserve the schedule and conservative progression; never
                        // invent identities or carry over movement-specific cues.
                        if workout.kind == .strength, var blocks = workout.workoutBlocks {
                            var used = Set(blocks.compactMap(\.exerciseID))
                            for index in blocks.indices where blocks[index].kind == .exercise {
                                guard let snapshot = blocks[index].exerciseSnapshot,
                                      !snapshot.primaryMuscles.isEmpty, !snapshot.equipment.isEmpty,
                                      (blocks[index].repetitions ?? 0) > 0,
                                      blocks[index].durationSeconds == nil,
                                      blocks[index].targetWeightKilograms == nil else { continue }
                                let muscleKeys = Set(snapshot.primaryMuscles.map(ATHLTHExerciseReferenceResolver.key))
                                let equipmentKeys = Set(snapshot.equipment.map(ATHLTHExerciseReferenceResolver.key))
                                guard let own = custom.first(where: {
                                    !used.contains($0.id) &&
                                    $0.exercise.snapshot.defaultStrengthTargetKind == .reps &&
                                    Set($0.exercise.primaryMuscles.map(ATHLTHExerciseReferenceResolver.key)) == muscleKeys &&
                                    Set($0.exercise.equipment.map(ATHLTHExerciseReferenceResolver.key)) == equipmentKeys
                                }) else { continue }
                                used.insert(own.id)
                                blocks[index].exerciseID = own.id
                                blocks[index].exerciseSlug = own.sourceIdentifier
                                blocks[index].exerciseSnapshot = own.exercise.snapshot
                                blocks[index].title = own.canonicalName
                                blocks[index].notes = nil
                                blocks[index].loadNote = nil
                                break // at most one compatible substitution per workout
                            }
                            workout.workoutBlocks = blocks
                        }
                        guard ATHLTHCoachLibraryGate.hasOnlyLibraryReferences(workout, ids: allowedIDs) else { return nil }
                    }
                    workouts = [AIProgramDraftSession(title: workout.title, kind: workout.kind.rawValue,
                        durationMinutes: workout.durationMinutes, targetDistanceKilometers: workout.targetDistanceKilometers,
                        targetPaceSecondsPerKilometer: workout.targetPaceSecondsPerKilometer,
                        notes: workout.notes, exercises: [], authoredWorkout: workout)]
                }
                days.append(AIProgramDraftDay(dayIndex: weekday, title: ATHLTHLocalization.choose(
                    english: names[weekday - 1], norwegian: norwegian[weekday - 1]), sessions: workouts))
            }
            weeks.append(AIProgramDraftWeek(weekNumber: week, title: ATHLTHLocalization.choose(
                english: "Week \(week)", norwegian: "Uke \(week)"), days: days))
        }
        let program = AIProgramDraft(title: intake.activeMuscleFocus.isEmpty ? intake.goal.title : intake.goal.title + " · " + intake.muscleFocusTitle,
            summary: "\(intake.weeks) " + ATHLTHLocalization.choose(english: "weeks", norwegian: "uker")
                + " · \(intake.sessionsPerWeek) " + ATHLTHLocalization.choose(english: "workouts/week", norwegian: "økter/uke")
                + " · " + intake.place.title, weeks: weeks)
        guard ATHLTHPlanDraftValidator.issues(in: program, expectedWeeks: intake.weeks,
            maximumSessionsPerWeek: intake.sessionsPerWeek, requireFullWeeks: true,
            requireExecutableWorkouts: true).isEmpty else { return nil }
        return ATHLTHCoachChatPlanDraft(intake: intake, program: program)
    }

    private static func focusedStrengthSession(
        _ intake: ATHLTHCoachChatPlanIntake, library: [ExerciseLibraryEntry],
        bodyweight: Bool, variation: Int
    ) -> PlannedSession? {
        let groups = intake.activeMuscleFocus
        guard !groups.isEmpty else { return nil }
        let candidates = library.filter { entry in
            guard entry.exercise.snapshot.defaultStrengthTargetKind == .reps else { return false }
            if bodyweight {
                guard !entry.exercise.equipment.isEmpty,
                      entry.exercise.equipment.allSatisfy({
                          ["bodyweight", "body weight", "none", "no equipment", "kroppsvekt"].contains($0.lowercased())
                      }) else { return false }
            }
            return groups.contains { $0.matches(entry) }
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        // Every selected group must be supported by actual library metadata.
        // Never silently replace a requested group with an unrelated exercise.
        var picked: [ExerciseLibraryEntry] = []
        var used = Set<UUID>()
        for group in groups {
            let matches = candidates.filter { group.matches($0) }
            guard !matches.isEmpty else { return nil }
            if picked.contains(where: { group.matches($0) }) { continue }
            let available = matches.filter { !used.contains($0.id) }
            guard !available.isEmpty else { return nil }
            let entry = available[variation % available.count]
            picked.append(entry)
            used.insert(entry.id)
        }
        let targetCount = max(4, groups.count)
        let remaining = candidates.filter { !used.contains($0.id) }
        if !remaining.isEmpty {
            for offset in 0..<min(max(0, targetCount - picked.count), remaining.count) {
                picked.append(remaining[(variation + offset) % remaining.count])
            }
        }
        guard picked.count >= 2 else { return nil }
        let exercises = picked.map { entry in
            PlannedExercise(id: UUID(), exerciseID: entry.id, embeddedExercise: entry.exercise.snapshot,
                sets: intake.experience == .beginner ? 2 : 3, reps: 10,
                targetWeightKilograms: nil, targetRPE: nil, restSeconds: 90, notes: nil)
        }
        let title = intake.muscleFocusTitle
        let minutes = max(30, picked.count * (intake.experience == .beginner ? 7 : 9))
        var workout = PlannedSession(id: UUID(), title: title, kind: .strength,
            scheduledStart: nil, durationMinutes: minutes, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: exercises, notes: nil)
        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        ATHLTHUnifiedWorkout.apply(blocks: blocks, title: title, routeID: nil,
            estimatedMinutes: minutes, to: &workout)
        return workout
    }
}
