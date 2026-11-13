import Foundation

/// Norwegian editorial localization for Zoned's offline training content.
/// The canonical English names/IDs remain in the source snapshots so language
/// changes cannot affect source IDs or matching; no remote translator required.
enum ATHLTHZonedLocalization {
    private static let plans: [String: (title: String, summary: String)] = [
        "5k-debutant": ("Din første 5 km", "Åtte ukers løpeplan med gradvis opptrapping frem mot din første 5-kilometer."),
        "5k-intermediaire": ("5 km · viderekommen", "Ti ukers plan for å forbedre tiden din på 5 km, med kvalitetsøkter."),
        "10k-debutant": ("Din første 10 km", "Ti ukers plan for å bygge utholdenhet gradvis frem mot 10 km."),
        "10k-intermediaire": ("10 km · viderekommen", "Tolv ukers løpeplan med terskeltrening og VO2-maksintervaller."),
        "semi-marathon": ("Halvmaraton", "14 ukers plan med gradvis lengre turer og terskeløkter."),
        "marathon": ("Maraton", "18 ukers plan med fem økter i uken, lange turer og trening i konkurransefart."),
        "base-building": ("Bygg utholdenhetsgrunnlaget", "Tolv ukers løpeplan for å bygge aerob kapasitet, uten et bestemt konkurransemål."),
        "reprise-longue-pause": ("Tilbake etter treningspause", "Ti ukers forsiktig opptrapping etter lengre opphold fra løping."),
        "retour-blessure": ("Tilbake etter skade", "Åtte ukers forsiktig opptrapping etter skade eller lengre pause. Ikke en medisinsk rehabiliteringsplan."),
        "trail-court-intermediaire": ("Terrengløp · viderekommen", "14 ukers plan mot 30 km terrengløp, med bakker, rask gange i stigning og tekniske nedoverbakker.")
    ]

