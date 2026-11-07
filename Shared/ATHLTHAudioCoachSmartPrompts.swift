import CoreLocation
import Foundation

/// Location messages are authored by the athlete; Audio Coach never guesses
/// which side of a street a landmark is on.
enum ATHLTHCoachLandmarkSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    case unspecified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return ATHLTHLocalization.choose(english: "Left", norwegian: "Venstre")
        case .right: return ATHLTHLocalization.choose(english: "Right", norwegian: "Høyre")
        case .unspecified: return ATHLTHLocalization.choose(english: "No side", norwegian: "Ingen side")
        }
    }
}

enum ATHLTHCoachLandmarkKind: String, Codable, CaseIterable, Identifiable {
    case ordinary
    case waterfront
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ordinary:
            return ATHLTHLocalization.choose(english: "Place", norwegian: "Sted")
        case .waterfront:
            return ATHLTHLocalization.choose(english: "Waterfront", norwegian: "Ved sjøen")
        case .home:
            return ATHLTHLocalization.choose(english: "Home", norwegian: "Hjemme")
        }
    }
}

enum ATHLTHCoachEncouragementStyle: String, Codable, CaseIterable, Identifiable {
    case praise
    case encouragement
    case push

    var id: String { rawValue }
    var title: String {
        switch self {
        case .praise: return ATHLTHLocalization.choose(english: "Praise", norwegian: "Gi skryt")
        case .encouragement: return ATHLTHLocalization.choose(english: "Encourage", norwegian: "Oppmuntre")
        case .push: return ATHLTHLocalization.choose(english: "More push", norwegian: "Mer push")
        }
    }
}

/// Only verified route progress and sampled terrain may feed environmental
/// coaching. No reverse geocoding, location guessing or mandatory network.
struct ATHLTHCoachEnvironmentalContext {
    var routeRemainingMeters: Double? = nil
    var routeProgressPercent: Double? = nil
    var terrain: ATHLTHCoachTerrain? = nil

    var nearVerifiedFinish: Bool {
        guard let remaining = routeRemainingMeters,
              let progress = routeProgressPercent,
              remaining.isFinite, progress.isFinite else { return false }
        return (0...200).contains(remaining) && (90...100).contains(progress)
    }
}

enum ATHLTHCoachTerrain: String {
    case uphill
    case downhill
}

struct ATHLTHCoachLandmark: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var side: ATHLTHCoachLandmarkSide
    // Optional to keep previously saved landmarks decodable.
    var kind: ATHLTHCoachLandmarkKind? = nil

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        latitude.isFinite && longitude.isFinite
    }

    func spokenPhrase(norwegian: Bool) -> String {
        // Named, manually selected geographic evidence. Never infer
        // 'by the sea' or 'at home' from arbitrary GPS coordinates.
        switch kind {
        case .waterfront:
            return norwegian
                ? "Sjøen er like ved deg nå. Nyt omgivelsene og hold rytmen!"
                : "You're close to the water. Enjoy the view and keep your rhythm!"
        case .home:
            return norwegian
                ? "Du er snart hjemme! Sterk innsats – finn kreftene til den siste biten."
                : "You're almost home! Great effort — finish this last stretch."
        case .ordinary, .none:
            break
        }
        switch side {
        case .left:
            return norwegian ? "Nå passerer du \(name) på venstre side"
                : "You're passing \(name) on your left"
        case .right:
            return norwegian ? "Nå passerer du \(name) på høyre side"
                : "You're passing \(name) on your right"
        case .unspecified:
            return norwegian ? "Nå passerer du \(name)"
                : "You're passing \(name)"
        }
    }
}

/// ATHLTH's contextual coaching or a user-directed set of triggers.
enum ATHLTHCoachMotivationControlMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic:
            return ATHLTHLocalization.choose(
                english: "ATHLTH decides", norwegian: "ATHLTH bestemmer")
        case .custom:
            return ATHLTHLocalization.choose(
                english: "My rules", norwegian: "Egendefinert")
        }
    }
}

