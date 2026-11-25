import Foundation

/// GPS pass-through evidence attached to the ORIGINAL workout journal.
/// This never starts an additional HealthKit capture or claims server-side
/// attestation. Only accurate outdoor samples may count towards a lap.
struct ATHLTHCompetitionGPSFix: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let timestamp: Date
    let courseDegrees: Double?
}

struct ATHLTHCompetitionGPSLapState: Codable, Equatable {
    var laps: Int = 0
    var outsideSamples: Int = 0
    var insideSamples: Int = 0
    var leftStartZone = false
    var lastLapAt: Date?
    var lastFixAt: Date?
    var crossingHeadingDegrees: Double?
    var totalAcceptedLapMeters: Double = 0
    var lastFixLatitude: Double?
    var lastFixLongitude: Double?
}

/// Hysteresis and course consistency protect against stationary GPS
/// wandering, duplicate callbacks and crossing the lap point the wrong way.
enum ATHLTHCompetitionGPSLapCounter {
    static let innerRadiusMeters = 18.0
    static let outerRadiusMeters = 43.0
    static let maxAccuracyMeters = 15.0
    static let minimumLapSeconds: TimeInterval = 35
    static let minimumTravelMeters = 45.0

    static func update(
        _ state: ATHLTHCompetitionGPSLapState,
        fix: ATHLTHCompetitionGPSFix,
        startLatitude: Double,
        startLongitude: Double,
        startSignalAt: Date,
        limit: Int
    ) -> ATHLTHCompetitionGPSLapState {
        guard (1...500).contains(limit),
              state.laps < limit,
              fix.timestamp >= startSignalAt,
              fix.timestamp <= Date().addingTimeInterval(2),
              fix.accuracyMeters.isFinite,
              (0...maxAccuracyMeters).contains(fix.accuracyMeters),
              (-90...90).contains(fix.latitude),
              (-180...180).contains(fix.longitude),
              (-90...90).contains(startLatitude),
              (-180...180).contains(startLongitude),
              state.lastFixAt.map({ fix.timestamp > $0 }) ?? true
        else { return state }

        var next = state
        if let last = state.lastFixAt {
            let elapsed = fix.timestamp.timeIntervalSince(last)
            let travelled: Double? = {
                guard let a = state.lastFixLatitude, let b = state.lastFixLongitude else { return nil }
                return haversineMeters(a, b, fix.latitude, fix.longitude)
            }()
            // A gap or teleport invalidates the unfinished lap, not the
            // previously accepted laps. Do not bridge missing GPS evidence.
            if elapsed > 25 || travelled.map({ $0 / elapsed > 9.5 }) == true {
                next.outsideSamples = 0
                next.insideSamples = 0
                next.leftStartZone = false
                next.totalAcceptedLapMeters = 0
                next.lastFixAt = fix.timestamp
                next.lastFixLatitude = fix.latitude
                next.lastFixLongitude = fix.longitude
                return next
            }
        }
        let distance = haversineMeters(fix.latitude, fix.longitude,
                                      startLatitude, startLongitude)
        if let a = state.lastFixLatitude, let b = state.lastFixLongitude,
           let last = state.lastFixAt {
            let travelled = haversineMeters(fix.latitude, fix.longitude, a, b)
            let elapsed = fix.timestamp.timeIntervalSince(last)
            if elapsed <= 25 && elapsed > 0 &&
               travelled / elapsed <= 9.5 {
                next.totalAcceptedLapMeters += travelled
            }
        }
        next.lastFixAt = fix.timestamp
        next.lastFixLatitude = fix.latitude
        next.lastFixLongitude = fix.longitude

        if distance >= outerRadiusMeters {
            next.insideSamples = 0
            next.outsideSamples = min(2, next.outsideSamples + 1)
            if next.outsideSamples >= 2 {
                next.leftStartZone = true
            }
            return next
        }
        if distance > innerRadiusMeters {
            next.insideSamples = 0
            return next
        }

        next.insideSamples = min(2, next.insideSamples + 1)
        guard next.insideSamples == 2, next.leftStartZone,
              next.totalAcceptedLapMeters >= minimumTravelMeters,
              fix.timestamp.timeIntervalSince(
                  next.lastLapAt ?? startSignalAt
              ) >= minimumLapSeconds
        else { return next }

        // Establish the accepted crossing direction from the first lap.
        // Ignore a later crossing in the reverse direction, when the GPS
        // reports a reliable heading. Absence of heading is not positive
        // proof of wrong-direction travel.
        if let expected = next.crossingHeadingDegrees,
           let actual = fix.courseDegrees, (0..<360).contains(actual),
           angularDifference(expected, actual) > 75 {
            next.insideSamples = 0
            return next
        }

        next.laps += 1
        next.lastLapAt = fix.timestamp
        if next.crossingHeadingDegrees == nil,
           let heading = fix.courseDegrees, (0..<360).contains(heading) {
            next.crossingHeadingDegrees = heading
        }
        next.leftStartZone = false
        next.insideSamples = 0
        next.outsideSamples = 0
        next.totalAcceptedLapMeters = 0
        return next
    }

