import Foundation

struct ATHLTHSharedExerciseAttachment: Codable, Hashable {
    let name: String
    let sourceID: UUID?
    let sourceIdentifier: String?
    let snapshot: ExerciseSnapshot?
    var originalCreatorID: UUID? = nil
    var originalCreatorUsername: String? = nil
    var originalExerciseID: UUID? = nil

    var previewBlock: WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: name,
            exerciseSlug: sourceIdentifier, distanceMeters: nil,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil, notes: nil, phase: .main
        )
        block.exerciseID = sourceID
        block.exerciseSnapshot = snapshot
        return block
    }
}

/// Only account-owned exercises from Mine øvelser can be sent.
/// The public catalog is already installed for every ATHLTH athlete.
enum ATHLTHPersonalExerciseSharing {
    static func isEligible(_ entry: ExerciseLibraryEntry, ownerID: UUID) -> Bool {
        entry.source == .custom &&
        entry.exercise.origin == .custom &&
        entry.exercise.ownerID == ownerID &&
        entry.exercise.sharedSourceExerciseID == nil &&
        entry.exercise.originalCreatorID.map { $0 == ownerID } != false
    }
}

/// Only athlete-authored and persisted items can be shared.
/// Imported copies and catalogue entries stay available for training.
enum ATHLTHPersonalSharePolicy {
    static func plan(_ item: TrainingPlan, ownerID: UUID) -> Bool {
        item.ownerID == ownerID &&
        item.sharedSourcePlanID == nil &&
        item.sharedSourceOwnerID == nil &&
        !item.tags.contains(where: { $0.hasPrefix("catalog:") })
    }
    static func workout(_ item: PlannedSession) -> Bool {
        item.sharedSourceSessionID == nil && item.sharedSourceOwnerID == nil
    }
    static func runningWorkout(_ item: RunningWorkoutTemplate) -> Bool {
        !item.isBuiltIn &&
        item.sharedSourceWorkoutID == nil && item.sharedSourceOwnerID == nil
    }
    static func route(_ item: TrainingRoute, ownerID: UUID) -> Bool {
        let source = item.routeSource?.lowercased() ?? ""
        return item.ownerID == ownerID &&
            item.sharedSourceRouteID == nil && item.sharedSourceOwnerID == nil &&
            !["shared", "community", "catalog", "public", "discovery"].contains(source)
    }
    static func savedPlans(_ items: [TrainingPlan], ownerID: UUID) -> [TrainingPlan] {
        var seen = Set<UUID>()
        return items.filter {
            plan($0, ownerID: ownerID) && seen.insert($0.id).inserted
        }
    }
    static func savedWorkouts(_ items: [PlannedSession]) -> [PlannedSession] {
        var seen = Set<UUID>()
        return items.filter {
            workout($0) && seen.insert($0.id).inserted
        }
    }
    static func savedRoutes(_ items: [TrainingRoute], ownerID: UUID) -> [TrainingRoute] {
        var seen = Set<UUID>()
        return items.filter {
            route($0, ownerID: ownerID) && seen.insert($0.id).inserted
        }
    }
}

enum ATHLTHShareDraftFactory {
    static func safeWorkout(
        _ original: PlannedSession, library: [ExerciseLibraryEntry]
    ) -> PlannedSession {
        var copy = ATHLTHExerciseReferenceResolver.portableSession(
            original, from: library
        )
        copy.scheduledStart = nil
        copy.meetingPoint = nil
        copy.routeID = nil
        copy.invitedPartnerID = nil
        copy.trainTogetherMode = nil
        copy.reminderMinutesBefore = nil
        copy.allowInviteeExercises = nil
        copy.gearIDs = nil
        copy.spotifyPlaylist = nil
        copy.spotifyAutoplayOnStart = nil
        copy.audioCoachConfiguration = nil
        copy.recoveryOriginalExercises = nil
        copy.recoveryAdjustedExercises = nil
        copy.recoveryAdjustedAt = nil
        return copy
    }

    static func workout(_ original: PlannedSession,
                        library: [ExerciseLibraryEntry],
                        ownerID: UUID,
                        savedWorkouts: [PlannedSession] = []) throws -> MessageShareDraft {
        guard ATHLTHPersonalSharePolicy.workout(original),
              savedWorkouts.contains(original) else {
            throw ATHLTHDirectShareError.onlySavedPersonalContent
        }
        let copy = safeWorkout(original, library: library)
        return try MessageShareDraft(
            kind: .workout, title: copy.title,
            subtitle: copy.durationMinutes.map { "\($0) min" },
            snapshot: copy,
            sourceObjectID: original.sharedSourceSessionID ?? original.id,
            sourceOwnerID: original.sharedSourceOwnerID ?? ownerID
        )
    }

