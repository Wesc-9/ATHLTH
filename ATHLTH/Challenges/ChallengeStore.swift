import CoreLocation
import Foundation

@MainActor
final class ChallengeStore: ObservableObject {
    @Published private(set) var challenges: [ATHLTHChallenge] = []

    init() {
        challenges = Self.loadChallenges()
        refreshStatuses()
    }

    var visibleChallenges: [ATHLTHChallenge] {
        challenges.sorted {
            challengeSortDate($0) < challengeSortDate($1)
        }
    }

    func challenge(id: UUID) -> ATHLTHChallenge? {
        challenges.first { $0.id == id }
    }

    func add(_ challenge: ATHLTHChallenge) {
        challenges.append(challenge)
        refreshStatuses()
        persist()
    }

    func update(_ challenge: ATHLTHChallenge) {
        guard let index = challenges.firstIndex(where: { $0.id == challenge.id }) else {
            return
        }

        guard !challenges[index].rulesAreLocked || challenge.rules == challenges[index].rules else {
            return
        }

        challenges[index] = challenge
        refreshStatuses()
        persist()
    }

    func cancel(_ challengeID: UUID) {
        guard let index = challenges.firstIndex(where: { $0.id == challengeID }) else {
            return
        }

        challenges[index].status = .cancelled
        persist()
    }

    func setParticipantState(
        challengeID: UUID,
        participantID: UUID,
        state: ChallengeParticipantState
    ) {
        guard let challengeIndex = challenges.firstIndex(where: { $0.id == challengeID }),
              let participantIndex = challenges[challengeIndex].participants.firstIndex(
                where: { $0.id == participantID }
              )
        else {
            return
        }

        challenges[challengeIndex].participants[participantIndex].state = state
        challenges[challengeIndex].participants[participantIndex].respondedAt = Date()
        refreshStatuses()
        persist()
    }

    func checkIn(
        challengeID: UUID,
        participantID: UUID,
        currentLocation: CLLocation? = nil
    ) {
        guard let index = challenges.firstIndex(where: { $0.id == challengeID }),
              let meetup = challenges[index].rules.meetup
        else {
            return
        }

        let meetupLocation = CLLocation(
            latitude: meetup.latitude,
            longitude: meetup.longitude
        )
        let distance = currentLocation.map { $0.distance(from: meetupLocation) }
        let verified = distance.map { $0 <= meetup.checkInRadiusMeters } ?? false

        challenges[index].checkIns.removeAll {
            $0.participantID == participantID
        }
        challenges[index].checkIns.append(
            ChallengeMeetupCheckIn(
                participantID: participantID,
                distanceFromMeetupMeters: distance,
                verifiedNearMeetup: verified
            )
        )
        persist()
    }

    func submitManualStrengthAttempt(
        challengeID: UUID,
        participantID: UUID,
        participantName: String,
        weightKilograms: Double?,
        reps: Int?,
        volumeKilograms: Double?,
        note: String?
    ) throws {
        guard let index = challenges.firstIndex(where: { $0.id == challengeID }) else {
            throw ChallengeStoreError.challengeNotFound
        }

        var challenge = challenges[index]

        guard challenge.sport == .strength else {
            throw ChallengeStoreError.invalidAttempt
        }

        guard challenge.rules.verificationPolicy.allowsManual else {
            throw ChallengeStoreError.manualNotAllowed
        }

        guard isWithinWindow(Date(), rules: challenge.rules) else {
            throw ChallengeStoreError.outsideChallengeWindow
        }

        let evaluation = try manualStrengthScore(
            rules: challenge.rules,
            weightKilograms: weightKilograms,
            reps: reps,
            volumeKilograms: volumeKilograms
        )

        let attempt = ChallengeAttempt(
            id: UUID(),
            challengeID: challenge.id,
            participantID: participantID,
            userID: challenge.participants.first(where: { $0.id == participantID })?.userID,
            participantName: participantName,
            submittedAt: Date(),
            startedAt: nil,
            endedAt: nil,
            verification: .manual,
            sourceWorkoutID: nil,
            durationSeconds: nil,
            distanceMeters: nil,
            weightKilograms: weightKilograms,
            reps: reps,
            volumeKilograms: volumeKilograms,
            routeMatchPercent: nil,
            score: evaluation.score,
            detail: evaluation.detail,
            manualNote: note?.trimmingCharacters(in: .whitespacesAndNewlines),
            isEligible: true,
            ineligibilityReason: nil
        )

        challenge.attempts.append(attempt)
        challenges[index] = challenge
        refreshStatuses()
        persist()
    }

