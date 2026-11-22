import Foundation

/// Exact/curated alias matching only. Fuzzy string similarity can silently
/// turn a cable movement into a different free-weight movement, so it must
/// never make that substitution in a workout.
enum ATHLTHExerciseReferenceResolver {
    static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "nb_NO"))
            .lowercased()
            // Foundation diacritic folding does not reliably transliterate
            // Norwegian ø/æ/å. Do this before stripping non-ASCII characters.
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "å", with: "a")
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
        "hollow body hold": "hollow-body-hold",
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

    /// Exact English/Norwegian names from the 68 distinct bundled movement
    /// records, not fuzzy translations. This list intentionally excludes
    /// the internal test and generic free-training placeholders. All values
    /// point back to the existing native exercise, never a new duplicate.
    private static let verifiedBundledNames: [String: String] = [
        "90 degree tabletop sit up": "tabletop-sit-up",
        "ab wheel rollout": "ab-wheel-rollout",
        "armheving": "push-up",
        "back extension": "back-extension",
        "barbell back squat": "back-squat",
        "barbell bent over row": "barbell-row",
        "barbell curl": "barbell-curl",
        "barbell hip thrust": "hip-thrust",
        "barbell overhead press": "overhead-press",
        "beinpress": "leg-press",
        "beinstrekk": "leg-extension",
        "bench press": "bench-press",
        "benkpress": "bench-press",
        "benkpress med manualer": "dumbbell-bench-press",
        "bicepscurl i kabel": "cable-curl",
        "bicepscurl med manualer": "dumbbell-curl",
        "bicepscurl med stang": "barbell-curl",
        "box step up": "step-up",
        "brystpress i apparat": "chest-press-machine",
        "bryststottet roing": "chest-supported-row",
        "bulgarian split squat": "bulgarian-split-squat",
        "bulgarsk utfall": "bulgarian-split-squat",
        "burpee": "burpee",
        "cable crunch": "cable-crunch",
        "cable curl": "cable-curl",
        "cable fly": "cable-fly",
        "chest press machine": "chest-press-machine",
        "chest supported row": "chest-supported-row",
        "chin up": "chin-up",
        "chin ups med underha ndsgrep": "chin-up",
        "conventional deadlift": "deadlift",
        "dead bug": "dead-bug",
        "dumbbell bench press": "dumbbell-bench-press",
        "dumbbell biceps curl": "dumbbell-curl",
        "dumbbell fly": "dumbbell-fly",
        "dumbbell lateral raise": "lateral-raise",
        "dumbbell row": "dumbbell-row",
        "dumbbell shoulder press": "dumbbell-shoulder-press",
        "enarms roing med manual": "one-arm-dumbbell-row",
        "ettbeins rumensk markloft": "single-leg-romanian-deadlift",
        "face pull": "face-pull",
        "flat dumbbell chest fly": "flat-dumbbell-chest-fly",
        "flyes med manualer": "dumbbell-fly",
        "flyes pa flat benk med manualer": "flat-dumbbell-chest-fly",
        "foroverboyd stangroing": "barbell-row",
        "front squat": "front-squat",
        "frontboy": "front-squat",
        "ga ende utfall": "walking-lunge",
        "glute bridge": "glute-bridge",
        "goblet squat": "goblet-squat",
        "hammer curl": "hammer-curl",
        "hammercurl": "hammer-curl",
        "hanging knee raise": "hanging-knee-raise",
        "hanging leg raise": "hanging-leg-raise",
        "hengende beinhev": "hanging-leg-raise",
        "hengende kneloft": "hanging-knee-raise",
        "hip thrust med stang": "hip-thrust",
        "hollow body hold": "hollow-body-hold",
        "hollow hold": "hollow-body-hold",
        "incline bench press": "incline-bench-press",
        "incline dumbbell bench press": "incline-dumbbell-bench-press",
        "kabel flyes": "cable-fly",
        "kettlebell sving": "kettlebell-swing",
        "kettlebell swing": "kettlebell-swing",
        "kneboy med stang": "back-squat",
        "la rcurl": "leg-curl",
        "lat pulldown": "lat-pulldown",
        "lateral raise": "lateral-raise-unspecified",
        "leg curl": "leg-curl",
        "leg extension": "leg-extension",
        "leg press": "leg-press",
        "liggende la rcurl": "lying-leg-curl",
        "liggende tricepspress": "skullcrusher",
        "lying leg curl": "lying-leg-curl",
        "magecrunch i kabel": "cable-crunch",
        "magehjul": "ab-wheel-rollout",
        "markloft": "deadlift",
        "mountain climber": "mountain-climber",
        "nedtrekk": "lat-pulldown",
        "omvendt crunch": "reverse-crunch",
        "omvendt flyes": "rear-delt-fly",
        "one arm dumbbell row": "one-arm-dumbbell-row",
        "overhead triceps extension": "overhead-triceps-extension",
        "pallof press": "pallof-press",
        "plank": "plank",
        "planke": "plank",
        "power clean": "power-clean",
        "pull up": "pull-up",
        "pull ups": "pull-up",
        "push up": "push-up",
        "rear delt fly": "rear-delt-fly",
        "reverse crunch": "reverse-crunch",
        "roing med manual": "dumbbell-row",
        "romanian deadlift": "romanian-deadlift",
        "rumensk markloft": "romanian-deadlift",
        "russian twist": "russian-twist",
        "russisk rotasjon": "russian-twist",
        "russisk rotasjon med vekt": "weighted-russian-twist",
        "rygghev": "back-extension",
        "seated cable row": "seated-cable-row",
        "seated calf raise": "seated-calf-raise",
        "seated dumbbell press": "seated-dumbbell-press",
        "seated leg curl": "seated-leg-curl",
        "seteloft": "glute-bridge",
        "side plank": "side-plank",
        "sidehev": "lateral-raise-unspecified",
        "sidehev med manualer": "lateral-raise",
        "sideplanke": "side-plank",
        "single leg romanian deadlift": "single-leg-romanian-deadlift",
        "sittende kabelroing": "seated-cable-row",
        "sittende la rcurl": "seated-leg-curl",
        "sittende skulderpress": "seated-dumbbell-press",
        "sittende ta hev": "seated-calf-raise",
        "situps med beina i 90 grader": "tabletop-sit-up",
        "six inch hold": "six-inch-hold",
        "six inch hold beinhold": "six-inch-hold",
        "skra benk med manualer": "incline-dumbbell-bench-press",
        "skra benk med stang": "incline-bench-press",
        "skulderpress med manualer": "dumbbell-shoulder-press",
        "skulderpress med stang": "overhead-press",
        "skullcrusher": "skullcrusher",
        "sta ende ta hev": "standing-calf-raise",
        "standing calf raise": "standing-calf-raise",
        "step up pa kasse": "step-up",
        "styrkevending": "power-clean",
        "triceps nedpress": "triceps-pushdown",
        "triceps over hodet": "overhead-triceps-extension",
        "triceps pushdown": "triceps-pushdown",
        "walking lunge": "walking-lunge",
        "weighted russian twist": "weighted-russian-twist"
    ]

    static func nativeSourceIdentifier(for name: String) -> String? {
        let normalized = key(name)
        // Reviewed GymCoach aliases take precedence where English source
        // vocabulary is less specific than a bundled movement title.
        guard let slug = normalizedNativeAliases[normalized] ??
            verifiedBundledNames[normalized]
        else { return nil }
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

    /// Legacy published HYROX recipes use short identifiers, while the
    /// stock exercise library uses athlth: names. These exact aliases are
    /// limited to published, app-owned stations — never private exercises.
    private static let publishedHYROXSourceAliases: [String: String] = [
        "burpee-broad-jump": "athlth:burpee-broad-jump",
        "farmers-carry": "athlth:farmers-carry",
        "hand-release-push-up": "athlth:hand-release-push-up",
        "rowing-erg": "athlth:rowing",
        "sandbag-walking-lunge": "athlth:sandbag-walking-lunge",
        "ski-erg": "athlth:skierg",
        "sled-pull": "athlth:sled-pull",
        "sled-push": "athlth:sled-push",
        "stationary-lunge": "athlth:stationary-lunge",
        "wall-ball": "athlth:wall-ball"
    ]

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
            if byIdentifier.count == 1 {
                return visibleEquivalent(of: byIdentifier[0], in: library)
            }
            // Older imported recipes used the public native source slug
            // without the "athlth-native-" prefix. Match only a reviewed,
            // real bundled exercise and never a similarly named private one.
            if let canonicalID = nativeSourceIdentifier(for: slug) {
                let native = library.filter {
                    $0.source == .athlthCatalog &&
                    $0.sourceIdentifier == canonicalID
                }
                if native.count == 1 {
                    return visibleEquivalent(of: native[0], in: library)
                }
            }
            if let canonicalID = publishedHYROXSourceAliases[slug] {
                let matches = library.filter {
                    $0.source == .athlthCatalog &&
                    $0.sourceIdentifier == canonicalID
                }
                if matches.count == 1 { return matches[0] }
            }
            // All other explicit source identifiers remain authoritative.
            // Never replace an absent private/custom exercise by title.
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
            return matches.count == 1
                ? visibleEquivalent(of: matches[0], in: library) : nil
        }

        // Single reviewed name-matching path for both modern workout blocks
        // and legacy PlannedExercise rows. Never guess private exercises.
        return resolvePublicName(block.title, in: library)
    }

    /// Only use this when the source has no explicit foreign/custom identity.
    /// The result is one already existing public exercise; no duplicate import.
    static func resolvePublicName(
        _ name: String,
        in library: [ExerciseLibraryEntry]
    ) -> ExerciseLibraryEntry? {
        let clean = key(name)
        guard !clean.isEmpty else { return nil }
        if let reviewedID = exerciseSourceIdentifier(for: name) {
            let source: ExerciseLibrarySource = reviewedID.hasPrefix("athlth-native-")
                ? .athlthCatalog : .repDB
            let matches = library.filter {
                $0.source == source && $0.sourceIdentifier == reviewedID
            }
            if matches.count == 1 {
                return visibleEquivalent(of: matches[0], in: library)
            }
        }

        // The canonical English name is a stronger proof than translated
        // display strings, which may be shared by different equipment types.
        let matches = library.filter {
            ($0.source == .repDB || $0.source == .athlthCatalog) &&
                key($0.canonicalName) == clean
        }
        if matches.count == 1 {
            return visibleEquivalent(of: matches[0], in: library)
        }
        // Two public entries with the same title are ambiguous, so stop.
        return nil
    }

    /// A native fallback is sometimes hidden from the default library grid
    /// when RepDB is installed. An *identical* public exercise from RepDB
    /// should be the visible shared source. Match complete English name AND
    /// equipment, never mere Norwegian translation or a similar movement.
    /// Explicit exercise UUIDs are handled before this function and cannot
    /// be silently reassigned across user accounts.
    static func visibleEquivalent(
        of source: ExerciseLibraryEntry,
        in library: [ExerciseLibraryEntry]
    ) -> ExerciseLibraryEntry {
        guard source.source == .athlthCatalog,
              source.sourceIdentifier?.hasPrefix("athlth-native-") == true
        else { return source }
        // Resolve the retired native alias to the exact reviewed RepDB ID.
        // Never substitute a merely similar exercise or a private record.
        if source.sourceIdentifier == "athlth-native-incline-dumbbell-bench-press" {
            // RepDB snapshots may use "Incline Dumbbell Press" instead of
            // "Incline Dumbbell Bench Press". Both are reviewed names for
            // the same dumbbell incline press, not the barbell variant.
            let reviewedNames: Set<String> = [
                "incline dumbbell press",
                "incline dumbbell bench press"
            ]
            let reviewed = library.filter { entry in
                guard entry.source == .repDB else { return false }
                let name = key(entry.canonicalName)
                let slug = entry.sourceIdentifier.map(key)
                return reviewedNames.contains(name) ||
                    slug == "incline dumbbell bench press"
            }
            if reviewed.count == 1 { return reviewed[0] }
        }
        if source.sourceIdentifier == "athlth-native-bench-press" {
            // The licensed RepDB bench press can describe its equipment
            // differently from the historical native record. Match the
            // reviewed movement identity, never an incline/dumbbell variant.
            let reviewed = library.filter { entry in
                entry.source == .repDB &&
                    (entry.sourceIdentifier == "bench-press" ||
                     key(entry.canonicalName) == "bench press")
            }
            if reviewed.count == 1 { return reviewed[0] }
        }
        let exactName = key(source.canonicalName)
        let equipment = Set(source.exercise.equipment.map(key))
        let identical = library.filter { entry in
            entry.source == .repDB &&
                key(entry.canonicalName) == exactName &&
                Set(entry.exercise.equipment.map(key)) == equipment
        }
        return identical.count == 1 ? identical[0] : source
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
            assessmentMethod: exercise.assessmentMethod,
            activityCategory: exercise.activityCategory,
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
            assessmentMethod: source.assessmentMethod,
            activityCategory: source.activityCategory,
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
            // Public catalog UUIDs are installation-independent only when
            // the receiving catalog uses the same revision. Export the stable
            // source slug instead, so another account can resolve it safely.
            // Custom exercises retain their explicit creator identity.
            if found.source == .custom {
                if let approved = shareableSnapshot(found.exercise) {
                    copy.exerciseID = found.id
                    copy.exerciseSlug = nil
                    copy.exerciseSnapshot = safeImportedSnapshot(
                        approved, fallbackTitle: block.title
                    )
                } else {
                    // A private/friends-only custom exercise must not expose
                    // its owner-specific identifier in a public plan export.
                    copy.exerciseID = nil
                    copy.exerciseSlug = nil
                }
            } else if let sourceID = found.sourceIdentifier {
                copy.exerciseID = nil
                copy.exerciseSlug = sourceID
            } else {
                // Unknown public catalog identities cannot be safely mapped
                // to another account without a stable source identifier.
                copy.exerciseID = nil
                copy.exerciseSlug = nil
            }
        } else {
            // Never forward a stale or foreign account's private identifier.
            // A recipient may still see the workout step's display title.
            copy.exerciseID = nil
            copy.exerciseSlug = nil
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
                    safe.exerciseID = nil
                    safe.embeddedExercise = ExerciseSnapshot(
                        name: linked.canonicalName,
                        instructions: [], primaryMuscles: [],
                        secondaryMuscles: [], equipment: [], imageURL: nil
                    )
                }
            } else {
                // Legacy planned exercises may contain private UUIDs from
                // another account. Do not export these unverified identities.
                safe.exerciseID = nil
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
