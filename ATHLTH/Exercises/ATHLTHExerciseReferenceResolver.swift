import Foundation

/// Exact/curated alias matching only. Fuzzy string similarity can silently
/// turn a cable movement into a different free-weight movement, so it must
/// never make that substitution in a workout.
enum ATHLTHExerciseReferenceResolver {
    static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "nb_NO"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reviewed equivalent names, not generic similarity heuristics.
    /// A missing dictionary key is deliberately unresolved.
    private static let nativeAliases: [String: String] = [
        "lat pulldown": "lat-pulldown",
        "nedtrekk": "lat-pulldown",
        "seated cable row": "seated-cable-row",
        "sittende kabelroing": "seated-cable-row",
        "bench press": "bench-press",
        "benkpress": "bench-press",
        "dumbbell bench press": "dumbbell-bench-press",
        "bent over row": "barbell-row",
        "barbell bent over row": "barbell-row",
        "one arm dumbbell row": "one-arm-dumbbell-row",
        "pull up": "pull-up",
        "pull ups": "pull-up",
        "push up": "push-up",
        "push ups": "push-up",
        "barbell back squat": "back-squat",
        "back squat": "back-squat",
        "leg press": "leg-press",
        "leg extension": "leg-extension",
        "bulgarian split squat": "bulgarian-split-squat",
        "goblet squat": "goblet-squat",
        "romanian deadlift": "romanian-deadlift",
        "deadlift": "deadlift",
        "conventional deadlift": "deadlift",
        "lying leg curl": "lying-leg-curl",
        "standing calf raise": "standing-calf-raise",
        "seated calf raise": "seated-calf-raise",
        "dumbbell shoulder press": "dumbbell-shoulder-press",
        "face pull": "face-pull",
        "barbell curl": "barbell-curl",
        "dumbbell curl": "dumbbell-curl",
        "hammer curl": "hammer-curl",
        "triceps pushdown": "triceps-pushdown",
        "overhead triceps extension": "overhead-triceps-extension",
        "cable fly": "cable-fly",
        "glute bridge": "glute-bridge",
        "plank": "plank",
        "side plank": "side-plank",
        "dead bug": "dead-bug",
        "pallof press": "pallof-press",
        "lateral raise": "lateral-raise",
        "kettlebell swing": "kettlebell-swing",
        "step up": "step-up",
        "burpee": "burpee",
        "mountain climber": "mountain-climber"
    ]

    static func nativeSourceIdentifier(for name: String) -> String? {
        let normalized = key(name)
        // Treat spaces, hyphens and underscores as equivalent for reviewed English names.
        // Do not guess across different equipment or movement variations.
        guard let slug = nativeAliases[normalized] ?? nativeAliases.first(where: {
            key($0.key) == normalized
        })?.value else { return nil }
        return "athlth-native-" + slug
    }

    static func resolve(
        _ block: WorkoutTemplateBlock,
        in library: [ExerciseLibraryEntry]
    ) -> ExerciseLibraryEntry? {
        guard block.kind == .exercise else { return nil }
        if let id = block.exerciseID {
            if let exact = library.first(where: { $0.id == id }) {
                return exact
            }
            if let imported = library.first(where: {
                $0.source == .custom &&
                $0.exercise.sharedSourceExerciseID == id
            }) {
                return imported
            }
        }
        if let slug = block.exerciseSlug, !slug.isEmpty {
            let byIdentifier = library.filter { $0.sourceIdentifier == slug ||
                ($0.sourceIdentifier != nil && key($0.sourceIdentifier!) == key(slug)) }
            if byIdentifier.count == 1 { return byIdentifier[0] }
        }

        // A friend's embedded instructions are authoritative for that
        // particular custom exercise. A local exercise with the same name
        // must not hide the sender's original technique and equipment.
        if block.exerciseSnapshot != nil { return nil }

        // User-created exercises are only matched by explicit IDs. Equal
        // titles alone are not proof that two personal exercises are the same.
        let clean = key(block.title)
        guard !clean.isEmpty else { return nil }
        let repdbExact = library.filter {
            $0.source == .repDB && key($0.canonicalName) == clean
        }
        if repdbExact.count == 1 { return repdbExact[0] }

        let nativeSlug = nativeSourceIdentifier(for: block.title)
        if let nativeSlug {
            let native = library.filter { $0.sourceIdentifier == nativeSlug }
            if native.count == 1 { return native[0] }
        }

        let matchingNative = library.filter {
            $0.source == .athlthCatalog && key($0.canonicalName) == clean
        }
        return matchingNative.count == 1 ? matchingNative[0] : nil
    }

