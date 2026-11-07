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
    private var lastZonePrompt = -Double.infinity
    private var lastTargetPacePrompt = -Double.infinity
    private var lastDropPrompt = -Double.infinity
    private var zonePromptCount = 0
    private var targetPacePromptCount = 0
    private var dropPromptCount = 0

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

        let stronger = settings.encouragementStyle == .push

        if let start = lowZoneSince, elapsed - start >= 18,
           elapsed - lastZonePrompt >= settings.resolvedBelowZoneRepeat {
            lastCueElapsed = elapsed
            lastZonePrompt = elapsed
            let choices = norwegian
                ? (stronger ? [
                    "Du er under målsonen. Finn litt mer driv og jobb deg kontrollert opp!",
                    "Kom igjen, bygg innsatsen mot målsonen, steg for steg!",
                    "Nå har du mer å hente. Øk litt dersom kroppen føles klar!"
                  ] : [
                    "Du ligger under planlagt pulssone. Øk litt om det kjennes riktig.",
                    "Litt under målsonen nå. Finn en god rytme og øk gradvis.",
                    "Pulsen er under målet. Jobb deg rolig tilbake mot sonen."
                  ])
                : (stronger ? [
                    "You're below the target zone. Build the effort, one step at a time!",
                    "Come on, bring the effort up steadily toward your target!",
                    "There's more to give if you feel ready. Build the effort!"
                  ] : [
                    "You're below the planned zone. Build the effort if it feels right.",
                    "A little under target now. Find your rhythm and build gradually.",
                    "Your pulse is below target. Work your way back steadily."
                  ])
            let line = choices[zonePromptCount % choices.count]
            zonePromptCount += 1
            return line
        }

        if let start = slowTargetSince, elapsed - start >= 20,
           elapsed - lastTargetPacePrompt >= settings.resolvedBelowPaceRepeat {
            lastCueElapsed = elapsed
            lastTargetPacePrompt = elapsed
            let choices = norwegian
                ? (stronger ? [
                    "Du ligger bak måltempoet. Finn frekvensen og press deg kontrollert tilbake!",
                    "Farten er under målet! Øk stegfrekvensen litt hvis du har overskudd.",
                    "Nå jakter vi tempoet. Bygg opp farten kontrollert!"
                  ] : [
                    "Tempoet ligger under målet. Finn rytmen og jobb deg gradvis tilbake.",
                    "Du er litt saktere enn planlagt. Små justeringer kan være nok.",
                    "Måltempoet er litt foran deg. Finn et jevnt, kontrollert steg."
                  ])
                : (stronger ? [
                    "You're behind target pace. Build your rhythm and work back!",
                    "Pace is below target! Pick up the cadence if you have energy.",
                    "Let's chase the goal pace. Build speed with control!"
                  ] : [
                    "You're slower than target. Find your rhythm and build back gradually.",
                    "A little behind planned pace. Small adjustments may be enough.",
                    "Target pace is ahead. Settle into a steady, controlled stride."
                  ])
            let line = choices[targetPacePromptCount % choices.count]
            targetPacePromptCount += 1
            return line
        }

        if let start = paceDropSince, elapsed - start >= 25,
           elapsed - lastDropPrompt >= settings.resolvedUnexpectedDropRepeat {
            lastCueElapsed = elapsed
            lastDropPrompt = elapsed
            let choices = norwegian
                ? (stronger ? [
                    "Farten har falt uten målt stigning. Finn igjen steget og jobb deg opp!",
                    "Et merkbart tempofall! Har du overskudd, ta tilbake rytmen!",
                    "Ingen bekreftet bakke nå. Prøv å samle stegene og hente tilbake tempo!"
                  ] : [
                    "Farten har falt uten registrert stigning. Finn rytmen om du har overskudd.",
                    "Du har senket farten en del. Sjekk pusten, og finn flyten igjen.",
                    "Tempoet har falt. Ta en kontrollert vurdering før du øker igjen."
                  ])
                : (stronger ? [
                    "Pace has dropped without a measured climb. Find your stride again!",
                    "A notable pace drop. If you have energy, regain that rhythm!",
                    "No verified climb here. Bring back your cadence if you can!"
                  ] : [
                    "Pace dropped without a registered climb. Find your rhythm if you can.",
                    "You've slowed down. Check your breathing and recover your flow.",
                    "Pace is dropping. Assess your effort before building again."
                  ])
            let line = choices[dropPromptCount % choices.count]
            dropPromptCount += 1
            return line
        }
        return nil
    }
}
