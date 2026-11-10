import Foundation

/// Personalized, read-only recommendations based on actual completed workouts.
/// No steps are treated as a running workout; planned, pending-import, and
/// unfinished sessions never establish an athlete's training habits.
enum HomeTrainingPatternAdvisor {
    enum Activity: String, CaseIterable {
        case running, walking, strength, cycling, other

        init(_ activity: WorkoutActivity) {
            switch activity {
            case .running: self = .running
            case .walking, .hiking: self = .walking
            case .strength: self = .strength
            case .cycling: self = .cycling
            default: self = .other
            }
        }
    }

    struct Event {
        let id: UUID
        let activity: Activity
        let startedAt: Date
        let minutes: Int
    }

    struct Pattern {
        let activity: Activity
        let count42Days: Int
        let sessionsPerWeek: Double
        let daysSinceLast: Int?
        let usualGapDays: Double?
        let usualMinutes: Int
    }

    struct StrengthRoutine {
        let focus: String
        let lastPerformed: Date
        let occurrences42Days: Int
        let session: PlannedSession
    }

    struct Snapshot {
        let now: Date
        let calendar: Calendar
        let events: [Event]
        let patterns: [Activity: Pattern]
        let routines: [StrengthRoutine]
        let dogName: String?

        var hasCompletedWorkoutToday: Bool {
            events.contains { calendar.isDate($0.startedAt, inSameDayAs: now) }
        }

        var usedActivities: Set<Activity> {
            Set(events.map(\.activity))
        }

        func pattern(_ activity: Activity) -> Pattern? { patterns[activity] }

