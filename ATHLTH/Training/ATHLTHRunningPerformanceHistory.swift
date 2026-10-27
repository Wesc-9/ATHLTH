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
        let hasMeasuredMinutes = (watch.recordedRunningMinutes ?? []).contains {
            $0.activeSeconds > 0 && $0.recordedDistanceMeters > 0
        }
        guard (watch.kind == .running || watch.kind == .walking),
              fullyStructured || hasMeasuredMinutes else { return nil }
        id = watch.id
        workoutID = watch.structuredWorkoutSourceID
        title = watch.structuredWorkoutTitle ??
            (watch.kind == .walking ? "Gåtur" : "Løpeøkt")
        completedAt = watch.endedAt
        source = "Apple Watch"
        steps = recorded
        minutes = watch.recordedRunningMinutes
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
        var seen = Set<UUID>()
        let unique = candidates.filter { seen.insert($0.id).inserted }
        if let exact = unique.first(where: {
            $0.id == workoutID || $0.healthWorkoutUUID == workoutID
        }) { return exact }
        guard duration.isFinite, duration > 0 else { return nil }
        let matches = unique.filter {
            abs($0.completedAt.timeIntervalSince(endDate)) <= 75 &&
            abs($0.steps.reduce(0) { $0 + $1.activeSeconds } - duration) <=
                max(20, duration * 0.07)
        }
        return matches.count == 1 ? matches[0] : nil
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
        var byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        var changed = false
        for workout in completed {
            guard let record = ATHLTHCompletedRunningPerformance(phone: workout)
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
        guard let record = ATHLTHCompletedRunningPerformance(phone: completed) else {
            return
        }
        var history = load(userID: userID)
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
        // A late HealthKit export may supply its workout UUID after the
        // first Watch result. Update the existing session without duplicates.
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
