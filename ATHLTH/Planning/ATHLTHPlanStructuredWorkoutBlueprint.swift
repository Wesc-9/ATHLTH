import Foundation

/// A single advanced workout definition shared by the plan wizard and Coach.
/// Basic never creates these blueprints. IDs, media and exercise snapshots
/// remain part of the existing ATHLTH training model.
struct ATHLTHPlanStructuredWorkoutBlueprint: Codable, Hashable {
    var title: String
    var kind: WorkoutKind
    var durationMinutes: Int
    var routeID: UUID?
    var blocks: [WorkoutTemplateBlock]
    /// Minutes since local midnight; nil means no fixed start time.
    var startMinuteOfDay: Int? = nil

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !blocks.isEmpty && blocks.count <= 200
            && blocks.contains { $0.kind == .run || $0.kind == .exercise
                || ($0.kind == .note
                    && ($0.wellnessKind != nil || $0.activityTag == "cycling")
                    && ($0.durationSeconds ?? 0) > 0) }
            && blocks.expandedForExecution().count <= 1_000
            && !Set(blocks.compactMap {
                $0.groupKind == .superset ? $0.groupID : nil
            }).contains { groupID in
                blocks.filter { $0.groupID == groupID && $0.kind == .exercise }.count < 2
            }
    }

    var category: String {
        let hasRun = blocks.contains {
            $0.kind == .run && $0.cardioActivity != .walking
        }
        let hasWalking = blocks.contains {
            $0.kind == .run && $0.cardioActivity == .walking
        }
        let hasStrength = blocks.contains { $0.kind == .exercise }
        let hasCycling = blocks.contains { $0.activityTag == "cycling" }
        let hasWellness = blocks.contains { $0.wellnessKind != nil }
        if [hasRun, hasWalking, hasStrength, hasCycling, hasWellness]
            .filter({ $0 }).count > 1 {
            return "hybrid"
        }
        if hasRun { return "running" }
        if hasWalking { return "walking" }
        if hasStrength { return "strength" }
        if hasCycling { return "cycling" }
        let wellness = blocks.compactMap(\.wellnessKind)
        if !wellness.isEmpty {
            return wellness.allSatisfy { $0 == .meditation }
                ? "recovery" : "mobility"
        }
        return "custom"
    }

    /// Structured execution is authoritative. Do not also execute legacy
    /// suggested exercises, or add an extra AI session on that day.
    func applying(to existing: PlannedSession?) -> PlannedSession {
        var workout = existing ?? PlannedSession(
            id: UUID(),
            title: title,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: durationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: routeID,
            exercises: [],
            notes: nil
        )
        workout.title = title
        if let startMinuteOfDay, (0..<1440).contains(startMinuteOfDay),
           let day = workout.scheduledStart {
            let calendar = Calendar.current
            workout.scheduledStart = calendar.date(byAdding: .minute,
                value: startMinuteOfDay, to: calendar.startOfDay(for: day))
        }
        workout.kind = kind
        workout.durationMinutes = min(max(durationMinutes, 5), 240)
        workout.routeID = blocks.contains(where: {
            $0.kind == .run && $0.isIndoor != true
        }) ? routeID : nil
        workout.exercises = []
        workout.workoutBlocks = blocks
        workout.workoutCategory = category
        workout.runningWorkout = nil
        workout.runningWorkouts = nil
        return workout
    }

    static func apply(
        _ choices: [Int: ATHLTHPlanStructuredWorkoutBlueprint],
        to weeks: inout [TrainingPlanWeek]
    ) {
        guard !choices.isEmpty else { return }
        for weekIndex in weeks.indices {
            for dayIndex in weeks[weekIndex].days.indices {
                let day = weeks[weekIndex].days[dayIndex].dayIndex
                guard let blueprint = choices[day], blueprint.isValid else {
                    continue
                }
                let previous = weeks[weekIndex].days[dayIndex].sessions.first
                weeks[weekIndex].days[dayIndex].sessions = [
                    blueprint.applying(to: previous)
                ]
            }
        }
    }
}

