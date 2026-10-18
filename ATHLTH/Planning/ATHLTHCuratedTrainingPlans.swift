import Foundation

/// Reviewed starting points for different athletes. Stable identifiers allow
/// favorites and saved plans to survive app updates. These are not an injury
/// rehabilitation or individualized medical prescription.
enum ATHLTHCuratedTrainingPlans {
    private static func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private static func plan(
        _ number: Int, _ slug: String,
        _ name: String, _ norwegianName: String,
        _ description: String, _ norwegianDescription: String,
        category: String, goal: String, norwegianGoal: String,
        level: String, weeks: Int, pattern: [String], tags: [String]
    ) -> TrainingPlanCatalogEntry {
        TrainingPlanCatalogEntry(
            id: UUID(uuidString: String(format: "B2000000-0000-0000-0000-%012d", number))!,
            slug: slug,
            title: tr(name, norwegianName),
            summary: tr(description, norwegianDescription),
            category: category, goal: tr(goal, norwegianGoal),
            level: tr(level, level == "Beginner" ? "Nybegynner" :
                level == "Advanced" ? "Avansert" : "Middels"),
            durationWeeks: weeks,
            sessionsPerWeek: pattern.count,
            workoutPattern: pattern, tags: tags,
            sortOrder: 100 + number * 10,
            catalogVersion: 3
        )
    }

