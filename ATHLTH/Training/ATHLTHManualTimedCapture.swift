import Foundation

/// A real iPhone wall-clock timer, not a GPS, heart-rate or HealthKit workout.
/// The original CustomQuickWorkoutJournal remains the ONE finished-history
/// source for every custom activity. This checkpoint protects an unfinished
/// timer across ordinary scene/process restoration without creating a second
/// recorded workout or changing the existing HealthKit owner.
struct ATHLTHManualTimedCheckpoint: Codable, Equatable {
    let id: UUID
    let userID: UUID
    let activity: CustomQuickWorkoutActivity
    let method: CustomQuickWorkoutMethod
    let startedAt: Date
    let durationMinutes: Int
    let workSeconds: Int
    let restSeconds: Int
    let rounds: Int
    let titleOverride: String?
    var accumulatedSeconds: TimeInterval
    var resumedAt: Date?
    var approvedTimeLimit: TimeInterval

    /// Reopen a stopped/recovered timer with the originally selected workout
    /// method. Do not use new default rounds, interval lengths or a new title.
    /// Do not restore social invitations or change Audio Coach automatically.
    var recoveryConfiguration: CustomQuickWorkoutConfiguration {
        CustomQuickWorkoutConfiguration(
            activity: activity, method: method,
            durationMinutes: durationMinutes,
            workSeconds: workSeconds, restSeconds: restSeconds,
            rounds: rounds, titleOverride: titleOverride
        )
    }

    func elapsed(at date: Date) -> TimeInterval {
        min(approvedTimeLimit, accumulatedSeconds + (
            resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        ))
    }

    var isValid: Bool {
        startedAt.timeIntervalSince1970.isFinite &&
            (1...720).contains(durationMinutes) &&
            (1...900).contains(workSeconds) &&
            (0...900).contains(restSeconds) &&
            (1...100).contains(rounds) &&
            accumulatedSeconds.isFinite && accumulatedSeconds >= 0 &&
            accumulatedSeconds <= 24 * 60 * 60 &&
            approvedTimeLimit.isFinite && approvedTimeLimit > 0 &&
            approvedTimeLimit <= 24 * 60 * 60 &&
            resumedAt.map { $0.timeIntervalSince1970.isFinite } ?? true
    }
}

/// Main-actor ownership extends the existing universal recording admission
/// to phone-timed cycling/yoga/mobility/other modes. No HKWorkoutSession is
/// opened; the saved provenance is always "iPhone-timed / manual metrics".
/// Account-scoped checkpoints are NOT silently deleted on a crash or logout.
@MainActor
enum ATHLTHManualTimedCapture {
    enum CaptureError: LocalizedError {
        case anotherWorkoutActive
        case unreadableCheckpoint
        case checkpointNotSaved

        var errorDescription: String? {
            switch self {
            case .anotherWorkoutActive:
                return ATHLTHLocalization.choose(
                    english: "Another workout is active. Finish or restore it first.",
                    norwegian: "En annen økt pågår. Fullfør eller gjenopprett den først."
                )
            case .unreadableCheckpoint:
                return ATHLTHLocalization.choose(
                    english: "The previous timer checkpoint cannot be read. It has not been overwritten.",
                    norwegian: "Forrige tidscheckpoint kan ikke leses. Det er ikke overskrevet."
                )
            case .checkpointNotSaved:
                return ATHLTHLocalization.choose(
                    english: "The workout timer could not be saved on this device. Try again.",
                    norwegian: "Tidtakeren kunne ikke lagres på enheten. Prøv igjen."
                )
            }
        }
    }

    private static let name = "manualTimedActiveV1"
    private static var active: ATHLTHManualTimedCheckpoint?
    private static var blockedUnreadableOwner: UUID?

    static var hasActiveCapture: Bool {
        active != nil || blockedUnreadableOwner != nil
    }

    static func current(for userID: UUID) -> ATHLTHManualTimedCheckpoint? {
        guard active?.userID == userID else { return nil }
        return active
    }

    /// Called on verified account activation, not on each SwiftUI render.
    /// A different account never inherits the previous timer's ID/state.
    @discardableResult
    static func switchAccount(
        _ userID: UUID?,
        defaults: UserDefaults = .standard
    ) -> ATHLTHManualTimedCheckpoint? {
        active = nil
        blockedUnreadableOwner = nil
        guard let userID else { return nil }
        let key = AccountLocalStorage.key(name, userID: userID)
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(
            ATHLTHManualTimedCheckpoint.self, from: data
        ), snapshot.userID == userID, snapshot.isValid else {
            // Fail closed. Do not replace unknown/newer schema with empty data.
            blockedUnreadableOwner = userID
            return nil
        }
        active = snapshot
        return snapshot
    }

