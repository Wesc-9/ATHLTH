import Foundation
import Supabase

/// Scheduled, score-eligible tournament exercises for the signed-in athlete.
/// One item per physical exercise; Home shows either the opening or the
/// deadline on the day concerned, without duplicating it on one date.
struct ATHLTHTournamentCalendarItem: Identifiable, Hashable {
    let id: UUID  // Server-owned exercise slot ID; stable across resyncs.
    let tournamentID: UUID
    let tournamentTitle: String
    let exerciseTitle: String
    let opensAt: Date
    let deadlineAt: Date
    let exerciseNumber: Int
    let phase: String

    func relevantDate(on day: Date, calendar: Calendar = .current) -> Date? {
        let opens = calendar.isDate(opensAt, inSameDayAs: day)
        let closes = calendar.isDate(deadlineAt, inSameDayAs: day)
        if opens { return opensAt }
        if closes { return deadlineAt }
        return nil
    }

    func isDeadline(on day: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(deadlineAt, inSameDayAs: day) &&
            !calendar.isDate(opensAt, inSameDayAs: day)
    }

    var readableTitle: String { "\(exerciseTitle) · \(tournamentTitle)" }
}

@MainActor
final class ATHLTHTournamentCalendarStore: ObservableObject {
    @Published private(set) var items: [ATHLTHTournamentCalendarItem] = []
    @Published private(set) var accountID: UUID?
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var errorMessage: String?

    private let tournamentCloud = ATHLTHTournamentCloudService()
    private let lobbyCloud = ATHLTHTournamentLobbyCloudService()
    private var isRefreshing = false

    func reset() {
        items = []
        accountID = nil
        lastRefreshedAt = nil
        errorMessage = nil
    }

    /// Returns false on an incomplete fetch: Calendar must not erase
    /// previously synced ATHLTH events merely because the network failed.
    @discardableResult
    func refresh(for userID: UUID, force: Bool = false) async -> Bool {
        if accountID != userID {
            reset()
            accountID = userID
        }
        if isRefreshing { return lastRefreshedAt != nil }
        if !force, let lastRefreshedAt,
           Date().timeIntervalSince(lastRefreshedAt) < 90 { return true }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let ids = try await tournamentCloud.myTournamentIDs(userID: userID)
            if ids.isEmpty {
                items = []
                lastRefreshedAt = Date()
                errorMessage = nil
                return true
            }
            let all = try await tournamentCloud.visibleTournaments()
            let active = all.filter {
                ids.contains($0.id) && $0.status == "active"
            }
            var newItems: [ATHLTHTournamentCalendarItem] = []
            let now = Date()
            let windowEnd = Calendar.current.date(
                byAdding: .day, value: 90, to: now
            ) ?? now.addingTimeInterval(90 * 86_400)

            for tournament in active {
                let entrants = try await tournamentCloud.entries(for: tournament.id)
                guard entrants.contains(where: {
                    $0.userID == userID && $0.response == "accepted" &&
                    $0.removedAt == nil
                }) else { continue }

                let matches = try await tournamentCloud.matches(
                    for: tournament.id
                )
                let eligible = matches.filter {
                    !$0.isWarmup && !$0.isBye &&
                    $0.status != "confirmed" &&
                    ($0.homeID == userID || $0.awayID == userID)
                }
                guard !eligible.isEmpty else { continue }
                let slots = try await lobbyCloud.matchExercises(
                    matchIDs: eligible.map(\.id)
                )
                let candidates = try await lobbyCloud.candidates(
                    tournamentID: tournament.id
                )
                let candidateNames = try await lobbyCloud.candidateNames(candidates)
                let candidateLookup = Dictionary(uniqueKeysWithValues:
                    candidates.map { ($0.id, $0.lookupID) })
                let activeSlotIDs = Set(slots.filter {
                    $0.state == "pending" &&
                    $0.deadlineAt >= Calendar.current.startOfDay(for: now) &&
                    $0.opensAtOrBefore(windowEnd)
                }.map(\.id))
                for slot in slots where activeSlotIDs.contains(slot.id) {
                    let exerciseName = candidateLookup[slot.candidateID]
                        .flatMap { candidateNames[$0] } ??
                        "Øvelse \(slot.position)"
                    newItems.append(ATHLTHTournamentCalendarItem(
                        id: slot.id,
                        tournamentID: tournament.id,
                        tournamentTitle: tournament.title,
                        exerciseTitle: exerciseName,
                        opensAt: slot.scheduledAt,
                        deadlineAt: slot.deadlineAt,
                        exerciseNumber: slot.position,
                        phase: eligible.first(where: { $0.id == slot.matchID })?
                            .phase.rawValue ?? "league"
                    ))
                }
            }

            items = Array(Dictionary(grouping: newItems, by: \.id)
                .compactMap { $0.value.first }
                .sorted {
                    $0.opensAt == $1.opensAt
                        ? $0.id.uuidString < $1.id.uuidString
                        : $0.opensAt < $1.opensAt
                }
                .prefix(500))
            lastRefreshedAt = Date()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func events(on date: Date) -> [ATHLTHTournamentCalendarItem] {
        items.filter { $0.relevantDate(on: date) != nil }
            .sorted {
                ($0.relevantDate(on: date) ?? $0.opensAt) <
                ($1.relevantDate(on: date) ?? $1.opensAt)
            }
    }
}

private extension ATHLTHTournamentMatchExerciseRemote {
    func opensAtOrBefore(_ date: Date) -> Bool { scheduledAt <= date }
}
