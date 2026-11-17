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

    static func workoutSummary(
        _ category: String,
        english: String,
        workoutID: String? = nil
    ) -> String {
        if workoutID == "THR-016" {
            return ATHLTHLocalization.choose(
                english: "Two separate threshold sessions on the same day, with 6–8 hours between. Record and save each as its OWN Apple Health workout; do not keep one workout active throughout the break.",
                norwegian: "To separate terskeløkter samme dag, med 6–8 timer mellom. Registrer og lagre hver for seg i Apple Helse. Ikke la én økt stå aktiv i hele pausen."
            )
        }
        if workoutID == "ASS-009" {
            return ATHLTHLocalization.choose(
                english: "Three-minute all-out test on a measured, flat 400 m track. Run all-out from the first second without pacing or looking at live speed. Record total distance and the distance in the final 30 seconds to estimate critical speed (CS) and D′.",
                norwegian: "Tre minutters maksimaltest på flat, oppmålt 400-metersbane. Løp maksimalt fra første sekund uten å disponere kreftene eller se på farten. Noter totaldistanse og distansen de siste 30 sekundene for å estimere kritisk hastighet (CS) og D′."
            )
        }
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
        switch input.lowercased() {
        case "--- 6-8h rest ---":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "6–8 hours between sessions",
                    norwegian: "6–8 timer mellom øktene"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "This plan contains TWO separate threshold workouts: finish and save the morning workout in Apple Health. Start a NEW workout in the evening, after 6–8 hours. Do not leave one workout recording running between sessions.",
                    norwegian: "Planen inneholder TO separate terskeløkter: Avslutt og lagre morgenøkten i Apple Helse. Start en NY økt på kvelden etter 6–8 timer. Ikke la én treningsregistrering gå mellom øktene."
                )
            )
        case "adjust pace based on readings":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Adjust pace after measurement",
                    norwegian: "Juster farten etter måling"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Use the recorded lactate readings to adjust the following effort. This instruction has no fixed duration.",
                    norwegian: "Bruk laktatmålingene til å tilpasse neste drag. Dette er en instruksjon uten egen varighet."
                )
            )
        case "10 single-leg hops per side + 10 bounding strides + 8 drop jumps + 10 a-skips per side":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Plyometric circuit",
                    norwegian: "Spenstsirkel"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "10 single-leg hops per side, 10 bounding strides, 8 drop jumps and 10 A-skips per side. Complete the exercises and move on manually; no duration was provided by the source.",
                    norwegian: "10 hink per bein, 10 spensthopp, 8 fallhopp og 10 A-skips per side. Gjennomfør øvelsene og gå videre manuelt. Kilden oppgir ingen varighet."
                )
            )
        case "walking then very slow jog":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Walk, then easy jog",
                    norwegian: "Gå, deretter rolig jogg"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Start by walking, then transition to a very easy jog. Use the prescribed duration for the whole step.",
                    norwegian: "Start med gange, og fortsett med svært rolig jogg. Varigheten gjelder hele deløkten."
                )
            )
        case "walking then recovery jog", "walk then very slow recovery jog":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Walk, then recovery jog",
                    norwegian: "Gå, deretter restitusjonsjogg"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Begin by walking, then jog lightly to cool down.",
                    norwegian: "Begynn med gange, og fortsett med rolig restitusjonsjogg."
                )
            )
        case "walk 3min then very slow jog":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Walk 3 min, then easy jog",
                    norwegian: "Gå 3 min, deretter rolig jogg"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Walk for the first 3 minutes, then continue with a very easy jog for the rest of this step.",
                    norwegian: "Gå de første 3 minuttene, og fortsett deretter med svært rolig jogg resten av deløkten."
                )
            )
        case "walking and recovery":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Walking recovery", norwegian: "Rolig gange"
                ),
                instructions: nil
            )
        case "6-minute test: run the greatest distance possible":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "6 min running test", norwegian: "6 min testløp"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run as far as possible in 6 minutes. Record the total distance.",
                    norwegian: "Løp så langt du klarer på 6 minutter. Noter totaldistansen."
                )
            )
        case "12-minute test: run the greatest distance possible at sustained effort":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "12 min Cooper test", norwegian: "12 min Cooper-test"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Cover the longest possible distance in 12 minutes at sustained effort. Record the total distance.",
                    norwegian: "Løp så langt du klarer med jevn, høy innsats i 12 minutter. Noter totaldistansen."
                )
            )
        case "1200m time trial (maximal effort)", "3600m time trial (maximal effort)":
            let distance = input.lowercased().hasPrefix("1200")
                ? "1200 m" : "3600 m"
            return StepCopy(
                title: distance + ATHLTHLocalization.choose(
                    english: " time trial", norwegian: " testløp"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run the full distance at maximum sustainable effort. Record your time.",
                    norwegian: "Løp hele distansen med maksimal, jevn innsats. Noter tiden."
                )
            )
        case "5000m time trial (maximal effort)":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "5 km time trial", norwegian: "5 km testløp"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run 5 km at maximum sustainable effort. Record your finishing time.",
                    norwegian: "Løp 5 km med maksimal, jevn innsats. Noter sluttiden."
                )
            )
        case "progressive 20m shuttle test (audio beep) until failure":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "20 m shuttle test", norwegian: "20 m skytteltest"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run repeated 20 m shuttles to the audio beeps as the speed increases, until you cannot keep up.",
                    norwegian: "Løp gjentatte drag på 20 meter etter lydsignalene. Farten øker gradvis. Fortsett til du ikke klarer å følge signalene."
                )
            )
        case "5 km at constant maf hr (180 - age). record time for each kilometer.":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "5 km MAF test", norwegian: "5 km MAF-test"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run 5 km at a steady MAF heart rate (180 minus age). Record the time for each kilometer.",
                    norwegian: "Løp 5 km med jevn MAF-puls (180 minus alder). Noter tiden for hver kilometer."
                )
            )
        case "progressive warmup: walk then very gradual acceleration over 12-15 min to reach maf hr":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Progressive MAF warmup", norwegian: "Gradvis MAF-oppvarming"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Start walking, then increase the speed gradually over 12–15 minutes until you reach your MAF heart rate.",
                    norwegian: "Begynn med gange, og øk farten gradvis over 12–15 minutter til du når MAF-pulsen din."
                )
            )
        case "progressive pace decrease over 10-15 min":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Gradual cool-down", norwegian: "Gradvis nedtrapping"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Reduce the pace gradually over 10–15 minutes.",
                    norwegian: "Senk farten gradvis over 10–15 minutter."
                )
            )
        case "jog down":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Jog downhill", norwegian: "Jogg ned bakken"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Easy jog back downhill. Move to the next interval when you are ready; no fixed time was supplied.",
                    norwegian: "Jogg rolig ned bakken. Gå til neste drag når du er klar. Det er ikke oppgitt noen fast tid."
                )
            )
        case "walk back":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Walk back", norwegian: "Gå tilbake"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Walk back to the starting point and continue manually when ready.",
                    norwegian: "Gå tilbake til startpunktet og fortsett manuelt når du er klar."
                )
            )
        case "partner's time":
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Partner recovery", norwegian: "Partnerpause"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Recover while your partner completes their interval. Continue manually when the partner finishes.",
                    norwegian: "Hvil mens partneren gjennomfører sitt drag. Fortsett manuelt når partneren er ferdig."
                )
            )
        default: break
        }
        if isRunning && input.lowercased().hasPrefix("progressive run: start at 8-9 km/h") {
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Conconi running test", norwegian: "Conconi-test"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Start at 8–9 km/h and increase by 0.5 km/h every 200 m (or every 2 min). Record heart rate at each stage and continue until exhaustion.",
                    norwegian: "Start på 8–9 km/t og øk med 0,5 km/t for hver 200 meter (eller hvert 2. minutt). Noter pulsen på hvert trinn, og fortsett til utmattelse."
                )
            )
        }
        if isRunning && input.lowercased().hasPrefix("4-5min stages at increasing speed") {
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "Lactate step test", norwegian: "Laktat-trinntest"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run 4–5-minute stages at increasing speed (+0.5 km/h per stage), starting around 60% of vVO2max. At each stage record HR, RPE and lactate if available. Continue until exhaustion.",
                    norwegian: "Løp trinn på 4–5 minutter med økende fart (+0,5 km/t per trinn). Start rundt 60 % av vVO2-maks. Noter puls, RPE og eventuelt laktat etter hvert trinn. Fortsett til utmattelse."
                )
            )
        }
        if isRunning && isThreeMinuteAllOut(input) {
            return StepCopy(
                title: ATHLTHLocalization.choose(
                    english: "3-minute all-out test",
                    norwegian: "3 min maksimaltest"
                ),
                instructions: ATHLTHLocalization.choose(
                    english: "Run all-out from the very first second for 180 seconds on a flat, measured track. Do not pace; let speed decrease naturally. Hide live pace, use the finish audio alert and record both the total distance and the distance covered from 2:30 to 3:00.",
                    norwegian: "Løp maksimalt fra første sekund i 180 sekunder på flat, oppmålt bane. Ikke spar på kreftene – la farten falle naturlig. Skjul live-tempo, bruk lydvarsel ved slutt og noter både totaldistanse og distansen mellom 2:30 og 3:00."
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

    /// Correct documented legacy source phrases without altering user-written
    /// titles or touching targets, routes, heart-rate zones or duration.
    static func normalizeLegacyImportedStep(_ block: WorkoutTemplateBlock)
        -> WorkoutTemplateBlock {
        let allOut = normalizeLegacyAllOutStep(block)
        guard allOut.kind == .run else { return allOut }
        let raw = allOut.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        // Exact phrases from older Zoned imports, including their original
        // mixed-language regex translations. Do not rewrite custom names.
        let sourceEnglish: String?
        switch raw {
        case "walking then very slow jog",
             "gange deretter svært langsom jogg":
            sourceEnglish = "Walking then very slow jog"
        case "walking then recovery jog",
             "gange deretter restitusjonsjogg":
            sourceEnglish = "Walking then recovery jog"
        case "walk then very slow recovery jog",
             "gå deretter svært langsom restitusjonsjogg":
            sourceEnglish = "Walk then very slow recovery jog"
        case "walk 3min then very slow jog",
             "gå 3min deretter svært langsom jogg":
            sourceEnglish = "Walk 3min then very slow jog"
        default:
            sourceEnglish = nil
        }
        guard let sourceEnglish else { return allOut }
        let copy = stepCopy(
            sourceEnglish: sourceEnglish,
            durationSeconds: allOut.durationSeconds, isRunning: true
        )
        var result = allOut
        result.title = copy.title
        if let instructions = copy.instructions {
            let existing = (result.notes ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.notes = existing.isEmpty ? instructions :
                (existing.contains(instructions) ? existing
                    : instructions + "\n" + existing)
        }
        return result
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
        (#"\baccelerations\b"#, "stigningsløp"),
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
