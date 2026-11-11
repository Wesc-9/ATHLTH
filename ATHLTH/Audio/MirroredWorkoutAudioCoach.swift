import AVFoundation
import Foundation

@MainActor
final class MirroredWorkoutAudioCoach:
    NSObject,
    AVSpeechSynthesizerDelegate
{
    private let synthesizer =
        AVSpeechSynthesizer()
    private let azureCoachSpeech = ATHLTHAzureWorkoutSpeech()
    private let audioOwner = "mirror-\(UUID().uuidString)"

    private var configuration:
        WatchAudioCoachConfiguration =
            .disabled
    private var guidanceGate =
        ATHLTHGuidancePriorityGate()
    private var eventLedger = ATHLTHCoachEventLedger()
    private var cueQueue = ATHLTHCoachCueQueue()
    private var localSpeechWatchdog: Task<Void, Never>?
    private var coachReplayMemory = ATHLTHCoachReplayMemory()
    var onLastSpokenCoachMessage: ((String?) -> Void)?

    var canReplayLastCoachMessage: Bool {
        configuration.enabled &&
        !finished &&
        coachReplayMemory.replayableText() != nil
    }

    func replayLastCoachMessage() {
        guard canReplayLastCoachMessage,
              let text = coachReplayMemory.replayableText()
        else { return }
        speak(text, priority: .structuredStep, rememberForReplay: false)
    }

    var onSpokenEventAttempt: ((ATHLTHCoachEvent, Date) -> Void)?
    private var workoutStartedAt: Date?
    private var pendingLocalSpokenEvent: (
        utterance: AVSpeechUtterance, event: ATHLTHCoachEvent
    )?

    private var nextDistanceMeters:
        Double?
    private var nextTimeSeconds:
        TimeInterval?
    private var nextFuelSeconds: TimeInterval?
    private var customAudioCoachLastSlots: [UUID: Int] = [:]
    private var smartCoachState = ATHLTHAudioCoachSmartState()
    private var adaptiveCoachState = ATHLTHCoachAdaptiveMotivation()
    private var measuredZoneCandidate: Int?
    private var measuredZoneFirstSeenAt: TimeInterval?
    private var lastMeasuredZoneAnnouncementAt: TimeInterval = -.infinity
    private var lastState:
        WatchWorkoutMirrorState?
    private var lastStepIndex: Int?
    private var currentRunningStepIndex: Int?
    private var lastIntervalProgressKey: String?
    private var lastIntervalWarningKey: String?
    private var announcedStart = false
    private var finished = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isEnabled: Bool {
        configuration.enabled
    }

    func prepare(
        _ configuration:
            WatchAudioCoachConfiguration
    ) {
        self.configuration =
            configuration
        guidanceGate.reset()
        eventLedger.reset()
        cueQueue.reset()
        coachReplayMemory.reset()
        onLastSpokenCoachMessage?(nil)
        lastState = nil
        lastStepIndex = nil
        lastIntervalProgressKey = nil
        lastIntervalWarningKey = nil
        announcedStart = false
        finished = false
        workoutStartedAt = nil
        pendingLocalSpokenEvent = nil
        smartCoachState.reset()
        adaptiveCoachState.reset()
        measuredZoneCandidate = nil
        measuredZoneFirstSeenAt = nil
        lastMeasuredZoneAnnouncementAt = -.infinity
        customAudioCoachLastSlots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: configuration.customRules ?? [],
            distanceMeters: 0,
            elapsedSeconds: 0
        )
        nextFuelSeconds = ATHLTHFuelVoicePrompt.nextDue(
            after: 0,
            config: configuration
        )

        if let interval =
                configuration
                    .distanceIntervalMeters,
           interval > 0 {
            nextDistanceMeters =
                interval
        } else {
            nextDistanceMeters =
                nil
        }

        if let interval =
                configuration
                    .timeIntervalSeconds,
           interval > 0 {
            nextTimeSeconds =
                interval
        } else {
            nextTimeSeconds =
                nil
        }

        if !configuration.enabled {
            stop()
        }
    }

    func handle(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) {
        guard configuration.enabled,
              !finished
        else {
            return
        }

        // Strength's detailed set, exercise and rest cues are generated
        // by Watch. The mirrored iPhone coach only has a generic start,
        // pause and completion vocabulary for strength, so speaking here
        // would duplicate the Watch-owned strength coaching.
        if snapshot.kind == .strength {
            if snapshot.state == .completed ||
                snapshot.state == .failed {
                finished = true
            }
            return
        }

        let previousState = lastState
        lastState = snapshot.state
        workoutStartedAt = snapshot.startedAt

        if snapshot.state == .running,
           !announcedStart {
            announcedStart = true

            if configuration
                .shouldAnnounceWorkoutStart {
                speak(
                    phrase(
                        english:
                            "Audio Coach ready. Workout started.",
                        norwegian:
                            "Audio Coach er klar. Økten er startet."
                    ),
                    priority:
                        .structuredStep
                )
            }
        }

        if configuration
            .shouldAnnouncePauseResume {
            if previousState == .running,
               snapshot.state == .paused {
                speak(
                    phrase(
                        english:
                            "Workout paused.",
                        norwegian:
                            "Økten er satt på pause."
                    ),
                    priority:
                        .structuredStep
                )
            } else if previousState == .paused,
                      snapshot.state == .running {
                speak(
                    phrase(
                        english:
                            "Workout resumed.",
                        norwegian:
                            "Økten fortsetter."
                    ),
                    priority:
                        .structuredStep
                )
            }
        }

        currentRunningStepIndex = snapshot.state == .running ? snapshot.runningStepIndex : nil
        if snapshot.state == .running,
           ATHLTHCoachSensorFreshness.isFresh(
               sampledAt: snapshot.capturedAt,
               maximumAge: ATHLTHCoachSensorFreshness.maximumSnapshotAge
           ) {
            announceStepIfNeeded(snapshot)
            announceIntervalProgressIfDue(snapshot)
            announceFuelIfNeeded(snapshot)
            let customDue = announceCustomAudioCoachRules(snapshot)
            announceMeasuredZoneIfNeeded(snapshot)
            announceRoutineIfNeeded(snapshot, customDue: customDue)
            announceSmartCoachIfNeeded(snapshot)
        }

        if snapshot.state == .completed {
            finished = true
            // Updated Watch owns its own final recap after checking saved
            // HealthKit running history. Never speak a second, competing
            // finish from iPhone when the Watch supports voice ownership.
            if snapshot.supportsAudioCoachVoiceLease == true {
                cueQueue.reset()
                return
            }
            if configuration.shouldAnnounceWorkoutComplete {
                let highlights = ATHLTHWorkoutCompletionSpokenSummary.make(
                    elapsedSeconds: snapshot.confirmedActiveDuration,
                    distanceMeters: snapshot.distanceMeters,
                    averageHeartRateBPM: snapshot.averageHeartRate
                )
                // Never rely on an Azure fallback after 'finished' becomes
                // true: its asynchronous completion callback is deliberately
                // suppressed after a stopped workout. Local speech is safe.
                speakFinishedWorkoutRecap(
                    phrase(
                        english: highlights.english,
                        norwegian: highlights.norwegian
                    )
                )
            }
        } else if snapshot.state == .failed {
            finished = true
        }
    }

    /// A new acknowledged lease must not replay an old start, step or
    /// milestone when iPhone takes over speech mid-workout.
    func synchronizeOnHandoff(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) {
        lastState = snapshot.state
        workoutStartedAt = snapshot.startedAt
        announcedStart =
            snapshot.state != .preparing
        lastStepIndex = snapshot.runningStepIndex
        measuredZoneCandidate = nil
        measuredZoneFirstSeenAt = nil
        lastMeasuredZoneAnnouncementAt = snapshot.elapsedTime

        if let interval = configuration.distanceIntervalMeters,
           interval > 0 {
            nextDistanceMeters =
                (floor(snapshot.distanceMeters / interval) + 1) * interval
        }
        if let interval = configuration.timeIntervalSeconds,
           interval > 0 {
            nextTimeSeconds =
                (floor(snapshot.elapsedTime / interval) + 1) * interval
        }
        customAudioCoachLastSlots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: configuration.customRules ?? [],
            distanceMeters: snapshot.distanceMeters,
            elapsedSeconds: snapshot.elapsedTime
        )
        nextFuelSeconds = ATHLTHFuelVoicePrompt.nextDue(
            after: snapshot.elapsedTime,
            config: configuration
        )
    }

    /// A Watch-originated attempt is not re-announced after a subsequent
    /// speech handoff to iPhone. Only the mirror store validates the receipt
    /// against its active workout before calling this method.
    func recordWatchSpokenEvent(
        _ receipt: ATHLTHCoachDeliveryReceipt,
        verifiedWorkoutStart: Date
    ) {
        guard receipt.isValid(for: verifiedWorkoutStart),
              workoutStartedAt.map({
                  abs($0.timeIntervalSince(verifiedWorkoutStart)) <= 1
              }) ?? true
        else { return }

        // The receipt can precede the very first snapshot handled by this
        // coach. Bind it to the independently verified active session so a
        // handoff cannot replay an already-spoken step.
        workoutStartedAt = verifiedWorkoutStart
        eventLedger.noteCompanionDelivery(id: receipt.deliveryID)
    }

    /// Stop audio immediately on expired ownership without discarding
    /// workout progress or queued configuration.
    func suspendForWatchFallback() {
        localSpeechWatchdog?.cancel()
        localSpeechWatchdog = nil
        azureCoachSpeech.stop()
        synthesizer.stopSpeaking(at: .immediate)
        ATHLTHSpokenAudioSession.deactivate(owner: audioOwner)
        guidanceGate.reset()
        cueQueue.reset()
    }

    func stop() {
        localSpeechWatchdog?.cancel()
        localSpeechWatchdog = nil
        azureCoachSpeech.stop()
        synthesizer.stopSpeaking(
            at: .immediate
        )
        ATHLTHSpokenAudioSession
            .deactivate(owner: audioOwner)
        guidanceGate.reset()
        eventLedger.reset()
        cueQueue.reset()
        coachReplayMemory.reset()
        onLastSpokenCoachMessage?(nil)
        configuration = .disabled
        nextDistanceMeters = nil
        nextTimeSeconds = nil
        nextFuelSeconds = nil
        customAudioCoachLastSlots = [:]
        smartCoachState.reset()
        adaptiveCoachState.reset()
        lastState = nil
        lastStepIndex = nil
        announcedStart = false
        finished = false
        workoutStartedAt = nil
        pendingLocalSpokenEvent = nil
    }

    private func announceIntervalProgressIfDue(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) {
        guard snapshot.runningAwaitingMainStart != true,
              let step = snapshot.runningStepTitle,
              !step.isEmpty,
              let index = snapshot.runningStepIndex,
              let elapsed = snapshot.runningStepElapsedSeconds,
              let remaining = snapshot.runningStepRemainingSeconds,
              elapsed.isFinite, elapsed >= 0,
              remaining.isFinite, remaining >= 0 else { return }

        if let warning = snapshot.runningIntervalCoachCountdownSeconds,
           warning >= 5, warning.isFinite,
           remaining > 0, remaining <= warning {
            let key = "\(snapshot.startedAt?.timeIntervalSince1970 ?? 0):\(index):\(Int(warning))"
            if lastIntervalWarningKey != key {
                lastIntervalWarningKey = key
                speak(
                    phrase(
                        english: "\(Int(ceil(remaining))) seconds left in \(step)",
                        norwegian: "\(Int(ceil(remaining))) sekunder igjen av \(step)"
                    ),
                    priority: .structuredStep,
                    event: ATHLTHCoachEvent(
                        kind: .runningStep, key: "mirror-warning:\(key)",
                        priority: .structuredStep,
                        createdAt: snapshot.capturedAt, validFor: 2, runningStepIndex: index
                    )
                )
            }
            return
        }

        guard let cadence = snapshot.runningIntervalCoachCueEverySeconds,
              cadence.isFinite, cadence >= 15,
              elapsed >= cadence, remaining > 2 else { return }
        let slot = Int(floor(elapsed / cadence))
        guard slot > 0, elapsed - Double(slot) * cadence < 2 else { return }
        let key = "\(snapshot.startedAt?.timeIntervalSince1970 ?? 0):\(index):\(slot)"
        guard lastIntervalProgressKey != key else { return }
        lastIntervalProgressKey = key
        speak(
            phrase(
                english: "\(Int(ceil(remaining))) seconds remaining in \(step)",
                norwegian: "\(Int(ceil(remaining))) sekunder igjen av \(step)"
            ),
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone, key: "mirror-interval:\(key)",
                priority: .routineCoach,
                createdAt: snapshot.capturedAt, validFor: 8
            )
        )
    }

    private func announceStepIfNeeded(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) {
        guard snapshot.runningAwaitingMainStart != true,
              configuration.announceCurrentWorkoutStep,
              let index =
                snapshot.runningStepIndex,
              index != lastStepIndex,
              let title =
                snapshot.runningStepTitle,
              !title.isEmpty
        else {
            return
        }

        lastStepIndex = index

        var text =
            phrase(
                english:
                    "Current step. \(title).",
                norwegian:
                    "Nåværende steg. \(title)."
            )

        if let count =
                snapshot.runningStepCount {
            text +=
                phrase(
                    english:
                        " Step \(index + 1) of \(count).",
                    norwegian:
                        " Steg \(index + 1) av \(count)."
                )
        }

        if let extra = ATHLTHIntervalCoachCue.phrase(
            brief: snapshot.runningStepCoachBrief,
            phase: snapshot.runningStepPhase,
            zone: snapshot.runningStepTargetHeartRateZone,
            norwegian: phrase(english: "en", norwegian: "no") == "no"
        ) {
            text += " " + extra
        }

        speak(
            text,
            priority: .structuredStep,
            event: ATHLTHCoachEvent(
                kind: .runningStep,
                key: String(index),
                priority: .structuredStep,
                createdAt: snapshot.capturedAt,
                validFor: 15, runningStepIndex: index
            )
        )
    }

    private func announceFuelIfNeeded(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) {
        guard let next = nextFuelSeconds,
              snapshot.elapsedTime >= next
        else { return }

        // Elapsed-time buckets are shared with Watch. A missed slot is not
        // read late after reconnect, pause or a temporary speech handoff.
        nextFuelSeconds = ATHLTHFuelVoicePrompt.nextDue(
            after: snapshot.elapsedTime,
            config: configuration
        )
        guard ATHLTHFuelVoicePrompt.isFreshDue(
            elapsed: snapshot.elapsedTime,
            scheduled: next
        ), let message = ATHLTHFuelVoicePrompt.phrase(
            config: configuration
        ) else { return }

        speak(
            message,
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: "fuel:\(Int(next))",
                priority: .routineCoach,
                createdAt: snapshot.capturedAt,
                validFor: 12
            )
        )
    }

    private func announceCustomAudioCoachRules(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> [ATHLTHAudioCoachDueAnnouncement] {
        ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: configuration.customRules ?? [],
            distanceMeters: snapshot.distanceMeters,
            elapsedSeconds: snapshot.elapsedTime,
            paceSecondsPerKilometer:
                ATHLTHCoachSensorFreshness.validPace(
                    resolvedPace(snapshot), sampledAt: snapshot.coachPaceSampleAt
                ) ? resolvedPace(snapshot) : nil,
            heartRateBPM: ATHLTHCoachSensorFreshness.validHeartRate(
                snapshot.heartRate, sampledAt: snapshot.coachHeartRateSampleAt
            ) ? snapshot.heartRate : nil,
            norwegian: phrase(english: "en", norwegian: "no") == "no",
            maximumHeartRateBPM: snapshot.coachResolvedMaximumHeartRateBPM ??
                configuration.smartPrompts?.maximumHeartRateBPM,
            lastSlots: &customAudioCoachLastSlots
        )
    }

    /// Keep iPhone voice ownership in sync with the Watch's measured-zone
    /// coaching. An actual pulse and a valid athlete HRmax are mandatory.
    private func announceMeasuredZoneIfNeeded(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) {
        guard (snapshot.kind == .running || snapshot.kind == .walking),
              // Updated Watch speaks measured-zone cues locally. Never
              // duplicate the same zone on the phone mirror.
              snapshot.supportsAudioCoachVoiceLease != true,
              (configuration.smartPrompts?.announceCurrentHeartRateZone ??
                configuration.announceHeartRate),
              (snapshot.runningStepTargetHeartRateZone == nil ||
               configuration.smartPrompts?.measuredZoneAnnouncementIntervalSeconds != nil),
              ATHLTHCoachSensorFreshness.validHeartRate(
                  snapshot.heartRate,
                  sampledAt: snapshot.coachHeartRateSampleAt
              ),
              let zone = ATHLTHHeartRateZones.measuredZone(
                  heartRateBPM: snapshot.heartRate,
                  maximumBPM: snapshot.coachResolvedMaximumHeartRateBPM ??
                    configuration.smartPrompts?.maximumHeartRateBPM
              )
        else {
            measuredZoneCandidate = nil
            measuredZoneFirstSeenAt = nil
            return
        }

        if measuredZoneCandidate != zone {
            measuredZoneCandidate = zone
            measuredZoneFirstSeenAt = snapshot.elapsedTime
            return
        }
        guard snapshot.elapsedTime - (measuredZoneFirstSeenAt ?? snapshot.elapsedTime) >= 15,
              snapshot.elapsedTime - lastMeasuredZoneAnnouncementAt >=
                (configuration.smartPrompts?.resolvedMeasuredZoneInterval ?? 180)
        else { return }
        lastMeasuredZoneAnnouncementAt = snapshot.elapsedTime
        speak(
            phrase(
                english: "Current heart-rate zone: Z\(zone).",
                norwegian: "Nåværende pulssone: S\(zone)."
            ),
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: "measured-zone-\(zone):\(Int(snapshot.elapsedTime))",
                priority: .routineCoach,
                createdAt: snapshot.capturedAt,
                validFor: 12
            )
        )
    }

    private func announceSmartCoachIfNeeded(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) {
        guard snapshot.kind == .running || snapshot.kind == .walking,
              let configuredSettings = configuration.smartPrompts
        else { return }

        // The independent periodic group is authoritative when both
        // legacy automatic motivation and an exact timer are configured.
        var resolvedSettings = configuredSettings
        if (configuration.customRules ?? []).contains(where: {
            $0.isEnabled && $0.selectedMetrics.contains(.motivation)
        }) {
            resolvedSettings.motivationEnabled = false
        }
        let settings = resolvedSettings
        let norwegian = phrase(english: "en", norwegian: "no") == "no"
        let positionCue = smartCoachState.nextLandmark(
            settings: settings,
            latitude: snapshot.currentLatitude,
            longitude: snapshot.currentLongitude,
            horizontalAccuracy: snapshot.currentHorizontalAccuracy,
            locationAge: Date().timeIntervalSince(
                snapshot.currentLocationSampledAt ?? .distantPast
            ),
            norwegian: norwegian,
            elapsedSeconds: snapshot.elapsedTime,
            routeProgressPercent: snapshot.routeProgressPercent
        )
        if let positionCue {
            speak(
                positionCue,
                priority: .routineCoach,
                event: ATHLTHCoachEvent(
                    kind: .routineMilestone,
                    key: "smart-place:\(Int(snapshot.elapsedTime))",
                    priority: .routineCoach,
                    createdAt: snapshot.capturedAt,
                    validFor: 10
                )
            )
            return
        }

        // Missing terrain evidence from an older Watch is never treated as
        // a verified flat/downhill stretch.
        let targetRange = ATHLTHHeartRateZones.range(
            for: snapshot.runningStepTargetHeartRateZone ??
                snapshot.heartRateTargetZone ??
                settings.preferredHeartRateZone ?? 0,
            maximumBPM: snapshot.coachResolvedMaximumHeartRateBPM ??
                settings.maximumHeartRateBPM
        )
        if let message = adaptiveCoachState.nextCue(
            settings: settings,
            elapsed: snapshot.elapsedTime,
            measuredPaceSecondsPerKilometer:
                ATHLTHCoachSensorFreshness.validPace(
                    resolvedPace(snapshot), sampledAt: snapshot.coachPaceSampleAt
                ) ? resolvedPace(snapshot) : nil,
            targetSlowestPaceSecondsPerKilometer:
                snapshot.runningStepTargetSlowestPaceSecondsPerKilometer ??
                snapshot.runningStepTargetPaceSecondsPerKilometer,
            measuredHeartRateBPM: ATHLTHCoachSensorFreshness.validHeartRate(
                snapshot.heartRate, sampledAt: snapshot.coachHeartRateSampleAt
            ) ? snapshot.heartRate : nil,
            targetHeartRateMinimumBPM:
                snapshot.heartRateTargetMinimumBPM ??
                targetRange.map { Double($0.lowerBound) },
            reliableNotClimbing:
                snapshot.coachReliableNonClimbingTerrain == true,
            norwegian: norwegian
        ) {
            smartCoachState.noteExternalPrompt(
                elapsed: snapshot.elapsedTime, settings: settings
            )
            speak(
                message,
                priority: .routineCoach,
                event: ATHLTHCoachEvent(
                    kind: .routineMilestone,
                    key: "adaptive-motivation:\(Int(snapshot.elapsedTime))",
                    priority: .routineCoach,
                    createdAt: snapshot.capturedAt,
                    validFor: 12
                )
            )
            return
        }

        if let message = smartCoachState.nextMotivation(
            settings: settings,
            elapsed: snapshot.elapsedTime,
            paceSecondsPerKilometer: resolvedPace(snapshot),
            norwegian: norwegian,
            environment: ATHLTHCoachEnvironmentalContext(
                routeRemainingMeters: snapshot.routeRemainingMeters,
                routeProgressPercent: snapshot.routeProgressPercent
            )
        ) {
            speak(
                message,
                priority: .routineCoach,
                event: ATHLTHCoachEvent(
                    kind: .routineMilestone,
                    key: "smart-motivation:\(Int(snapshot.elapsedTime))",
                    priority: .routineCoach,
                    createdAt: snapshot.capturedAt,
                    validFor: 12
                )
            )
        }
    }

    private func announceRoutineIfNeeded(
        _ snapshot: WatchWorkoutLiveSnapshot,
        customDue: [ATHLTHAudioCoachDueAnnouncement]
    ) {
        var due = false
        var milestoneKeys: [String] = []

        if let next =
                nextDistanceMeters,
           snapshot.distanceMeters >= next {
            due = true
            milestoneKeys.append("d\(Int(next.rounded()))")

            if let interval =
                    configuration
                        .distanceIntervalMeters,
               interval > 0 {
                var advanced = next
                while advanced <=
                        snapshot.distanceMeters {
                    advanced += interval
                }
                nextDistanceMeters =
                    advanced
            }
        }

        if let next =
                nextTimeSeconds,
           snapshot.elapsedTime >= next {
            due = true
            milestoneKeys.append("t\(Int(next.rounded()))")

            if let interval =
                    configuration
                        .timeIntervalSeconds,
               interval > 0 {
                var advanced = next
                while advanced <=
                        snapshot.elapsedTime {
                    advanced += interval
                }
                nextTimeSeconds =
                    advanced
            }
        }

        let covered = customDue.reduce(
            into: Set<ATHLTHAudioCoachRule.Metric>()
        ) { result, cue in
            result.formUnion(cue.metrics)
        }
        var parts: [String] = []
        if due {
            let regular = routinePhrase(snapshot, excluding: covered)
            if !regular.isEmpty { parts.append(regular) }
        }
        parts.append(contentsOf: customDue.map(\.text))
        guard !parts.isEmpty else { return }

        speak(
            parts.joined(separator: ". "),
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: ATHLTHAudioCoachRuleDelivery.stableDeliveryKey(
                    standardMilestones: due ? milestoneKeys : [],
                    customAnnouncements: customDue
                ),
                priority: .routineCoach,
                createdAt: snapshot.capturedAt,
                validFor: 10
            )
        )
    }

    private func routinePhrase(
        _ snapshot: WatchWorkoutLiveSnapshot,
        excluding metrics: Set<ATHLTHAudioCoachRule.Metric>
    ) -> String {
        var english: [String] = []
        var norwegian: [String] = []

        if configuration.announceDistance,
           !metrics.contains(.distance) {
            let kilometers =
                snapshot.distanceMeters /
                1_000
            english.append(
                String(
                    format:
                        "Distance %.2f kilometers",
                    kilometers
                )
            )
            norwegian.append(
                String(
                    format:
                        "Distanse %.2f kilometer",
                    kilometers
                )
            )
        }

        if configuration.announceElapsedTime,
           !metrics.contains(.elapsedTime) {
            let minutes =
                Int(
                    snapshot.elapsedTime
                        .rounded(.down)
                ) / 60
            let seconds =
                Int(
                    snapshot.elapsedTime
                        .rounded(.down)
                ) % 60

            english.append(
                seconds == 0
                    ? "\(minutes) minutes"
                    : "\(minutes) minutes \(seconds) seconds"
            )
            norwegian.append(
                seconds == 0
                    ? "\(minutes) minutter"
                    : "\(minutes) minutter \(seconds) sekunder"
            )
        }

        if configuration.announceAveragePace,
           !metrics.contains(.pace),
           let pace =
                resolvedPace(snapshot) {
            let total =
                max(
                    Int(
                        pace.rounded()
                    ),
                    0
                )
            let min = total / 60
            let sec = total % 60

            english.append(
                String(
                    format:
                        "Pace %d minutes %02d seconds per kilometer",
                    min,
                    sec
                )
            )
            norwegian.append(
                String(
                    format:
                        "Tempo %d minutter %02d sekunder per kilometer",
                    min,
                    sec
                )
            )
        }

        if configuration.announceHeartRate,
           !metrics.contains(.heartRate),
           ATHLTHCoachSensorFreshness.validHeartRate(
               snapshot.heartRate,
               sampledAt: snapshot.coachHeartRateSampleAt
           ) {
            english.append(
                "Heart rate \(Int(snapshot.heartRate.rounded()))"
            )
            norwegian.append(
                "Puls \(Int(snapshot.heartRate.rounded()))"
            )
        }

        if configuration
            .announceClockTime {
            let formatter =
                DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            let value =
                formatter.string(
                    from: Date()
                )
            english.append(
                "Time \(value)"
            )
            norwegian.append(
                "Klokken er \(value)"
            )
        }

        if configuration
            .announceRemainingRouteDistance,
           let remaining =
                snapshot
                    .routeRemainingMeters {
            english.append(
                String(
                    format:
                        "%.1f kilometers remaining",
                    max(
                        remaining,
                        0
                    ) / 1_000
                )
            )
            norwegian.append(
                String(
                    format:
                        "%.1f kilometer igjen",
                    max(
                        remaining,
                        0
                    ) / 1_000
                )
            )
        }

        if configuration
            .announceEstimatedRemainingRouteTime,
           let remaining =
                snapshot
                    .routeRemainingMeters,
           let pace =
                resolvedPace(snapshot),
           pace > 0 {
            let seconds =
                max(
                    remaining,
                    0
                ) / 1_000 * pace
            let minutes =
                Int(
                    (
                        seconds /
                        60
                    ).rounded()
                )

            english.append(
                "About \(minutes) minutes remaining"
            )
            norwegian.append(
                "Omtrent \(minutes) minutter igjen"
            )
        }

        if configuration
            .announceCurrentWorkoutStep,
           let title =
                snapshot
                    .runningStepTitle,
           !title.isEmpty {
            english.append(
                "Current step \(title)"
            )
            norwegian.append(
                "Nåværende steg \(title)"
            )
        }

        return phrase(
            english:
                english.joined(
                    separator: ". "
                ),
            norwegian:
                norwegian.joined(
                    separator: ". "
                )
        )
    }

    private func resolvedPace(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> TimeInterval? {
        guard ATHLTHCoachSensorFreshness.validPace(
            snapshot.currentPaceSecondsPerKilometer,
            sampledAt: snapshot.coachPaceSampleAt
        ) else { return nil }

        return snapshot.currentPaceSecondsPerKilometer
    }

    private func phrase(
        english: String,
        norwegian: String
    ) -> String {
        switch configuration.language {
        case .english:
            return english
        case .norwegian:
            return norwegian
        case .system:
            let code =
                Locale.autoupdatingCurrent
                    .language
                    .languageCode?
                    .identifier
                    .lowercased()

            return (
                code == "nb" ||
                code == "nn" ||
                code == "no"
            )
                ? norwegian
                : english
        }
    }

    private func speakFinishedWorkoutRecap(_ phrase: String) {
        guard configuration.enabled, !phrase.isEmpty else { return }
        // The last announcement owns the remaining speaker time. Old
        // kilometre, interval and motivation cues cannot play after finish.
        cueQueue.reset()
        azureCoachSpeech.stop()
        synthesizer.stopSpeaking(at: .immediate)
        guidanceGate.reset()

        // The finish recap must use the same selected speaker as the
        // mirrored workout. Unlike routine cues, completion may speak
        // after finished=true; Azure's async fallback is still allowed.
        let routed = azureCoachSpeech.begin(
            phrase,
            voiceIdentifier: configuration.voiceIdentifier,
            duckMusic: configuration.shouldDuckOtherAudio,
            onFallback: { [weak self] in
                self?.speakFinishedWorkoutRecapLocally(phrase)
            },
            onStarted: {},
            onFinished: {}
        )
        if !routed {
            speakFinishedWorkoutRecapLocally(phrase)
        }
    }

    private func speakFinishedWorkoutRecapLocally(_ phrase: String) {
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = ATHLTHCoachPreferredSystemVoice.resolve(
            selectedIdentifier: configuration.voiceIdentifier,
            language: configuration.language
        )
        utterance.rate = configuration.resolvedSpeechRate
        utterance.volume = configuration.resolvedSpeechVolume
        try? ATHLTHSpokenAudioSession.activate(
            duckOtherAudio: configuration.shouldDuckOtherAudio,
            owner: audioOwner
        )
        synthesizer.speak(utterance)
        watchLocalSpeech(utterance)
    }

    private func speak(
        _ text: String,
        priority:
            ATHLTHGuidancePriority,
        event: ATHLTHCoachEvent? = nil,
        rememberForReplay: Bool = true
    ) {
        guard !text.isEmpty,
              configuration.enabled,
              !finished
        else {
            return
        }
        if let event,
           !eventLedger.canDeliver(event) {
            return
        }

        let decision =
            guidanceGate
                .voiceDecision(
                    for: priority,
                    isSpeaking:
                        synthesizer.isSpeaking || azureCoachSpeech.isBusy,
                    quietPeriodSeconds:
                        configuration
                            .resolvedGuidanceQuietPeriodSeconds
                )

        switch decision {
        case .drop:
            if priority >= .ghostImportant {
                let queuedEvent = event ??
                    ATHLTHCoachEventFallback.event(for: priority)
                cueQueue.enqueue(
                    ATHLTHCoachQueuedCue(
                        event: queuedEvent,
                        text: text
                    )
                )
            }
            return
        case .interruptAndDeliver:
            azureCoachSpeech.stop()
            synthesizer.stopSpeaking(
                at: .immediate
            )
        case .deliver:
            break
        }

        // Only acknowledge a cue when the selected speech engine starts.
        let spokenText = rememberForReplay
            ? (configuration.speechStyle ?? .balanced).render(
                text,
                language: configuration.language,
                priority: priority,
                eventKind: event?.kind
            )
            : text
        let utterance =
            AVSpeechUtterance(
                string: spokenText
            )

        // The mirrored iPhone coach uses the same selected/highest-quality
        // local voice as live running and the settings preview.
        utterance.voice = ATHLTHCoachPreferredSystemVoice.resolve(
            selectedIdentifier: configuration.voiceIdentifier,
            language: configuration.language
        )

        utterance.rate =
            configuration
                .resolvedSpeechRate
        utterance.volume =
            configuration
                .resolvedSpeechVolume

        let routedToAzure = azureCoachSpeech.begin(
            spokenText,
            voiceIdentifier: configuration.voiceIdentifier,
            duckMusic: configuration.shouldDuckOtherAudio,
            shouldStart: { [weak self] in
                guard let self, self.configuration.enabled, !self.finished else { return false }
                guard let event else { return true }
                return event.isFresh() && (event.runningStepIndex == nil ||
                    event.runningStepIndex == self.currentRunningStepIndex)
            },
            onFallback: { [weak self] in
                guard let self, self.configuration.enabled, !self.finished
                else { return }
                try? ATHLTHSpokenAudioSession.activate(
                    duckOtherAudio: self.configuration.shouldDuckOtherAudio,
                    owner: self.audioOwner
                )
                self.pendingLocalSpokenEvent = event.map {
                    (utterance: utterance, event: $0)
                }
                self.synthesizer.speak(utterance)
                self.watchLocalSpeech(utterance)
            },
            onStarted: { [weak self] in
                guard let self, let event else { return }
                self.markSpokenEventStarted(event)
            },
            onFinished: { [weak self] in
                guard let self else { return }
                self.guidanceGate.voiceDidFinish()
                self.deliverNextQueuedCue()
            }
        )
        if !routedToAzure {
            try? ATHLTHSpokenAudioSession.activate(
                duckOtherAudio: configuration.shouldDuckOtherAudio,
                owner: audioOwner
            )
            pendingLocalSpokenEvent = event.map {
                (utterance: utterance, event: $0)
            }
            synthesizer.speak(utterance)
            watchLocalSpeech(utterance)
        }
        if rememberForReplay,
           ATHLTHCoachReplayMemory.mayRemember(priority: priority) {
            coachReplayMemory.remember(spokenText, priority: priority)
            onLastSpokenCoachMessage?(coachReplayMemory.text)
        }
    }

    private func markSpokenEventStarted(_ event: ATHLTHCoachEvent) {
        guard eventLedger.canDeliver(event) else { return }
        eventLedger.didDeliver(event)
        if let workoutStartedAt {
            onSpokenEventAttempt?(event, workoutStartedAt)
        }
    }

    /// The local synthesizer occasionally loses its finish callback during a
    /// Bluetooth handoff. A bounded watchdog always releases our own lease.
    private func watchLocalSpeech(_ utterance: AVSpeechUtterance) {
        localSpeechWatchdog?.cancel()
        // Release ducking promptly if AVSpeechSynthesizer drops its finish
        // callback during an AirPods/Bluetooth route change. The previous
        // 60-second minimum left music quiet long after a short cue ended.
        let seconds = max(12, min(48, Double(utterance.speechString.count) / 8 + 10))
        localSpeechWatchdog = Task { @MainActor [weak self] in
            for _ in 0..<Int(ceil(seconds)) {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                if !self.synthesizer.isSpeaking && !self.azureCoachSpeech.isBusy {
                    self.localSpeechWatchdog = nil
                    ATHLTHSpokenAudioSession.deactivate(owner: self.audioOwner)
                    self.guidanceGate.voiceDidFinish()
                    self.deliverNextQueuedCue()
                    return
                }
            }
            guard !Task.isCancelled, let self,
                  !self.azureCoachSpeech.isBusy else { return }
            self.synthesizer.stopSpeaking(at: .immediate)
            self.localSpeechWatchdog = nil
            ATHLTHSpokenAudioSession.deactivate(owner: self.audioOwner)
            self.guidanceGate.voiceDidFinish()
            self.deliverNextQueuedCue()
        }
    }

    private func deliverNextQueuedCue() {
        let currentIndex = currentRunningStepIndex
        cueQueue.discardObsoleteRunningSteps(currentIndex: currentIndex)
        guard !finished, !synthesizer.isSpeaking,
              !azureCoachSpeech.isBusy,
              let next = cueQueue.popNext()
        else { return }
        speak(
            next.text,
            priority: next.event.priority,
            event: next.event
        )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        // The AVFoundation delegate may call this off the main actor.
        // Pass only the Sendable object identity into the actor-isolated Task.
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self,
                  let pending = self.pendingLocalSpokenEvent,
                  ObjectIdentifier(pending.utterance) == utteranceID else { return }
            self.pendingLocalSpokenEvent = nil
            self.markSpokenEventStarted(pending.event)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer:
            AVSpeechSynthesizer,
        didFinish utterance:
            AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.pendingLocalSpokenEvent.map({
                ObjectIdentifier($0.utterance) == utteranceID
            }) == true {
                self.pendingLocalSpokenEvent = nil
            }
            guard !self
                    .synthesizer
                    .isSpeaking,
                  !self.azureCoachSpeech.isBusy
            else {
                return
            }

            self.guidanceGate
                .voiceDidFinish()
            // A cancelled system utterance can finish its delegate callback
            // after an Azure replacement has already started. Never release
            // the ducking audio session while a second coach voice is active.
            self.localSpeechWatchdog?.cancel()
            self.localSpeechWatchdog = nil
            ATHLTHSpokenAudioSession.deactivate(owner: audioOwner)
            self.deliverNextQueuedCue()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer:
            AVSpeechSynthesizer,
        didCancel utterance:
            AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.pendingLocalSpokenEvent.map({
                ObjectIdentifier($0.utterance) == utteranceID
            }) == true {
                self.pendingLocalSpokenEvent = nil
            }
            guard !self
                    .synthesizer
                    .isSpeaking,
                  !self.azureCoachSpeech.isBusy
            else {
                return
            }

            self.guidanceGate
                .voiceDidFinish()
            // A cancelled system utterance can finish its delegate callback
            // after an Azure replacement has already started. Never release
            // the ducking audio session while a second coach voice is active.
            self.localSpeechWatchdog?.cancel()
            self.localSpeechWatchdog = nil
            ATHLTHSpokenAudioSession.deactivate(owner: audioOwner)
            self.deliverNextQueuedCue()
        }
    }
}
