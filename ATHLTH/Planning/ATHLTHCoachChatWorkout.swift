import Foundation

struct ATHLTHCoachChatWorkoutIntake: Codable, Hashable {
    enum Focus: String, CaseIterable, Codable {
        case fullBody, back, legs, chest, shoulders, arms, core, running, walking
        var title: String {
            let no: String
            let en: String
            switch self {
            case .fullBody: (en, no) = ("Full body", "Helkropp")
            case .back: (en, no) = ("Back", "Rygg")
            case .legs: (en, no) = ("Legs", "Bein")
            case .chest: (en, no) = ("Chest", "Bryst")
            case .shoulders: (en, no) = ("Shoulders", "Skuldre")
            case .arms: (en, no) = ("Arms", "Armer")
            case .core: (en, no) = ("Core", "Kjerne")
            case .running: (en, no) = ("Running", "Løping")
            case .walking: (en, no) = ("Walking", "Gåing")
            }
            return ATHLTHLocalization.choose(english: en, norwegian: no)
        }
        var muscle: String? {
            switch self {
            case .back: return "Back"
            case .legs: return "Legs"
            case .chest: return "Chest"
            case .shoulders: return "Shoulders"
            case .arms: return "Biceps"
            case .core: return "Core"
            default: return nil
            }
        }
    }
    var focus: Focus = .fullBody
    var place: ATHLTHCoachChatPlanIntake.Place = .gym
    var experience: ATHLTHCoachChatPlanIntake.Experience = .beginner
    var date = Calendar.current.startOfDay(for: Date())
    var minutes = 30
    var alternatives = 1
    var ownOnly = false
    var submitted = false
    var rememberPreferences: Bool? = nil
    var forTogether: Bool? = nil

    static func isTogetherRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        return ["tren sammen", "trene sammen", "fellesøkt", "felles økt", "train together", "workout together"].contains { text.contains($0) } &&
            ["lag", "planlegg", "foreslå", "sett opp", "create", "plan", "suggest", "gi meg"].contains { text.contains($0) }
    }

    static func isRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        guard !ATHLTHCoachChatPlanIntake.isCreationRequest(text),
              !["flytt ", "utsett ", "endre ", "postpone ", "reschedule "].contains(where: { text.contains($0) }) else { return false }
        return isTogetherRequest(source) || ATHLTHCoachWorkoutCreationIntent.isRequest(source) ||
            (["økt", "workout", "session"].contains { text.contains($0) } &&
             ["planlegg", "planlegge", "gi meg", "foreslå", "forslag", "alternativ", "suggest", "plan a", "give me"].contains { text.contains($0) })
    }

    static func prefilled(from source: String, now: Date = Date(), calendar: Calendar = .current,
                          preferences: ATHLTHCoachPreferences? = nil) -> Self {
        let text = source.lowercased()
        var intake = Self()
        intake.forTogether = isTogetherRequest(source) ? true : nil
        intake.focus = preferences?.workoutFocus ?? intake.focus
        if let minutes = preferences?.minutes, (15...60).contains(minutes) { intake.minutes = minutes }
        let plan = ATHLTHCoachChatPlanIntake.prefilled(from: source, preferences: preferences)
        intake.place = plan.place == .seasonal ? .gym : plan.place
        intake.experience = plan.experience
        intake.date = calendar.startOfDay(for: now)
        if ["om en uke", "om én uke", "om 1 uke", "neste uke", "in a week", "next week"].contains(where: { text.contains($0) }) {
            intake.date = calendar.date(byAdding: .day, value: 7, to: intake.date) ?? intake.date
        } else if text.contains("i morgen") || text.contains("tomorrow") {
            intake.date = calendar.date(byAdding: .day, value: 1, to: intake.date) ?? intake.date
        }
        if text.contains("rygg") || text.contains("back") { intake.focus = .back }
        else if text.contains("bryst") || text.contains("chest") { intake.focus = .chest }
        else if text.contains("skuld") || text.contains("shoulder") { intake.focus = .shoulders }
        else if text.contains("arm") || text.contains("biceps") || text.contains("triceps") { intake.focus = .arms }
        else if text.contains("kjerne") || text.contains("core") { intake.focus = .core }
        else if ["lår", "bein", "legs", "thigh"].contains(where: { text.contains($0) }) { intake.focus = .legs }
        else if text.contains("løp") || text.contains("running") { intake.focus = .running }
        else if text.contains("gåtur") || text.contains("walking") { intake.focus = .walking }
        else if text.contains("helkropp") || text.contains("full body") { intake.focus = .fullBody }
        if let range = text.range(of: #"\b(?:15|20|25|30|35|40|45|50|55|60)\s*(?:minutter|min|minutes)\b"#, options: .regularExpression),
           let minutes = Int(text[range].prefix(while: { $0.isNumber })) { intake.minutes = minutes }
        if ["tre ", "3 ", "three "].contains(where: { text.contains($0 + "alternativ") || text.contains($0 + "økt") || text.contains($0 + "workout") }) { intake.alternatives = 3 }
        else if ["to ", "2 ", "two "].contains(where: { text.contains($0 + "alternativ") || text.contains($0 + "økt") || text.contains($0 + "workout") }) { intake.alternatives = 2 }
        intake.ownOnly = text.contains("mine øvelser") || text.contains("my exercises")
        return intake
    }
}

struct ATHLTHCoachChatWorkoutDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    let workout: PlannedSession
    let date: Date
    var used = false
    var forTogether: Bool? = nil
}

enum ATHLTHCoachLibraryGate {
    static func hasOnlyLibraryReferences(_ workout: PlannedSession, library: [ExerciseLibraryEntry]) -> Bool {
        hasOnlyLibraryReferences(workout, ids: Set(library.map(\.id)))
    }

    static func hasOnlyLibraryReferences(_ workout: PlannedSession, ids: Set<UUID>) -> Bool {
        workout.exercises.allSatisfy { $0.exerciseID.map(ids.contains) == true } &&
            workout.resolvedWorkoutBlocks.allSatisfy { block in
                if block.kind == .exercise || block.exerciseID != nil || block.exerciseSlug != nil {
                    return block.exerciseID.map(ids.contains) == true
                }
                return true // generic time/rest instructions are not library exercises
            }
    }
}

@MainActor
enum ATHLTHCoachChatWorkoutFactory {
    static func makeDrafts(_ intake: ATHLTHCoachChatWorkoutIntake, library: [ExerciseLibraryEntry]) -> [ATHLTHCoachChatWorkoutDraft] {
        guard (1...3).contains(intake.alternatives), (15...60).contains(intake.minutes),
              intake.date >= Calendar.current.startOfDay(for: Date()) else { return [] }
        if intake.focus == .running || intake.focus == .walking {
            // A free timed cardio workout needs no invented exercise record.
            guard intake.alternatives == 1 else { return [] }
            let kind: WorkoutKind = intake.focus == .running ? .running : .walking
            var workout = PlannedSession(id: UUID(), title: intake.focus.title, kind: kind,
                scheduledStart: nil, durationMinutes: intake.minutes, targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: [], notes: nil)
            workout.workoutBlocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
            guard ATHLTHCoachLibraryGate.hasOnlyLibraryReferences(workout, library: library) else { return [] }
            return [ATHLTHCoachChatWorkoutDraft(workout: workout, date: intake.date, forTogether: intake.forTogether)]
        }
        let bodyweight = intake.place == .outdoors || intake.place == .home
        let candidates = StrengthAIExerciseSelectionPolicy.available(from: library, excluding: [],
            source: intake.ownOnly ? .mine : .library,
            focuses: intake.focus == .arms ? ["Biceps", "Triceps"] : intake.focus.muscle.map { [$0] } ?? [], equipment: nil)
            .filter { entry in
                guard !bodyweight || (!entry.exercise.equipment.isEmpty && entry.exercise.equipment.allSatisfy({
                    ["bodyweight", "body weight", "none", "no equipment", "kroppsvekt"].contains($0.lowercased())
                })) else { return false }
                // Require primary focus, not merely a secondary stabilizer.
                guard let muscle = intake.focus.muscle else { return true }
                let groups = ([entry.bodyPart].compactMap { $0 } + entry.exercise.primaryMuscles).map(ExerciseLibraryStore.canonicalMuscleFilter)
                return groups.contains(muscle) || (intake.focus == .arms && groups.contains("Triceps"))
            }
        let count = min(5, max(2, intake.minutes / 10))
        guard candidates.count >= count + intake.alternatives - 1 else { return [] }
        var drafts: [ATHLTHCoachChatWorkoutDraft] = []
        for variant in 0..<intake.alternatives {
            let start = min(variant * count, candidates.count - count - (intake.alternatives - 1 - variant))
            let entries = Array(candidates[start..<(start + count)])
            let exercises = entries.map { entry in
                PlannedExercise(id: UUID(), exerciseID: entry.id, embeddedExercise: entry.exercise.snapshot,
                    sets: intake.experience == .beginner ? 2 : 3, reps: 10,
                    targetWeightKilograms: nil, targetRPE: nil, restSeconds: 90, notes: nil)
            }
            let title = intake.focus.title + (intake.alternatives > 1 ? " · \(variant + 1)" : "")
            var workout = PlannedSession(id: UUID(), title: title, kind: .strength,
                scheduledStart: nil, durationMinutes: intake.minutes, targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: exercises, notes: nil)
            let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
            ATHLTHUnifiedWorkout.apply(blocks: blocks, title: title, routeID: nil,
                estimatedMinutes: intake.minutes, to: &workout)
            guard ATHLTHWorkoutExerciseBinding.bind(&workout, library: library).isReady,
                  ATHLTHCoachLibraryGate.hasOnlyLibraryReferences(workout, library: library) else { return [] }
            drafts.append(ATHLTHCoachChatWorkoutDraft(workout: workout, date: intake.date, forTogether: intake.forTogether))
        }
        return drafts
    }
}
