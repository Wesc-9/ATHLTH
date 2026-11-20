import Foundation

/// One activity interpretation for the existing universal workout timeline.
///
/// This is a projection only: it never opens a HealthKit workout, changes
/// capture ownership or writes a second history record. Legacy workouts
/// retain their original Codable schema and original plan/workout IDs.
struct ATHLTHUnifiedActivityProfile: Equatable {
    let category: String
    let workoutKind: WorkoutKind

    init(
        blocks: [WorkoutTemplateBlock],
        fallbackKind: WorkoutKind = .custom
    ) {
        let cardio = blocks.filter {
            $0.kind == .run && !$0.isActiveRecovery
        }
        // Old walking recipes may contain untagged .run blocks. Do not
        // reinterpret them as running merely because of an old block schema.
        let legacyWalking = fallbackKind == .walking && !cardio.isEmpty &&
            cardio.allSatisfy { $0.cardioActivity == nil }
        let walking = legacyWalking || cardio.contains {
            $0.cardioActivity == .walking
        }
        let running = !legacyWalking && cardio.contains {
            $0.cardioActivity != .walking
        }
        let strength = blocks.contains { $0.kind == .exercise }
        let cycling = blocks.contains {
            $0.kind == .note && $0.activityTag?.lowercased() == "cycling"
        }
        let wellness = blocks.compactMap(\.wellnessKind)
        let mobility = !wellness.isEmpty
        let activities = [running, walking, strength, cycling, mobility]
            .filter { $0 }.count

        if activities > 1 {
            category = "hybrid"
            workoutKind = .custom
        } else if running {
            let treadmill = !cardio.isEmpty && cardio.allSatisfy {
                $0.isIndoor == true && $0.treadmillInclinePercent != nil
            }
            category = treadmill ? "treadmill" : "running"
            workoutKind = .running
        } else if walking {
            category = "walking"
            workoutKind = .walking
        } else if strength {
            category = "strength"
            workoutKind = .strength
        } else if cycling {
            // Cycling has its own planned activity and live presentation.
            // The legacy WorkoutKind remains .custom until a separately
            // tested cycling capture owner is implemented.
            category = "cycling"
            workoutKind = .custom
        } else if mobility {
            let meditationOnly = wellness.allSatisfy { $0 == .meditation }
            category = meditationOnly ? "recovery" : "mobility"
            workoutKind = meditationOnly ? .recovery : .mobility
        } else {
            // Only notes/rests have no specific activity; preserve legacy
            // intent and never fabricate exercise volume or GPS distance.
            workoutKind = fallbackKind
            switch fallbackKind {
            case .running: category = "running"
            case .walking: category = "walking"
            case .strength: category = "strength"
            case .mobility: category = "mobility"
            case .recovery: category = "recovery"
            default: category = "custom"
            }
        }
    }

    /// Existing saved plans may predate the universal block timeline.
    /// Trust an explicit saved category when there are no structured blocks,
    /// then fall back to the original WorkoutKind. Never parse the title.
    static func category(for workout: PlannedSession) -> String {
        let blocks = workout.resolvedWorkoutBlocks
        if !blocks.isEmpty {
            return Self(blocks: blocks, fallbackKind: workout.kind).category
        }
        let saved = workout.workoutCategory?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch saved {
        case "running", "walking", "strength", "cycling", "mobility",
             "recovery", "hybrid", "custom", "treadmill":
            return saved!
        case "yoga", "stretching", "meditation":
            return saved == "meditation" ? "recovery" : "mobility"
        case "hiking":
            return "walking"
        default:
            return Self(blocks: [], fallbackKind: workout.kind).category
        }
    }
}
