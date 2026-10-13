import Foundation

/// Audio Coach information density. Trigger intervals and voice delivery
/// are intentionally independent and never overwritten by a content preset.
enum ATHLTHCoachContentLevel: String, CaseIterable, Identifiable, Codable {
    case simple
    case standard
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple:
            return ATHLTHLocalization.choose(
                english: "Simple", norwegian: "Enkel"
            )
        case .standard:
            return ATHLTHLocalization.choose(
                english: "Standard", norwegian: "Standard"
            )
        case .advanced:
            return ATHLTHLocalization.choose(
                english: "Advanced", norwegian: "Avansert"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .simple:
            return ATHLTHLocalization.choose(
                english: "The essentials",
                norwegian: "Kun det viktigste"
            )
        case .standard:
            return ATHLTHLocalization.choose(
                english: "Balanced guidance",
                norwegian: "Balansert veiledning"
            )
        case .advanced:
            return ATHLTHLocalization.choose(
                english: "Detailed workout insight",
                norwegian: "Detaljerte treningsdata"
            )
        }
    }

    /// Caller preserves on/off, language, distance/time intervals, voice,
    /// quiet period, Watch ownership and user-selected output route.
    func applying(
        to original: WatchAudioCoachConfiguration
    ) -> WatchAudioCoachConfiguration {
        var value = original
        value.announceDistance = true
        value.announceElapsedTime = true
        value.announceAveragePace = self != .simple
        value.announceClockTime = self == .advanced
        value.announceHeartRate = self == .advanced
        value.announceRemainingRouteDistance = self != .simple
        value.announceEstimatedRemainingRouteTime = self == .advanced
        value.announceCurrentWorkoutStep = true
        value.announceRemainingStepTime = self != .simple
        value.announceRemainingStepDistance = self == .advanced
        // Start/pause/end cues are useful at every level.
        value.announceWorkoutStart = true
        value.announcePauseResume = true
        value.announceWorkoutComplete = true
        return value
    }

    static func matching(
        _ configuration: WatchAudioCoachConfiguration
    ) -> ATHLTHCoachContentLevel? {
        allCases.first { level in
            let match = level.applying(to: configuration)
            return Self.contentSignature(match) ==
                Self.contentSignature(configuration)
        }
    }

    private static func contentSignature(
        _ value: WatchAudioCoachConfiguration
    ) -> [Bool] {
        [
            value.announceDistance,
            value.announceElapsedTime,
            value.announceAveragePace,
            value.announceClockTime,
            value.announceHeartRate,
            value.announceRemainingRouteDistance,
            value.announceEstimatedRemainingRouteTime,
            value.announceCurrentWorkoutStep,
            value.announceRemainingStepTime,
            value.announceRemainingStepDistance,
            value.shouldAnnounceWorkoutStart,
            value.shouldAnnouncePauseResume,
            value.shouldAnnounceWorkoutComplete
        ]
    }
}

 
/// Consistent user-facing coaching intensity across supported workouts.
/// The underlying content, voice, delivery and device models remain unchanged.
enum ATHLTHCoachExperiencePreset: String, CaseIterable, Identifiable {
    case calm, balanced, active

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return ATHLTHLocalization.choose(english: "Calm", norwegian: "Rolig")
        case .balanced: return ATHLTHLocalization.choose(english: "Balanced", norwegian: "Balansert")
        case .active: return ATHLTHLocalization.choose(english: "Active", norwegian: "Aktiv")
        }
    }

    var subtitle: String {
        switch self {
        case .calm: return ATHLTHLocalization.choose(
            english: "Key moments only", norwegian: "Bare det viktigste")
        case .balanced: return ATHLTHLocalization.choose(
            english: "Regular guidance", norwegian: "Passe mye veiledning")
        case .active: return ATHLTHLocalization.choose(
            english: "More detailed updates", norwegian: "Tett oppfølging")
        }
    }

    var contentLevel: ATHLTHCoachContentLevel {
        switch self {
        case .calm: return .simple
        case .balanced: return .standard
        case .active: return .advanced
        }
    }

    var speechStyle: ATHLTHCoachSpeechStyle {
        switch self {
        case .calm: return .minimal
        case .balanced: return .balanced
        case .active: return .motivating
        }
    }

    var distanceIntervalKilometers: Double {
        switch self {
        case .calm: return 2.0
        case .balanced: return 1.0
        case .active: return 0.5
        }
    }
}