    func ingestStrengthWorkout(
        _ workout: StrengthWorkoutLog,
        userID: UUID,
        displayName: String
    ) {
        guard workout.isFinished else { return }

        let candidateIDs = challenges
            .filter {
                $0.sport == .strength &&
                $0.rules.verificationPolicy.allowsVerified &&
                isWithinWindow(workout.startedAt, rules: $0.rules)
            }
            .map(\.id)

        for challengeID in candidateIDs {
            guard let challengeIndex = challenges.firstIndex(where: { $0.id == challengeID }),
                  let participant = participant(
                    in: challenges[challengeIndex],
                    userID: userID
                  )
            else {
                continue
            }

            let challenge = challenges[challengeIndex]
            guard let evaluation = strengthScore(
                workout: workout,
                rules: challenge.rules
            ) else {
                continue
            }

            let eventKey = "strength-\(workout.id.uuidString)-challenge-\(challenge.id.uuidString)"
            guard !challenge.attempts.contains(where: {
                $0.manualNote == eventKey
            }) else {
                continue
            }

            let attempt = ChallengeAttempt(
                id: UUID(),
                challengeID: challenge.id,
                participantID: participant.id,
                userID: userID,
                participantName: displayName,
                submittedAt: workout.endedAt ?? Date(),
                startedAt: workout.startedAt,
                endedAt: workout.endedAt,
                verification: .athlth,
                sourceWorkoutID: workout.id,
                durationSeconds: workout.endedAt?.timeIntervalSince(workout.startedAt),
                distanceMeters: nil,
                weightKilograms: evaluation.weight,
                reps: evaluation.reps,
                volumeKilograms: evaluation.volume,
                routeMatchPercent: nil,
                score: evaluation.score,
                detail: evaluation.detail,
                manualNote: eventKey,
                isEligible: evaluation.isEligible,
                ineligibilityReason: evaluation.reason
            )

            challenges[challengeIndex].attempts.append(attempt)
        }

        refreshStatuses()
        persist()
    }

    func ingestWatchWorkout(
        _ result: WatchWorkoutResult,
        health: HealthKitManager,
        userID: UUID,
        displayName: String
    ) async {
        guard result.kind == .running else { return }

        let candidateIDs = challenges
            .filter {
                $0.sport == .running &&
                $0.rules.verificationPolicy.allowsVerified &&
                isWithinWindow(result.startedAt, rules: $0.rules)
            }
            .map(\.id)

        for challengeID in candidateIDs {
            guard let challengeIndex = challenges.firstIndex(where: { $0.id == challengeID }),
                  let participant = participant(
                    in: challenges[challengeIndex],
                    userID: userID
                  )
            else {
                continue
            }

            let challenge = challenges[challengeIndex]
            let sourceKey = result.healthKitWorkoutUUID?.uuidString ?? result.id.uuidString

            guard !challenge.attempts.contains(where: {
                $0.sourceWorkoutID?.uuidString == sourceKey ||
                $0.manualNote == "watch-\(sourceKey)"
            }) else {
                continue
            }

            let evidence = await health.challengeRunningEvidence(
                for: result,
                rules: challenge.rules
            )

            let attempt = ChallengeAttempt(
                id: UUID(),
                challengeID: challenge.id,
                participantID: participant.id,
                userID: userID,
                participantName: displayName,
                submittedAt: result.endedAt,
                startedAt: evidence.startedAt,
                endedAt: evidence.endedAt,
                verification: .appleHealth,
                sourceWorkoutID: result.healthKitWorkoutUUID ?? result.id,
                durationSeconds: evidence.durationSeconds,
                distanceMeters: evidence.distanceMeters,
                weightKilograms: nil,
                reps: nil,
                volumeKilograms: nil,
                routeMatchPercent: evidence.routeMatchPercent,
                score: evidence.score,
                detail: evidence.detail,
                manualNote: "watch-\(sourceKey)",
                isEligible: evidence.isEligible,
                ineligibilityReason: evidence.ineligibilityReason
            )

            challenges[challengeIndex].attempts.append(attempt)
        }

        refreshStatuses()
        persist()
    }

    func leaderboard(for challengeID: UUID) -> [ChallengeLeaderboardEntry] {
        guard let challenge = challenges.first(where: { $0.id == challengeID }) else {
            return []
        }

        let participants = challenge.participants.filter {
            $0.state == .creator || $0.state == .accepted
        }

        var scored: [(participant: ChallengeParticipant, attempt: ChallengeAttempt?, score: Double?, count: Int)] = []

        for participant in participants {
            let attempts = challenge.attempts.filter {
                $0.participantID == participant.id && $0.isEligible
            }

            if challenge.rules.scoring == .mostDistance {
                let totalScore = attempts.reduce(0) {
                    $0 + ($1.distanceMeters ?? 0)
                }

                let representative = attempts.max {
                    ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0)
                }

                scored.append(
                    (
                        participant,
                        representative,
                        attempts.isEmpty ? nil : totalScore,
                        attempts.count
                    )
                )
            } else {
                let best = attempts.sorted { lhs, rhs in
                    if challenge.rules.scoring.prefersLowerScore {
                        return lhs.score < rhs.score
                    }
                    return lhs.score > rhs.score
                }.first

                scored.append(
                    (
                        participant,
                        best,
                        best?.score,
                        attempts.count
                    )
                )
            }
        }