/// Optional in Watch transfers: older iPhone/Watch builds continue to decode.
struct ATHLTHAudioCoachSmartSettings: Codable, Hashable {
    var motivationEnabled = false
    var motivationIntervalSeconds = 60
    var randomEncouragementEnabled = false
    var randomIntervalSeconds = 240
    var customEncouragements: [String] = []
    var landmarks: [ATHLTHCoachLandmark] = []
    // Optional so already stored profiles and old Watch transfers still decode.
    var encouragementStyle: ATHLTHCoachEncouragementStyle? = nil
    var contextualFeedbackEnabled: Bool? = nil
    // Separate from spoken BPM: athletes can hear the measured zone without
    // requiring raw heart-rate announcements. Optional for old workouts.
    var announceCurrentHeartRateZone: Bool? = nil
    // Supplied from the athlete profile when the workout is launched; never
    // infer a zone without a valid configured/estimated HR maximum.
    var maximumHeartRateBPM: Double? = nil
    // Optional = old Watch profiles decode unchanged. Explicit selections
    // in the new editor are picked up by Watch and the mirrored iPhone voice.
    var measuredZoneAnnouncementIntervalSeconds: Int? = nil
    var targetZoneVoiceAlertsEnabled: Bool? = nil
    /// Applies to free runs; an interval's programmed zone takes precedence.
    var preferredHeartRateZone: Int? = nil
    var confirmWhenBackInZone: Bool? = nil
    var coachingMode: ATHLTHCoachMotivationControlMode? = nil
    var strongStartDurationSeconds: Int? = nil
    var pushWhenBelowTargetZone: Bool? = nil
    var pushWhenBelowTargetPace: Bool? = nil
    var pushOnUnexpectedPaceDrop: Bool? = nil
    var paceDropThresholdPercent: Int? = nil
    var adaptiveCooldownSeconds: Int? = nil

    var resolvedMeasuredZoneInterval: TimeInterval {
        TimeInterval(min(max(measuredZoneAnnouncementIntervalSeconds ?? 180, 30), 900))
    }

    var resolvedAdaptiveCooldown: TimeInterval {
        TimeInterval(min(max(adaptiveCooldownSeconds ?? 150, 60), 600))
    }

    var resolvedPaceDropPercent: Double {
        Double(min(max(paceDropThresholdPercent ?? 15, 8), 35)) / 100
    }

    var isContextualFeedbackEnabled: Bool {
        contextualFeedbackEnabled ?? true
    }

    var validatedMotivationInterval: Double {
        Double(min(max(motivationIntervalSeconds, 30), 600))
    }

    var validatedRandomInterval: Double {
        Double(min(max(randomIntervalSeconds, 90), 900))
    }
}

/// Saves the entire voice experience, not only the independent metric rules.
/// Existing ATHLTHAudioCoachRuleSet entries remain untouched.
struct ATHLTHAudioCoachProfile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var configuration: WatchAudioCoachConfiguration
}

/// Shared, workout-scoped policy for Watch and iPhone voice ownership.
/// No network AI, unverifiable PB claims, or location access is required here.
struct ATHLTHAudioCoachSmartState {
    private(set) var lastMotivationSlot = 0
    private(set) var nextRandomAt: Double = 0
    private(set) var lastSpokenAt: Double = -.infinity
    private(set) var priorMinutePace: Double?
    private var recentPhraseTexts: [String] = []
    private var announcedLandmarks: Set<UUID> = []
    private var lastTerrainLocation: CLLocation?
    private(set) var inferredTerrain: ATHLTHCoachTerrain?
    // Missing terrain classification does not prove flat ground.
    private(set) var hasReliableTerrainEvidence = false
    private var lastTerrainPhraseAt: Double = -.infinity
    private var announcedFinalStretch = false

    mutating func reset() { self = Self() }

