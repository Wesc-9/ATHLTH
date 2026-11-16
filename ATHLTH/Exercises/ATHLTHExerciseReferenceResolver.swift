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
        "hip thrust": "hip-thrust",
        "barbell hip thrust": "hip-thrust",
        "plank": "plank",
        "side plank": "side-plank",
        "dead bug": "dead-bug",
        "pallof press": "pallof-press",
        "kettlebell swing": "kettlebell-swing",
        "step up": "step-up",
        "burpee": "burpee",
        "mountain climber": "mountain-climber",
        // Exact reviewed GymCoach program names. Similar-looking variations
        // must remain separate; for example Leg Curl is not always lying.
        "overhead press": "overhead-press",
        "barbell row": "barbell-row",
        "front squat": "front-squat",
        "incline bench press": "incline-bench-press",
        "incline dumbbell press": "incline-dumbbell-bench-press",
        "rear delt fly": "rear-delt-fly",
        "hanging leg raise": "hanging-leg-raise",
        "cable curl": "cable-curl",
        "chin up": "chin-up",
        "dumbbell row": "dumbbell-row",
        "leg curl": "leg-curl",
        "lateral raise": "lateral-raise-unspecified",
        "power clean": "power-clean",
        "skullcrusher": "skullcrusher"
    ]

    private static let normalizedNativeAliases: [String: String] = {
        Dictionary(uniqueKeysWithValues: nativeAliases.map { (key($0.key), $0.value) })
    }()

    static func nativeSourceIdentifier(for name: String) -> String? {
        let normalized = key(name)
        // Treat spaces, hyphens and underscores as equivalent for reviewed English names.
        // Do not guess across different equipment or movement variations.
        guard let slug = normalizedNativeAliases[normalized] else { return nil }
        return "athlth-native-" + slug
    }

    /// Reviewed RepDB IDs already present in the shipped/downloadable exercise
    /// library. Never map incline curls to hammer curls or an equipment-free
    /// reverse lunge to a kettlebell variant.
    private static let reviewedRepDBAliases: [String: String] = [
        "bird dog": "bird-dog",
        "fuglehund": "bird-dog",
        "bodyweight squat": "bodyweight-squat",
        "knebøy med kroppsvekt": "bodyweight-squat",
        "reverse lunge": "kettlebell-reverse-lunge",
        "bakoverutfall med kettlebell": "kettlebell-reverse-lunge",
        "bodyweight reverse lunge": "bodyweight-reverse-lunge",
        "bakoverutfall med kroppsvekt": "bodyweight-reverse-lunge",
        "incline dumbbell curl": "incline-db-curl",
        "skrå manualcurl": "incline-db-curl",
        "bicepscurl med manualer på skråbenk": "incline-db-curl"
    ]

    private static let normalizedRepDBAliases: [String: String] = {
        Dictionary(uniqueKeysWithValues: reviewedRepDBAliases.map {
            (key($0.key), $0.value)
        })
    }()

    /// Use this for curated source workouts. Native IDs and RepDB IDs share a
    /// single exact-identity resolution path without creating duplicate data.
    static func exerciseSourceIdentifier(for name: String) -> String? {
        nativeSourceIdentifier(for: name) ??
            normalizedRepDBAliases[key(name)]
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
            // An explicit identity from another athlete or account must not
            // be silently replaced with a similarly named stock exercise.
            return nil
        }
        if let slug = block.exerciseSlug, !slug.isEmpty {
            let normalizedSlug = key(slug)
            let byIdentifier = library.filter { entry in
                guard let identifier = entry.sourceIdentifier else { return false }
                return identifier == slug || key(identifier) == normalizedSlug
            }
            if byIdentifier.count == 1 { return byIdentifier[0] }
            // Explicit source identifiers are authoritative. Do not fall
            // back to a name match when the referenced item is unavailable.
            return nil
        }

        // Older GymCoach-based plans were saved before explicit slugs were
        // attached. Their snapshots contain a canonical English source name
        // and NO technique or media, while the visible title may be Norwegian.
        // Recover only verified bundled-catalog names, never arbitrary shared
        // user snapshots or an exercise with a known foreign/private UUID.
        if let snapshot = block.exerciseSnapshot {
            guard block.exerciseID == nil,
                  snapshot.instructions.isEmpty,
                  snapshot.imageURL == nil,
                  snapshot.videoURL == nil,
                  ATHLTHGymCoachStrengthLibrary.hasSourceExercise(
                      named: snapshot.name
                  ),
                  let identifier = nativeSourceIdentifier(for: snapshot.name)
            else { return nil }
            let matches = library.filter {
                $0.sourceIdentifier == identifier &&
                $0.source == .athlthCatalog
            }
            return matches.count == 1 ? matches[0] : nil
        }

        // User-created exercises are only matched by explicit IDs. Equal
        // titles alone are not proof that two personal exercises are the same.
        let clean = key(block.title)
        guard !clean.isEmpty else { return nil }
        if let reviewedID = exerciseSourceIdentifier(for: block.title) {
            let source: ExerciseLibrarySource = reviewedID.hasPrefix("athlth-native-")
                ? .athlthCatalog : .repDB
            let matches = library.filter {
                $0.source == source && $0.sourceIdentifier == reviewedID
            }
            if matches.count == 1 { return matches[0] }
        }

        let repdbExact = library.filter {
            $0.source == .repDB && key($0.canonicalName) == clean
        }
        if repdbExact.count == 1 { return repdbExact[0] }

        // Match an English canonical name even when the workout title uses
        // hyphens/underscores instead of spaces. Never infer a different exercise.
        let canonicalMatches = library.filter {
            ($0.source == .repDB || $0.source == .athlthCatalog) &&
            key($0.canonicalName) == clean
        }
        if canonicalMatches.count == 1 { return canonicalMatches[0] }

        let matchingNative = library.filter {
            $0.source == .athlthCatalog && key($0.canonicalName) == clean
        }
        return matchingNative.count == 1 ? matchingNative[0] : nil
    }

    /// Portable, deliberately bounded content. Do not share local files,
    /// expiring signed URLs, or private query tokens inside chat attachments.
    static func shareableSnapshot(
        _ exercise: Exercise,
        allowDirectFriendShare: Bool = false
    ) -> ExerciseSnapshot? {
        guard exercise.origin == .custom &&
              exercise.isVisibleOutsideOwnerLibrary &&
              (exercise.resolvedVisibility == .publicListing ||
                (allowDirectFriendShare &&
                 exercise.resolvedVisibility == .friends)) else {
            return nil
        }
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
