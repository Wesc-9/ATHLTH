import Foundation

/// The presentation catalogue. These map directly onto existing Watch audio
/// configuration fields; there is no second, competing list of stored rules.
enum ATHLTHAudioCoachOption: String, CaseIterable, Identifiable {
    case distanceUpdates, timedUpdates
    case distance, elapsedTime, averagePace, clockTime, heartRate, currentZone
    case motivation, contextual, randomEncouragement
    case targetZoneCoach, adaptiveMotivation
    case workoutStart, pauseResume, workoutFinish, intervalRecoveryCountdown
    case routeRemaining, routeETA
    case currentStep, remainingStepTime, remainingStepDistance
    case customAnnouncements, customPhrases, landmarks

    var id: String { rawValue }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var title: String {
        switch self {
        case .distanceUpdates: return tr("Distance updates", "Oppdatering etter distanse")
        case .timedUpdates: return tr("Timed updates", "Oppdatering etter tid")
        case .distance: return tr("Distance", "Distanse")
        case .elapsedTime: return tr("Elapsed time", "Tid")
        case .averagePace: return tr("Average pace", "Gjennomsnittstempo")
        case .clockTime: return tr("Clock time", "Klokkeslett")
        case .heartRate: return tr("Heart rate", "Puls")
        case .currentZone: return tr("Current heart-rate zone", "Målt pulssone")
        case .targetZoneCoach: return tr("Target-zone guidance", "Veiledning for målsone")
        case .adaptiveMotivation: return tr("Situational motivation", "Situasjonsstyrt motivasjon")
        case .motivation: return tr("Motivational coaching", "Motivasjonssnakk")
        case .contextual: return tr("Hills and final stretch", "Bakker og siste etappe")
        case .randomEncouragement: return tr("Surprise encouragement", "Tilfeldig oppmuntring")
        case .workoutStart: return tr("Workout start", "Øktstart")
        case .pauseResume: return tr("Pause and resume", "Pause og fortsett")
        case .intervalRecoveryCountdown: return tr("Spoken rest countdown", "Hørbar nedtelling til og fra pause")
        case .workoutFinish: return tr("Finish summary", "Oppsummering ved mål")
        case .routeRemaining: return tr("Remaining route distance", "Gjenstående rutelengde")
        case .routeETA: return tr("Estimated time to finish", "Estimert tid til mål")
        case .currentStep: return tr("Current and next interval", "Nåværende og neste intervall")
        case .remainingStepTime: return tr("Remaining interval time", "Gjenstående intervalltid")
        case .remainingStepDistance: return tr("Remaining interval distance", "Gjenstående intervalldistanse")
        case .customAnnouncements: return tr("Independent announcements", "Egne beskjeder")
        case .customPhrases: return tr("Personal motivation phrases", "Egne motivasjonsmeldinger")
        case .landmarks: return tr("Places along the route", "Steder langs ruten")
        }
    }

    var category: String {
        switch self {
        case .distanceUpdates, .timedUpdates, .distance, .elapsedTime,
             .averagePace, .clockTime:
            return tr("Workout updates", "Øktoppdateringer")
        case .heartRate, .currentZone, .targetZoneCoach:
            return tr("Heart rate", "Puls")
        case .motivation, .contextual, .randomEncouragement, .adaptiveMotivation,
             .customPhrases, .landmarks:
            return tr("Motivation", "Motivasjon")
        case .workoutStart, .pauseResume, .workoutFinish, .intervalRecoveryCountdown:
            return tr("Events", "Hendelser")
        case .routeRemaining, .routeETA, .currentStep, .remainingStepTime,
             .remainingStepDistance:
            return tr("Workout guidance", "Rute og intervaller")
        case .customAnnouncements:
            return tr("My rules", "Egne regler")
        }
    }

    var symbol: String {
        switch self {
        case .distanceUpdates: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .timedUpdates: return "timer"
        case .distance: return "figure.run"
        case .elapsedTime: return "clock"
        case .averagePace: return "speedometer"
        case .clockTime: return "clock.badge"
        case .heartRate: return "heart"
        case .currentZone, .targetZoneCoach: return "heart.text.square"
        case .motivation, .contextual, .randomEncouragement, .adaptiveMotivation:
            return "sparkles"
        case .workoutStart: return "play.circle"
        case .pauseResume: return "pause.circle"
        case .intervalRecoveryCountdown: return "timer"
        case .workoutFinish: return "flag.checkered"
        case .routeRemaining, .routeETA: return "map"
        case .currentStep, .remainingStepTime, .remainingStepDistance: return "repeat"
        case .customAnnouncements: return "waveform.badge.plus"
        case .customPhrases: return "text.quote"
        case .landmarks: return "mappin.and.ellipse"
        }
    }