/// A dated override for a single day of a multi-week plan.
/// Keys use (zero-based weekIndex * 7 + calendar weekday, Monday = 1).
/// Other weeks retain the template. Optional fields allow incremental edits.
struct ATHLTHPlanWeekDayEdit: Codable, Hashable {
    var kind: WorkoutKind?
    var title: String?
    var durationMinutes: Int?
    var detailedWorkout: ATHLTHPlanStructuredWorkoutBlueprint?
    var isCustomTitle = false
    var removeTemplateDetail = false
    // Optional: existing persisted plans must continue decoding.
    var isRestDay: Bool? = nil
    var additionalDetailedWorkouts: [ATHLTHPlanStructuredWorkoutBlueprint]? = nil
    /// Optional per-date location, independent of the plan's other dates.
    var trainingPlace: ATHLTHTrainingPlace? = nil

    func scheduledSessions(from originals: [PlannedSession]) -> [PlannedSession] {
        if isRestDay == true { return [] }
        // Selecting only a place must not manufacture a workout on an empty day.
        if originals.isEmpty, detailedWorkout == nil, kind == nil,
           title == nil, (additionalDetailedWorkouts ?? []).isEmpty {
            return []
        }
        let first = applying(to: originals.first)
        let extras = (additionalDetailedWorkouts ?? [])
            .filter(\.isValid)
            .map { $0.applying(to: nil) }
        return ([first] + Array(originals.dropFirst()) + extras).map { workout in
            var copy = workout
            copy.plannedTrainingPlace = trainingPlace
            return copy
        }
    }

    func applying(to original: PlannedSession?) -> PlannedSession {
        var result = original ?? PlannedSession(
            id: UUID(), title: title ?? kind?.title ?? "Workout",
            kind: kind ?? .strength, scheduledStart: nil,
            durationMinutes: durationMinutes ?? 45,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        if let detailedWorkout, detailedWorkout.isValid {
            result = detailedWorkout.applying(to: result)
        } else {
            if let kind, kind != result.kind {
                // A changed training type cannot inherit a previous activity's
                // strength exercises, running recipe, route or structured steps.
                result.exercises = []
                result.workoutBlocks = nil
                result.workoutTemplateID = nil
                result.workoutCategory = nil
                result.runningWorkout = nil
                result.runningWorkouts = nil
                result.targetDistanceKilometers = nil
                result.targetPaceSecondsPerKilometer = nil
                result.routeID = nil
            }
            if removeTemplateDetail {
                result.workoutBlocks = nil
                result.exercises = []
                result.workoutTemplateID = nil
                result.runningWorkout = nil
                result.runningWorkouts = nil
                result.workoutCategory = nil
            }
            if let kind { result.kind = kind }
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.title = title
            }
            if let durationMinutes { result.durationMinutes = min(max(durationMinutes, 5), 240) }
        }
        return result
    }

    static func apply(
        _ edits: [Int: ATHLTHPlanWeekDayEdit],
        to weeks: inout [TrainingPlanWeek],
        startDate: Date
    ) {
        let calendar = Calendar.current
        let startWeekday = (calendar.component(.weekday, from: startDate) + 5) % 7 + 1
        for (key, edit) in edits where key >= 1 {
            let weekIndex = (key - 1) / 7
            let weekday = (key - 1) % 7 + 1
            guard weeks.indices.contains(weekIndex) else { continue }
            let relativeDay = (weekday - startWeekday + 7) % 7 + 1
            guard let dayIndex = weeks[weekIndex].days.firstIndex(
                where: { $0.dayIndex == relativeDay }
            ) else { continue }
            let previous = weeks[weekIndex].days[dayIndex].sessions
            var sessions = edit.scheduledSessions(from: previous)
            // The plan's first day is startDate, regardless of weekday.
            // Resolve each session's local clock time against its actual date.
            if let actualDate = calendar.date(byAdding: .day,
                value: weekIndex * 7 + relativeDay - 1, to: startDate) {
                let midnight = calendar.startOfDay(for: actualDate)
                let blueprints = [edit.detailedWorkout].compactMap { $0 }
                    + (edit.additionalDetailedWorkouts ?? [])
                for (index, blueprint) in blueprints.enumerated()
                    where sessions.indices.contains(index) {
                    if let minute = blueprint.startMinuteOfDay,
                       (0..<1440).contains(minute) {
                        sessions[index].scheduledStart = calendar.date(
                            byAdding: .minute, value: minute, to: midnight)
                    }
                }
            }
            weeks[weekIndex].days[dayIndex].sessions = sessions
        }
    }
}
