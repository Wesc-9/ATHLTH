import Foundation
import SwiftUI

/// Version 4 of the private workout-message attachment. The original workout
/// is immutable until its owner explicitly approves this proposal.
struct WorkoutChangeProposal: Codable, Hashable, Identifiable {
    let id: UUID
    let proposedBy: UUID
    let ownerID: UUID
    let original: PlannedSession
    let proposed: PlannedSession
    let submittedAt: Date

    var workoutID: UUID { original.id }
    var hasChanges: Bool { !WorkoutChangeComparison.rows(self).isEmpty }
}

/// Version 5 message attachment; includes the approved revision so the
/// recipient can accept the latest agreed workout, not an obsolete invite.
struct WorkoutChangeDecision: Codable, Hashable {
    let proposalID: UUID
    let workoutID: UUID
    let approved: Bool
    let approvedWorkout: PlannedSession?
}

enum WorkoutChangeComparison {
    struct Row: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let before: String
        let after: String
    }

    static func rows(_ proposal: WorkoutChangeProposal) -> [Row] {
        let before = fields(proposal.original)
        let after = fields(proposal.proposed)
        let names = Set(before.keys).union(after.keys).sorted()
        return names.compactMap { key in
            // A copied workout may have a different internal ID; identity is
            // provided by the original invitation rather than a user edit.
            guard key != "id", key != "sharedSourceOwnerID",
                  key != "sharedSourceSessionID",
                  key != "gearIDs", key != "spotifyPlaylist",
                  key != "spotifyAutoplayOnStart",
                  signature(before[key]) != signature(after[key])
            else { return nil }
            return Row(
                key: key,
                label: titles[key] ?? displayName(key),
                before: label(before[key], key: key),
                after: label(after[key], key: key)
            )
        }
    }

    private static let titles: [String: String] = [
        "title": "Øktnavn",
        "kind": "Økttype",
        "scheduledStart": "Tidspunkt",
        "durationMinutes": "Varighet",
        "targetDistanceKilometers": "Distanse",
        "targetPaceSecondsPerKilometer": "Tempo",
        "routeID": "Rute",
        "exercises": "Øvelser og sett",
        "notes": "Beskrivelse",
        "runningWorkout": "Løpeøkt",
        "runningWorkouts": "Løpeøkter",
        "workoutBlocks": "Øktstruktur",
        "audioCoachConfiguration": "Lydcoach",
        "meetingPoint": "Oppmøtested",
        "trainTogetherMode": "Hvordan trener dere?",
        "reminderMinutesBefore": "Påminnelse"
    ]

    private static func fields(_ workout: PlannedSession) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(workout),
              let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else { return [:] }
        return object
    }

    private static func signature(_ value: Any?) -> String {
        guard let value else { return "nil" }
        let bytes = try? JSONSerialization.data(
            withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]
        )
        return bytes.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func label(_ value: Any?, key: String) -> String {
        guard let value else { return "–" }
        if let text = value as? String {
            if key == "scheduledStart",
               let date = ISO8601DateFormatter().date(from: text) {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
            return String(text.prefix(110))
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let list = value as? [Any] {
            return list.isEmpty ? "–" : "\(list.count) elementer · endret"
        }
        if let object = value as? [String: Any] {
            if key == "meetingPoint" {
                return object["name"] as? String ?? "Oppmøtested"
            }
            return "Endret"
        }
        return "Endret"
    }

    private static func displayName(_ key: String) -> String {
        key.replacingOccurrences(
            of: "([a-z])([A-Z])", with: "$1 $2",
            options: .regularExpression
        ).capitalized
    }
}

/// Renders all changed values in red; approvals happen only through messages.
struct ThreadWorkoutChangeProposalCard: View {
    let proposal: WorkoutChangeProposal
    let decision: WorkoutChangeDecision?
    let currentUserID: UUID?
    let isWorking: Bool
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(
                ATHLTHLocalization.choose(
                    english: "WORKOUT · CHANGE REQUEST",
                    norwegian: "TRENINGSØKT · ENDRINGSFORSLAG"
                ),
                systemImage: "square.and.pencil"
            )
            .font(.system(size: 10, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(proposal.proposed.title)
                .font(.headline)
            Text(ATHLTHLocalization.choose(
                english: "Red details are proposed, not yet applied.",
                norwegian: "Røde detaljer er foreslått, ikke gjennomført."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            ForEach(WorkoutChangeComparison.rows(proposal)) { change in
                VStack(alignment: .leading, spacing: 5) {
                    Text(change.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text(change.before)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(change.after)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 12))
            }

            if let decision {
                Label(
                    decision.approved
                        ? ATHLTHLocalization.choose(
                            english: "Approved", norwegian: "Godkjent"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Declined", norwegian: "Avslått"
                        ),
                    systemImage: decision.approved
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            } else if currentUserID == proposal.ownerID {
                HStack(spacing: 9) {
                    Button(action: onDecline) {
                        Text(ATHLTHLocalization.choose(
                            english: "Decline", norwegian: "Avslå"
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(action: onApprove) {
                        HStack {
                            if isWorking { ProgressView().controlSize(.mini) }
                            Text(ATHLTHLocalization.choose(
                                english: "Approve", norwegian: "Godkjenn"
                            ))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
                .disabled(isWorking)
            } else {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Awaiting creator approval",
                        norwegian: "Venter på godkjenning"
                    ),
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .padding(16)
        .frame(maxWidth: 330, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.99),
                             ATHLTHTheme.surfaceStone.opacity(0.89),
                             ATHLTHTheme.cardWarm.opacity(0.71)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(Color.white.opacity(0.98), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.07),
                radius: 13, x: 0, y: 6)
    }
}
