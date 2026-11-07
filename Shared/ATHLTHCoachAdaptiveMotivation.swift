import Foundation

/// Reactive motivation runs on BOTH Watch and iPhone voice owners. It never
/// substitutes an athlete's planned targets for measured sensor values.
struct ATHLTHCoachAdaptiveMotivation {
    private var lastCueElapsed: TimeInterval = -.infinity
    private var lastStartSlot = -1
    private var lowZoneSince: TimeInterval?
    private var slowTargetSince: TimeInterval?
    private var paceDropSince: TimeInterval?
    private var reliablePaceBaseline: Double?

    mutating func reset() { self = Self() }

    /// nil means no justified intervention. Every trigger needs a live
    /// measurement, a stable shortfall and a global anti-spam cooldown.
    mutating func nextCue(
        settings: ATHLTHAudioCoachSmartSettings,
        elapsed: TimeInterval,
        measuredPaceSecondsPerKilometer: Double?,
        targetSlowestPaceSecondsPerKilometer: Double?,
        measuredHeartRateBPM: Double?,
        targetHeartRateMinimumBPM: Double?,
        reliableNotClimbing: Bool,
        norwegian: Bool
    ) -> String? {
        guard settings.coachingMode == .custom,
              elapsed.isFinite, elapsed >= 0 else { return nil }

        let pace: Double? = {
            guard let measuredPaceSecondsPerKilometer,
                  measuredPaceSecondsPerKilometer.isFinite,
                  (150...1_200).contains(measuredPaceSecondsPerKilometer)
            else { return nil }
            return measuredPaceSecondsPerKilometer
        }()

        // A validated baseline is only updated when pace is stable or
        // improving. Repeated slow readings cannot drag the baseline down
        // and then retrigger a fake recovery.
        if reliableNotClimbing, let pace {
            if let baseline = reliablePaceBaseline {
                if pace <= baseline * 1.05 {
                    reliablePaceBaseline = baseline * 0.9 + pace * 0.1
                }
            } else if elapsed >= 60 {
                reliablePaceBaseline = pace
            }
        }

        let belowHeartRate: Bool = {
            guard settings.pushWhenBelowTargetZone == true,
                  let measuredHeartRateBPM,
                  (30...240).contains(measuredHeartRateBPM),
                  let targetHeartRateMinimumBPM,
                  targetHeartRateMinimumBPM.isFinite
            else { return false }
            return measuredHeartRateBPM < targetHeartRateMinimumBPM
        }()
        lowZoneSince = belowHeartRate ? (lowZoneSince ?? elapsed) : nil

        let slowerThanTarget: Bool = {
            guard settings.pushWhenBelowTargetPace == true,
                  let pace, let targetSlowestPaceSecondsPerKilometer,
                  targetSlowestPaceSecondsPerKilometer.isFinite,
                  targetSlowestPaceSecondsPerKilometer > 0
            else { return false }
            return pace > targetSlowestPaceSecondsPerKilometer * 1.04
        }()
        slowTargetSince = slowerThanTarget ? (slowTargetSince ?? elapsed) : nil

        // A non-climbing terrain classification must come from good GPS
        // altitude samples; unknown terrain cannot be called "flat".
        let paceDropped: Bool = {
            guard settings.pushOnUnexpectedPaceDrop == true,
                  reliableNotClimbing, let pace,
                  let baseline = reliablePaceBaseline
            else { return false }
            return pace > baseline * (1 + settings.resolvedPaceDropPercent)
        }()
        paceDropSince = paceDropped ? (paceDropSince ?? elapsed) : nil

        guard elapsed - lastCueElapsed >= settings.resolvedAdaptiveCooldown
        else { return nil }

        let startupSeconds = min(max(settings.strongStartDurationSeconds ?? 0, 0), 600)
        if startupSeconds > 0, elapsed >= 15, elapsed <= Double(startupSeconds) {
            let slot = Int(elapsed / 60)
            if slot > lastStartSlot {
                lastStartSlot = slot
                lastCueElapsed = elapsed
                let phrases = norwegian
                    ? [
                        "Du er i gang! Finn flyten og jobb deg kontrollert opp i tempo.",
                        "Sterk åpning! Hold rytmen og gi deg selv en god start.",
                        "Nå bygger du økten. Bruk energien og hold stegene lette."
                      ]
                    : [
                        "You're moving! Find your rhythm and build the pace steadily.",
                        "Strong start! Hold your rhythm and settle into the effort.",
                        "You're building this session. Stay light and focused."
                      ]
                return phrases[slot % phrases.count]
            }
        }

        if let start = lowZoneSince, elapsed - start >= 18 {
            lastCueElapsed = elapsed
            return norwegian
                ? "Du ligger under planlagt pulssone. Øk innsatsen litt om det kjennes riktig."
                : "You're below the planned heart-rate zone. Gently build the effort if it feels right."
        }

        if let start = slowTargetSince, elapsed - start >= 20 {
            lastCueElapsed = elapsed
            return norwegian
                ? "Tempoet ligger under målet nå. Finn rytmen og jobb deg gradvis tilbake."
                : "Your pace is slower than the goal. Find your rhythm and build back gradually."
        }

        if let start = paceDropSince, elapsed - start >= 25 {
            lastCueElapsed = elapsed
            return norwegian
                ? "Farten har falt merkbart uten en registrert stigning. Finn rytmen igjen om du har overskudd."
                : "Your pace has dropped with no verified climb. Find your rhythm if you have energy left."
        }
        return nil
    }
}