    private static func haversineMeters(
        _ lat1: Double, _ lon1: Double,
        _ lat2: Double, _ lon2: Double
    ) -> Double {
        let radians = Double.pi / 180
        let a = sin((lat2 - lat1) * radians / 2)
        let b = sin((lon2 - lon1) * radians / 2)
        let h = a * a +
            cos(lat1 * radians) * cos(lat2 * radians) * b * b
        return 12_742_000 * asin(min(1, sqrt(max(0, h))))
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let delta = abs(a.truncatingRemainder(dividingBy: 360) -
                        b.truncatingRemainder(dividingBy: 360))
        return min(delta, 360 - delta)
    }
}

/// An optional competition overlay on the one original running workout.
/// This identity follows the same source workout through live, summary and
/// server result submission; it never becomes a second workout recording.
struct ATHLTHCompetitionCaptureContext: Codable, Equatable {
    let tournamentID: UUID
    let startSignalAt: Date
    let raceRules: ATHLTHCompetitionRaceRules
    var lapState: ATHLTHCompetitionGPSLapState = .init()

    var lapSummary: String {
        "\(lapState.laps)/\(raceRules.lapCount) runder"
    }

    var isRaceArmed: Bool { Date() >= startSignalAt }
}


/// Local measurements prefill a competition report, but never attest the
/// source to the server or submit health information without the athlete.
struct ATHLTHCompetitionLocalResult: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let value: Double

    static func cardioValue(activity: String, metric: String, target: Double?,
                            workoutActivity: WorkoutActivity, distance: Double?,
                            duration: Double) -> Double? {
        guard (activity == "running" && workoutActivity == .running) ||
              (activity == "walking" && workoutActivity == .walking),
              let target, target.isFinite, target > 0,
              let distance, distance.isFinite, distance > 0,
              duration.isFinite, duration > 0 else { return nil }
        // Never extrapolate a 5 km split from a longer workout.
        if metric == "distance", abs(distance-target) <= target*0.02 { return duration }
        if metric == "duration", abs(duration-target) <= 5 { return distance }
        return nil
    }

    /// Positive values mean improvement, independent of scoring direction.
    /// This is a private comparison only; it never alters official points.
    static func improvementPercent(metric: String, baseline: Double, current: Double) -> Double? {
        guard ["distance", "duration", "time", "repetitions"].contains(metric),
              baseline.isFinite, baseline > 0, baseline <= 100_000_000,
              current.isFinite, current >= 0, current <= 100_000_000,
              metric != "distance" || current > 0 else { return nil }
        let difference = metric == "distance" ? baseline - current : current - baseline
        return 100 * difference / baseline
    }

    /// Local classification is not server attestation. Unknown and mixed
    /// environments never satisfy a restricted cardio venue.
    static func matchesVenue(_ venue: ATHLTHCompetitionEnvironment, indoor: Bool?,
                             phoneEnvironment: RunEnvironment?, mixed: Bool) -> Bool {
        if venue == .any { return true }
        if mixed { return false }
        switch venue {
        case .any: return true
        case .outdoor: return indoor == false && (phoneEnvironment == nil || phoneEnvironment == .outdoor)
        case .indoor: return indoor == true && phoneEnvironment != .outdoor
        case .treadmill: return indoor == true && phoneEnvironment == .treadmill
        case .gym: return false // a cardio record does not establish a gym location
        }
    }

    static func personalBaseline(exercise: ATHLTHSharedEventExerciseRow, libraryExerciseID: UUID?,
                                 health: [WorkoutSummary], phone: [PhoneWorkout],
                                 strength: [StrengthWorkoutLog], venue: ATHLTHCompetitionEnvironment = .any) -> Self? {
        guard let opened = exercise.opensAt, opened <= Date() else { return nil }
        let cutoff = opened.addingTimeInterval(-0.001)
        let lower = opened.addingTimeInterval(-90 * 86_400)
        let candidates = suggestions(exercise: exercise, libraryExerciseID: libraryExerciseID,
                                     health: health, phone: phone, strength: strength,
                                     historicalWindow: lower...cutoff, venue: venue)
            .filter { $0.value > 0 }
        return candidates.sorted {
            if $0.value == $1.value { return $0.date > $1.date }
            return exercise.metric == "distance" ? $0.value < $1.value : $0.value > $1.value
        }.first
    }

    static func suggestions(exercise: ATHLTHSharedEventExerciseRow, libraryExerciseID: UUID?,
                            health: [WorkoutSummary], phone: [PhoneWorkout],
                            strength: [StrengthWorkoutLog],
                            historicalWindow: ClosedRange<Date>? = nil,
                            venue: ATHLTHCompetitionEnvironment = .any) -> [Self] {
        guard let start = historicalWindow?.lowerBound ?? exercise.opensAt,
              let end = historicalWindow?.upperBound ?? exercise.deadlineAt else { return [] }
        if exercise.activity == "strength" {
            // Match the actual library exercise identity, not just a name.
            // Templates without a stable identity require manual entry.
            guard venue != .treadmill, venue != .outdoor, let libraryExerciseID else { return [] }
            return strength.compactMap { log in
                guard log.isFinished, let finished = log.endedAt,
                      log.startedAt >= start, finished <= end, finished <= Date(),
                      finished > log.startedAt else { return nil }
                let performed = log.exercises.filter { $0.exercise.libraryExerciseID == libraryExerciseID }
                guard performed.count == 1, let movement = performed.first else { return nil }
                let sets = movement.sets.filter(\.countsTowardTrainingLoad)
                guard !sets.isEmpty else { return nil }
                let measured: Double
                if exercise.metric == "repetitions" {
                    let values = sets.compactMap(\.resolvedCompletedReps)
                    guard values.count == sets.count else { return nil }
                    measured = Double(values.reduce(0,+))
                } else if exercise.metric == "time" {
                    let values = sets.compactMap(\.resolvedCompletedDurationSeconds)
                    guard let longest = values.max() else { return nil }
                    measured = Double(longest)
                } else { return nil }
                guard exercise.accepts(measured), measured > 0 else { return nil }
                return Self(id: log.id, title: log.title, date: finished, value: measured)
            }.sorted { $0.date > $1.date }
        }
        let history = ATHLTHArenaWorkoutIdentity.distinct(
            (phone.filter { $0.end != nil }.map(SocialPublishableWorkout.init(phoneWorkout:)) +
             health.map(SocialPublishableWorkout.init(summary:))).sorted { $0.endDate > $1.endDate })
        return history.compactMap { workout in
            let original = phone.first { ($0.healthID ?? $0.id) == workout.id }
            let mixed = original?.indoorSwitchActiveSeconds != nil ||
                original?.gpsDistanceBeforeIndoorSwitchMeters != nil
            guard matchesVenue(venue, indoor: workout.isIndoor,
                               phoneEnvironment: original?.runEnvironment, mixed: mixed) else { return nil }
            guard workout.startDate >= start, workout.endDate <= end, workout.endDate <= Date(),
                  workout.endDate > workout.startDate,
                  ATHLTHArenaLocalEvidenceCheck.verify(workout, health: health, phone: phone, strength: strength).isUsable,
                  let value = cardioValue(activity: exercise.activity, metric: exercise.metric,
                     target: exercise.targetValue, workoutActivity: workout.activity,
                     distance: workout.distanceMeters, duration: workout.duration),
                  exercise.accepts(value) else { return nil }
            return Self(id: workout.id, title: workout.title, date: workout.endDate, value: value)
        }
    }
}