    /// Portable, deliberately bounded content. Do not share local files,
    /// expiring signed URLs, or private query tokens inside chat attachments.
    static func shareableSnapshot(_ exercise: Exercise) -> ExerciseSnapshot? {
        guard exercise.origin == .custom &&
              exercise.isVisibleOutsideOwnerLibrary else { return nil }
        let name = String(exercise.name.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(140))
        guard !name.isEmpty else { return nil }

        func words(_ source: [String], maxItems: Int) -> [String] {
            Array(source.prefix(maxItems)).map {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(700))
            }.filter { !$0.isEmpty }
        }
        func publicURL(_ url: URL?) -> URL? {
            guard let url, url.scheme?.lowercased() == "https",
                  url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { return nil }
            return url
        }
        return ExerciseSnapshot(
            name: name,
            instructions: words(exercise.instructions, maxItems: 12),
            primaryMuscles: words(exercise.primaryMuscles, maxItems: 12),
            secondaryMuscles: words(exercise.secondaryMuscles, maxItems: 12),
            equipment: words(exercise.equipment, maxItems: 12),
            imageURL: publicURL(exercise.imageURL),
            videoURL: publicURL(exercise.videoURL)
        )
    }

    static func safeImportedSnapshot(
        _ source: ExerciseSnapshot, fallbackTitle: String
    ) -> ExerciseSnapshot? {
        let name = String((source.name.isEmpty ? fallbackTitle : source.name)
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        guard !name.isEmpty else { return nil }
        func clean(_ source: [String]) -> [String] {
            Array(source.prefix(12)).map {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(700))
            }.filter { !$0.isEmpty }
        }
        // A receiver never trusts media URLs embedded in a third-party
        // attachment as a reason to fetch or persist a private asset.
        return ExerciseSnapshot(
            name: name,
            instructions: clean(source.instructions),
            primaryMuscles: clean(source.primaryMuscles),
            secondaryMuscles: clean(source.secondaryMuscles ?? []),
            equipment: clean(source.equipment),
            imageURL: nil, videoURL: nil
        )
    }

    /// Preserve author-approved custom metadata and stable native references
    /// without embedding any licensed RepDB dataset in a chat message.
    static func portableBlock(
        _ block: WorkoutTemplateBlock,
        from library: [ExerciseLibraryEntry]
    ) -> WorkoutTemplateBlock {
        guard block.kind == .exercise else { return block }
        var copy = block
        // A received custom exercise is not automatically licensed for
        // forwarding. Send instructions only for a locally owned exercise
        // whose creator has explicitly enabled sharing.
        copy.exerciseSnapshot = nil
        if let found = resolve(block, in: library) {
            copy.exerciseID = found.id
            if let sourceID = found.sourceIdentifier {
                copy.exerciseSlug = sourceID
            }
            if found.source == .custom,
               let approved = shareableSnapshot(found.exercise) {
                copy.exerciseSnapshot = safeImportedSnapshot(
                    approved, fallbackTitle: block.title
                )
            }
        }
        return copy
    }

    static func portableSession(
        _ workout: PlannedSession,
        from library: [ExerciseLibraryEntry]
    ) -> PlannedSession {
        var result = workout
        result.exercises = workout.exercises.map { planned in
            var safe = planned
            let linked = planned.exerciseID.flatMap { identifier in
                library.first(where: { $0.id == identifier })
            }
            if let linked, linked.source == .custom {
                // The owner's "Allow in shared plans" toggle applies to
                // legacy planned exercises just as it does to new blocks.
                if let shared = shareableSnapshot(linked.exercise) {
                    safe.embeddedExercise = shared
                } else {
                    safe.embeddedExercise = ExerciseSnapshot(
                        name: linked.canonicalName,
                        instructions: [], primaryMuscles: [],
                        secondaryMuscles: [], equipment: [], imageURL: nil
                    )
                }
            } else {
                // An exercise received from someone else may be previewed
                // locally, but the original author has not consented to
                // its further distribution by this user.
                safe.embeddedExercise = ExerciseSnapshot(
                    name: planned.embeddedExercise.name,
                    instructions: [], primaryMuscles: [],
                    secondaryMuscles: [], equipment: [], imageURL: nil
                )
            }
            return safe
        }
        if let blocks = result.workoutBlocks {
            result.workoutBlocks = blocks.map {
                portableBlock($0, from: library)
            }
        }
        return result
    }

    static func portablePlan(
        _ plan: TrainingPlan,
        from library: [ExerciseLibraryEntry]
    ) -> TrainingPlan {
        var result = plan
        result.weeks = plan.weeks.map { week in
            var copy = week
            copy.days = week.days.map { day in
                var dayCopy = day
                dayCopy.sessions = day.sessions.map {
                    portableSession($0, from: library)
                }
                return dayCopy
            }
            return copy
        }
        return result
    }
}