    static var entries: [TrainingPlanCatalogEntry] {
        [
            plan(1, "strength-two-day-consistency",
                 "Strength · 2 Days", "Styrke · 2 dager",
                 "A manageable two-day full-body routine for busy weeks.",
                 "To gjennomførbare helkroppsøkter for en travel hverdag.",
                 category: "strength", goal: "Consistency and whole-body strength",
                 norwegianGoal: "Regelmessighet og helkroppsstyrke",
                 level: "Beginner", weeks: 8,
                 pattern: ["full_body_a", "full_body_b"],
                 tags: ["strength", "beginner", "2 days", "full body"]),

            plan(2, "strength-upper-lower-foundation",
                 "Upper / Lower Foundation", "Over- og underkropp · grunnplan",
                 "Four balanced weekly sessions alternating upper and lower body.",
                 "Fire balanserte økter i uken fordelt på over- og underkropp.",
                 category: "strength", goal: "Build an upper/lower routine",
                 norwegianGoal: "Etablere en over-/underkroppssplitt",
                 level: "Intermediate", weeks: 8,
                 pattern: ["upper_body", "lower_body", "upper_body", "lower_body"],
                 tags: ["upper", "lower", "styrke", "overkropp", "underkropp"]),

            plan(3, "strength-ppl-3",
                 "Push / Pull / Legs · 3 Days", "Push / Pull / Legs · 3 dager",
                 "An introductory three-day split; each muscle group is trained once weekly.",
                 "En enkel tredelt splitt. Hver muskelgruppe får én hovedøkt per uke.",
                 category: "strength", goal: "Learn a classic gym split",
                 norwegianGoal: "Lære en klassisk treningssplitt",
                 level: "Intermediate", weeks: 8,
                 pattern: ["push", "pull", "legs"],
                 tags: ["ppl", "gym", "push", "pull", "legs"]),

            plan(4, "strength-ppl-6",
                 "Push / Pull / Legs · Advanced", "Push / Pull / Legs · avansert",
                 "Six sessions for experienced lifters who tolerate high training frequency.",
                 "Seks økter for erfarne utøvere som tåler høy treningsfrekvens.",
                 category: "strength", goal: "Higher-frequency hypertrophy",
                 norwegianGoal: "Muskelvekst med høyere frekvens",
                 level: "Advanced", weeks: 8,
                 pattern: ["push", "pull", "legs", "push", "pull", "legs"],
                 tags: ["ppl", "advanced", "hypertrophy", "muskelvekst"]),

            plan(5, "focus-chest-triceps",
                 "Chest & Triceps Focus", "Bryst og triceps · fokus",
                 "Twice-weekly pressing emphasis, balanced with pulling and leg training.",
                 "To brystfokuserte økter ukentlig, med rygg og bein som støtte.",
                 category: "muscle_focus", goal: "Develop chest and triceps",
                 norwegianGoal: "Prioritere bryst og triceps",
                 level: "Intermediate", weeks: 8,
                 pattern: ["chest", "legs", "push", "back"],
                 tags: ["chest", "bryst", "triceps", "press"]),

            plan(6, "focus-back-biceps",
                 "Back & Biceps Focus", "Rygg og biceps · fokus",
                 "Two pulling-focused days plus lower-body and pressing sessions.",
                 "To ryggfokuserte dager med bein og pressøvelser i tillegg.",
                 category: "muscle_focus", goal: "Develop back and biceps",
                 norwegianGoal: "Prioritere rygg og biceps",
                 level: "Intermediate", weeks: 8,
                 pattern: ["back", "lower_body", "pull", "push"],
                 tags: ["back", "rygg", "biceps", "pull"]),

            plan(7, "focus-shoulders",
                 "Shoulders & Upper Body", "Skuldre og overkropp",
                 "Build shoulder strength with balanced pushing, pulling and leg support.",
                 "Skulderstyrke med balansert press, draøvelser og beintrening.",
                 category: "muscle_focus", goal: "Shoulder development",
                 norwegianGoal: "Utvikle skuldre",
                 level: "Intermediate", weeks: 8,
                 pattern: ["shoulders_core", "lower_body", "upper_body"],
                 tags: ["shoulders", "skuldre", "core"]),

            plan(8, "focus-glutes-hamstrings",
                 "Glutes & Hamstrings", "Sete og bakside lår",
                 "Posterior-chain priority with recovery days between lower-body sessions.",
                 "Sete og bakside lår med hvile mellom de tunge underkroppsøktene.",
                 category: "muscle_focus", goal: "Glutes and posterior-chain strength",
                 norwegianGoal: "Styrke sete og bakside lår",
                 level: "Intermediate", weeks: 8,
                 pattern: ["glutes", "upper_body", "lower_body"],
                 tags: ["glutes", "sete", "hamstrings", "bakside"]),

            plan(9, "focus-quadriceps",
                 "Quadriceps & Legs", "Fremside lår og bein",
                 "Squat and knee-extension focus with posterior-chain balance.",
                 "Knebøyfokus og fremside lår, balansert med trening av baksiden.",
                 category: "muscle_focus", goal: "Quad and leg development",
                 norwegianGoal: "Prioritere fremside lår",
                 level: "Intermediate", weeks: 8,
                 pattern: ["quads", "upper_body", "legs"],
                 tags: ["quads", "bein", "legs", "quadriceps"]),

            plan(10, "focus-arms",
                 "Arms · Biceps & Triceps", "Armer · biceps og triceps",
                 "Direct arm work alongside compound upper-body and leg training.",
                 "Egen armøkt kombinert med baseøvelser og beintrening.",
                 category: "muscle_focus", goal: "Arm hypertrophy",
                 norwegianGoal: "Muskelvekst i armene",
                 level: "Intermediate", weeks: 8,
                 pattern: ["arms", "lower_body", "upper_body"],
                 tags: ["arms", "armer", "biceps", "triceps"]),

            plan(11, "focus-core-stability",
                 "Core & Stability", "Kjerne og stabilitet",
                 "A practical core-focused plan with whole-body strength and easy activity.",
                 "Kjernefokus med helkroppsstyrke og rolig aktivitet.",
                 category: "muscle_focus", goal: "Core control and general fitness",
                 norwegianGoal: "Kjernestabilitet og funksjon",
                 level: "Beginner", weeks: 6,
                 pattern: ["core", "full_body_a", "core"],
                 tags: ["core", "kjerne", "mage", "stability"]),

            plan(12, "home-bodyweight-8w",
                 "Home Strength · No Gym", "Hjemmetrening · uten treningssenter",
                 "Accessible bodyweight training with short sessions and simple progression.",
                 "Tilgjengelig styrketrening hjemme, med korte økter og enkel progresjon.",
                 category: "strength", goal: "Strength without gym equipment",
                 norwegianGoal: "Styrke uten treningsapparater",
                 level: "Beginner", weeks: 8,
                 pattern: ["home", "core", "home"],
                 tags: ["home", "hjemme", "bodyweight", "no equipment"]),

            plan(13, "strength-compound-cycle",
                 "Compound Strength Cycle", "Grunnstyrke · baseøvelser",
                 "Three compound-focused days. Keep loads manageable and refine technique.",
                 "Tre økter med baseøvelser. Prioriter teknikk og håndterbar belastning.",
                 category: "strength", goal: "Build compound-lift strength",
                 norwegianGoal: "Øke styrke i baseøvelser",
                 level: "Intermediate", weeks: 8,
                 pattern: ["power_squat", "power_bench", "power_deadlift"],
                 tags: ["5x5", "strength", "baseøvelser", "powerlifting"]),

            plan(14, "powerlifting-technique",
                 "Powerlifting · Foundation", "Styrkeløft · grunnplan",
                 "Build sound squat, bench and deadlift practice across three days.",
                 "Bygg trygg teknikk og styrke i knebøy, benkpress og markløft.",
                 category: "competition", goal: "Learn the three competition lifts",
                 norwegianGoal: "Beherske de tre styrkeløftene",
                 level: "Intermediate", weeks: 10,
                 pattern: ["power_squat", "power_bench", "power_deadlift"],
                 tags: ["powerlifting", "styrkeløft", "squat", "bench", "deadlift"]),

            plan(15, "powerlifting-meet-prep",
                 "Powerlifting · Meet Preparation", "Styrkeløft · konkurranseforberedelse",
                 "Twelve weeks of skill work, controlled heavy practice and a lower-volume final phase.",
                 "Tolv uker med løfteteknikk, kontrollert tung trening og roligere sluttfase.",
                 category: "competition", goal: "Prepare for a powerlifting meet",
                 norwegianGoal: "Forberede styrkeløftkonkurranse",
                 level: "Advanced", weeks: 12,
                 pattern: ["power_squat", "power_bench", "power_deadlift", "power_bench"],
                 tags: ["powerlifting", "competition", "meet", "styrkeløft"]),

            plan(16, "race-5k-speed",
                 "5K · Race Preparation", "5 km · konkurranseforberedelse",
                 "Eight weeks of easy mileage, short intervals and a controlled race-pace session.",
                 "Åtte uker med rolige turer, korte intervaller og konkurransetempo.",
                 category: "competition", goal: "Improve 5K performance",
                 norwegianGoal: "Forbedre tiden på 5 km",
                 level: "Intermediate", weeks: 8,
                 pattern: ["easy_run", "interval_run", "race_pace_run"],
                 tags: ["5k", "race", "running", "løping"]),

            plan(17, "race-10k-prep",
                 "10K · Race Preparation", "10 km · konkurranseforberedelse",
                 "Ten weeks combining easy endurance, threshold work and longer running.",
                 "Ti uker med rolig utholdenhet, terskelarbeid og lengre løpeturer.",
                 category: "competition", goal: "Race 10 kilometers",
                 norwegianGoal: "Løpe 10 km konkurranse",
                 level: "Intermediate", weeks: 10,
                 pattern: ["easy_run", "tempo_run", "full_body_a", "long_run"],
                 tags: ["10k", "race", "threshold", "terskel"]),

            plan(18, "race-half-marathon",
                 "Half Marathon · Race Preparation", "Halvmaraton · konkurranseplan",
                 "Twelve weeks for runners with an established base; steady long runs and a taper.",
                 "Tolv uker for løpere med treningsgrunnlag, langtur og nedtrapping.",
                 category: "competition", goal: "Prepare for a half marathon",
                 norwegianGoal: "Forberede halvmaraton",
                 level: "Intermediate", weeks: 12,
                 pattern: ["easy_run", "tempo_run", "full_body_a", "long_run"],
                 tags: ["half-marathon", "race", "21.1k", "halvmaraton"]),

            plan(19, "race-marathon",
                 "Marathon · Race Preparation", "Maraton · konkurranseplan",
                 "Sixteen weeks for experienced runners with an existing mileage base, including recovery and taper.",
                 "Seksten uker for erfarne løpere med etablert mengdegrunnlag, restitusjon og nedtrapping.",
                 category: "competition", goal: "Prepare for a marathon",
                 norwegianGoal: "Forberede maraton",
                 level: "Advanced", weeks: 16,
                 pattern: ["easy_run", "tempo_run", "full_body_a", "easy_run", "long_run"],
                 tags: ["marathon", "race", "advanced", "maraton"]),

            plan(20, "trail-hills-foundation",
                 "Trail & Hills", "Terrengløp og bakker",
                 "Build hill-running skills and easy trail endurance without racing every session.",
                 "Bygg kapasitet i bakker og terreng uten å løpe hardt hver økt.",
                 category: "running", goal: "Trail and uphill running",
                 norwegianGoal: "Terreng- og motbakkeløping",
                 level: "Intermediate", weeks: 10,
                 pattern: ["easy_run", "hill_run", "full_body_b", "long_run"],
                 tags: ["trail", "hills", "terrain", "terreng", "bakker"]),

            plan(21, "hyrox-first-event",
                 "HYROX-Style · First Event", "HYROX-inspirert · første konkurranse",
                 "Four weekly sessions mixing aerobic work, strength and station technique.",
                 "Fire økter med utholdenhet, styrke og teknikk på konkurransestasjoner.",
                 category: "hybrid", goal: "Build hybrid race readiness",
                 norwegianGoal: "Forberede hybridkonkurranse",
                 level: "Intermediate", weeks: 10,
                 pattern: ["easy_run", "upper_body", "hyrox_skills", "lower_body"],
                 tags: ["hyrox", "hybrid", "stations", "competition"]),

            plan(22, "hyrox-competitive-build",
                 "HYROX-Style · Performance", "HYROX-inspirert · prestasjon",
                 "Twelve weeks combining intervals, station endurance and strength for experienced athletes.",
                 "Tolv uker med intervaller, stasjonsarbeid og styrke for erfarne utøvere.",
                 category: "competition", goal: "Develop hybrid race performance",
                 norwegianGoal: "Utvikle kapasitet til hybridkonkurranse",
                 level: "Advanced", weeks: 12,
                 pattern: ["interval_run", "upper_body", "easy_run", "hyrox_circuit", "lower_body"],
                 tags: ["hyrox", "hybrid", "competition", "advanced"]),

            plan(23, "hybrid-three-day",
                 "Hybrid · 3 Days", "Hybrid · 3 dager",
                 "A sustainable split for people who want to run and build strength.",
                 "En gjennomførbar kombinasjon for deg som vil løpe og trene styrke.",
                 category: "hybrid", goal: "Running plus strength",
                 norwegianGoal: "Kombinere løp og styrke",
                 level: "Beginner", weeks: 8,
                 pattern: ["full_body_a", "easy_run", "full_body_b"],
                 tags: ["hybrid", "allround", "run", "strength"]),

            plan(24, "walking-strength-foundation",
                 "Walking & Strength", "Gåing og styrke",
                 "Low-barrier walking and resistance sessions for developing a training habit.",
                 "Rolige gåturer og tilpasset styrke for gode treningsvaner.",
                 category: "general_fitness", goal: "Everyday activity and strength",
                 norwegianGoal: "Aktiv hverdag og grunnstyrke",
                 level: "Beginner", weeks: 8,
                 pattern: ["walking", "home", "walking"],
                 tags: ["walking", "gåing", "beginner", "hverdagsaktivitet"])
        ]
    }
}

