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
    var goal: Goal = .strength
    var place: Place = .gym
    var experience: Experience = .beginner
    var startDate = Calendar.current.startOfDay(for: Date())
    var weeks = 8
    var sessionsPerWeek = 3
    var submitted = false

    static func isCreationRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        let plan = ["treningsplan", "treningsprogram", "training plan", "training program", "workout plan"].contains { text.contains($0) }
        let creation = ["lag ", "lage ", "lager ", "opprett", "sett opp", "sette opp", "create", "make", "build", "generate", "ønsker", "vil ha", "trenger"].contains { text.contains($0) }
        let adjustment = ["endre ", "juster ", "flytt ", "utsett ", "change ", "adjust ", "move "].contains { text.contains($0) }
        return plan && creation && !adjustment
    }

    static func prefilled(from source: String) -> Self {
        var result = Self()
        let text = source.lowercased()
        if ["lår", "bein", "benstyrke", "quadriceps", "leg strength", "thigh"].contains(where: { text.contains($0) }) {
            result.goal = .legs
        } else if text.contains("løp") && text.contains("styrke") || text.contains("running") && text.contains("strength") {
            result.goal = .hybrid
        } else if text.contains("løp") || text.contains("running") { result.goal = .running }
        else if text.contains("gåtur") || text.contains("walking") { result.goal = .walking }
        if (text.contains("sommer") && text.contains("vinter")) || (text.contains("summer") && text.contains("winter")) {
            result.place = .seasonal
        } else if text.contains("utendørs") || text.contains(" ute") || text.contains("outdoors") {
            result.place = .outdoors
        } else if text.contains("hjemme") || text.contains("at home") { result.place = .home }
        if text.contains("regelmessig") || text.contains("experienced") { result.experience = .regular }
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
                    if workout.kind == .strength, var blocks = workout.workoutBlocks {
                        if intake.goal == .legs && outside {
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
                    if intake.goal == .legs && outside {
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
        let program = AIProgramDraft(title: intake.goal.title,
            summary: "\(intake.weeks) " + ATHLTHLocalization.choose(english: "weeks", norwegian: "uker")
                + " · \(intake.sessionsPerWeek) " + ATHLTHLocalization.choose(english: "workouts/week", norwegian: "økter/uke")
                + " · " + intake.place.title, weeks: weeks)
        guard ATHLTHPlanDraftValidator.issues(in: program, expectedWeeks: intake.weeks,
            maximumSessionsPerWeek: intake.sessionsPerWeek, requireFullWeeks: true,
            requireExecutableWorkouts: true).isEmpty else { return nil }
        return ATHLTHCoachChatPlanDraft(intake: intake, program: program)
    }
}
