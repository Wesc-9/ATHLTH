import Foundation

/// One activity interpretation for the existing universal workout timeline.
///
/// This is a projection only: it never opens a HealthKit workout, changes
/// capture ownership or writes a second history record. Legacy workouts
/// retain their original Codable schema and original plan/workout IDs.
/// Normalizes a known activity tag on an existing note block. Unrecognized
/// tags remain instructions; titles are never guessed to be sport names.
/// The same policy is used by the planner, live router and launch admission.
enum ATHLTHWorkoutActivityTagPolicy {
    static func activity(for block: WorkoutTemplateBlock)
        -> CustomQuickWorkoutActivity? {
        guard block.kind == .note,
              let raw = block.activityTag?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).lowercased(),
              !raw.isEmpty else { return nil }
        let tag = raw.filter { $0.isLetter || $0.isNumber }
        switch tag {
        case "cycling", "bicycle", "biking": return .cycling
        case "rowing", "row": return .rowing
        case "stairclimber", "stairclimbing", "stairs": return .stairClimber
        case "hiit": return .hiit
        case "circuit", "circuittraining": return .circuit
        case "functional", "functionaltraining": return .functional
        case "mobility": return .mobility
        case "yoga": return .yoga
        case "sports", "sport": return .sports
        case "other": return .other
        default: return nil
        }
    }
}

 
/// Sport-specific presentation and target policy for the ONE existing
/// workout timeline. Does not allocate a HealthKit session, save a workout,
/// or claim that a planned metric was measured by a sensor.
enum ATHLTHWorkoutSportMode: Equatable {
    case running, walking, strength, cycling, rowing, stairClimber
    case hiit, circuit, functional, yoga, mobility, sports, other
    case recovery, instructions

    init(category: String) {
        let normalized = category.lowercased()
            .filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "running", "treadmill": self = .running
        case "walking", "hiking": self = .walking
        case "strength": self = .strength
        case "cycling", "biking", "bicycle": self = .cycling
        case "rowing", "row": self = .rowing
        case "stairclimber", "stairclimbing", "stairs": self = .stairClimber
        case "hiit": self = .hiit
        case "circuit", "circuittraining": self = .circuit
        case "functional", "functionaltraining": self = .functional
        case "yoga": self = .yoga
        case "mobility", "stretching", "meditation": self = .mobility
        case "sports", "sport": self = .sports
        case "recovery", "rest": self = .recovery
        case "instructions", "note": self = .instructions
        default: self = .other
        }
    }

    static func forBlock(_ block: WorkoutTemplateBlock) -> Self {
        switch block.kind {
        case .run:
            return block.cardioActivity == .walking ? .walking : .running
        case .exercise:
            return .strength
        case .rest:
            return .recovery
        case .note:
            if let activity = ATHLTHWorkoutActivityTagPolicy.activity(for: block) {
                return Self(category: activity.rawValue)
            }
            return block.wellnessKind == nil ? .instructions : .mobility
        }
    }

    /// Existing capture engines stay authoritative. A sport changes the
    /// controls shown to the athlete, never the recording owner.
    var engine: ATHLTHLiveWorkoutEngine {
        switch self {
        case .running, .walking, .rowing, .stairClimber: return .endurance
        case .strength: return .strength
        case .cycling: return .cycling
        case .yoga, .mobility: return .mobility
        case .recovery: return .recovery
        case .hiit, .circuit, .functional, .sports, .other, .instructions:
            return .instructions
        }
    }

    var title: String {
        switch self {
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .cycling: return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
        case .rowing: return ATHLTHLocalization.choose(english: "Rowing", norwegian: "Roing")
        case .stairClimber: return ATHLTHLocalization.choose(english: "Stair climbing", norwegian: "Trappetrening")
        case .hiit: return "HIIT"
        case .circuit: return ATHLTHLocalization.choose(english: "Circuit training", norwegian: "Sirkeltrening")
        case .functional: return ATHLTHLocalization.choose(english: "Functional training", norwegian: "Funksjonell trening")
        case .yoga: return "Yoga"
        case .mobility: return ATHLTHLocalization.choose(english: "Mobility", norwegian: "Bevegelighet")
        case .sports: return ATHLTHLocalization.choose(english: "Sports", norwegian: "Idrett")
        case .other: return ATHLTHLocalization.choose(english: "Other workout", norwegian: "Annen trening")
        case .recovery: return ATHLTHLocalization.choose(english: "Recovery", norwegian: "Pause")
        case .instructions: return ATHLTHLocalization.choose(english: "Instructions", norwegian: "Veiledning")
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .cycling: return "bicycle"
        case .rowing: return "figure.rower"
        case .stairClimber: return "figure.stairs"
        case .hiit: return "timer"
        case .circuit: return "repeat"
        case .functional: return "figure.strengthtraining.functional"
        case .yoga: return "figure.yoga"
        case .mobility: return "figure.cooldown"
        case .sports: return "sportscourt"
        case .other: return "figure.mixed.cardio"
        case .recovery: return "pause.circle"
        case .instructions: return "text.alignleft"
        }
    }

    var nextActionTitle: String {
        switch self {
        case .strength:
            return ATHLTHLocalization.choose(english: "Complete set & next", norwegian: "Fullfør sett og neste")
        case .running, .walking, .cycling, .rowing, .stairClimber,
             .hiit, .circuit, .functional:
            return ATHLTHLocalization.choose(english: "Complete interval & next", norwegian: "Fullfør intervall og neste")
        case .recovery:
            return ATHLTHLocalization.choose(english: "End rest & next", norwegian: "Avslutt pause og neste")
        case .yoga, .mobility, .sports, .other, .instructions:
            return ATHLTHLocalization.choose(english: "Next step", norwegian: "Neste del")
        }
    }

    /// Bare instruction blocks must not display a made-up exercise target.
    var showsPlannedTargets: Bool { self != .instructions }
}

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
        let tagged = Set(blocks.compactMap {
            ATHLTHWorkoutActivityTagPolicy.activity(for: $0)
        })
        let cycling = tagged.contains(.cycling)
        let wellness = blocks.compactMap(\.wellnessKind)
        let mobility = !wellness.isEmpty ||
            tagged.contains(.mobility) || tagged.contains(.yoga)
        // Yoga and mobility are one wellness family, not two workout
        // recordings. Other explicitly tagged sports have distinct segments.
        let otherSports = tagged.subtracting([
            .cycling, .yoga, .mobility
        ])
        let activities = [running, walking, strength, cycling, mobility]
            .filter { $0 }.count + otherSports.count

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
            let meditationOnly = !wellness.isEmpty &&
                wellness.allSatisfy { $0 == .meditation } &&
                !tagged.contains(.yoga) && !tagged.contains(.mobility)
            category = meditationOnly ? "recovery" : "mobility"
            workoutKind = meditationOnly ? .recovery : .mobility
        } else if let sport = otherSports.first {
            // These use the shared plan format while preserving a dedicated
            // sport identity until a verified capture adapter is available.
            category = sport.rawValue.lowercased()
            workoutKind = .custom
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
        case "rowing", "stairclimber", "stair_climbing", "hiit",
             "circuit", "functional", "sports", "other":
            return saved == "stair_climbing" ? "stairclimber" : saved!
        case "hiking":
            return "walking"
        default:
            return Self(blocks: [], fallbackKind: workout.kind).category
        }
    }
}