    /// Terrain cues use independently recorded, accurate, fresh GPS altitude.
    /// Do not infer grade from one point or from horizontal GPS noise.
    mutating func observeTerrain(location: CLLocation, now: Date = Date()) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 25,
              location.verticalAccuracy >= 0,
              location.verticalAccuracy <= 8,
              abs(now.timeIntervalSince(location.timestamp)) <= 12,
              location.altitude.isFinite else {
            inferredTerrain = nil
            hasReliableTerrainEvidence = false
            return
        }
        guard let anchor = lastTerrainLocation else {
            lastTerrainLocation = location
            return
        }
        guard location.timestamp > anchor.timestamp else { return }
        let traveled = location.distance(from: anchor)
        guard traveled.isFinite, traveled >= 70 else { return }
        // Discontinuous samples require a new reliable anchor, not a guessed
        // climb between two far-away fixes.
        guard traveled <= 400 else {
            lastTerrainLocation = location
            inferredTerrain = nil
            hasReliableTerrainEvidence = false
            return
        }
        hasReliableTerrainEvidence = true
        let climbed = location.altitude - anchor.altitude
        let gradient = climbed / max(traveled, 1)
        inferredTerrain = climbed >= 7 && gradient >= 0.035
            ? .uphill
            : climbed <= -7 && gradient <= -0.035
                ? .downhill : nil
        lastTerrainLocation = location
    }

    mutating func nextMotivation(
        settings: ATHLTHAudioCoachSmartSettings,
        elapsed: Double,
        paceSecondsPerKilometer: Double?,
        norwegian: Bool,
        environment: ATHLTHCoachEnvironmentalContext = .init()
    ) -> String? {
        guard elapsed.isFinite, elapsed >= 0 else { return nil }

        if settings.motivationEnabled {
            let slot = Int(min(floor(elapsed / settings.validatedMotivationInterval),
                               Double(Int.max / 2)))
            if slot > lastMotivationSlot {
                lastMotivationSlot = slot
                let currentPace = validatedPace(paceSecondsPerKilometer)
                let previousPace = priorMinutePace
                priorMinutePace = currentPace

                if elapsed - lastSpokenAt >= 35 {
                    let style = settings.encouragementStyle ?? .encouragement
                    var proposed: String?

                    if settings.isContextualFeedbackEnabled &&
                       environment.nearVerifiedFinish && !announcedFinalStretch {
                            announcedFinalStretch = true
                            proposed = pickDistinct(norwegian
                                ? [
                                    "Nå er du på siste del av ruten! Bra jobbet – hold fokus helt inn.",
                                    "Målet er like foran deg. Du har gjort jobben, finn en god avslutning!",
                                    "Siste etappe! Behold flyten helt til du er fremme.",
                                    "Du er nesten ved mål. Sterk innsats, avslutt kontrollert!",
                                    "Det er kort igjen til mål. God rytme – fullfør sterkt."
                                  ]
                                : [
                                    "You're on the final stretch! Great work — keep your focus.",
                                    "The finish is close. You've done the work, finish well!",
                                    "Last stretch! Keep your rhythm all the way.",
                                    "You're almost at the finish. Strong effort, stay in control.",
                                    "Not far to go. Keep your flow and finish strong."
                                  ])
                    } else if settings.isContextualFeedbackEnabled,
                              let terrain = environment.terrain,
                              elapsed - lastTerrainPhraseAt >= 240 {
                            lastTerrainPhraseAt = elapsed
                            switch terrain {
                            case .uphill:
                                proposed = pickDistinct(norwegian
                                    ? [
                                        "Du er i en bakke nå. Kortere steg og jevn innsats – dette klarer du!",
                                        "Bra jobbet i stigningen. Finn din egen rytme oppover.",
                                        "Det går oppover. Du bygger styrke for hvert steg – hold kontrollen.",
                                        "Sterk innsats i bakken! Hold pusten rolig og jobb deg frem."
                                      ]
                                    : [
                                        "You're climbing now. Shorter steps and a steady effort!",
                                        "Nice work uphill. Find your own rhythm on the climb.",
                                        "The route is rising. Keep your effort controlled and strong.",
                                        "Solid work on this hill. Breathe steadily and keep moving."
                                      ])
                            case .downhill:
                                proposed = pickDistinct(norwegian
                                    ? [
                                        "Nå går det nedover. Slapp av i skuldrene og finn god flyt.",
                                        "Du er i en nedoverbakke. La beina flyte, men behold kontrollen.",
                                        "Fin anledning til å finne rytmen igjen. Løp kontrollert nedover.",
                                        "Godt jobbet oppover! Bruk nedoverbakken til å finne pusten."
                                      ]
                                    : [
                                        "You're heading downhill. Relax your shoulders and flow.",
                                        "On the descent, let your legs move while staying in control.",
                                        "Use this downhill to settle into a good rhythm.",
                                        "Good climbing work. Recover your breathing on the descent."
                                      ])
                            }
                    } else if let currentPace, let previous = previousPace, previous > 0 {
                            let ratio = currentPace / previous
                            if ratio < 0.94 {
                                proposed = pickDistinct(norwegian
                                    ? [
                                        "Du har økt farten siden sist. Flott jobbet!",
                                        "Du har økt farten, og ser ut til å ha funnet flyten!",
                                        "Du har økt farten. Sterkt! Behold kontrollen.",
                                        "Du har økt farten siden forrige oppdatering – godt driv!",
                                        "Du har økt farten. Fortsett med den gode rytmen."
                                      ]
                                    : [
                                        "You've picked up the pace. Great work!",
                                        "You've picked up the pace and found your flow!",
                                        "You're moving faster. Strong work, stay in control.",
                                        "You've increased your speed since the last update. Nice!",
                                        "Your pace has improved. Keep that good rhythm!"
                                      ])
                            } else if (0.94...1.06).contains(ratio) {
                                proposed = pickDistinct(norwegian
                                    ? [
                                        "Du holder et jevnt tempo. Godt jobbet!",
                                        "Flott rytme! Du holder farten stabil.",
                                        "Dette er stabilt og fint. Fortsett i din egen rytme.",
                                        "Du holder godt på tempoet. Stødig innsats!",
                                        "Jevn fart og godt fokus – sterk gjennomføring."
                                      ]
                                    : [
                                        "You're holding a steady pace. Nice work!",
                                        "Great rhythm — your pace is stable.",
                                        "Good consistency. Keep your own rhythm.",
                                        "You're holding your pace well. Strong effort!",
                                        "Steady speed and good focus — keep going."
                                      ])
                            }
                    }

                    lastSpokenAt = elapsed
                    return proposed ?? selectPhrase(
                        settings: settings, norwegian: norwegian,
                        style: style
                    )
                }
            }
        }

        guard settings.randomEncouragementEnabled else { return nil }
        if nextRandomAt == 0 {
            nextRandomAt = settings.validatedRandomInterval
        }
        guard elapsed >= nextRandomAt, elapsed - lastSpokenAt >= 35 else {
            return nil
        }
        let base = Int(settings.validatedRandomInterval)
        let variation = Int.random(in: -(base / 4)...(base / 4))
        nextRandomAt = elapsed + Double(base + variation)
        lastSpokenAt = elapsed
        return selectPhrase(
            settings: settings, norwegian: norwegian,
            style: settings.encouragementStyle ?? .encouragement
        )
    }

    mutating func nextLandmark(
        settings: ATHLTHAudioCoachSmartSettings,
        latitude: Double?,
        longitude: Double?,
        horizontalAccuracy: Double?,
        locationAge: TimeInterval,
        norwegian: Bool,
        elapsedSeconds: TimeInterval? = nil,
        routeProgressPercent: Double? = nil
    ) -> String? {
        guard let latitude, let longitude, let horizontalAccuracy,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              horizontalAccuracy >= 0, horizontalAccuracy <= 30,
              locationAge >= -3, locationAge <= 12
        else { return nil }

        let here = CLLocation(latitude: latitude, longitude: longitude)
        for landmark in settings.landmarks.prefix(30) where
            landmark.isValid && !announcedLandmarks.contains(landmark.id) {
            // Starting near the athlete's saved home must not trigger
            // a deceptive "almost home" announcement at minute zero.
            if landmark.kind == .home {
                guard let elapsedSeconds,
                      elapsedSeconds.isFinite,
                      elapsedSeconds >= 600 else { continue }
                if let routeProgressPercent {
                    guard routeProgressPercent.isFinite,
                          routeProgressPercent >= 85 else { continue }
                }
            }
            let there = CLLocation(latitude: landmark.latitude,
                                   longitude: landmark.longitude)
            // Close enough to describe as passing, not simply "nearby".
            if here.distance(from: there) <= 65 {
                announcedLandmarks.insert(landmark.id)
                return landmark.spokenPhrase(norwegian: norwegian)
            }
        }
        return nil
    }

    private func validatedPace(_ pace: Double?) -> Double? {
        guard let pace, pace.isFinite, (150...1200).contains(pace) else { return nil }
        return pace
    }

    /// Text-based anti-repeat memory covers metric, terrain and freeform
    /// phrases together, even when the active motivational preset changes.
    private mutating func pickDistinct(_ choices: [String]) -> String {
        let recentToAvoid = recentPhraseTexts.suffix(
            max(0, min(10, choices.count - 1))
        )
        let available = choices.filter { !recentToAvoid.contains($0) }
        // Prefer the longest possible novelty window. A small contextual
        // phrase bank may recur after all its lines have been used, but never
        // immediately while another option exists.
        let selected = (available.isEmpty ? choices : available)
            .randomElement() ?? ""
        recentPhraseTexts.append(selected)
        if recentPhraseTexts.count > 14 {
            recentPhraseTexts.removeFirst()
        }
        return selected
    }

    private mutating func selectPhrase(
        settings: ATHLTHAudioCoachSmartSettings,
        norwegian: Bool,
        style: ATHLTHCoachEncouragementStyle
    ) -> String {
        let builtInNO = [
            "Bra jobbet! Hold fokus på neste steg.",
            "Sterkt! Du bygger deg opp for hvert minutt.",
            "Finn rytmen din, og la beina jobbe.",
            "Du gjør en innsats du kan være stolt av.",
            "Ta ett steg om gangen. Du er i gang!",
            "Dette er tiden du investerer i deg selv.",
            "Du trenger ikke være raskest. Bare fortsett.",
            "Slipp skuldrene og hold en naturlig rytme.",
            "Fantastisk at du er ute og beveger deg!",
            "Se fremover. Du har mer å gi.",
            "Rolig og kontrollert. Du har styringen.",
            "Hvert steg teller mot målet ditt.",
            "God flyt! Fortsett med din egen rytme.",
            "Behold fokuset. Du er på vei.",
            "Sterk innsats, og du er fortsatt i gang.",
            "Pust rolig, slapp av i armene.",
            "Du bygger utholdenhet for hver økt.",
            "Slik skaper du gode vaner.",
            "Dette er en god investering i formen din.",
            "Finn et tempo som passer deg, og nyt turen.",
            "Ett steg nærmere den formen du ønsker deg.",
            "Hold kursen. Du gjør jobben.",
            "Ta noen dype pust og kjenn at kroppen jobber.",
            "Sett pris på fremgangen, også de små stegene.",
            "Du er sterkere enn du var da du startet.",
            "Stødig rytme, godt fokus.",
            "Små fremskritt er også fremskritt.",
            "Du er i bevegelse, og det er det som teller.",
            "Nå handler det bare om neste lille etappe.",
            "Hold hodet høyt og blikket frem.",
            "Det er lov å justere tempoet. Behold kontrollen.",
            "Du har allerede gjort det viktigste: Du startet.",
            "Gi deg selv kreditt for jobben du legger ned.",
            "Kjenn på flyten og bruk den.",
            "En kilometer om gangen.",
            "Du finner styrken i jevn innsats.",
            "Ta et øyeblikk og finn pusten igjen.",
            "Fortsett med ditt tempo. Det er din økt.",
            "Du klarer mer enn du tror.",
            "Veldig bra fokus. Fortsett."
        ]
        let builtInEN = [
            "Nice work! Focus on the next step.",
            "Strong effort. You're building momentum.",
            "Find your rhythm and let your legs move.",
            "This is an effort you can be proud of.",
            "One step at a time. You're doing it.",
            "This time is an investment in yourself.",
            "You don't have to be the fastest. Keep going.",
            "Relax your shoulders and find your stride.",
            "It's great that you're out and moving.",
            "Look ahead. You've got this.",
            "Easy and controlled. You're in charge.",
            "Every step counts towards your goal.",
            "Nice flow! Keep your own rhythm.",
            "Stay focused. You're moving forward.",
            "Good effort, and you're still going.",
            "Breathe easy and relax your arms.",
            "You're building endurance with every session.",
            "This is how good habits are made.",
            "You're investing in your fitness today.",
            "Find a pace that suits you and enjoy the run.",
            "One step closer to your fitness goals.",
            "Stay the course. You're doing the work.",
            "Take a deep breath and feel your body working.",
            "Appreciate every bit of progress.",
            "You're stronger than when you started.",
            "Steady rhythm, clear focus.",
            "Small improvements are still improvements.",
            "You're moving, and that's what matters.",
            "Just think about the next short stretch.",
            "Keep your head up and eyes forward.",
            "It's okay to adjust your pace. Stay in control.",
            "You've already done the hardest part: starting.",
            "Give yourself credit for showing up.",
            "Find your flow and go with it.",
            "One kilometer at a time.",
            "Your strength grows through steady effort.",
            "Take a moment to settle your breathing.",
            "Keep your own pace. This is your run.",
            "You can do more than you think.",
            "Great focus. Keep it going."
        ]
        let custom = settings.customEncouragements.prefix(40)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let phrases: [String]
        switch style {
        case .praise:
            phrases = norwegian
                ? [
                    "Sterkt gjennomført så langt! Du fortjener ros for innsatsen.",
                    "Godt jobbet! Du har virkelig lagt ned en fin innsats.",
                    "Dette er solid trening. Du kan være stolt av jobben du gjør.",
                    "Herlig innsats! Du finner stadig en god rytme.",
                    "Veldig bra fokus. Du gjennomfører med kontroll.",
                    "Bravo! Du investerer skikkelig i formen i dag.",
                    "God flyt og godt jobbet. Fortsett på din måte.",
                    "Du gjør fremskritt ved å møte opp og jobbe jevnt.",
                    "Se hvor langt du allerede har kommet i dag. Sterkt!",
                    "Flott at du holder det gående. Det er verdifull trening.",
                    "Du bygger både kapasitet og selvtillit. Bra jobbet!",
                    "Fin innsats! Du holder hodet kaldt og beina i gang."
                  ]
                : [
                    "Strong effort so far! You deserve credit for your work.",
                    "Nice work! You're putting in a solid effort.",
                    "This is quality training. Be proud of the work you're doing.",
                    "Great effort! You're finding a good rhythm.",
                    "Excellent focus. You're moving with control.",
                    "Bravo! You're investing in your fitness today.",
                    "Nice flow and great work. Keep it your way.",
                    "Showing up and keeping at it is real progress.",
                    "Look how far you've come today. Strong work!",
                    "Well done for keeping at it. Every step counts.",
                    "You're building fitness and confidence. Good job!",
                    "Solid work. Keep your head clear and legs moving."
                  ]
        case .encouragement:
            phrases = norwegian ? builtInNO : builtInEN
        case .push:
            phrases = norwegian
                ? [
                    "Du har mer å gi. Finn rytmen og fokuser på neste etappe!",
                    "Nå jobber vi! Hold fokus og gi en kontrollert innsats.",
                    "Kom igjen! Bruk de neste minuttene godt.",
                    "Du har kommet så langt. Fortsett med godt driv!",
                    "Finn et tydelig mål foran deg, og jobb deg dit!",
                    "Sterkt! Behold trykket, uten å miste kontrollen.",
                    "Et steg av gangen, men med skikkelig vilje. Kjør på!",
                    "Nå gjelder det å holde fokuset. Du klarer dette!",
                    "Fint driv. Sjekk rytmen og jobb videre!",
                    "Gi deg selv en god avslutning på denne delen!",
                    "Du har en oppgave nå: Hold en god, jevn innsats!",
                    "Kom igjen! Finn flyten og behold den gjennom neste del.",
                    "Du har gjennomført mye. Bruk energien smart videre!",
                    "Det er nå du kan vise hva du har jobbet for!",
                    "Hold konsentrasjonen. Neste etappe er din!",
                    "Du er på vei. Fortsett med besluttsomhet og kontroll."
                  ]
                : [
                    "You've got more to give. Focus on the next stretch!",
                    "Let's work! Keep your focus and a controlled effort.",
                    "Come on! Make the next few minutes count.",
                    "You've come this far. Keep that momentum!",
                    "Pick a point ahead and work steadily towards it!",
                    "Strong effort! Keep pushing without losing control.",
                    "One step at a time with real determination. Go!",
                    "Stay focused now. You've got this!",
                    "Good drive. Find your rhythm and keep moving!",
                    "Give this section a strong finish!",
                    "Your task now: keep a good steady effort!",
                    "Come on! Find your flow and own the next stretch!",
                    "You've done plenty. Use your energy wisely now!",
                    "This is a chance to show what you've trained for!",
                    "Keep your concentration. The next stretch is yours!",
                    "You're moving forward. Stay determined and in control."
                  ]
        }
        let customEligible = custom.filter {
            !recentPhraseTexts.suffix(10).contains($0)
        }
        let pool = !customEligible.isEmpty && Bool.random()
            ? customEligible : phrases
        return pickDistinct(pool)
    }
}