    static func plan(_ original: TrainingPlan,
                     library: [ExerciseLibraryEntry],
                     ownerID: UUID,
                     savedPlans: [TrainingPlan] = []) throws -> MessageShareDraft {
        guard ATHLTHPersonalSharePolicy.plan(original, ownerID: ownerID),
              savedPlans.contains(original) else {
            throw ATHLTHDirectShareError.onlySavedPersonalContent
        }
        var copy = ATHLTHExerciseReferenceResolver.portablePlan(
            original, from: library
        )
        copy.startDate = nil
        copy.endDate = nil
        copy.builderProfile = nil
        copy.spotifyPlaylist = nil
        copy.spotifyAutoplayOnWorkoutStart = false
        copy.visibility = .privateOnly
        copy.weeks = copy.weeks.map { week in
            var updated = week
            updated.days = week.days.map { day in
                var result = day
                result.sessions = day.sessions.map {
                    safeWorkout($0, library: library)
                }
                return result
            }
            return updated
        }
        return try MessageShareDraft(
            kind: .trainingPlan, title: copy.title,
            subtitle: "\(copy.weeks.count) " +
                ATHLTHLocalization.choose(english: "weeks", norwegian: "uker"),
            snapshot: copy,
            sourceObjectID: original.sharedSourcePlanID ?? original.id,
            sourceOwnerID: original.sharedSourceOwnerID ?? ownerID,
            shareVersion: original.sharedSourceVersion ?? original.version
        )
    }

    static func exercise(_ entry: ExerciseLibraryEntry,
                         ownerID: UUID,
                         creatorUsername: String? = nil,
                         savedExercises: [ExerciseLibraryEntry] = []) throws -> MessageShareDraft {
        guard ATHLTHPersonalExerciseSharing.isEligible(entry, ownerID: ownerID),
              savedExercises.contains(where: {
                  $0.id == entry.id &&
                  $0.exercise == entry.exercise &&
                  $0.source == entry.source
              }) else {
            throw ATHLTHDirectShareError.onlyPersonalExercises
        }
        guard let consented = ATHLTHExerciseReferenceResolver.shareableSnapshot(
            entry.exercise
        ) else {
            throw ATHLTHDirectShareError.privateExercise
        }
        let snapshot = ATHLTHExerciseReferenceResolver.safeImportedSnapshot(
            consented, fallbackTitle: entry.canonicalName
        )
        let originalID = entry.exercise.originalExerciseID ??
            entry.exercise.sharedSourceExerciseID ?? entry.id
        let originalCreatorID = entry.exercise.originalCreatorID ??
            (entry.exercise.sharedSourceExerciseID == nil ? ownerID : nil)
        let originalCreatorUsername = entry.exercise.originalCreatorUsername ??
            (originalCreatorID == ownerID ? creatorUsername : nil)
        var attachment = ATHLTHSharedExerciseAttachment(
            name: String(entry.canonicalName.prefix(140)),
            sourceID: originalID,
            sourceIdentifier: nil,
            snapshot: snapshot
        )
        attachment.originalCreatorID = originalCreatorID
        attachment.originalCreatorUsername = originalCreatorUsername
        attachment.originalExerciseID = originalID
        return try MessageShareDraft(
            kind: .exercise, title: attachment.name,
            subtitle: ATHLTHLocalization.choose(
                english: "Exercise", norwegian: "Øvelse"
            ),
            snapshot: attachment,
            sourceObjectID: originalID,
            sourceOwnerID: originalCreatorID
        )
    }
}

enum ATHLTHDirectShareError: LocalizedError {
    case privateExercise
    case onlyPersonalExercises
    case onlySavedPersonalContent

    var errorDescription: String? {
        switch self {
        case .privateExercise:
            return ATHLTHLocalization.choose(
                english: "Enable sharing for this private exercise in My Exercises before sending it.",
                norwegian: "Tillat deling av denne private øvelsen i Mine øvelser før du sender den."
            )
        case .onlyPersonalExercises:
            return ATHLTHLocalization.choose(
                english: "Only your saved, self-created exercises can be shared.",
                norwegian: "Du kan bare sende øvelser du har laget selv og lagret i Mine øvelser."
            )
        case .onlySavedPersonalContent:
            return ATHLTHLocalization.choose(
                english: "Only items you created and saved can be shared.",
                norwegian: "Du kan bare dele innhold du har laget selv og lagret."
            )
        }
    }
}

extension MessageShareDraft: Identifiable {
    var id: String {
        kind.rawValue + ":" + (sourceObjectID?.uuidString ?? title)
    }
}
