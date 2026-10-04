import AVFoundation
import Foundation

@MainActor
final class MirroredWorkoutAudioCoach:
    NSObject,
    AVSpeechSynthesizerDelegate
{
    private let synthesizer =
        AVSpeechSynthesizer()

    private var configuration:
        WatchAudioCoachConfiguration =
            .disabled
    private var guidanceGate =
        ATHLTHGuidancePriorityGate()

    private var nextDistanceMeters:
        Double?
    private var nextTimeSeconds:
        TimeInterval?
    private var lastState:
        WatchWorkoutMirrorState?
    private var lastStepIndex: Int?
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
        lastState = nil
        lastStepIndex = nil
        announcedStart = false
        finished = false

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

        let previousState = lastState
        lastState = snapshot.state

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

        if snapshot.state == .running {
            announceStepIfNeeded(
                snapshot
            )
            announceRoutineIfNeeded(
                snapshot
            )
        }

        if snapshot.state == .completed {
            finished = true

            if configuration
                .shouldAnnounceWorkoutComplete {
                speak(
                    phrase(
                        english:
                            "Workout complete. Nice work.",
                        norwegian:
                            "Økten er fullført. Bra jobbet."
                    ),
                    priority:
                        .structuredStep
                )
            }
        } else if snapshot.state == .failed {
            finished = true
        }
    }

    func stop() {
        synthesizer.stopSpeaking(
            at: .immediate
        )
        ATHLTHSpokenAudioSession
            .deactivate()
        guidanceGate.reset()
        configuration = .disabled
        nextDistanceMeters = nil
        nextTimeSeconds = nil
        lastState = nil
        lastStepIndex = nil
        announcedStart = false
        finished = false
    }

    private func announceStepIfNeeded(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) {
        guard configuration
                .announceCurrentWorkoutStep,
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

        speak(
            text,
            priority:
                .structuredStep
        )
    }

    private func announceRoutineIfNeeded(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) {
        var due = false

        if let next =
                nextDistanceMeters,
           snapshot.distanceMeters >= next {
            due = true

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

        guard due else {
            return
        }

        let text =
            routinePhrase(snapshot)

        guard !text.isEmpty else {
            return
        }

        speak(
            text,
            priority:
                .routineCoach
        )
    }

    private func routinePhrase(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> String {
        var english: [String] = []
        var norwegian: [String] = []

        if configuration.announceDistance {
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

        if configuration
            .announceElapsedTime {
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

        if configuration
            .announceAveragePace,
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

        if configuration
            .announceHeartRate,
           snapshot.heartRate > 0 {
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
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> TimeInterval? {
        if let current =
                snapshot
                    .currentPaceSecondsPerKilometer,
           current > 0,
           current.isFinite {
            return current
        }

        guard snapshot.distanceMeters > 20,
              snapshot.elapsedTime > 0
        else {
            return nil
        }

        let pace =
            snapshot.elapsedTime /
            snapshot.distanceMeters *
            1_000

        return pace.isFinite &&
            pace > 0
            ? pace
            : nil
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

    private func speak(
        _ text: String,
        priority:
            ATHLTHGuidancePriority
    ) {
        guard !text.isEmpty else {
            return
        }

        let decision =
            guidanceGate
                .voiceDecision(
                    for: priority,
                    isSpeaking:
                        synthesizer.isSpeaking,
                    quietPeriodSeconds:
                        configuration
                            .resolvedGuidanceQuietPeriodSeconds
                )

        switch decision {
        case .drop:
            return
        case .interruptAndDeliver:
            synthesizer.stopSpeaking(
                at: .immediate
            )
        case .deliver:
            break
        }

        do {
            try ATHLTHSpokenAudioSession
                .activate(
                    duckOtherAudio:
                        configuration
                            .shouldDuckOtherAudio
                )
        } catch {
            // Spoken coaching must never interfere with workout capture.
        }

        let utterance =
            AVSpeechUtterance(
                string: text
            )

        if let identifier =
                configuration
                    .voiceIdentifier,
           let voice =
                AVSpeechSynthesisVoice(
                    identifier:
                        identifier
                ) {
            utterance.voice = voice
        } else {
            switch configuration.language {
            case .norwegian:
                utterance.voice =
                    AVSpeechSynthesisVoice(
                        language: "nb-NO"
                    )
            case .english:
                utterance.voice =
                    AVSpeechSynthesisVoice(
                        language: "en-US"
                    )
            case .system:
                break
            }
        }

        utterance.rate =
            configuration
                .resolvedSpeechRate
        utterance.volume =
            configuration
                .resolvedSpeechVolume

        synthesizer.speak(
            utterance
        )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer:
            AVSpeechSynthesizer,
        didFinish utterance:
            AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self
                    .synthesizer
                    .isSpeaking
            else {
                return
            }

            self.guidanceGate
                .voiceDidFinish()
            ATHLTHSpokenAudioSession
                .deactivate()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer:
            AVSpeechSynthesizer,
        didCancel utterance:
            AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self
                    .synthesizer
                    .isSpeaking
            else {
                return
            }

            self.guidanceGate
                .voiceDidFinish()
            ATHLTHSpokenAudioSession
                .deactivate()
        }
    }
}
