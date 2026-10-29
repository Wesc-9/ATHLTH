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

struct ATHLTHCoachLandmark: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var side: ATHLTHCoachLandmarkSide

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        latitude.isFinite && longitude.isFinite
    }

    func spokenPhrase(norwegian: Bool) -> String {
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

/// Optional in Watch transfers: older iPhone/Watch builds continue to decode.
struct ATHLTHAudioCoachSmartSettings: Codable, Hashable {
    var motivationEnabled = false
    var motivationIntervalSeconds = 60
    var randomEncouragementEnabled = false
    var randomIntervalSeconds = 240
    var customEncouragements: [String] = []
    var landmarks: [ATHLTHCoachLandmark] = []

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
    private var recentPhraseIndices: [Int] = []
    private var announcedLandmarks: Set<UUID> = []

    mutating func reset() { self = Self() }

    mutating func nextMotivation(
        settings: ATHLTHAudioCoachSmartSettings,
        elapsed: Double,
        paceSecondsPerKilometer: Double?,
        norwegian: Bool
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
                    let context: String?
                    if let currentPace, let previous = previousPace {
                        let ratio = currentPace / previous
                        if ratio < 0.94 {
                            context = norwegian
                                ? "Du har økt farten siden forrige oppdatering. Bra jobbet!"
                                : "You've picked up the pace since the last update. Nice work!"
                        } else if (0.94...1.06).contains(ratio) {
                            context = norwegian
                                ? "Du holder et jevnt tempo. Fortsett slik!"
                                : "You're keeping a steady pace. Keep it up!"
                        } else {
                            context = nil
                        }
                    } else {
                        context = nil
                    }
                    lastSpokenAt = elapsed
                    return context ?? selectPhrase(
                        settings: settings, norwegian: norwegian
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
        return selectPhrase(settings: settings, norwegian: norwegian)
    }

    mutating func nextLandmark(
        settings: ATHLTHAudioCoachSmartSettings,
        latitude: Double?,
        longitude: Double?,
        horizontalAccuracy: Double?,
        locationAge: TimeInterval,
        norwegian: Bool
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

    private mutating func selectPhrase(
        settings: ATHLTHAudioCoachSmartSettings,
        norwegian: Bool
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
        let builtIn = norwegian ? builtInNO : builtInEN
        let options = builtIn + custom
        let eligible = options.indices.filter { !recentPhraseIndices.contains($0) }
        let available = eligible.isEmpty ? Array(options.indices) : eligible
        let customChoices = available.filter { $0 >= builtIn.count }
        let builtInChoices = available.filter { $0 < builtIn.count }
        // User-authored phrases should be heard, not drowned out by the
        // much larger built-in bank. Alternate pools at random when possible.
        let chosenPool = !customChoices.isEmpty &&
            (builtInChoices.isEmpty || Bool.random())
            ? customChoices : builtInChoices
        let picked = (chosenPool.isEmpty ? available : chosenPool)
            .randomElement() ?? 0
        recentPhraseIndices.append(picked)
        if recentPhraseIndices.count > 9 { recentPhraseIndices.removeFirst() }
        return options[picked]
    }
}
