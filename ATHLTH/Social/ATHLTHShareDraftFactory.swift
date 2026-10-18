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

enum ATHLTHShareDraftFactory {
    static func workout(_ original: PlannedSession,
                        library: [ExerciseLibraryEntry],
                        ownerID: UUID) throws -> MessageShareDraft {
        var copy = ATHLTHExerciseReferenceResolver.portableSession(
            original, from: library
        )
        copy.scheduledStart = nil
        copy.meetingPoint = nil
        copy.routeID = nil
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
        copy.weeks = copy.weeks.map { week in
            var updated = week
            updated.days = week.days.map { day in
                var result = day
                result.sessions = day.sessions.map { workout in
                    var clean = workout
                    clean.scheduledStart = nil
                    clean.meetingPoint = nil
                    clean.routeID = nil
                    return clean
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
        let custom = entry.source == .custom
        var snapshot: ExerciseSnapshot?
        if custom {
            guard let consented = ATHLTHExerciseReferenceResolver.shareableSnapshot(
                entry.exercise
            ) else {
                throw ATHLTHDirectShareError.privateExercise
            }
            snapshot = ATHLTHExerciseReferenceResolver.safeImportedSnapshot(
                consented, fallbackTitle: entry.canonicalName
            )
        }
        let attachment = ATHLTHSharedExerciseAttachment(
            name: String(entry.canonicalName.prefix(140)),
            sourceID: custom ? entry.id : nil,
            sourceIdentifier: entry.sourceIdentifier,
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
    var errorDescription: String? {
        ATHLTHLocalization.choose(
            english: "Enable sharing for this private exercise in My Exercises before sending it.",
            norwegian: "Tillat deling av denne private øvelsen i Mine øvelser før du sender den."
        )
    }
}
