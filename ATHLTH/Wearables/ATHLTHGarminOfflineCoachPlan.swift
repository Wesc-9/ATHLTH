import Foundation

/// First offline speech subset. This is a projection of the existing user
/// configuration; never silently replace a selected voice or drop rules.
/// Developer speech pack is a local test asset, not a production voice.
struct ATHLTHGarminOfflineCoachPlan: Equatable {
    enum ProjectionError: Error { case disabled, unsupported, voiceUnavailable }
    let language: String
    let start: Bool
    let pauseResume: Bool
    let complete: Bool
    let setComplete: Bool
    let restStart: Bool
    let restEnd: Bool
    let restCountdown: Int?
    let toRecovery: Int?
    let fromRecovery: Int?

    init(configuration c: WatchAudioCoachConfiguration, sport: ATHLTHGarminLiveSport,
         resolvedLanguage: WatchAudioCoachLanguage, developerVoiceExplicitlyAccepted: Bool) throws {
        guard c.enabled else { throw ProjectionError.disabled }
        guard developerVoiceExplicitlyAccepted,
              c.voiceIdentifier == nil,
              c.language == .system || c.language == resolvedLanguage,
              resolvedLanguage == .english || resolvedLanguage == .norwegian
        else { throw ProjectionError.voiceUnavailable }
        // These features require the complete shared trigger/rendering port.
        guard c.customRules?.isEmpty != false, c.coachGroups?.isEmpty != false,
              c.smartPrompts == nil, c.effectiveBoundaryCountdownRules.isEmpty,
              c.distanceIntervalMeters == nil, c.timeIntervalSeconds == nil,
              !c.announceDistance, !c.announceElapsedTime, !c.announceAveragePace,
              !c.announceClockTime, !c.announceHeartRate,
              !c.announceRemainingRouteDistance, !c.announceEstimatedRemainingRouteTime,
              !c.announceCurrentWorkoutStep, !c.announceRemainingStepTime,
              !c.announceRemainingStepDistance, c.fuelReminderIntervalMinutes == nil,
              c.strengthStatusIntervalSeconds == nil, c.strengthMotivationEverySets == nil,
              c.strengthPersonalMotivationPhrase == nil,
              c.resolvedStrengthCountdownToRest == nil,
              c.speechStyle == nil, c.speechRate == nil, c.speechVolume == nil,
              c.outputPreference != .iPhone,
              c.muteOtherAudio != true, c.duckOtherAudio != true
        else { throw ProjectionError.unsupported }
        if sport == .strength {
            guard !c.shouldAnnounceStrengthNextExercise,
                  !c.shouldAnnounceStrengthNextSetDetails,
                  !c.shouldAnnounceStrengthExerciseProgress,
                  !c.shouldAnnounceStrengthExerciseComplete
            else { throw ProjectionError.unsupported }
        }
        language = resolvedLanguage.rawValue
        start = c.shouldAnnounceWorkoutStart
        pauseResume = c.shouldAnnouncePauseResume
        complete = c.shouldAnnounceWorkoutComplete
        setComplete = sport == .strength && c.shouldAnnounceStrengthSetComplete
        restStart = sport == .strength && c.shouldAnnounceStrengthRestStarted
        restEnd = sport == .strength && c.shouldAnnounceStrengthRestComplete
        restCountdown = sport == .strength && c.shouldAnnounceStrengthRestCountdown
            ? (c.resolvedStrengthCountdownFromRest ?? c.resolvedStrengthRestCountdownSeconds) : nil
        toRecovery = sport == .strength ? nil : c.resolvedIntervalCountdownToRecovery
        fromRecovery = sport == .strength ? nil : c.resolvedIntervalCountdownFromRecovery
        // The initial local pack has 1...10 clips only. After-countdown
        // semantics requiring another spoken instruction are not implemented.
        guard [restCountdown, toRecovery, fromRecovery].compactMap({$0}).allSatisfy({ (1...10).contains($0) }),
              toRecovery == nil || c.resolvedIntervalAfterCountdownToRecovery == .numbersOnly,
              fromRecovery == nil || c.resolvedIntervalAfterCountdownFromRecovery == .numbersOnly,
              c.strengthAfterCountdownFromRest == nil || c.strengthAfterCountdownFromRest == .numbersOnly
        else { throw ProjectionError.unsupported }
    }

    var message: [String: Any] {
        var result: [String: Any] = ["pack": "developer-v1", "language": language,
            "start": start, "pauseResume": pauseResume, "complete": complete,
            "setComplete": setComplete, "restStart": restStart, "restEnd": restEnd]
        if let restCountdown { result["restCountdown"] = restCountdown }
        if let toRecovery { result["toRecovery"] = toRecovery }
        if let fromRecovery { result["fromRecovery"] = fromRecovery }
        return result
    }
}
