import Foundation

enum StrengthProgressionKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case addWeight
    case addReps
    case doubleProgression
    case percentage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No automatic progression"
        case .addWeight: return "Add weight"
        case .addReps: return "Add reps"
        case .doubleProgression: return "Double progression"
        case .percentage: return "Percentage"
        }
    }
}

struct StrengthProgressionRule: Codable, Hashable {
    var kind: StrengthProgressionKind
    var amount: Double
    var minimumReps: Int?
    var maximumReps: Int?
    var applyWhenAllSetsCompleted: Bool

    static let none = StrengthProgressionRule(
        kind: .none,
        amount: 0,
        minimumReps: nil,
        maximumReps: nil,
        applyWhenAllSetsCompleted: true
    )
}

enum RunningWorkoutType: String, CaseIterable, Identifiable, Codable, Hashable {
    case easy
    case recovery
    case longRun
    case tempo
    case threshold
    case intervals
    case fartlek
    case hills
    case racePace
    case progression
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Easy Run"
        case .recovery: return "Recovery Run"
        case .longRun: return "Long Run"
        case .tempo: return "Tempo"
        case .threshold: return "Threshold"
        case .intervals: return "Intervals"
        case .fartlek: return "Fartlek"
        case .hills: return "Hill Repeats"
        case .racePace: return "Race Pace"
        case .progression: return "Progression Run"
        case .custom: return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .easy, .recovery: return "figure.run"
        case .longRun: return "road.lanes"
        case .tempo, .threshold, .racePace: return "speedometer"
        case .intervals: return "repeat"
        case .fartlek: return "waveform.path"
        case .hills: return "mountain.2.fill"
        case .progression: return "chart.line.uptrend.xyaxis"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum RunningBlockKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case warmup
    case work
    case recovery
    case steady
    case cooldown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmup: return "Warm-up"
        case .work: return "Work"
        case .recovery: return "Recovery"
        case .steady: return "Steady"
        case .cooldown: return "Cool-down"
        }
    }
}

enum RunningMeasureKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case distance
    case time
    case open

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return "Distance"
        case .time: return "Time"
        case .open: return "Open"
        }
    }
}

enum RunningIntensityKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case easy
    case pace
    case heartRateZone
    case rpe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No target"
        case .easy: return "Easy effort"
        case .pace: return "Pace"
        case .heartRateZone: return "Heart-rate zone"
        case .rpe: return "RPE"
        }
    }
}

struct RunningIntensityTarget: Codable, Hashable {
    var kind: RunningIntensityKind
    var paceMinSecondsPerKilometer: Double?
    var paceMaxSecondsPerKilometer: Double?
    var heartRateZone: Int?
    var rpe: Double?

    static let easy = RunningIntensityTarget(
        kind: .easy,
        paceMinSecondsPerKilometer: nil,
        paceMaxSecondsPerKilometer: nil,
        heartRateZone: nil,
        rpe: nil
    )

    static let none = RunningIntensityTarget(
        kind: .none,
        paceMinSecondsPerKilometer: nil,
        paceMaxSecondsPerKilometer: nil,
        heartRateZone: nil,
        rpe: nil
    )
}

struct RunningStepTarget: Codable, Hashable {
    var measure: RunningMeasureKind
    var distanceMeters: Double?
    var durationSeconds: TimeInterval?
    var intensity: RunningIntensityTarget

    static func distance(
        _ meters: Double,
        intensity: RunningIntensityTarget = .none
    ) -> RunningStepTarget {
        RunningStepTarget(
            measure: .distance,
            distanceMeters: meters,
            durationSeconds: nil,
            intensity: intensity
        )
    }

    static func time(
        _ seconds: TimeInterval,
        intensity: RunningIntensityTarget = .none
    ) -> RunningStepTarget {
        RunningStepTarget(
            measure: .time,
            distanceMeters: nil,
            durationSeconds: seconds,
            intensity: intensity
        )
    }

    static let open = RunningStepTarget(
        measure: .open,
        distanceMeters: nil,
        durationSeconds: nil,
        intensity: .none
    )
}

struct RunningWorkoutBlock: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: RunningBlockKind
    var title: String
    var repetitions: Int
    var work: RunningStepTarget
    var recovery: RunningStepTarget?
    var notes: String?

    init(
        id: UUID = UUID(),
        kind: RunningBlockKind,
        title: String,
        repetitions: Int = 1,
        work: RunningStepTarget,
        recovery: RunningStepTarget? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.repetitions = repetitions
        self.work = work
        self.recovery = recovery
        self.notes = notes
    }
}

struct RunningWorkoutTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var type: RunningWorkoutType
    var summary: String
    var blocks: [RunningWorkoutBlock]
    var routeID: UUID?
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    var estimatedDistanceMeters: Double? {
        let values = blocks.compactMap { block -> Double? in
            guard block.work.measure == .distance,
                  let workDistance = block.work.distanceMeters
            else {
                return nil
            }

            let recoveryDistance: Double
            if let recovery = block.recovery,
               recovery.measure == .distance {
                recoveryDistance = recovery.distanceMeters ?? 0
            } else {
                recoveryDistance = 0
            }

            return (
                workDistance * Double(max(block.repetitions, 1))
            ) + (
                recoveryDistance * Double(max(block.repetitions - 1, 0))
            )
        }

        guard values.count == blocks.count else { return nil }
        return values.reduce(0, +)
    }
}

enum ExerciseLibrarySource: String, Codable, Hashable {
    case repDB
    case custom
}

struct ExerciseLibraryEntry: Identifiable, Hashable {
    let id: UUID
    let exercise: Exercise
    let source: ExerciseLibrarySource
    let sourceIdentifier: String?
    let summary: String?
    let tips: [String]
    let category: String?
    let difficulty: String?
    let bodyPart: String?
    let imageStartURL: URL?
    let imagePeakURL: URL?

    var name: String { exercise.name }
}