        func daysSince(_ date: Date) -> Int {
            max(0, calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: now)
            ).day ?? 0)
        }

        func count(_ activity: Activity, lastDays days: Int) -> Int {
            let threshold = calendar.date(byAdding: .day, value: -days,
                                          to: calendar.startOfDay(for: now)) ?? now
            return events.filter {
                $0.activity == activity &&
                $0.startedAt >= threshold && $0.startedAt <= now
            }.count
        }

        var totalCount42Days: Int { events.count }
        var supportsPersonalization: Bool { !events.isEmpty }
    }

    static func snapshot(
        workouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        phoneHistory: [PhoneWorkout],
        dogs: [ATHLTHPet] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Snapshot {
        let start = calendar.date(byAdding: .day, value: -42,
                                  to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-42 * 86_400)
        var events: [Event] = []
        // Indexed reconciliation avoids scanning all prior sessions for
        // every local workout. Each time bucket covers two minutes and
        // adjacent buckets are also checked to preserve the +/-120s rule.
        var eventIDs: Set<UUID> = []
        var startsByActivity: [Activity: [Int: [Date]]] = [:]

        func bucket(for date: Date) -> Int {
            Int(floor(date.timeIntervalSince1970 / 120))
        }

        func append(_ event: Event) {
            events.append(event)
            eventIDs.insert(event.id)
            let index = bucket(for: event.startedAt)
            startsByActivity[event.activity, default: [:]][index, default: []]
                .append(event.startedAt)
        }

        func hasNearbyStart(_ date: Date, activity: Activity) -> Bool {
            let index = bucket(for: date)
            guard let starts = startsByActivity[activity] else { return false }
            for candidateBucket in (index - 1)...(index + 1) {
                if starts[candidateBucket]?.contains(where: {
                    abs($0.timeIntervalSince(date)) <= 120
                }) == true {
                    return true
                }
            }
            return false
        }

        func accepts(_ date: Date, duration: TimeInterval) -> Bool {
            date >= start && date <= now && duration.isFinite &&
            (5 * 60...8 * 3_600).contains(duration)
        }

        for workout in workouts where accepts(
            workout.startDate, duration: workout.duration
        ) {
            append(Event(
                id: workout.id, activity: Activity(workout.activity),
                startedAt: workout.startDate,
                minutes: Int((workout.duration / 60).rounded())
            ))
        }

        let finishedStrength = strengthHistory.filter {
            guard let end = $0.endedAt else { return false }
            return accepts($0.startedAt, duration: end.timeIntervalSince($0.startedAt))
        }
        for record in finishedStrength {
            // HealthKit and ATHLTH logs can describe the same workout.
            if (record.healthMetrics.healthKitWorkoutUUID.map {
                eventIDs.contains($0)
            } ?? false) ||
                hasNearbyStart(record.startedAt, activity: .strength) {
                continue
            }
            let duration = record.endedAt!.timeIntervalSince(record.startedAt)
            append(Event(
                id: record.id, activity: .strength, startedAt: record.startedAt,
                minutes: Int((duration / 60).rounded())
            ))
        }

        for record in phoneHistory {
            guard let end = record.end,
                  accepts(record.start, duration: end.timeIntervalSince(record.start))
            else { continue }
            let activity: Activity = record.walking ? .walking : .running
            if eventIDs.contains(record.id) ||
                (record.healthID.map { eventIDs.contains($0) } ?? false) ||
                hasNearbyStart(record.start, activity: activity) {
                continue
            }
            append(Event(
                id: record.id, activity: activity, startedAt: record.start,
                minutes: Int((end.timeIntervalSince(record.start) / 60).rounded())
            ))
        }
        events.sort { $0.startedAt > $1.startedAt }

        var patterns: [Activity: Pattern] = [:]
        for activity in Activity.allCases {
            let matching = events.filter { $0.activity == activity }
            guard !matching.isEmpty else { continue }
            let uniqueDays = Set(matching.map {
                calendar.startOfDay(for: $0.startedAt)
            }).sorted()
            let gaps = zip(uniqueDays, uniqueDays.dropFirst()).compactMap { pair -> Double? in
                let days = calendar.dateComponents(
                    [.day], from: pair.0, to: pair.1
                ).day ?? 0
                return days > 0 ? Double(days) : nil
            }
            let minutes = matching.map(\.minutes).sorted()
            let typical = minutes[minutes.count / 2]
            patterns[activity] = Pattern(
                activity: activity, count42Days: matching.count,
                sessionsPerWeek: Double(matching.count) / 6,
                daysSinceLast: matching.first.map {
                    max(0, calendar.dateComponents(
                        [.day], from: calendar.startOfDay(for: $0.startedAt),
                        to: calendar.startOfDay(for: now)
                    ).day ?? 0)
                },
                usualGapDays: gaps.isEmpty ? nil : gaps.sorted()[gaps.count / 2],
                usualMinutes: typical
            )
        }

        let routines = strengthRoutines(
            from: finishedStrength, calendar: calendar
        )
        return Snapshot(
            now: now, calendar: calendar, events: events,
            patterns: patterns, routines: routines,
            dogName: dogs.first(where: {
                $0.species == "dog" &&
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })?.name
        )
    }

    private static func focus(for exercise: StrengthExerciseLog) -> String? {
        let muscles = exercise.exercise.primaryMuscles.map {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let name = exercise.exercise.name.lowercased()
        if muscles.contains(where: {
            $0.contains("pectoral") || $0.contains("chest") ||
            $0.contains("bryst")
        }) || ["bench press", "chest press", "cable fly", "chest fly",
              "benkpress", "brystpress"].contains(where: name.contains) {
            return "chest"
        }
        if muscles.contains(where: {
            $0.contains("latissimus") || $0.contains("back") ||
            $0.contains("rygg") || $0.contains("trapezius")
        }) { return "back" }
        if muscles.contains(where: {
            $0.contains("quadriceps") || $0.contains("hamstring") ||
            $0.contains("glute") || $0.contains("leg") ||
            $0.contains("lår") || $0.contains("bein")
        }) { return "legs" }
        if muscles.contains(where: {
            $0.contains("deltoid") || $0.contains("shoulder") ||
            $0.contains("skulder")
        }) { return "shoulders" }
        if muscles.contains(where: {
            $0.contains("abdom") || $0.contains("core") ||
            $0.contains("mage")
        }) { return "core" }
        return nil
    }

    private static func strengthRoutines(
        from history: [StrengthWorkoutLog], calendar: Calendar
    ) -> [StrengthRoutine] {
        var focused: [(focus: String, workout: StrengthWorkoutLog)] = []
        for log in history {
            var counts: [String: Int] = [:]
            for exercise in log.exercises where
                exercise.sets.contains(where: \.isCompleted) {
                if let focus = focus(for: exercise) {
                    counts[focus, default: 0] += 1
                }
            }
            if let best = counts.max(by: { $0.value < $1.value }),
               best.value >= 1 {
                focused.append((best.key, log))
            }
        }
        var results: [StrengthRoutine] = []
        for focus in Set(focused.map { $0.focus }) {
            let matches = focused.filter { $0.focus == focus }
                .sorted { $0.workout.startedAt > $1.workout.startedAt }
            guard matches.count >= 2, let latest = matches.first,
                  let end = latest.workout.endedAt else { continue }
            let log = latest.workout
            let blocks: [WorkoutTemplateBlock] = log.exercises.compactMap { exercise in
                let finished = exercise.sets.filter { $0.isCompleted }
                guard !finished.isEmpty else { return nil }
                let typicalReps = finished.compactMap(\.completedReps).sorted()
                var block = WorkoutTemplateBlock(
                    sequence: 1, kind: .exercise,
                    title: exercise.exercise.name,
                    exerciseSlug: nil, distanceMeters: nil,
                    repetitions: typicalReps.isEmpty
                        ? nil : typicalReps[typicalReps.count / 2],
                    durationSeconds: nil,
                    targetWeightKilograms: nil, loadNote: nil,
                    notes: nil, phase: .main,
                    setCount: min(finished.count, 12)
                )
                block.exerciseSnapshot = exercise.exercise
                return block
            }
            guard !blocks.isEmpty else { continue }
            let minutes = Int((end.timeIntervalSince(log.startedAt) / 60).rounded())
            let regularTitle = log.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let focusedTitle: String
            if regularTitle.isEmpty ||
               ["styrke", "strength", "styrkeøkt", "workout"].contains(
                regularTitle.lowercased()
               ) {
                focusedTitle = ATHLTHLocalization.isNorwegian
                    ? (["chest": "Brystøkt", "back": "Ryggøkt",
                        "legs": "Beinøkt", "shoulders": "Skulderøkt",
                        "core": "Kjerneøkt"][focus] ?? "Styrkeøkt")
                    : (["chest": "Chest workout", "back": "Back workout",
                        "legs": "Leg workout", "shoulders": "Shoulder workout",
                        "core": "Core workout"][focus] ?? "Strength workout")
            } else {
                focusedTitle = regularTitle
            }
            var session = PlannedSession(
                id: UUID(), title: focusedTitle, kind: .strength,
                scheduledStart: nil, durationMinutes: min(max(minutes, 20), 120),
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil, exercises: [],
                notes: ATHLTHLocalization.choose(
                    english: "Based on your completed strength session. Adjust load to today's condition.",
                    norwegian: "Basert på en tidligere gjennomført styrkeøkt. Tilpass belastningen til dagsformen."
                )
            )
            session.workoutBlocks = blocks.enumerated().map { index, source in
                ATHLTHWorkoutPhasePlacement.renumbered(source, sequence: index + 1)
            }
            session.workoutCategory = "strength"
            results.append(StrengthRoutine(
                focus: focus, lastPerformed: log.startedAt,
                occurrences42Days: matches.count, session: session
            ))
        }
        return results
    }

    static func recommend(
        snapshot: Snapshot,
        readiness: HomeDailyRecommendationPolicy.Readiness,
        trainingLoadRatio: Double?,
        hasWorkoutToday: Bool,
        plannedWorkoutTitle: String?
    ) -> HomeDailyRecommendationPolicy.Advice? {
        typealias Choice = HomeDailyRecommendationPolicy.SuggestedWorkout
        guard snapshot.supportsPersonalization else { return nil }
        func tr(_ en: String, _ no: String) -> String {
            ATHLTHLocalization.choose(english: en, norwegian: no)
        }
        let overLoaded = (trainingLoadRatio ?? 0) >= 1.5
        let lowered = readiness == .recover || readiness == .takeItEasy || overLoaded
        let count = snapshot.totalCount42Days
        let preferred = snapshot.patterns.values.sorted {
            if $0.count42Days != $1.count42Days {
                return $0.count42Days > $1.count42Days
            }
            return $0.activity.rawValue < $1.activity.rawValue
        }.first
        guard let main = preferred else { return nil }
        let runs = snapshot.pattern(.running)
        let walk = snapshot.pattern(.walking)
        let strength = snapshot.pattern(.strength)
        let mainMinutes = min(max(main.usualMinutes, 15), 75)
        let recentRuns = snapshot.count(.running, lastDays: 4)
        let only = snapshot.usedActivities.count == 1
        let recentStrength = strength?.daysSinceLast ?? 90
        let daysSinceRun = runs?.daysSinceLast ?? 90

        var choice: Choice
        var proposedStrength: PlannedSession?
        var explanation: String

        // Keep existing scheduled workouts when reasonable. A poor readiness
        // signal changes the suggestion but never edits the athlete's plan.
        if hasWorkoutToday, plannedWorkoutTitle != nil, !lowered {
            choice = .planned
            explanation = tr(
                "Today's planned session fits your schedule. Adjust the effort to recovery.",
                "Dagens planlagte økt passer inn i treningsrytmen din. Tilpass intensiteten til restitusjonen."
            )
        } else if snapshot.hasCompletedWorkoutToday {
            choice = .restDay
            explanation = tr(
                "You have already completed a workout today. Recovery is the priority.",
                "Du har allerede gjennomført en økt i dag. Restitusjon prioriteres."
            )
        } else if lowered {
            if main.activity == .walking {
                choice = .easyWalk(minutes: min(mainMinutes, 25))
            } else if main.activity == .running && readiness != .recover &&
                        !overLoaded && (runs?.sessionsPerWeek ?? 0) >= 3 {
                choice = .easyRun(minutes: min(mainMinutes, 20))
            } else {
                choice = .restDay
            }
            explanation = tr(
                "Recovery or recent training load suggests a lighter day than your usual routine.",
                "Restitusjon eller treningsbelastning tilsier en roligere dag enn du vanligvis har."
            )
        } else {
            // Strength sessions are never injected into a runner-only history.
            // A completed routine with repeated real exercises can be reused
            // when that muscle group has had time since its last session.
            let eligibleStrength = snapshot.routines
                .filter {
                    let days = snapshot.daysSince($0.lastPerformed)
                    let typicalGap = strength?.usualGapDays ?? 7
                    return days >= 3 &&
                        days <= Int(max(10, min(21, typicalGap * 2.5))) &&
                        $0.occurrences42Days >= 2
                }
                .sorted {
                    let ld = snapshot.daysSince($0.lastPerformed)
                    let rd = snapshot.daysSince($1.lastPerformed)
                    return ld > rd
                }
            let pickStrength = eligibleStrength.first
            let rotateToStrength = pickStrength != nil && strength != nil &&
                (main.activity == .strength ||
                 (recentRuns >= 2 && recentStrength >= 3))
            if rotateToStrength, let routine = pickStrength {
                choice = .historicalStrength
                proposedStrength = routine.session
                let focus = localizedFocus(routine.focus)
                if recentRuns >= 2 {
                    explanation = tr(
                        "You have recorded \(recentRuns) runs in the last four days. \(focus) is a strength focus you have trained repeatedly, last \(snapshot.daysSince(routine.lastPerformed)) days ago.",
                        "Du har registrert \(recentRuns) løpeturer de siste fire dagene. \(focus) er et styrkefokus du har trent flere ganger, sist for \(snapshot.daysSince(routine.lastPerformed)) dager siden."
                    )
                } else {
                    explanation = tr(
                        "This is a familiar \(focus) strength routine from your own training history. Its last session was \(snapshot.daysSince(routine.lastPerformed)) days ago.",
                        "Dette er en kjent \(focus)-økt fra din egen treningshistorikk. Siste økt var for \(snapshot.daysSince(routine.lastPerformed)) dager siden."
                    )
                }
            } else {
                // A frequent runner should be assessed against their *own*
                // weekly frequency and normal gap, not a universal 2-day cut.
                let nextActivity: Activity = {
                    if main.activity == .running, let walk,
                       walk.count42Days > (runs?.count42Days ?? 0) {
                        return .walking
                    }
                    return main.activity
                }()
                switch nextActivity {
                case .running:
                    let frequency = runs?.sessionsPerWeek ?? 0
                    let gap = runs?.usualGapDays ?? 7
                    let normalReturn = daysSinceRun <= Int(max(3, ceil(gap * 1.6)))
                    if frequency >= 3 && normalReturn &&
                       readiness == .ready && daysSinceRun >= 1 {
                        choice = .progressiveRun(
                            minutes: min(max(runs?.usualMinutes ?? 30, 20), 45)
                        )
                    } else {
                        let historicMinutes = min(
                            max(runs?.usualMinutes ?? 25, 15), 45
                        )
                        choice = .easyRun(
                            minutes: normalReturn
                                ? historicMinutes : min(historicMinutes, 20)
                        )
                    }
                    explanation = normalReturn
                        ? tr(
                            "Based on your usual \(frequency.formatted(.number.precision(.fractionLength(1)))) runs per week and the last registered run \(daysSinceRun) days ago.",
                            "Basert på omtrent \(frequency.formatted(.number.precision(.fractionLength(1)))) løpeturer per uke og siste registrerte løpetur for \(daysSinceRun) dager siden."
                        )
                        : tr(
                            "It has been \(daysSinceRun) days since your last registered run, longer than your usual gap. Resume with a shorter easy session.",
                            "Det er \(daysSinceRun) dager siden siste registrerte løpetur, lenger enn ditt vanlige opphold. Start med en kortere, rolig økt."
                        )
                case .walking:
                    let previousLength = min(
                        max(walk?.usualMinutes ?? 25, 15), 75
                    )
                    let daysOff = walk?.daysSinceLast ?? 90
                    let expected = walk?.usualGapDays ?? 7
                    choice = .easyWalk(
                        minutes: daysOff > Int(max(4, expected * 1.7))
                            ? min(previousLength, 25) : previousLength
                    )
                    explanation = tr(
                        "Walking is your usual activity, so the recommendation follows your walking history.",
                        "Gåturer er din vanlige aktivitet, derfor tar anbefalingen utgangspunkt i turhistorikken din."
                    )
                case .strength:
                    if let routine = pickStrength {
                        choice = .historicalStrength
                        proposedStrength = routine.session
                        explanation = tr(
                            "This strength routine repeats exercises you have completed before, with recovery time since the last session.",
                            "Denne styrkeøkten bruker øvelser du har gjennomført tidligere, med tid til restitusjon siden sist."
                        )
                    } else {
                        choice = .restDay
                        explanation = tr(
                            "Your history is mainly strength training. No sufficiently recovered, repeated exercise group is confirmed today.",
                            "Historikken din består hovedsakelig av styrke. Vi har ikke nok grunnlag for å velge en bestemt muskelgruppe i dag."
                        )
                    }
                case .cycling, .other:
                    choice = .restDay
                    explanation = tr(
                        "Your logged activities are not running or walking. Choose one of your usual activities in Train.",
                        "Aktivitetene dine er ikke løping eller gåturer. Velg en av dine vanlige aktiviteter under Tren."
                    )
                }
            }
        }

        // Preserve the category of the athlete's actual routine. When the
        // account only contains running, neither walking nor strength is
        // introduced as a filler recommendation.
        if only && main.activity == .running && choice.kind == .walking {
            choice = .restDay
        }
        if only && main.activity == .strength && choice.kind == .walking {
            choice = .restDay
        }

        let title: String
        let detail: String
        switch choice {
        case .planned:
            title = plannedWorkoutTitle ?? tr("Planned workout", "Planlagt økt")
            detail = tr("Follow your existing session.", "Følg den planlagte økten.")
        case .restDay:
            title = tr("Recovery day", "Restitusjonsdag")
            detail = tr("Rest or use your usual light mobility routine.",
                        "Hvil, eller velg lett bevegelighet som du kjenner fra før.")
        case .historicalStrength:
            title = proposedStrength?.title ?? tr("Strength workout", "Styrkeøkt")
            detail = tr("Your previous exercises · adjust sets and weights.",
                        "Dine tidligere øvelser · tilpass sett og belastning.")
        case .easyWalk(let minutes):
            title = tr("Walk · \(minutes) min", "Gåtur · \(minutes) min")
            detail = tr("Comfortable walking at your usual pace.",
                        "Rolig tur i ditt vanlige tempo.")
        case .easyRun(let minutes):
            title = tr("Easy run · \(minutes) min", "Rolig løpetur · \(minutes) min")
            detail = tr("Comfortable pace, adjustable duration.",
                        "Behagelig tempo, tilpass varigheten.")
        case .progressiveRun(let minutes):
            title = tr("Progressive run · \(minutes) min",
                       "Progressiv løpetur · \(minutes) min")
            detail = tr("Start easy and increase the pace only if comfortable.",
                        "Start rolig og øk farten bare hvis det føles riktig.")
        case .tempoRun(let minutes):
            title = tr("Tempo run · \(minutes) min", "Tempoøkt · \(minutes) min")
            detail = tr("Controlled running.", "Kontrollert løping.")
        }

        // The Home tile is intentionally short. The longer, specific
        // explanation above is retained for its information sheet.
        let shortDescription: String = {
            switch choice {
            case .planned:
                return tr(
                    "Your planned workout is ready. Adjust the effort.",
                    "Den planlagte økten er klar. Tilpass innsatsen."
                )
            case .restDay:
                if snapshot.hasCompletedWorkoutToday {
                    return tr(
                        "You have trained today. Make room for recovery.",
                        "Du har trent i dag. Gi kroppen tid til hvile."
                    )
                }
                return lowered
                    ? tr("A quieter day is recommended.",
                         "En roligere dag passer best nå.")
                    : tr("Prioritize recovery today.",
                         "Prioriter restitusjon i dag.")
            case .historicalStrength:
                return tr(
                    "A familiar strength session fits your history.",
                    "En kjent styrkeøkt passer treningsrytmen din."
                )
            case .easyWalk:
                return tr(
                    "An easy walk fits today's recommendation.",
                    "En rolig gåtur passer i dag."
                )
            case .easyRun:
                if lowered {
                    return tr(
                        "Keep your run shorter and easy today.",
                        "Velg en kort og rolig løpetur i dag."
                    )
                }
                if let days = runs?.daysSinceLast,
                   let gap = runs?.usualGapDays,
                   days > Int(max(3, ceil(gap * 1.6))) {
                    return tr(
                        "\(days) days since your last run. Ease back in.",
                        "\(days) dager siden siste løpetur. Start rolig igjen."
                    )
                }
                return tr(
                    "An easy run fits your usual training rhythm.",
                    "En rolig løpetur passer treningsrytmen din."
                )
            case .progressiveRun:
                return tr(
                    "Start easy. Increase the pace only if comfortable.",
                    "Start rolig. Øk farten bare hvis det føles bra."
                )
            case .tempoRun:
                return tr(
                    "Controlled running fits your current rhythm.",
                    "Kontrollert tempo passer treningsrytmen din."
                )
            }
        }()

        let petPrompt: String? = {
            guard case .easyWalk = choice, let dogName = snapshot.dogName
            else { return nil }
            return tr(
                "Bring \(dogName) if the walk suits them? Select your pet when starting. ",
                "Ta med \(dogName) hvis turen passer? Velg kjæledyr ved start. "
            )
        }()
        let cadence = main.sessionsPerWeek.formatted(
            .number.precision(.fractionLength(1))
        )
        let evidence = tr(
            "Based on \(count) recorded sessions over 6 weeks · \(cadence) \(main.activity.rawValue) sessions/week",
            "Basert på \(count) registrerte økter på 6 uker · ca. \(cadence) \(localizedActivity(main.activity))/uke"
        )
        return HomeDailyRecommendationPolicy.Advice(
            title: title, detail: detail, source: tr(
                "Based on your routine", "Basert på dine treningsvaner"
            ), symbol: "sparkles", destination: .training,
            evidence: evidence, dayDescription: explanation,
            shortDescription: shortDescription,
            suggestedWorkout: choice, suggestedTitle: title,
            suggestedDetail: (petPrompt ?? "") + detail,
            strengthSession: proposedStrength
        )
    }

    private static func localizedActivity(_ activity: Activity) -> String {
        switch activity {
        case .running: return ATHLTHLocalization.choose(english: "run", norwegian: "løp")
        case .walking: return ATHLTHLocalization.choose(english: "walk", norwegian: "gåtur")
        case .strength: return ATHLTHLocalization.choose(english: "strength", norwegian: "styrkeøkt")
        case .cycling: return ATHLTHLocalization.choose(english: "ride", norwegian: "sykkeltur")
        case .other: return ATHLTHLocalization.choose(english: "workout", norwegian: "økt")
        }
    }

    private static func localizedFocus(_ focus: String) -> String {
        let no: [String: String] = [
            "chest": "bryst", "back": "rygg", "legs": "bein",
            "shoulders": "skuldre", "core": "kjernemuskulatur"
        ]
        return ATHLTHLocalization.isNorwegian ? (no[focus] ?? focus) : focus
    }
}