/// One explicitly selected competition per account and device. A completed
/// workout is never shared by this path until the athlete enables it.
@MainActor
enum ATHLTHCompetitionAutoReporting {
    private struct Consent: Codable, Equatable {
        let tournamentID: UUID
        let enabledAt: Date
    }
    private static let storageName = "competitionAutoReporting"
    private static let queueName = "competitionAutoReportingPending"
    private struct PendingMeasurement: Codable, Equatable {
        let consent: Consent
        let targetID: UUID
        let workoutID: UUID
        let score: Double
        let started: Date
        let ended: Date
        let deadline: Date
        var id: String { targetID.uuidString + workoutID.uuidString }
    }
    private static var syncingUsers: Set<UUID> = []
    private static var lastErrors: [UUID: String] = [:]
    private static func pending(userID: UUID) -> [PendingMeasurement] {
        AccountLocalStorage.read([PendingMeasurement].self, name: queueName, userID: userID, defaults: .standard) ?? []
    }
    private static func savePending(_ items: [PendingMeasurement], userID: UUID) {
        guard !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: userID)) else { return }
        AccountLocalStorage.write(items, name: queueName, userID: userID, defaults: .standard)
    }
    static func syncStatus(tournamentID: UUID, userID: UUID) -> String? {
        guard enabled(tournamentID: tournamentID, userID: userID) else { return nil }
        let count = pending(userID: userID).filter { $0.consent.tournamentID == tournamentID }.count
        if count > 0 { return "\(count) resultat(er) venter på synkronisering." }
        return lastErrors[userID]
    }
    static func retryPending(userID: UUID) async {
        guard let selection = consent(userID: userID), syncingUsers.insert(userID).inserted else { return }
        defer { syncingUsers.remove(userID) }
        let cloud = ATHLTHTournamentSingleEventCloud()
        let items = pending(userID: userID)
        for item in items {
            guard !Task.isCancelled, consent(userID: userID) == selection else { break }
            guard item.consent == selection else {
                savePending(pending(userID: userID).filter { $0.id != item.id }, userID: userID)
                continue
            }
            if item.deadline <= Date() {
                savePending(pending(userID: userID).filter { $0.id != item.id }, userID: userID)
                lastErrors[userID] = "Et resultat kunne ikke synkroniseres før øvelsesfristen."
                continue
            }
            do {
                _ = try await cloud.submitLocal(tournamentID: selection.tournamentID, userID: userID,
                    targetID: item.targetID, workoutID: item.workoutID, score: item.score,
                    started: item.started, ended: item.ended)
                savePending(pending(userID: userID).filter { $0.id != item.id }, userID: userID)
            } catch {
                lastErrors[userID] = "Resultatet venter på ny innsending."
                break
            }
        }
        if pending(userID: userID).isEmpty && lastErrors[userID] == "Resultatet venter på ny innsending." {
            lastErrors[userID] = nil
        }
    }
    private static var inFlight: Set<String> = []
    private static func consent(userID: UUID) -> Consent? {
        guard !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: userID)) else { return nil }
        return AccountLocalStorage.read([Consent].self, name: storageName,
            userID: userID, defaults: .standard)?.first
    }
    static func enabled(tournamentID: UUID, userID: UUID) -> Bool {
        consent(userID: userID)?.tournamentID == tournamentID
    }
    static func setEnabled(_ enabled: Bool, tournamentID: UUID, userID: UUID) {
        guard !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: userID)) else { return }
        if !enabled && !Self.enabled(tournamentID: tournamentID, userID: userID) { return }
        if enabled && Self.enabled(tournamentID: tournamentID, userID: userID) { return }
        savePending([], userID: userID)
        lastErrors[userID] = nil
        let records: [Consent] = enabled ? [Consent(tournamentID: tournamentID, enabledAt: Date())] : []
        AccountLocalStorage.write(records, name: storageName, userID: userID, defaults: .standard)
    }
    static func supports(_ tournament: ATHLTHTournamentRemote) -> Bool {
        tournament.status == "active" && tournament.proofMode == .opponent &&
            tournament.requiredEnvironment == "any" && tournament.raceRules.discipline == .workout &&
            tournament.raceRules.recordingDevice == .any &&
            (!tournament.singleEventMode || tournament.raceRules.exerciseScoringVersion == 2)
    }

    private static func measurement(target: ATHLTHCompetitionLocalTarget,
                                    workout: SocialPublishableWorkout,
                                    strengthLog: StrengthWorkoutLog?) -> (key: String, value: Double)? {
        guard workout.startDate >= target.opensAt, workout.endDate <= target.deadlineAt else { return nil }
        if target.activity == "strength" {
            guard workout.activity == .strength, let log = strengthLog, log.isFinished,
                  let id = target.libraryExerciseID else { return nil }
            let performed = log.exercises.filter { $0.exercise.libraryExerciseID == id }
            guard performed.count == 1, let exercise = performed.first else { return nil }
            let sets = exercise.sets.filter(\.countsTowardTrainingLoad)
            guard !sets.isEmpty else { return nil }
            let value: Double
            if target.metric == "repetitions" {
                let reps = sets.compactMap(\.resolvedCompletedReps)
                guard reps.count == sets.count else { return nil }
                value = Double(reps.reduce(0,+))
            } else if target.metric == "time" {
                guard let longest = sets.compactMap(\.resolvedCompletedDurationSeconds).max() else { return nil }
                value = Double(longest)
            } else { return nil }
            guard value.isFinite, value > 0, value <= 100_000_000 else { return nil }
            return ("strength:" + id.uuidString, value)
        }
        guard let value = ATHLTHCompetitionLocalResult.cardioValue(activity: target.activity,
            metric: target.metric, target: target.targetValue, workoutActivity: workout.activity,
            distance: workout.distanceMeters, duration: workout.duration),
              value.isFinite, value > 0, value <= 100_000_000 else { return nil }
        return ("cardio:" + target.activity, value)
    }

    static func submitCompletedWorkout(_ workout: SocialPublishableWorkout,
                                       sourceIDs: Set<UUID>, strengthLogs: [StrengthWorkoutLog],
                                       userID: UUID) async {
        guard let selection = consent(userID: userID), workout.startDate >= selection.enabledAt,
              workout.endDate > workout.startDate, workout.endDate <= Date() else { return }
        let key = userID.uuidString + selection.tournamentID.uuidString + workout.id.uuidString
        guard inFlight.insert(key).inserted else { return }
        defer { inFlight.remove(key) }
        let cloud = ATHLTHTournamentSingleEventCloud()
        do {
            let targets = try await cloud.localTargets(tournamentID: selection.tournamentID, userID: userID)
            let ids = sourceIDs.union([workout.id])
            let matchingLogs = strengthLogs.filter { log in
                (ids.contains(log.id) || log.healthMetrics.healthKitWorkoutUUID.map { ids.contains($0) } == true) &&
                log.isFinished && abs(log.startedAt.timeIntervalSince(workout.startDate)) <= 120 &&
                log.endedAt.map { abs($0.timeIntervalSince(workout.endDate)) <= 120 } == true
            }
            let strengthLog = matchingLogs.count == 1 ? matchingLogs.first : nil
            let values = targets.compactMap { target -> (ATHLTHCompetitionLocalTarget, String, Double)? in
                guard let result = measurement(target: target, workout: workout, strengthLog: strengthLog) else { return nil }
                return (target, result.key, result.value)
            }
            // Do not assign one measurement to multiple eligible exercises or
            // overlapping fixtures, even if one has already been submitted.
            for (target, metricKey, score) in values where target.progress == "pending" {
                guard values.filter({ $0.1 == metricKey }).count == 1,
                      consent(userID: userID) == selection else { continue }
                let item = PendingMeasurement(consent: selection, targetID: target.id,
                    workoutID: strengthLog?.id ?? workout.id, score: score,
                    started: workout.startDate, ended: workout.endDate, deadline: target.deadlineAt)
                var queue = pending(userID: userID)
                if !queue.contains(where: { $0.id == item.id }) {
                    queue.append(item)
                    savePending(queue, userID: userID)
                }
            }
            lastErrors[userID] = nil
            await retryPending(userID: userID)
        } catch {
            // The workout remains saved locally. Without a server target, do
            // not guess which competition exercise should receive the result.
            lastErrors[userID] = "Kunne ikke hente åpne konkurranseøvelser. Bruk treningshistorikken for å registrere resultatet."
        }
    }
}