    var requiresConfiguration: Bool {
        switch self {
        case .distanceUpdates, .timedUpdates, .currentZone, .targetZoneCoach,
             .adaptiveMotivation, .motivation, .randomEncouragement,
             .customAnnouncements, .customPhrases, .intervalRecoveryCountdown,
             .landmarks:
            return true
        default:
            return false
        }
    }

    var isContentList: Bool {
        self == .customAnnouncements || self == .customPhrases || self == .landmarks
    }

    func isVisible(route: Bool, structured: Bool) -> Bool {
        switch self {
        case .routeRemaining, .routeETA: return route
        case .currentStep, .remainingStepTime, .remainingStepDistance, .intervalRecoveryCountdown:
            return structured
        case .landmarks: return route
        default: return true
        }
    }

    func isActive(in d: AudioCoachDraft) -> Bool {
        switch self {
        case .distanceUpdates:
            return d.distanceTriggerEnabled
        case .timedUpdates:
            return d.timeTriggerEnabled
        case .distance:
            return d.announceDistance && (d.distanceTriggerEnabled || d.timeTriggerEnabled)
        case .elapsedTime:
            return d.announceElapsedTime && (d.distanceTriggerEnabled || d.timeTriggerEnabled)
        case .averagePace:
            return d.announceAveragePace && (d.distanceTriggerEnabled || d.timeTriggerEnabled)
        case .clockTime:
            return d.announceClockTime && (d.distanceTriggerEnabled || d.timeTriggerEnabled)
        case .heartRate:
            return d.announceHeartRate && (d.distanceTriggerEnabled || d.timeTriggerEnabled)
        case .currentZone: return d.smartPrompts.announceCurrentHeartRateZone ?? false
        case .targetZoneCoach:
            return d.smartPrompts.targetZoneVoiceAlertsEnabled == true ||
                d.smartPrompts.preferredHeartRateZone != nil
        case .adaptiveMotivation: return d.smartPrompts.coachingMode == .custom
        case .motivation: return d.smartPrompts.motivationEnabled
        case .contextual:
            return d.smartPrompts.motivationEnabled &&
                (d.smartPrompts.contextualFeedbackEnabled ?? true)
        case .randomEncouragement: return d.smartPrompts.randomEncouragementEnabled
        case .workoutStart: return d.announceWorkoutStart
        case .pauseResume: return d.announcePauseResume
        case .intervalRecoveryCountdown:
            return d.smartPrompts.intervalCountdownToRecoverySeconds != nil ||
                d.smartPrompts.intervalCountdownFromRecoverySeconds != nil
        case .workoutFinish: return d.announceWorkoutComplete
        case .routeRemaining: return d.announceRemainingRouteDistance
        case .routeETA: return d.announceEstimatedRemainingRouteTime
        case .currentStep: return d.announceCurrentWorkoutStep
        case .remainingStepTime: return d.announceRemainingStepTime
        case .remainingStepDistance: return d.announceRemainingStepDistance
        case .customAnnouncements: return !d.customRules.isEmpty
        case .customPhrases:
            return d.smartPrompts.randomEncouragementEnabled &&
                !d.smartPrompts.customEncouragements.isEmpty
        case .landmarks: return !d.smartPrompts.landmarks.isEmpty
        }
    }