extension ATHLTHCoachExperiencePreset {
    /// Watch-facing preset. Preserves audio route, voice, safety notifications
    /// and active HealthKit session settings. Does not require new wire fields.
    func applying(
        to original: WatchAudioCoachConfiguration,
        kind: WatchWorkoutKind
    ) -> WatchAudioCoachConfiguration {
        var value = original
        if kind == .strength {
            value.announceStrengthRestComplete = true
            value.announceStrengthNextExercise = true
            switch self {
            case .calm:
                value.announceStrengthSetComplete = false
                value.announceStrengthRestStarted = false
                value.announceStrengthRestCountdown = false
                value.announceStrengthNextSetDetails = false
                value.announceStrengthExerciseProgress = false
                value.strengthStatusIntervalSeconds = nil
            case .balanced:
                value.announceStrengthSetComplete = true
                value.announceStrengthRestStarted = false
                value.announceStrengthRestCountdown = true
                value.announceStrengthNextSetDetails = true
                value.announceStrengthExerciseProgress = false
                value.strengthStatusIntervalSeconds = nil
            case .active:
                value.announceStrengthSetComplete = true
                value.announceStrengthRestStarted = true
                value.announceStrengthRestCountdown = true
                value.announceStrengthNextSetDetails = true
                value.announceStrengthExerciseProgress = true
                value.strengthStatusIntervalSeconds = 15 * 60
            }
        } else {
            value = contentLevel.applying(to: value)
            if kind == .running || kind == .walking {
                value.distanceIntervalMeters = distanceIntervalKilometers * 1_000
                value.timeIntervalSeconds = nil
            } else {
                // No GPS distance requirement for HIIT, yoga or other sports.
                value.distanceIntervalMeters = nil
                switch self {
                case .calm: value.timeIntervalSeconds = 15 * 60
                case .balanced: value.timeIntervalSeconds = 10 * 60
                case .active: value.timeIntervalSeconds = 5 * 60
                }
            }
        }
        value.enabled = true
        // Speaking personality is independent of guidance frequency.
        return value
    }

    func matches(
        _ configuration: WatchAudioCoachConfiguration,
        kind: WatchWorkoutKind
    ) -> Bool {
        guard configuration.enabled else { return false }

        let expected = applying(to: configuration, kind: kind)
        if kind == .strength {
            return configuration.shouldAnnounceStrengthSetComplete ==
                expected.shouldAnnounceStrengthSetComplete
                && configuration.shouldAnnounceStrengthRestStarted ==
                expected.shouldAnnounceStrengthRestStarted
                && configuration.shouldAnnounceStrengthRestCountdown ==
                expected.shouldAnnounceStrengthRestCountdown
                && configuration.shouldAnnounceStrengthRestComplete ==
                expected.shouldAnnounceStrengthRestComplete
                && configuration.shouldAnnounceStrengthNextExercise ==
                expected.shouldAnnounceStrengthNextExercise
                && configuration.shouldAnnounceStrengthNextSetDetails ==
                expected.shouldAnnounceStrengthNextSetDetails
                && configuration.shouldAnnounceStrengthExerciseProgress ==
                expected.shouldAnnounceStrengthExerciseProgress
                && configuration.strengthStatusIntervalSeconds ==
                expected.strengthStatusIntervalSeconds
        }
        return ATHLTHCoachContentLevel.matching(configuration) == contentLevel
            && configuration.distanceIntervalMeters ==
                expected.distanceIntervalMeters
            && configuration.timeIntervalSeconds ==
                expected.timeIntervalSeconds
    }
}


/// Keeps routine distance/time commentary out of short or nearly completed
/// intervals. Planned-step announcements and independent safety alerts still
/// take precedence. A suppressed routine milestone is intentionally skipped
/// instead of replaying stale metrics after the next step begins.
enum ATHLTHCoachRoutineContextPolicy {
    static func shouldSpeakMilestone(
        step: WatchRunningWorkoutStep?,
        elapsedInStep: TimeInterval,
        distanceInStepMeters: Double
    ) -> Bool {
        guard let step else { return true }

        // Give the coach's new-step instruction time to finish.
        guard elapsedInStep.isFinite, elapsedInStep >= 20 else {
            return false
        }

        switch step.measure {
        case .time:
            guard let duration = step.durationSeconds,
                  duration.isFinite, duration > 0 else { return true }
            return duration - elapsedInStep > 20
        case .distance:
            guard let distance = step.distanceMeters,
                  distance.isFinite, distance > 0 else { return true }
            return distance - max(distanceInStepMeters, 0) > 75
        case .open:
            return true
        }
    }
}

/// Concise instructions based on the user's planned interval, shared by
/// iPhone and Apple Watch. Use only explicit plan targets; no invented pace.
enum ATHLTHCoachStructuredStepSpeech {
    enum Position {
        case starting, current, next
    }

