import Foundation

/// Actual per-effort speeds, stored only for a completely finished recording.
/// Never use planned target pace as proof of a performed result.
struct ATHLTHCompletedRunningPerformance: Identifiable, Codable, Hashable {
    let id: UUID
    let workoutID: UUID?
    let title: String
    let completedAt: Date
    let source: String
    let steps: [ATHLTHRecordedRunningStep]
    var minutes: [ATHLTHRecordedRunningMinute]? = nil
    /// Link to the HealthKit activity shown in the actual post-run detail.
    var healthWorkoutUUID: UUID? = nil

    var workSteps: [ATHLTHRecordedRunningStep] {
        steps.filter { !["warmup", "cooldown", "recovery", "rest"]
            .contains(($0.phase ?? "main").lowercased()) }
    }

    var averageWorkSpeed: Double? {
        let measured = workSteps.filter { $0.actualSpeedKilometersPerHour != nil }
        let elapsed = measured.reduce(0.0) { $0 + $1.activeSeconds }
        guard elapsed > 0 else { return nil }
        let meters = measured.reduce(0.0) { $0 + $1.distanceMeters }
        let speed = meters * 3.6 / elapsed
        return speed.isFinite && speed > 0 ? speed : nil
    }

    var userReported: Bool { workSteps.contains { $0.isUserReported } }

    static func validFullRecording(
        _ steps: [ATHLTHRecordedRunningStep],
        expectedCount: Int
    ) -> Bool {
        guard expectedCount > 0,
              steps.count == expectedCount,
              Set(steps.map(\.index)) == Set(0..<expectedCount),
              steps.allSatisfy({
                  $0.activeSeconds >= 10 && $0.activeSeconds.isFinite &&
                  $0.distanceMeters >= 0 && $0.distanceMeters.isFinite
              })
        else { return false }
        return steps.contains {
            !["warmup", "cooldown", "recovery", "rest"]
                .contains(($0.phase ?? "main").lowercased()) &&
                $0.actualSpeedKilometersPerHour != nil
        }
    }

    init?(phone: PhoneWorkout) {
        guard let finished = phone.end,
              phone.structuredWorkoutComplete == true,
              let recipe = phone.structuredRunningWorkout,
              let recorded = phone.recordedRunningSteps,
              Self.validFullRecording(recorded, expectedCount: recipe.steps.count)
        else { return nil }
        id = phone.id
        workoutID = phone.plannedSessionID ?? recipe.sourceWorkoutID
        // The structured recipe is more informative than a generic
        // environment label such as "Tredemølle". Preserve custom titles.
        let recordedTitle = phone.workoutTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = ["tredemølle", "treadmill", "løping innendørs",
                       "indoor running", "løping", "running"]
        if let recordedTitle, !recordedTitle.isEmpty,
           !generic.contains(recordedTitle.lowercased()) {
            title = recordedTitle
        } else {
            title = recipe.title
        }
        completedAt = finished
        source = "iPhone"
        steps = recorded
        minutes = phone.recordedRunningMinutes
        healthWorkoutUUID = phone.healthID
    }

    init?(watch: WatchWorkoutResult) {
        let recorded = watch.recordedRunningSteps ?? []
        let fullyStructured = watch.structuredWorkoutFullyCompleted == true &&
            Self.validFullRecording(recorded, expectedCount: recorded.count)
        // Untrusted or partially transferred Watch minute evidence cannot
        // create a fake performance record with infinite speed or distance.
        let verifiedMinutes = (watch.recordedRunningMinutes ?? []).filter {
            $0.stepIndex >= 0 &&
            $0.stepElapsedAtEndSeconds.isFinite &&
            $0.stepElapsedAtEndSeconds >= 0 &&
            $0.activeSeconds.isFinite &&
            $0.activeSeconds > 0 &&
            $0.recordedDistanceMeters.isFinite &&
            $0.recordedDistanceMeters > 0
        }
        let hasMeasuredMinutes = !verifiedMinutes.isEmpty
        guard (watch.kind == .running || watch.kind == .walking),
              watch.startedAt.timeIntervalSince1970.isFinite,
              watch.endedAt.timeIntervalSince1970.isFinite,
              watch.endedAt >= watch.startedAt,
              watch.duration.isFinite, watch.duration > 0,
              fullyStructured || hasMeasuredMinutes else { return nil }
        id = watch.id
        workoutID = watch.structuredWorkoutSourceID
        let fallbackTitle = watch.kind == .walking ? "Gåtur" : "Løpeøkt"
        title = ATHLTHRunningResultPresentation.titleForRun(
            watch.structuredWorkoutTitle ?? fallbackTitle,
            fallback: fallbackTitle
        )
        completedAt = watch.endedAt
        source = "Apple Watch"
        // A minute-only recovery is valuable evidence of a genuine run,
        // but a partial interval transfer is not proof the interval plan
        // was completed. Do not promote its incomplete steps to a PR.
        steps = fullyStructured ? recorded : []
        minutes = verifiedMinutes.isEmpty ? nil : verifiedMinutes
        healthWorkoutUUID = watch.healthKitWorkoutUUID
    }
}