    static func beginOrResume(
        configuration: CustomQuickWorkoutConfiguration,
        userID: UUID,
        at now: Date = Date(),
        defaults: UserDefaults = .standard
    ) throws -> ATHLTHManualTimedCheckpoint {
        if let active {
            guard active.userID == userID &&
                    active.activity == configuration.activity &&
                    active.method == configuration.method else {
                throw CaptureError.anotherWorkoutActive
            }
            return active
        }
        guard blockedUnreadableOwner == nil else {
            throw CaptureError.unreadableCheckpoint
        }
        let key = AccountLocalStorage.key(name, userID: userID)
        if defaults.data(forKey: key) != nil {
            // In case account restoration has not run yet, restore rather
            // than creating a new ID on top of an existing checkpoint.
            _ = switchAccount(userID, defaults: defaults)
            return try beginOrResume(
                configuration: configuration, userID: userID,
                at: now, defaults: defaults
            )
        }

        let reservation = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
        defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(reservation) }
        let snapshot = ATHLTHManualTimedCheckpoint(
            id: UUID(), userID: userID,
            activity: configuration.activity, method: configuration.method,
            startedAt: now,
            durationMinutes: max(1, min(720, configuration.durationMinutes)),
            workSeconds: max(1, min(900, configuration.workSeconds)),
            restSeconds: max(0, min(900, configuration.restSeconds)),
            rounds: max(1, min(100, configuration.rounds)),
            titleOverride: configuration.titleOverride,
            accumulatedSeconds: 0,
            resumedAt: now, approvedTimeLimit: 5 * 3600
        )
        guard commit(snapshot, defaults: defaults) else {
            throw CaptureError.checkpointNotSaved
        }
        return snapshot
    }

    /// Pause, resume and cap changes become visible only after a successful
    /// checkpoint. A failed write never silently "commits" the in-memory view.
    @discardableResult
    static func update(
        id: UUID, userID: UUID,
        accumulatedSeconds: TimeInterval,
        resumedAt: Date?,
        approvedTimeLimit: TimeInterval,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let previous = current(for: userID),
              previous.id == id else { return false }
        var updated = previous
        updated.accumulatedSeconds = accumulatedSeconds
        updated.resumedAt = resumedAt
        updated.approvedTimeLimit = approvedTimeLimit
        return commit(updated, defaults: defaults)
    }

    /// Finish only after the canonical manual record has been durably
    /// acknowledged. A failed cleanup keeps the original checkpoint so the
    /// athlete can retry without manufacturing a second history ID.
    @discardableResult
    static func closeAfterSavedRecord(
        id: UUID, userID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard current(for: userID)?.id == id else { return false }
        return remove(id: id, userID: userID, defaults: defaults)
    }

    /// Explicit Discard is the ONLY other path that clears an unfinished
    /// phone timer. Background, sheet dismissal and logout preserve it.
    @discardableResult
    static func discard(
        id: UUID, userID: UUID, defaults: UserDefaults = .standard
    ) -> Bool {
        guard current(for: userID)?.id == id else { return false }
        return remove(id: id, userID: userID, defaults: defaults)
    }

    private static func remove(
        id: UUID, userID: UUID, defaults: UserDefaults
    ) -> Bool {
        guard active?.id == id && active?.userID == userID else {
            return false
        }
        let key = AccountLocalStorage.key(name, userID: userID)
        defaults.removeObject(forKey: key)
        guard defaults.data(forKey: key) == nil else { return false }
        active = nil
        return true
    }

    private static func commit(
        _ snapshot: ATHLTHManualTimedCheckpoint,
        defaults: UserDefaults
    ) -> Bool {
        guard snapshot.isValid,
              blockedUnreadableOwner == nil,
              active == nil ||
                (active?.id == snapshot.id &&
                 active?.userID == snapshot.userID) else { return false }
        do {
            try AccountLocalStorage.writeChecked(
                snapshot, name: name,
                userID: snapshot.userID, defaults: defaults
            )
            guard AccountLocalStorage.read(
                ATHLTHManualTimedCheckpoint.self,
                name: name, userID: snapshot.userID, defaults: defaults
            ) == snapshot else { return false }
            active = snapshot
            return true
        } catch {
            return false
        }
    }
}