    static func planTitle(_ id: String, english: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return english }
        return plans[id]?.title ?? text(english)
    }

    static func planSummary(_ id: String, english: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return english }
        return plans[id]?.summary ?? text(english)
    }

    static func workoutSummary(_ category: String, english: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return english }
        let summary: [String: String] = [
            "assessment": "Testøkt for å vurdere form og utvikling. Tilpass belastningen til eget nivå.",
            "recovery": "Rolig restitusjonsøkt med lett intensitet.",
            "endurance": "Utholdenhetsøkt med kontrollert intensitet og gradvis progresjon.",
            "long_run": "Langtur for økt utholdenhet. Hold planlagt intensitet.",
            "threshold": "Terskeløkt med målrettet arbeidsbelastning og aktive pauser.",
            "tempo": "Tempoøkt med kontrollert fart og belastning.",
            "vma_intervals": "Intervalløkt for utvikling av aerob kapasitet og VO2-maks.",
            "fartlek": "Fartslek med variasjon mellom raske og rolige deler.",
            "hills": "Bakkeøkt som utvikler styrke og løpsøkonomi.",
            "mixed": "Kombinasjonsøkt med flere treningsformer eller intensiteter.",
            "race_pace": "Konkurransespesifikk økt med planlagte fartsperioder.",
            "trail": "Terrengøkt med tilpasning til underlag og stigning."
        ]
        return summary[category] ?? text(english)
    }

    static func phase(_ value: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return value.capitalized }
        switch value.lowercased() {
        case "base": return "Grunntrening"
        case "build": return "Oppbygging"
        case "peak": return "Toppuke"
        case "taper": return "Nedtrapping"
        case "recovery": return "Restitusjon"
        default: return text(value)
        }
    }

    /// Split source *instructions* from the short name shown in a timeline.
    /// This is editorial presentation; the prescribed duration and intensity
    /// continue to come exclusively from the canonical Zoned step model.
    struct StepCopy {
        let title: String
        let instructions: String?
    }

    private static func isThreeMinuteAllOut(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("sustained maximal effort") &&
            (lower.contains("last 30") || lower.contains("30 sekunder"))
    }

    static func stepCopy(
        sourceEnglish: String,
        durationSeconds: Double?,
        isRunning: Bool
    ) -> StepCopy {
        let input = sourceEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRunning && isThreeMinuteAllOut(input) {
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "3-minute all-out test",
                    norwegian: "3 min maksimaltest"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run at maximum sustainable effort on a track for 3 minutes. Record total distance and the pace of the final 30 seconds.",
                    norwegian: "Løp med maksimal innsats på bane i 3 minutter. Noter totaldistanse og tempo de siste 30 sekundene."
                )
            )
        }

        // Full sentences belong in Notes, not the button or exercise name.
        // Preserve source text verbatim for non-curated instructions; this
        // prevents losing test guidance in any of the 240 bundled workouts.
        let firstSentence = input.components(separatedBy: ". ").first ?? input
        if input.count > 74 {
            let title: String
            if firstSentence.count <= 55 && firstSentence != input {
                title = text(firstSentence)
            } else if let durationSeconds, durationSeconds > 0 {
                title = ATHLTHWorkoutStepCopy.duration(durationSeconds) + " · " +
                    ATHLTHLocalization.choose(
                        english: isRunning ? "Running" : "Training",
                        norwegian: isRunning ? "Løping" : "Trening"
                    )
            } else {
                title = ATHLTHLocalization.choose(
                    english: isRunning ? "Running segment" : "Workout segment",
                    norwegian: isRunning ? "Løpsdel" : "Øktdel"
                )
            }
            return StepCopy(title: title, instructions: text(input))
        }
        return StepCopy(title: text(input), instructions: nil)
    }

    /// Historical saved/personalized imports can contain the old mixed-language
    /// sentence as their title. Correct only this known catalog instruction,
    /// never replace names the athlete wrote themselves by a generic heuristic.
    static func normalizeLegacyAllOutStep(
        _ block: WorkoutTemplateBlock
    ) -> WorkoutTemplateBlock {
        guard block.kind == .run, isThreeMinuteAllOut(block.title),
              (block.durationSeconds ?? 0) == 180 else { return block }
        var clean = block
        let copy = stepCopy(
            sourceEnglish: block.title, durationSeconds: block.durationSeconds,
            isRunning: true
        )
        clean.title = copy.title
        if let instructions = copy.instructions {
            let existing = (clean.notes ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            clean.notes = existing.isEmpty ? instructions :
                (existing.contains(instructions) ? existing : instructions + "\n" + existing)
        }
        return clean
    }

    /// Athletic microcopy, not machine translation of medical instructions.
    /// Preserve percentages, distances, repetitions and numbers.
    static func text(_ english: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return english }
        if english == "3-Minute All-Out Test" ||
           english == "3-Minutt All-Out Test" {
            return "3-minutters maksimaltest"
        }
        var localized = english
        for (from, to) in substitutions {
            localized = localized.replacingOccurrences(
                of: from, with: to, options: [.regularExpression, .caseInsensitive]
            )
        }
        // Zoned's six-zone source may contain Z6 in labels; athlete UI only
        // uses the app's five-zone scheme.
        localized = localized.replacingOccurrences(
            of: "\\bZ6\\b", with: "Z5", options: [.regularExpression, .caseInsensitive]
        )
        return localized
    }

    /// Ordered longest/most-specific phrases first, so "recovery jog"
    /// is localized before "jog", and "half-marathon" before "marathon".
    private static let substitutions: [(String, String)] = [
        (#"\bHalf.Marathon\b"#, "Halvmaraton"),
        (#"\bCritical Velocity\b"#, "kritisk fart"),
        (#"\bMaximum Aerobic Function\b"#, "maksimal aerob kapasitet"),
        (#"\bVO2max\b"#, "VO2-maks"),
        (#"\btime trial\b"#, "testløp"),
        (#"\bRace day\b"#, "Konkurransedag"),
        (#"\bLong Endurance Ride\b"#, "Lang sykkeltur med utholdenhetsfokus"),
        (#"\bRecovery Spin\b"#, "Rolig restitusjon på sykkel"),
        (#"\bRecovery jog\b"#, "Restitusjonsjogg"),
        (#"\bRecovery run\b"#, "Restitusjonsløp"),
        (#"\bProgressive jog\b"#, "Progressiv jogg"),
        (#"\bRecovery between blocks\b"#, "Pause mellom blokker"),
        (#"\bProgressive accelerations\b"#, "Progressive stigningsløp"),
        (#"\bProgressive cool.down\b"#, "Gradvis nedtrapping"),
        (#"\bEasy cool.down\b"#, "Rolig nedtrapping"),
        (#"\bCool.down\b"#, "Nedtrapping"),
        (#"\bWarm.up\b"#, "Oppvarming"),
        (#"\bLong Run\b"#, "Langtur"),
        (#"\bShort Run\b"#, "Kort løpetur"),
        (#"\bBase Endurance\b"#, "Grunnutholdenhet"),
        (#"\bEndurance Run\b"#, "Utholdenhetsløp"),
        (#"\bEndurance Ride\b"#, "Utholdenhetssykling"),
        (#"\bThreshold\b"#, "Terskel"),
        (#"\bFartlek\b"#, "Fartslek"),
        (#"\bStrides\b"#, "Stigningsløp"),
        (#"\bPace\b"#, "Fart"),
        (#"\bSpeed\b"#, "Hurtighet"),
        (#"\bQuality\b"#, "Kvalitet"),
        (#"\bDrills\b"#, "Løpsdriller"),
        (#"\bIntervals\b"#, "Intervaller"),
        (#"\bInterval\b"#, "Intervall"),
        (#"\bRepetitions\b"#, "Repetisjoner"),
        (#"\bRepeats\b"#, "Drag"),
        (#"\bSurges\b"#, "Fartsøkninger"),
        (#"\bHills\b"#, "Bakker"),
        (#"\bHill\b"#, "Bakke"),
        (#"\bClimbs\b"#, "Stigninger"),
        (#"\bClimb\b"#, "Stigning"),
        (#"\bDownhill\b"#, "Nedoverbakke"),
        (#"\bUphill\b"#, "Oppoverbakke"),
        (#"\bTrail\b"#, "Terreng"),
        (#"\bFlat terrain\b"#, "Flatt terreng"),
        (#"\bFlat\b"#, "Flatt"),
        (#"\bRunning\b"#, "Løping"),
        (#"\bRunner\b"#, "Løper"),
        (#"\bRun\b"#, "Løp"),
        (#"\bJogging\b"#, "Jogging"),
        (#"\bJog\b"#, "Jogg"),
        (#"\bWalk.down\b"#, "Gå ned"),
        (#"\bWalking\b"#, "Gange"),
        (#"\bWalk\b"#, "Gå"),
        (#"\bSprint(s)?\b"#, "Sprint$1"),
        (#"\bFast\b"#, "Rask"),
        (#"\bSlow\b"#, "Langsom"),
        (#"\bVery\b"#, "Svært"),
        (#"\bEasy\b"#, "Rolig"),
        (#"\bHard\b"#, "Hard"),
        (#"\bLight\b"#, "Lett"),
        (#"\bProgressive\b"#, "Progressiv"),
        (#"\bGradual\b"#, "Gradvis"),
        (#"\bContinuous\b"#, "Sammenhengende"),
        (#"\bExtended\b"#, "Utvidet"),
        (#"\bClassic\b"#, "Klassisk"),
        (#"\bBeginner\b"#, "Nybegynner"),
        (#"\bIntermediate\b"#, "Viderekommen"),
        (#"\bAdvanced\b"#, "Avansert"),
        (#"\bElite\b"#, "Elite"),
        (#"\bRecovery\b"#, "Restitusjon"),
        (#"\bRegeneration\b"#, "Restitusjon"),
        (#"\bAerobic\b"#, "Aerob"),
        (#"\bEndurance\b"#, "Utholdenhet"),
        (#"\bTempo\b"#, "Tempo"),
        (#"\bStrength\b"#, "Styrke"),
        (#"\bCycling\b"#, "Sykling"),
        (#"\bBike\b"#, "Sykkel"),
        (#"\bCadence\b"#, "Tråkkfrekvens"),
        (#"\bGear\b"#, "Gir"),
        (#"\bTrack\b"#, "Bane"),
        (#"\bStairs\b"#, "Trapper"),
        (#"\bStair\b"#, "Trapp"),
        (#"\bTechnique\b"#, "Teknikk"),
        (#"\bMobility\b"#, "Bevegelighet"),
        (#"\bStretching\b"#, "Uttøying"),
        (#"\bLactate\b"#, "Laktat"),
        (#"\bMinutes\b"#, "Minutter"),
        (#"\bMinute\b"#, "Minutt"),
        (#"\bmin\b"#, "min"),
        (#"\bSeconds\b"#, "Sekunder"),
        (#"\bSecond\b"#, "Sekund"),
        (#"\bsec\b"#, "sek"),
        (#"\brecovery\b"#, "restitusjon"),
        (#"\brest\b"#, "pause"),
        (#"\bbetween\b"#, "mellom"),
        (#"\bwith\b"#, "med"),
        (#"\band\b"#, "og"),
        (#"\bthen\b"#, "deretter"),
        (#"\bat\b"#, "i"),
        (#"\bin\b"#, "i"),
        (#"\bon\b"#, "på"),
        (#"\bfor\b"#, "i"),
        (#"\bto\b"#, "til")
    ]
}
