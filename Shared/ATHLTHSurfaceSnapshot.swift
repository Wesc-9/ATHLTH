import Foundation

struct ATHLTHSurfaceSnapshot: Codable, Equatable {
    var recoveryScore: Int?
    var recoveryState: String
    var nextWorkoutTitle: String?
    var nextWorkoutDate: Date?
    var primaryGoalTitle: String?
    var primaryGoalProgress: Double?
    var activeWorkout: ATHLTHSurfaceWorkoutSnapshot?
    // Durable, account-scoped presentation tombstone. Never stores health
    // samples or a second workout recording; legacy snapshots decode nil.
    var lastFinishedWorkout: ATHLTHSurfaceWorkoutTerminalMarker? = nil
    // A single terminal marker is insufficient after multiple workouts:
    // an old delayed Watch packet can otherwise resurrect session N-1.
    // Optional to decode existing app-group snapshots without migration.
    var recentFinishedWorkouts: [ATHLTHSurfaceWorkoutTerminalMarker]? = nil
    var updatedAt: Date

    static let empty = ATHLTHSurfaceSnapshot(
        recoveryScore: nil,
        recoveryState: "Open ATHLTH",
        nextWorkoutTitle: nil,
        nextWorkoutDate: nil,
        primaryGoalTitle: nil,
        primaryGoalProgress: nil,
        activeWorkout: nil,
        updatedAt: .distantPast
    )
}

struct ATHLTHSurfaceWorkoutSnapshot: Codable, Equatable {
    var title: String
    var systemImage: String
    var state: String
    var startedAt: Date?
    var elapsedTime: TimeInterval
    var distanceMeters: Double
    var heartRate: Double
    var updatedAt: Date
    // Optional for old cached iPhone/iPad widget snapshots.
    var currentStep: String? = nil
    var nextStep: String? = nil
    var runningIntervalOrdinal: Int? = nil
    var runningIntervalTotal: Int? = nil
    var runningInRecovery: Bool? = nil
    var runningStepRemainingSeconds: TimeInterval? = nil
    // Additive so old app-group snapshots remain decodable on upgrade.
    var strengthRestEndsAt: Date? = nil
    var strengthSetIndex: Int? = nil
    var strengthSetCount: Int? = nil
}

/// Only the session identifier needed to stop late Watch/relay telemetry
/// from resurrecting a previously finished widget workout.
struct ATHLTHSurfaceWorkoutTerminalMarker: Codable, Equatable {
    let systemImage: String
    let startedAt: Date?
    let fallbackTitle: String
    let finishedAt: Date

    init(workout: ATHLTHSurfaceWorkoutSnapshot, finishedAt: Date) {
        systemImage = workout.systemImage
        startedAt = workout.startedAt
        fallbackTitle = workout.title
        self.finishedAt = finishedAt
    }
}

enum ATHLTHSurfaceWorkoutOrdering {
    static let maximumRecentFinished = 12

    /// A bounded history protects older terminal sessions after the user
    /// has started and stopped more than one recording on this account.
    static func rememberFinished(
        _ finished: ATHLTHSurfaceWorkoutTerminalMarker,
        in snapshot: inout ATHLTHSurfaceSnapshot
    ) {
        var entries = snapshot.recentFinishedWorkouts ?? []
        if let previous = snapshot.lastFinishedWorkout,
           !entries.contains(previous) {
            entries.append(previous)
        }
        if !entries.contains(finished) {
            entries.append(finished)
        }
        entries.sort { $0.finishedAt > $1.finishedAt }
        snapshot.recentFinishedWorkouts = Array(
            entries.prefix(maximumRecentFinished)
        )
        if snapshot.lastFinishedWorkout.map({
            finished.finishedAt >= $0.finishedAt
        }) ?? true {
            snapshot.lastFinishedWorkout = finished
        }
    }

    static func matchesAnyFinished(
        _ workout: ATHLTHSurfaceWorkoutSnapshot,
        in snapshot: ATHLTHSurfaceSnapshot
    ) -> Bool {
        matchesTerminal(workout, marker: snapshot.lastFinishedWorkout) ||
            (snapshot.recentFinishedWorkouts ?? []).contains {
                matchesTerminal(workout, marker: $0)
            }
    }

    static func sameSession(
        _ lhs: ATHLTHSurfaceWorkoutSnapshot,
        _ rhs: ATHLTHSurfaceWorkoutSnapshot
    ) -> Bool {
        guard lhs.systemImage == rhs.systemImage else { return false }
        switch (lhs.startedAt, rhs.startedAt) {
        case let (one?, two?):
            return abs(one.timeIntervalSince(two)) < 2
        case (nil, nil):
            return lhs.title == rhs.title
        default:
            return false
        }
    }

    static func matchesTerminal(
        _ workout: ATHLTHSurfaceWorkoutSnapshot,
        marker: ATHLTHSurfaceWorkoutTerminalMarker?
    ) -> Bool {
        guard let marker,
              workout.systemImage == marker.systemImage else { return false }
        switch (workout.startedAt, marker.startedAt) {
        case let (one?, two?):
            return abs(one.timeIntervalSince(two)) < 2
        case (nil, nil):
            return workout.title == marker.fallbackTitle
        default:
            return false
        }
    }

    /// The widgets and spectator iPad must respect the same record clock as
    /// Live Activity. Neither equal/older samples nor older sessions may
    /// rewind a newer workout, and a closed session cannot reappear.
    static func accepts(
        incoming: ATHLTHSurfaceWorkoutSnapshot,
        current: ATHLTHSurfaceWorkoutSnapshot?,
        terminal: ATHLTHSurfaceWorkoutTerminalMarker?,
        recentFinished: [ATHLTHSurfaceWorkoutTerminalMarker] = [],
        now: Date = Date()
    ) -> Bool {
        let timestamp = incoming.updatedAt.timeIntervalSince1970
        guard timestamp.isFinite,
              now.timeIntervalSince(incoming.updatedAt) >= -10,
              !matchesTerminal(incoming, marker: terminal),
              !recentFinished.contains(where: {
                  matchesTerminal(incoming, marker: $0)
              })
        else { return false }
        guard let current else { return true }
        if sameSession(current, incoming) {
            return incoming.updatedAt >= current.updatedAt
        }
        // Different workouts are ordered by their actual start, not message
        // arrival time. An old terminal packet must not hide a new workout.
        if let previousStart = current.startedAt,
           let incomingStart = incoming.startedAt {
            return incomingStart > previousStart
        }
        return false
    }
}

enum ATHLTHSurfaceSharedStore {
    static let appGroupIdentifier = "group.com.wesc9.athlth"
    static let snapshotKey = "athlth.surface.snapshot.v1"

    static func load() -> ATHLTHSurfaceSnapshot {
        guard let defaults = UserDefaults(
            suiteName: appGroupIdentifier
        ),
        let data = defaults.data(forKey: snapshotKey),
        let decoded = try? JSONDecoder().decode(
            ATHLTHSurfaceSnapshot.self,
            from: data
        ) else {
            return .empty
        }

        return decoded
    }

    static func save(_ snapshot: ATHLTHSurfaceSnapshot) {
        guard let defaults = UserDefaults(
            suiteName: appGroupIdentifier
        ),
        let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
    }
}