/// A consumed Watch result remains available for the athlete's progression.
/// Account scoping, stable result IDs and known workout IDs prevent duplicates
/// and cross-account attribution.
enum ATHLTHRunningPerformanceHistory {
    private static let name = "completedRunningPerformance"

    /// Match HealthKit activity identity first. A unique close completion
    /// match recovers legitimate older exports with a different local UUID,
    /// but never guesses when two sessions fall in the same time window.
    static func match(
        workoutID: UUID,
        endDate: Date,
        duration: TimeInterval,
        candidates: [ATHLTHCompletedRunningPerformance]
    ) -> ATHLTHCompletedRunningPerformance? {
        var byID: [UUID: ATHLTHCompletedRunningPerformance] = [:]
        var conflictingLocalIDs: Set<UUID> = []
        for candidate in candidates {
            if let existing = byID[candidate.id] {
                if let previousHealth = existing.healthWorkoutUUID,
                   let incomingHealth = candidate.healthWorkoutUUID,
                   previousHealth != incomingHealth {
                    // Conflicting persisted identities are never resolved
                    // by choosing the most recent or first duplicate.
                    conflictingLocalIDs.insert(candidate.id)
                } else if existing.healthWorkoutUUID == nil &&
                          candidate.healthWorkoutUUID != nil {
                    // A later HealthKit backfill supersedes the same
                    // unlinked local snapshot.
                    byID[candidate.id] = candidate
                }
            } else {
                byID[candidate.id] = candidate
            }
        }
        let unique = byID.values.filter {
            !conflictingLocalIDs.contains($0.id)
        }

        // HealthKit identity is authoritative. If multiple local IDs claim
        // the same saved HealthKit recording, do not guess which is correct.
        let healthMatches = unique.filter { $0.healthWorkoutUUID == workoutID }
        if !healthMatches.isEmpty {
            return healthMatches.count == 1 ? healthMatches[0] : nil
        }
        if let local = unique.first(where: { $0.id == workoutID }) {
            return local
        }
        guard duration.isFinite, duration > 0,
              endDate.timeIntervalSince1970.isFinite else { return nil }

        // Timestamp-based matching is a legacy recovery route ONLY for
        // records that have never acquired a HealthKit identity. A different
        // explicit UUID is decisive evidence of a different recording.
        let matches = unique.filter { candidate in
            guard candidate.healthWorkoutUUID == nil,
                  candidate.completedAt.timeIntervalSince1970.isFinite,
                  abs(candidate.completedAt.timeIntervalSince(endDate)) <= 75
            else { return false }
            let elapsed = candidate.steps.reduce(0.0) {
                $0 + $1.activeSeconds
            }
            return elapsed.isFinite && elapsed > 0 &&
                abs(elapsed - duration) <= max(20, duration * 0.07)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// One HealthKit workout belongs to one local progression result.
    /// Preserve verified UUIDs across delayed phone/Watch callbacks.
    static func reconciledRecord(
        _ incoming: ATHLTHCompletedRunningPerformance,
        with existing: [ATHLTHCompletedRunningPerformance]
    ) -> ATHLTHCompletedRunningPerformance? {
        var result = incoming
        if let previous = existing.first(where: { $0.id == incoming.id }),
           let saved = previous.healthWorkoutUUID {
            if let newLink = incoming.healthWorkoutUUID, newLink != saved {
                return nil
            }
            result.healthWorkoutUUID = saved
        }
        if let linked = result.healthWorkoutUUID,
           existing.contains(where: {
               $0.id != result.id && $0.healthWorkoutUUID == linked
           }) {
            return nil
        }
        return result
    }

    static func load(userID: UUID) -> [ATHLTHCompletedRunningPerformance] {
        AccountLocalStorage.read(
            [ATHLTHCompletedRunningPerformance].self, name: name, userID: userID
        ) ?? []
    }

    /// Phone-only structured runs must feed the same account-scoped personal
    /// performance view as Watch runs, without requiring a HealthKit export.
    /// Idempotent by the original workout id; a later HealthKit save may add
    /// its UUID and should replace the older local snapshot.
    /// Recover earlier phone sessions when the record feature is upgraded.
    /// Runs once per account activation and only writes when new records
    /// actually exist. Never recalculate an unfinished session as a PR.
    static func backfillPhoneHistory(
        _ completed: [PhoneWorkout], userID: UUID
    ) {
        var stored = load(userID: userID)
        var byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { previous, next in
            // Old imported duplicates must never crash account activation.
            if previous.healthWorkoutUUID != nil && next.healthWorkoutUUID == nil { return previous }
            if next.healthWorkoutUUID != nil && previous.healthWorkoutUUID == nil { return next }
            return previous.completedAt >= next.completedAt ? previous : next
        })
        var changed = false
        for workout in completed {
            guard let proposed = ATHLTHCompletedRunningPerformance(phone: workout),
                  let record = reconciledRecord(
                      proposed, with: Array(byID.values)
                  )
            else { continue }
            if byID[record.id] != record {
                byID[record.id] = record
                changed = true
            }
        }
        guard changed else { return }
        stored = byID.values.sorted { $0.completedAt > $1.completedAt }
        if stored.count > 300 { stored = Array(stored.prefix(300)) }
        AccountLocalStorage.write(stored, name: name, userID: userID)
        ATHLTHTrainingDataChangeSignal.post(userID: userID)
    }

    static func savePhone(_ completed: PhoneWorkout, userID: UUID) {
        guard let proposed = ATHLTHCompletedRunningPerformance(phone: completed)
        else { return }
        var history = load(userID: userID)
        guard let record = reconciledRecord(proposed, with: history)
        else { return }
        if let index = history.firstIndex(where: { $0.id == record.id }) {
            if history[index] == record { return }
            history[index] = record
        } else {
            history.insert(record, at: 0)
        }
        history.sort { $0.completedAt > $1.completedAt }
        if history.count > 300 { history = Array(history.prefix(300)) }
        AccountLocalStorage.write(history, name: name, userID: userID)
        ATHLTHTrainingDataChangeSignal.post(userID: userID)
    }

    static func saveWatch(
        _ result: WatchWorkoutResult,
        userID: UUID,
        knownWorkoutIDs: Set<UUID>,
        knownHealthWorkoutIDs: Set<UUID> = []
    ) {
        guard let record = ATHLTHCompletedRunningPerformance(watch: result)
        else { return }
        let recognizedPlan = record.workoutID.map { knownWorkoutIDs.contains($0) } ?? false
        let recognizedHealth = record.healthWorkoutUUID.map {
            knownHealthWorkoutIDs.contains($0)
        } ?? false
        guard recognizedPlan || recognizedHealth else { return }
        var history = load(userID: userID)
        // A late HealthKit export may add the UUID; a delayed packet must
        // never erase it or create another result for the same recording.
        guard let record = reconciledRecord(record, with: history)
        else { return }
        if let index = history.firstIndex(where: { $0.id == record.id }) {
            if history[index] == record { return }
            history[index] = record
        } else {
            history.insert(record, at: 0)
        }
        history.sort { $0.completedAt > $1.completedAt }
        if history.count > 300 { history = Array(history.prefix(300)) }
        AccountLocalStorage.write(history, name: name, userID: userID)
        ATHLTHTrainingDataChangeSignal.post(userID: userID)
    }
}

/// Post-run presentation rules. Watch may publish one recorded running step
/// for a normal unstructured run; that is not an interval session.
enum ATHLTHRunningResultPresentation {
    static func hasDetailedPhases(_ performance: ATHLTHCompletedRunningPerformance) -> Bool {
        let recorded = performance.steps.filter {
            $0.activeSeconds.isFinite && $0.activeSeconds >= 10
        }
        guard recorded.count > 1 else { return false }
        if performance.workSteps.count > 1 { return true }
        return recorded.contains {
            ["warmup", "cooldown", "recovery", "rest"].contains(
                ($0.phase ?? "main").lowercased()
            )
        }
    }

    /// Legacy watch titles can describe a different workout category, while
    /// HealthKit's activity is running. Never label a run as strength training.
    static func titleForRun(_ title: String, fallback: String) -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let strengthOnly: Set<String> = [
            "styrke", "styrkeøkt", "styrketrening",
            "strength", "strength training", "strength workout",
            "functional strength training", "tradisjonell styrketrening"
        ]
        guard !normalized.isEmpty,
              !strengthOnly.contains(normalized.lowercased())
        else { return fallback }
        return normalized
    }
}
