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

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !blocks.isEmpty && blocks.count <= 200
            && blocks.contains { $0.kind == .run || $0.kind == .exercise }
            && blocks.expandedForExecution().count <= 1_000
            && !Set(blocks.compactMap {
                $0.groupKind == .superset ? $0.groupID : nil
            }).contains { groupID in
                blocks.filter { $0.groupID == groupID && $0.kind == .exercise }.count < 2
            }
    }

    var category: String {
        let hasRun = blocks.contains { $0.kind == .run }
        let hasStrength = blocks.contains { $0.kind == .exercise }
        if hasRun && hasStrength { return "hybrid" }
        if hasRun {
            let walkingOnly = blocks.filter { $0.kind == .run }.allSatisfy {
                $0.cardioActivity == .walking
            }
            return walkingOnly ? "walking" : "running"
        }
        if hasStrength { return "strength" }
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
            if kind != nil && kind != result.kind {
                // Changing from strength to walking/running cannot inherit the
                // exercises, targets or route of the old seeded session.
                result.exercises = []
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
            let previous = weeks[weekIndex].days[dayIndex].sessions.first
            weeks[weekIndex].days[dayIndex].sessions = [edit.applying(to: previous)]
        }
    }
}