extension TrainingPlanCatalogEntry {
    /// Editorial prerequisites shown before someone copies an advanced plan.
    /// All plans still require the athlete to adapt to their health, capacity
    /// and current training history.
    var readinessGuidance: String? {
        switch slug {
        case "race-marathon", "marathon-build":
            return ATHLTHLocalization.choose(
                english: "For regular runners with an established weekly running base and comfortable long runs. If you are new to running, build a shorter-distance foundation first. Adjust the last two weeks to your real race date.",
                norwegian: "For løpere med etablert ukentlig løpsmengde og erfaring med rolige langturer. Er du ny som løper, bygg grunnlaget med kortere distanser først. Tilpass de to siste ukene til faktisk løpsdato."
            )
        case "race-half-marathon", "half-marathon-foundation":
            return ATHLTHLocalization.choose(
                english: "You should already be running consistently. Use the first weeks to verify that the planned long runs match your current level, then adjust duration as needed.",
                norwegian: "Du bør allerede løpe regelmessig. Bruk de første ukene til å kontrollere at langturen passer nivået ditt, og juster varigheten ved behov."
            )
        case "powerlifting-meet-prep", "powerlifting-technique":
            return ATHLTHLocalization.choose(
                english: "Prior lifting technique and safe spotting matter. These are submaximal training templates, not 1RM testing instructions. Arrange competition attempts with a qualified coach.",
                norwegian: "God løfteteknikk og trygg sikring er viktig. Malene inneholder submaksimale økter, ikke instruksjoner for maksløft. Planlegg konkurranseforsøk med kvalifisert trener."
            )
        case "hyrox-competitive-build", "hyrox-first-event":
            return ATHLTHLocalization.choose(
                english: "Requires access to relevant stations. Choose manageable loads, practice safe transitions and check your official event division rules separately.",
                norwegian: "Krever tilgang til relevante stasjoner. Velg håndterbare belastninger, øv på trygge overganger og kontroller reglene for din konkurranseklasse separat."
            )
        case "strength-ppl-6":
            return ATHLTHLocalization.choose(
                english: "Six days each week is demanding. Intended for experienced lifters with sufficient sleep, food and recovery. Switch to the three-day or upper/lower plan if progress or recovery stalls.",
                norwegian: "Seks økter i uken er krevende. Ment for erfarne utøvere med nok søvn, mat og restitusjon. Velg en kortere splitt hvis fremgang eller restitusjon stopper opp."
            )
        default:
            return category == "competition" ? ATHLTHLocalization.choose(
                english: "Race preparation should start from your current fitness, not a target time alone. Plan the final weeks around your actual event date.",
                norwegian: "Konkurranseforberedelse må ta utgangspunkt i formen du har i dag, ikke bare ønsket sluttid. Tilpass sluttukene til faktisk konkurransedato."
            ) : nil
        }
    }
}
