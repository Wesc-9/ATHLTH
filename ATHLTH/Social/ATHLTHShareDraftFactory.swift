import Foundation

struct ATHLTHSharedExerciseAttachment: Codable, Hashable {
    let name: String
    let sourceID: UUID?
    let sourceIdentifier: String?
    let snapshot: ExerciseSnapshot?

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
        entry.exercise.ownerID == ownerID
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
                        ownerID: UUID) throws -> MessageShareDraft {
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
                     ownerID: UUID) throws -> MessageShareDraft {
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
                         ownerID: UUID) throws -> MessageShareDraft {
        guard ATHLTHPersonalExerciseSharing.isEligible(entry, ownerID: ownerID) else {
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
        let attachment = ATHLTHSharedExerciseAttachment(
            name: String(entry.canonicalName.prefix(140)),
            sourceID: entry.id,
            sourceIdentifier: nil,
            snapshot: snapshot
        )
        return try MessageShareDraft(
            kind: .exercise, title: attachment.name,
            subtitle: ATHLTHLocalization.choose(
                english: "Exercise", norwegian: "Øvelse"
            ),
            snapshot: attachment,
            sourceObjectID: entry.id,
            sourceOwnerID: ownerID
        )
    }
}

enum ATHLTHDirectShareError: LocalizedError {
    case privateExercise
    case onlyPersonalExercises

    var errorDescription: String? {
        switch self {
        case .privateExercise:
            return ATHLTHLocalization.choose(
                english: "Enable sharing for this private exercise in My Exercises before sending it.",
                norwegian: "Tillat deling av denne private øvelsen i Mine øvelser før du sender den."
            )
        case .onlyPersonalExercises:
            return ATHLTHLocalization.choose(
                english: "Only your own exercises from My Exercises can be shared.",
                norwegian: "Du kan bare sende egne øvelser fra Mine øvelser."
            )
        }
    }
}

extension MessageShareDraft: Identifiable {
    var id: String {
        kind.rawValue + ":" + (sourceObjectID?.uuidString ?? title)
    }
}
