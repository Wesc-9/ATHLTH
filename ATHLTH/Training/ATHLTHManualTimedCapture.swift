import Foundation
@preconcurrency import HealthKit

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
    private static var sensorCapture: AnyObject?
    private static var sensorDeadline: Task<Void, Never>?

    @available(iOS 26.0, *)
    private static var nativeSensor: ATHLTHPhoneLiveSensorCapture? {
        sensorCapture as? ATHLTHPhoneLiveSensorCapture
    }

    private static func discardSensor() {
        sensorDeadline?.cancel()
        sensorDeadline = nil
        if #available(iOS 26.0, *) { nativeSensor?.discard() }
        sensorCapture = nil
    }

    private static func startSensor(for snapshot: ATHLTHManualTimedCheckpoint) {
        guard #available(iOS 26.0, *), snapshot.activity == .sports,
              UserDefaults.standard.bool(forKey: "athlth.airpods.liveSensorPilot"),
              UserDefaults.standard.object(forKey: "settings.appleHealthIntegrationEnabled") as? Bool ?? true,
              HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        let capture = ATHLTHPhoneLiveSensorCapture(workoutID: snapshot.id, startedAt: snapshot.startedAt)
        sensorCapture = capture
        capture.start(store: store, configuration: config)
        updateSensor(for: snapshot)
    }

    private static func updateSensor(for snapshot: ATHLTHManualTimedCheckpoint) {
        sensorDeadline?.cancel()
        sensorDeadline = nil
        guard #available(iOS 26.0, *), let sensor = nativeSensor,
              sensor.workoutID == snapshot.id else { return }
        let remaining = snapshot.approvedTimeLimit - snapshot.elapsed(at: Date())
        sensor.setPaused(snapshot.resumedAt == nil || remaining <= 0)
        guard snapshot.resumedAt != nil, remaining > 0 else { return }
        sensorDeadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard !Task.isCancelled, active?.id == snapshot.id, active?.userID == snapshot.userID,
                  nativeSensor?.workoutID == snapshot.id else { return }
            nativeSensor?.setPaused(true)
        }
    }

    static func freshSensorPulse(id: UUID, userID: UUID, at now: Date) -> Double? {
        guard #available(iOS 26.0, *), let checkpoint = current(for: userID),
              checkpoint.id == id, checkpoint.resumedAt != nil,
              checkpoint.elapsed(at: now) < checkpoint.approvedTimeLimit,
              UserDefaults.standard.object(forKey: "settings.appleHealthIntegrationEnabled") as? Bool ?? true,
              nativeSensor?.workoutID == id else { return nil }
        return nativeSensor?.freshHeartRate(at: now)
    }

    static func sensorSummary(id: UUID, userID: UUID) -> CustomQuickMeasuredSensorMetrics? {
        guard #available(iOS 26.0, *), current(for: userID)?.id == id,
              UserDefaults.standard.object(forKey: "settings.appleHealthIntegrationEnabled") as? Bool ?? true,
              let sensor = nativeSensor, sensor.workoutID == id else { return nil }
        let totals = sensor.summary()
        return CustomQuickMeasuredSensorMetrics.make(activeCalories: totals.activeCalories,
            averageHeartRate: totals.averageHeartRate, maxHeartRate: totals.maxHeartRate)
    }

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
        discardSensor()
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
                    active.method == configuration.method &&
                    active.durationMinutes == max(1, min(720, configuration.durationMinutes)) &&
                    active.workSeconds == max(1, min(900, configuration.workSeconds)) &&
                    active.restSeconds == max(0, min(900, configuration.restSeconds)) &&
                    active.rounds == max(1, min(100, configuration.rounds)) &&
                    active.titleOverride == configuration.titleOverride else {
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
        if defaults === UserDefaults.standard { startSensor(for: snapshot) }
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

        // Pause/resume is authorized by the SAME lifecycle policy as the
        // measured iPhone and structured recorders. Changing the time cap
        // without switching running state is only a checkpoint update.
        if (previous.resumedAt == nil) != (resumedAt == nil) {
            let command: ATHLTHUniversalWorkoutCommand =
                resumedAt == nil ? .pause : .resume
            let phase: ATHLTHWorkoutSessionPhase =
                previous.resumedAt == nil ? .paused : .work
            guard ATHLTHUniversalWorkoutLifecycle.nextPhase(
                for: command, workoutID: previous.id,
                expectedWorkoutID: id, source: .manualTimer,
                recordingOwner: .iPhone, phase: phase
            ) != nil else { return false }
        }

        var updated = previous
        updated.accumulatedSeconds = accumulatedSeconds
        updated.resumedAt = resumedAt
        updated.approvedTimeLimit = approvedTimeLimit
        guard commit(updated, defaults: defaults) else { return false }
        updateSensor(for: updated)
        return true
    }

    /// Finish only after the canonical manual record has been durably
    /// acknowledged. A failed cleanup keeps the original checkpoint so the
    /// athlete can retry without manufacturing a second history ID.
    @discardableResult
    static func closeAfterSavedRecord(
        id: UUID, userID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let checkpoint = current(for: userID),
              checkpoint.id == id,
              ATHLTHUniversalWorkoutLifecycle.nextPhase(
                  for: .finish, workoutID: checkpoint.id,
                  expectedWorkoutID: id, source: .manualTimer,
                  recordingOwner: .iPhone,
                  phase: checkpoint.resumedAt == nil ? .paused : .work
              ) != nil else { return false }
        // The saved CustomQuickWorkoutJournal is still the one original
        // finished record. This clears only its already-saved live timer.
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
        discardSensor()
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
