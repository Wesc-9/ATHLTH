import Foundation

/// Structured iPhone work already has an authoritative per-workout
/// checkpoint and completion journal. This admission index only reserves
/// the existing universal recording slot; it never records a second workout,
/// changes HealthKit ownership or rewrites a planned recipe.
@MainActor
enum ATHLTHStructuredCaptureAdmission {
    private static var owner: UUID?
    private(set) static var activeWorkoutID: UUID?
    private static var unresolvedCheckpoint = false

    static var hasActiveCapture: Bool {
        activeWorkoutID != nil || unresolvedCheckpoint
    }

    /// Recover the existing structured checkpoint names for this account.
    /// Reject ambiguous or unreadable checkpoints instead of starting another
    /// recording or silently replacing unknown future-version data.
    static func switchAccount(
        _ accountID: UUID?,
        defaults: UserDefaults = .standard
    ) {
        owner = accountID
        activeWorkoutID = nil
        unresolvedCheckpoint = false
        guard let accountID else { return }
        let prefix = AccountLocalStorage.key(
            "structuredWorkoutInProgress.v1.", userID: accountID
        )
        var candidate: UUID?
        for (key, raw) in defaults.dictionaryRepresentation()
            where key.hasPrefix(prefix) {
            guard let data = raw as? Data,
                  let id = UUID(uuidString: String(key.dropFirst(prefix.count))),
                  let checkpoint = try? JSONDecoder().decode(
                    ATHLTHStructuredWorkoutCheckpoint.self, from: data
                  ), checkpoint.workoutID == id,
                  checkpoint.startedAt.timeIntervalSince1970.isFinite,
                  checkpoint.savedAt.timeIntervalSince1970.isFinite,
                  checkpoint.savedAt <= Date().addingTimeInterval(3600),
                  checkpoint.savedAt > Date().addingTimeInterval(-7 * 86_400),
                  checkpoint.executionBlocks.indices.contains(
                    checkpoint.currentIndex
                  ) else {
                unresolvedCheckpoint = true
                continue
            }
            if candidate != nil && candidate != id {
                unresolvedCheckpoint = true
            }
            candidate = id
        }
        activeWorkoutID = candidate
    }

    static func admit(workoutID: UUID, userID: UUID) throws {
        if owner == userID && activeWorkoutID == workoutID &&
           !unresolvedCheckpoint { return }
        guard owner == userID, !hasActiveCapture else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        let reservation = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
        defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(reservation) }
        activeWorkoutID = workoutID
    }

    /// Only a confirmed deleted completion/discard checkpoint may release
    /// the slot. A minimized screen continues to be an active session.
    static func release(workoutID: UUID, userID: UUID) {
        guard owner == userID,
              activeWorkoutID == workoutID else { return }
        activeWorkoutID = nil
    }
}