    static func phrase(
        for step: WatchRunningWorkoutStep,
        position: Position,
        norwegian: Bool
    ) -> String {
        let introduction: String
        switch position {
        case .starting: introduction = norwegian ? "Starter" : "Starting"
        case .current: introduction = norwegian ? "Nå" : "Current"
        case .next: introduction = norwegian ? "Neste" : "Next"
        }

        var parts = [introduction, step.title]

        switch step.measure {
        case .time:
            if let seconds = step.durationSeconds,
               seconds.isFinite, seconds > 0 {
                let rounded = Int(seconds.rounded())
                if rounded >= 60 {
                    let minutes = rounded / 60
                    let remainder = rounded % 60
                    let unit = norwegian
                        ? (minutes == 1 ? "minutt" : "minutter")
                        : (minutes == 1 ? "minute" : "minutes")
                    let secondsUnit = norwegian ? "sekunder" : "seconds"
                    parts.append(remainder == 0
                        ? "\(minutes) \(unit)"
                        : "\(minutes) \(unit) \(remainder) \(secondsUnit)")
                } else {
                    parts.append("\(rounded) " +
                        (norwegian ? "sekunder" : "seconds"))
                }
            }
        case .distance:
            if let meters = step.distanceMeters,
               meters.isFinite, meters > 0 {
                if meters >= 1_000, meters.truncatingRemainder(dividingBy: 1_000) == 0 {
                    parts.append("\(Int(meters / 1_000)) " +
                        (norwegian ? "kilometer" : "kilometers"))
                } else {
                    parts.append("\(Int(meters.rounded())) " +
                        (norwegian ? "meter" : "meters"))
                }
            }
        case .open:
            break
        }

        let paceValues = [
            step.targetPaceMinSecondsPerKilometer,
            step.targetPaceMaxSecondsPerKilometer
        ].compactMap { $0 }.filter { $0.isFinite && (120...1_800).contains($0) }
        if !paceValues.isEmpty {
            let fast = paceValues.min()!
            let slow = paceValues.max()!
            func format(_ value: Double) -> String {
                let seconds = Int(value.rounded())
                return String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
            let target = fast == slow
                ? format(fast)
                : "\(format(fast))–\(format(slow))"
            parts.append((norwegian ? "Målfart " : "Target pace ") +
                target + " min/km")
        } else if let intensity = step.intensityText,
                  !intensity.isEmpty {
            // For non-pace training targets retain the user's plan label.
            parts.append(intensity)
        }

        return parts.joined(separator: ". ")
    }
}


extension ATHLTHCoachStructuredStepSpeech {
    /// Returns only remaining targets that were explicitly configured.
    /// No guessed tempo, route duration or sensor-dependent value is spoken.
    static func remainingSummary(
        for step: WatchRunningWorkoutStep,
        elapsedInStep: TimeInterval,
        distanceInStepMeters: Double,
        announceTime: Bool,
        announceDistance: Bool,
        norwegian: Bool
    ) -> String? {
        switch step.measure {
        case .time:
            guard announceTime,
                  let target = step.durationSeconds,
                  target.isFinite, target > 0,
                  elapsedInStep.isFinite
            else { return nil }
            let remaining = max(target - max(elapsedInStep, 0), 0)
            guard remaining > 0 else { return nil }
            let seconds = Int(remaining.rounded(.up))
            let duration: String
            if seconds < 60 {
                duration = "\(seconds) " + (norwegian ? "sekunder" : "seconds")
            } else {
                let minutes = seconds / 60
                let rest = seconds % 60
                let minuteUnit = norwegian
                    ? (minutes == 1 ? "minutt" : "minutter")
                    : (minutes == 1 ? "minute" : "minutes")
                duration = "\(minutes) \(minuteUnit)" +
                    (rest > 0 ? " \(rest) " + (norwegian ? "sekunder" : "seconds") : "")
            }
            return (norwegian ? "Tid igjen i intervallet: " : "Time left in interval: ") +
                duration

        case .distance:
            guard announceDistance,
                  let target = step.distanceMeters,
                  target.isFinite, target > 0,
                  distanceInStepMeters.isFinite
            else { return nil }
            let remaining = max(target - max(distanceInStepMeters, 0), 0)
            guard remaining > 0 else { return nil }
            return (norwegian ? "Distanse igjen i intervallet: " :
                "Distance left in interval: ") +
                "\(Int(remaining.rounded())) " +
                (norwegian ? "meter" : "meters")

        case .open:
            return nil
        }
    }
}