    func setActive(_ active: Bool, in d: inout AudioCoachDraft) {
        switch self {
        case .distanceUpdates:
            d.distanceTriggerEnabled = active
        case .timedUpdates:
            d.timeTriggerEnabled = active
        case .distance:
            d.announceDistance = active
            if active && !d.distanceTriggerEnabled && !d.timeTriggerEnabled {
                d.distanceTriggerEnabled = true
            }
        case .elapsedTime:
            d.announceElapsedTime = active
            if active && !d.distanceTriggerEnabled && !d.timeTriggerEnabled {
                d.distanceTriggerEnabled = true
            }
        case .averagePace:
            d.announceAveragePace = active
            if active && !d.distanceTriggerEnabled && !d.timeTriggerEnabled {
                d.distanceTriggerEnabled = true
            }
        case .clockTime:
            d.announceClockTime = active
            if active && !d.distanceTriggerEnabled && !d.timeTriggerEnabled {
                d.distanceTriggerEnabled = true
            }
        case .heartRate:
            d.announceHeartRate = active
            if active && !d.distanceTriggerEnabled && !d.timeTriggerEnabled {
                d.distanceTriggerEnabled = true
            }
        case .currentZone:
            d.smartPrompts.announceCurrentHeartRateZone = active
            if active {
                // A zone-announcement option must have a concrete interval,
                // even alongside programmed target-zone alerts.
                if d.smartPrompts.measuredZoneAnnouncementIntervalSeconds == nil {
                    d.smartPrompts.measuredZoneAnnouncementIntervalSeconds = 60
                }
            } else {
                d.smartPrompts.measuredZoneAnnouncementIntervalSeconds = nil
            }
        case .targetZoneCoach:
            d.smartPrompts.targetZoneVoiceAlertsEnabled = active
            if active { d.smartPrompts.confirmWhenBackInZone = true }
        case .adaptiveMotivation:
            d.smartPrompts.coachingMode = active ? .custom : .automatic
            if active && d.smartPrompts.strongStartDurationSeconds == nil {
                d.smartPrompts.strongStartDurationSeconds = 180
            }
        case .motivation: d.smartPrompts.motivationEnabled = active
        case .contextual:
            if active { d.smartPrompts.motivationEnabled = true }
            d.smartPrompts.contextualFeedbackEnabled = active
        case .randomEncouragement: d.smartPrompts.randomEncouragementEnabled = active
        case .workoutStart: d.announceWorkoutStart = active
        case .pauseResume: d.announcePauseResume = active
        case .intervalRecoveryCountdown:
            d.smartPrompts.intervalCountdownToRecoverySeconds = active ? 10 : nil
            d.smartPrompts.intervalCountdownFromRecoverySeconds = active ? 10 : nil
        case .workoutFinish: d.announceWorkoutComplete = active
        case .routeRemaining: d.announceRemainingRouteDistance = active
        case .routeETA: d.announceEstimatedRemainingRouteTime = active
        case .currentStep: d.announceCurrentWorkoutStep = active
        case .remainingStepTime: d.announceRemainingStepTime = active
        case .remainingStepDistance: d.announceRemainingStepDistance = active
        case .customAnnouncements:
            if !active { d.customRules = [] }
        case .customPhrases:
            if !active { d.smartPrompts.customEncouragements = [] }
        case .landmarks:
            if !active { d.smartPrompts.landmarks = [] }
        }
    }

    func detail(in draft: AudioCoachDraft) -> String {
        switch self {
        case .distanceUpdates:
            return tr("Every ", "Hver ") +
                (draft.distanceIntervalKilometers * 1_000).formatted(
                    .number.precision(.fractionLength(0))
                ) + " m"
        case .timedUpdates:
            let seconds = draft.timeIntervalSeconds
            if seconds < 60 { return "\(seconds) s" }
            if seconds.isMultiple(of: 60) { return "\(seconds / 60) min" }
            return "\(seconds / 60) min \(seconds % 60) s"
        case .motivation: return tr("About every ", "Omtrent hvert ") +
            "\(draft.smartPrompts.motivationIntervalSeconds) s"
        case .randomEncouragement: return tr("About every ", "Omtrent hvert ") +
            "\(draft.smartPrompts.randomIntervalSeconds) s"
        case .customAnnouncements: return "\(draft.customRules.count) " +
            tr("rules", "regler")
        case .customPhrases: return "\(draft.smartPrompts.customEncouragements.count) " +
            tr("phrases", "meldinger")
        case .landmarks: return "\(draft.smartPrompts.landmarks.count) " +
            tr("places", "steder")
        case .currentZone:
            if let interval = draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds {
                return tr("Every", "Hvert") + " \(interval) s"
            }
            return tr("Every 3 minutes", "Hvert tredje minutt")
        case .targetZoneCoach:
            return draft.smartPrompts.preferredHeartRateZone.map {
                tr("Target zone", "Målsone") + " \($0)"
            } ?? tr("Uses planned interval zone", "Bruker pulssonen i treningsøkten")
        case .adaptiveMotivation:
            return tr("Based on live effort and targets", "Styres av faktisk innsats og mål")
        case .intervalRecoveryCountdown:
            return tr("Before and during interval recovery", "Før og under intervallpause")
        default: return tr("Enabled", "Aktiv")
        }
    }
}