        let ranked = scored
            .filter { $0.score != nil }
            .sorted { lhs, rhs in
                guard let left = lhs.score, let right = rhs.score else {
                    return lhs.score != nil
                }

                if challenge.rules.scoring.prefersLowerScore {
                    return left < right
                }
                return left > right
            }

        var ranksByParticipant: [UUID: Int] = [:]
        for (index, item) in ranked.enumerated() {
            ranksByParticipant[item.participant.id] = index + 1
        }

        return scored
            .map {
                ChallengeLeaderboardEntry(
                    participant: $0.participant,
                    bestAttempt: $0.attempt,
                    score: $0.score,
                    attemptCount: $0.count,
                    rank: ranksByParticipant[$0.participant.id]
                )
            }
            .sorted {
                switch ($0.rank, $1.rank) {
                case let (.some(left), .some(right)):
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return $0.participant.displayName < $1.participant.displayName
                }
            }
    }

    func refreshStatuses(now: Date = Date()) {
        var changed = false

        for index in challenges.indices {
            if challenges[index].status == .cancelled ||
                challenges[index].status == .completed {
                continue
            }

            if let endsAt = challenges[index].rules.endsAt,
               now > endsAt {
                if challenges[index].status != .completed {
                    challenges[index].status = .completed
                    changed = true
                }
                continue
            }

            if now >= challenges[index].rules.startsAt {
                if challenges[index].rules.lockRulesAtStart &&
                    challenges[index].rulesLockedAt == nil {
                    challenges[index].rulesLockedAt = challenges[index].rules.startsAt
                    changed = true
                }

                if challenges[index].status != .active {
                    challenges[index].status = .active
                    changed = true
                }
            } else {
                let hasAccepted = challenges[index].participants.contains {
                    $0.state == .accepted || $0.state == .creator
                }
                let nextStatus: ATHLTHChallengeStatus = hasAccepted ? .upcoming : .invited

                if challenges[index].status != nextStatus {
                    challenges[index].status = nextStatus
                    changed = true
                }
            }
        }

        if changed {
            persist()
        }
    }

    private func participant(
        in challenge: ATHLTHChallenge,
        userID: UUID
    ) -> ChallengeParticipant? {
        challenge.participants.first {
            $0.userID == userID &&
            ($0.state == .creator || $0.state == .accepted)
        }
    }

    private func isWithinWindow(
        _ date: Date,
        rules: ATHLTHChallengeRules
    ) -> Bool {
        guard date >= rules.startsAt else { return false }

        if let endsAt = rules.endsAt {
            return date <= endsAt
        }

        return true
    }

    private func manualStrengthScore(
        rules: ATHLTHChallengeRules,
        weightKilograms: Double?,
        reps: Int?,
        volumeKilograms: Double?
    ) throws -> (score: Double, detail: String) {
        switch rules.scoring {
        case .heaviestWeight:
            guard let weightKilograms, weightKilograms > 0 else {
                throw ChallengeStoreError.missingRequiredValue
            }
            return (
                weightKilograms,
                "\(Self.kg(weightKilograms)) kg · Manual"
            )

        case .mostReps:
            guard let reps, reps > 0 else {
                throw ChallengeStoreError.missingRequiredValue
            }

            if let required = rules.fixedWeightKilograms {
                guard let weightKilograms,
                      abs(weightKilograms - required) <= 0.1
                else {
                    throw ChallengeStoreError.weightRequirementNotMet
                }

                return (
                    Double(reps),
                    "\(reps) reps @ \(Self.kg(weightKilograms)) kg · Manual"
                )
            }

            return (Double(reps), "\(reps) reps · Manual")

        case .exerciseVolume, .workoutVolume:
            let resolvedVolume: Double

            if let volumeKilograms, volumeKilograms > 0 {
                resolvedVolume = volumeKilograms
            } else if let weightKilograms, let reps,
                      weightKilograms > 0, reps > 0 {
                resolvedVolume = weightKilograms * Double(reps)
            } else {
                throw ChallengeStoreError.missingRequiredValue
            }

            return (
                resolvedVolume,
                "\(Self.kg(resolvedVolume)) kg volume · Manual"
            )

        case .fastestDistance, .farthestInTime, .mostDistance, .fastestRoute:
            throw ChallengeStoreError.invalidAttempt
        }
    }

    private func strengthScore(
        workout: StrengthWorkoutLog,
        rules: ATHLTHChallengeRules
    ) -> (
        score: Double,
        weight: Double?,
        reps: Int?,
        volume: Double?,
        detail: String,
        isEligible: Bool,
        reason: String?
    )? {
        let normalizedExercise = rules.exerciseName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let exercises = workout.exercises.filter { exercise in
            guard let normalizedExercise, !normalizedExercise.isEmpty else {
                return true
            }

            return exercise.exercise.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == normalizedExercise
        }

        switch rules.scoring {
        case .heaviestWeight:
            let sets = exercises.flatMap(\.sets).filter(\.isCompleted)
            guard let best = sets
                .compactMap({ set -> (Double, Int?)? in
                    guard let weight = set.completedWeightKilograms,
                          weight > 0
                    else {
                        return nil
                    }
                    return (weight, set.completedReps)
                })
                .max(by: { $0.0 < $1.0 })
            else {
                return nil
            }

            return (
                best.0,
                best.0,
                best.1,
                nil,
                "\(Self.kg(best.0)) kg\(best.1.map { " × \($0)" } ?? "")",
                true,
                nil
            )

        case .mostReps:
            let requiredWeight = rules.fixedWeightKilograms
            let qualifying = exercises.flatMap(\.sets).compactMap { set -> (Int, Double?)? in
                guard set.isCompleted,
                      let reps = set.completedReps,
                      reps > 0
                else {
                    return nil
                }

                if let requiredWeight {
                    guard let weight = set.completedWeightKilograms,
                          abs(weight - requiredWeight) <= 0.1
                    else {
                        return nil
                    }
                    return (reps, weight)
                }

                return (reps, set.completedWeightKilograms)
            }

            guard let best = qualifying.max(by: { $0.0 < $1.0 }) else {
                return (
                    0,
                    nil,
                    nil,
                    nil,
                    "No qualifying set",
                    false,
                    requiredWeight.map {
                        "No completed set at \(Self.kg($0)) kg."
                    } ?? "No completed set with reps was found."
                )
            }

            return (
                Double(best.0),
                best.1,
                best.0,
                nil,
                "\(best.0) reps\(best.1.map { " @ \(Self.kg($0)) kg" } ?? "")",
                true,
                nil
            )

        case .exerciseVolume:
            let volume = exercises
                .flatMap(\.sets)
                .reduce(0.0) { partial, set in
                    guard set.isCompleted,
                          let weight = set.completedWeightKilograms,
                          let reps = set.completedReps
                    else {
                        return partial
                    }

                    return partial + weight * Double(reps)
                }

            guard volume > 0 else { return nil }

            return (
                volume,
                nil,
                nil,
                volume,
                "\(Self.kg(volume)) kg exercise volume",
                true,
                nil
            )

        case .workoutVolume:
            guard workout.totalVolumeKilograms > 0 else { return nil }

            return (
                workout.totalVolumeKilograms,
                nil,
                nil,
                workout.totalVolumeKilograms,
                "\(Self.kg(workout.totalVolumeKilograms)) kg workout volume",
                true,
                nil
            )

        case .fastestDistance, .farthestInTime, .mostDistance, .fastestRoute:
            return nil
        }
    }

    private func challengeSortDate(_ challenge: ATHLTHChallenge) -> Date {
        if challenge.status == .active {
            return .distantPast
        }

        return challenge.rules.startsAt
    }

    private static func kg(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }

    private func persist() {
        guard let url = Self.storageURL,
              let data = try? JSONEncoder().encode(challenges)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func loadChallenges() -> [ATHLTHChallenge] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                [ATHLTHChallenge].self,
                from: data
              )
        else {
            return []
        }

        return decoded
    }

    private static var storageURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("challenges-v1.json", isDirectory: false)
    }
}

enum ChallengeStoreError: LocalizedError {
    case challengeNotFound
    case invalidAttempt
    case manualNotAllowed
    case outsideChallengeWindow
    case missingRequiredValue
    case weightRequirementNotMet

    var errorDescription: String? {
        switch self {
        case .challengeNotFound:
            return "Challenge not found."
        case .invalidAttempt:
            return "This attempt does not match the challenge rules."
        case .manualNotAllowed:
            return "Manual attempts are not allowed in this challenge."
        case .outsideChallengeWindow:
            return "This attempt is outside the challenge time window."
        case .missingRequiredValue:
            return "Enter the required result before submitting."
        case .weightRequirementNotMet:
            return "The entered weight does not match the required challenge weight."
        }
    }
}
