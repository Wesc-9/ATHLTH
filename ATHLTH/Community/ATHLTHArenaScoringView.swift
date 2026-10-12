import Foundation
import SwiftUI
import Supabase

/// A live duel may offer a result *draft*, never award points by itself.
/// A fresh ID allows the organizer to explicitly reopen review of the same race.
struct ATHLTHArenaLiveOutcomeDraft: Identifiable {
    let id = UUID()
    let roundID: UUID
    let rankedSlots: [UUID]
    let evidenceNote: String
}

/// Presentation-only ranking of already approved server points.
/// Tied positive totals share the same competition position (1, 1, 3).
/// Zero, invalid or negative totals are unranked, never a race victory.
enum ATHLTHArenaSeriesScorePresentation {
    static func visiblePoints(_ raw: Double) -> Double {
        raw.isFinite ? max(raw, 0) : 0
    }

    static func ordered(
        _ members: [ATHLTHArenaRemoteMember]
    ) -> [ATHLTHArenaRemoteMember] {
        members
            .filter { $0.response == "accepted" || $0.response == "deleted" }
            .sorted { left, right in
                let lhs = visiblePoints(left.points)
                let rhs = visiblePoints(right.points)
                // Sorting must remain strictly ordered even for tiny
                // fractional score differences. Tie display is handled by
                // competitionRank, not by an epsilon-based sort comparator.
                if lhs != rhs { return lhs > rhs }
                if left.createdAt != right.createdAt {
                    return left.createdAt < right.createdAt
                }
                return left.slotID.uuidString < right.slotID.uuidString
            }
    }

    static func competitionRank(
        for member: ATHLTHArenaRemoteMember,
        among standings: [ATHLTHArenaRemoteMember]
    ) -> Int? {
        let points = visiblePoints(member.points)
        guard points > 0,
              standings.contains(where: { $0.slotID == member.slotID })
        else { return nil }
        return standings.filter {
            visiblePoints($0.points) > points + 0.001
        }.count + 1
    }

    static func approvedLeaderPoints(
        among standings: [ATHLTHArenaRemoteMember]
    ) -> Double {
        standings.map { visiblePoints($0.points) }.max() ?? 0
    }

    static func gapToLeader(
        for member: ATHLTHArenaRemoteMember,
        among standings: [ATHLTHArenaRemoteMember]
    ) -> Double {
        guard standings.contains(where: { $0.slotID == member.slotID }) else {
            return 0
        }
        return max(0, approvedLeaderPoints(among: standings) -
                   visiblePoints(member.points))
    }
}

/// Immutable read-only timeline built from result proposals returned by
/// Supabase. A proposal isn't proof of a completed workout and never awards
/// Arena points without the separate unanimous vote/settlement flow.
enum ATHLTHArenaResultHistoryPresentation {
    enum State: Equatable {
        case approved
        case pending
        case rejected
        case expired
        case unresolved

        static func resolve(_ raw: String) -> Self {
            switch raw {
            case "approved": return .approved
            case "pending": return .pending
            case "rejected": return .rejected
            case "expired": return .expired
            default: return .unresolved
            }
        }
    }

    static func recent(
        _ results: [ATHLTHArenaRoundResult],
        for roundIDs: Set<UUID>,
        limit: Int = 4
    ) -> [ATHLTHArenaRoundResult] {
        guard limit > 0 else { return [] }
        return Array(
            results
                .filter { roundIDs.contains($0.roundID) }
                .sorted { left, right in
                    if left.createdAt != right.createdAt {
                        return left.createdAt > right.createdAt
                    }
                    return left.id.uuidString < right.id.uuidString
                }
                .prefix(limit)
        )
    }
}

/// Arena scoring is confirmed by the whole group. Manual evidence is never
/// labelled as HealthKit/GPS verified; there is no silent point allocation.
struct ATHLTHArenaScoringSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let series: ATHLTHArenaRemoteSeries
    let members: [ATHLTHArenaRemoteMember]
    let rounds: [ATHLTHArenaRemoteProposal]
    let isOrganizer: Bool
    @Binding var liveOutcomeDraft: ATHLTHArenaLiveOutcomeDraft?
    let onChanged: () async -> Void

    @State private var results: [ATHLTHArenaRoundResult] = []
    @State private var resultsLoaded = false
    @State private var votes: [ATHLTHArenaRoundResultVote] = []
    @State private var linkedWorkouts: [ATHLTHArenaWorkoutEvidence] = []
    @State private var loading = false
    @State private var writing = false
    @State private var errorMessage: String?
    @State private var confirmStart = false
    @State private var roundToScore: ATHLTHArenaRemoteProposal?
    @State private var checkingLiveProposal = false

    private let cloud = ATHLTHArenaCloudService()

    private var acceptedIDs: Set<UUID> {
        Set(members.filter { $0.response == "accepted" }.compactMap(\.userID))
    }

    private var roundProgress: ATHLTHArenaRoundProgress {
        ATHLTHArenaRoundProgress.summarize(
            roundIDs: rounds.map(\.id),
            results: results
        )
    }

    private var rankedMembers: [ATHLTHArenaRemoteMember] {
        ATHLTHArenaSeriesScorePresentation.ordered(members)
    }

    private var personalStanding: ATHLTHArenaRemoteMember? {
        rankedMembers.first { $0.userID == session.profile.userID }
    }

    private var recentResultHistory: [ATHLTHArenaRoundResult] {
        ATHLTHArenaResultHistoryPresentation.recent(
            results,
            for: Set(rounds.map(\.id))
        )
    }

    private var startReady: Bool {
        guard series.status == "draft",
              members.filter({ $0.response == "accepted" && $0.userID != nil }).count >= 2,
              members.allSatisfy({ $0.response == "accepted" }),
              !rounds.isEmpty else { return false }

        return rounds.allSatisfy { round in
            let roundApprovals = Set(
                (approvedRules[round.id] ?? []).map(\.userID)
            )
            return acceptedIDs.isSubset(of: roundApprovals)
        }
    }

    /// A parent passes approvals to avoid duplicate queries and misleading
    /// local-only readiness. The server always revalidates readiness atomically.
    let approvedRules: [UUID: [ATHLTHArenaRemoteApproval]]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Overall standings", norwegian: "Sammenlagtstilling"
                ))
                .font(.headline)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Refresh standings", norwegian: "Oppdater poengstilling"
                    ))
                }
            }

            if series.status != "draft", !rounds.isEmpty, resultsLoaded {
                roundProgressCard
                if personalStanding != nil { personalScoreCard }
                if !recentResultHistory.isEmpty { recentResultHistoryCard }
            }

            ForEach(rankedMembers) { member in
                let rank = ATHLTHArenaSeriesScorePresentation.competitionRank(
                    for: member, among: rankedMembers
                )
                HStack(spacing: 12) {
                    Text(rank.map { "\($0)." } ?? "–")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(width: 27)
                    Image(systemName: member.isDeleted
                          ? "person.crop.circle.badge.xmark"
                          : rank == 1 ? "trophy.fill" : "person.crop.circle.fill")
                        .foregroundStyle(member.isDeleted ? Color.gray : ATHLTHTheme.accentDeep)
                    Text(memberName(member))
                        .font(.subheadline.weight(rank == 1 ? .semibold : .regular))
                        .foregroundStyle(member.isDeleted ? Color.gray : ATHLTHTheme.primaryText)
                    Spacer()
                    Text("\(ATHLTHArenaSeriesScorePresentation.visiblePoints(member.points).formatted()) p")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(member.isDeleted ? Color.gray : ATHLTHTheme.primaryText)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }

            if series.status == "draft" {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "Ready to start?", norwegian: "Klar til å starte?"
                    ))
                    .font(.subheadline.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "All athletes must accept and approve every round. Once started, rules are locked.",
                        norwegian: "Alle må godta invitasjonen og godkjenne hver runde. Reglene låses ved start."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    if isOrganizer {
                        Button {
                            confirmStart = true
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Start competition", norwegian: "Start konkurransen"
                            ), systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(!startReady || writing)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: series.status == "completed"
                          ? "trophy.fill" : "timer")
                    Text(series.status == "completed"
                         ? ATHLTHLocalization.choose(english: "Final results", norwegian: "Sluttresultat")
                         : ATHLTHLocalization.choose(english: "Competition active", norwegian: "Konkurransen pågår"))
                    .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            if series.status == "completed",
               series.completionReason != "deadline_unresolved",
               let first = rankedMembers.first,
               ATHLTHArenaSeriesScorePresentation.visiblePoints(first.points) > 0 {
                let champions = rankedMembers.filter {
                    ATHLTHArenaSeriesScorePresentation.competitionRank(
                        for: $0, among: rankedMembers
                    ) == 1
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 50, height: 50)
                            .background(
                                ATHLTHTheme.champagneSoft.opacity(0.27),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(champions.count == 1
                                ? ATHLTHLocalization.choose(
                                    english: "Arena champion", norwegian: "Arena-mester"
                                  )
                                : ATHLTHLocalization.choose(
                                    english: "Joint Arena champions", norwegian: "Delte Arena-mestere"
                                  ))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            Text(champions.map(memberName).joined(separator: " · "))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Final score approved by all eligible participants.",
                        norwegian: "Sluttresultatet er godkjent av alle stemmeberettigede deltakerne."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(ATHLTHTheme.accentDeep.opacity(0.15), lineWidth: 1)
                )
            }

            if series.status == "completed",
               series.completionReason == "deadline_unresolved" {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Finished with unresolved rounds",
                            norwegian: "Avsluttet med uavklarte runder"
                        ),
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "Only unanimously approved results received points. Missing or disputed results received no points; the table shows approved results only.",
                        norwegian: "Bare enstemmig godkjente resultater har fått poeng. Manglende eller omstridte runder gir ingen poeng. Tabellen viser godkjente resultater."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(16)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 18))
            }

            if series.status != "draft" {
                Text(ATHLTHLocalization.choose(
                    english: "Round results · approved by participants",
                    norwegian: "Runderesultater · godkjennes av deltakerne"
                ))
                .font(.headline)

                ForEach(rounds) { round in
                    resultRow(round)
                        .id("arena-review-\(round.id.uuidString)")
                }
            }

            Text(ATHLTHLocalization.choose(
                english: "Manual results require unanimous participant approval. GPS, exercise and Apple Health verification will follow separately.",
                norwegian: "Manuelle resultater krever enstemmig godkjenning. Verifisering mot GPS, treningsøvelser og Apple Health kommer separat."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: series.id) { await reload() }
        .task(id: series.id) { await listenForScoring(table: "arena_round_results") }
        .task(id: series.id) { await listenForScoring(table: "arena_round_result_votes") }
        .task(id: series.id) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                await reload()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .onChange(of: liveOutcomeDraft?.id) { _, _ in
            guard let draft = liveOutcomeDraft else { return }
            Task { await prepareLiveOutcome(draft) }
        }
        .sheet(item: $roundToScore, onDismiss: {
            liveOutcomeDraft = nil
        }) { round in
            ATHLTHArenaOutcomeEditor(
                round: round,
                series: series,
                members: rankedMembers,
                suggestedSlots: (
                    liveOutcomeDraft?.roundID == round.id
                        ? liveOutcomeDraft?.rankedSlots : nil
                ) ?? ATHLTHArenaSuggestedRanking.eligibleSuggestion(
                    template: round.template,
                    scoring: series.scoring,
                    roundID: round.id,
                    requiredSlots: rankedMembers.map(\.slotID),
                    evidence: linkedWorkouts
                ),
                initialEvidence: liveOutcomeDraft?.roundID == round.id
                    ? liveOutcomeDraft?.evidenceNote : nil
            ) { slots, note in
                Task { await propose(round: round, slots: slots, evidence: note) }
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Lock the rounds and start?",
                norwegian: "Låse rundene og starte?"
            ),
            isPresented: $confirmStart,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Start competition", norwegian: "Start konkurransen"
            )) {
                Task { await start() }
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Rules and participants are frozen until the competition ends, except for unanimously approved replacements of deleted users.",
                norwegian: "Regler og deltakere låses til konkurransen avsluttes, bortsett fra enstemmig godkjente erstatninger for slettede brukere."
            ))
        }
    }

    /// Read-only personal snapshot. Member points are server-settled:
    /// a Live Ghost finish or a pending vote cannot contribute.
    @ViewBuilder
    private var personalScoreCard: some View {
        if let member = personalStanding {
            let points = ATHLTHArenaSeriesScorePresentation.visiblePoints(member.points)
            let position = ATHLTHArenaSeriesScorePresentation.competitionRank(
                for: member, among: rankedMembers
            )
            let behind = ATHLTHArenaSeriesScorePresentation.gapToLeader(
                for: member, among: rankedMembers
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "Your Arena standing",
                        norwegian: "Din Arena-stilling"
                    ))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Spacer(minLength: 0)
                    Text(series.status == "completed"
                        ? ATHLTHLocalization.choose(
                            english: "Final", norwegian: "Avsluttet"
                          )
                        : ATHLTHLocalization.choose(
                            english: "Provisional", norwegian: "Foreløpig"
                          ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.map { "#\($0)" } ?? "–")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(ATHLTHLocalization.choose(
                            english: "Position", norwegian: "Plassering"
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(points.formatted()) p")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(ATHLTHLocalization.choose(
                            english: "Approved points", norwegian: "Godkjente poeng"
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }

                Text(points == 0
                    ? ATHLTHLocalization.choose(
                        english: "No approved points yet. Pending Live Ghost times and result proposals do not affect the standings.",
                        norwegian: "Ingen godkjente poeng ennå. Ventende Live Ghost-tider og resultatforslag påvirker ikke stillingen."
                      )
                    : behind > 0.001
                        ? ATHLTHLocalization.choose(
                            english: "\(behind.formatted()) points behind the lead. Only participant-approved results count.",
                            norwegian: "\(behind.formatted()) poeng bak ledelsen. Kun deltaker-godkjente resultater teller."
                          )
                        : ATHLTHLocalization.choose(
                            english: "You share or hold the lead on approved points.",
                            norwegian: "Du leder eller deler ledelsen basert på godkjente poeng."
                          )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(15)
            .background(
                ATHLTHTheme.vitalitySoft.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .accessibilityElement(children: .combine)
        }
    }

    /// A compact activity timeline, not a second leaderboard. Every date
    /// is the proposal creation date, never inferred as an approval date.
    private var recentResultHistoryCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Recent round results",
                    norwegian: "Nylige runderesultater"
                ))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer(minLength: 0)
                Text(ATHLTHLocalization.choose(
                    english: "Last proposals",
                    norwegian: "Siste forslag"
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            ForEach(recentResultHistory) { result in
                let state = ATHLTHArenaResultHistoryPresentation.State.resolve(
                    result.status
                )
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: historyIcon(state))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(historyColor(state))
                        .frame(width: 23)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            rounds.first(where: { $0.id == result.roundID })?.title ??
                            ATHLTHLocalization.choose(
                                english: "Competition round",
                                norwegian: "Konkurranserunde"
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(2)

                        Text(historyTitle(state))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(historyColor(state))

                        Text(result.createdAt.formatted(
                            date: .abbreviated, time: .shortened
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }

            Text(ATHLTHLocalization.choose(
                english: "These are submitted result proposals. Only unanimously approved results can award Arena points.",
                norwegian: "Dette er innsendte resultatforslag. Bare enstemmig godkjente resultater kan gi Arena-poeng."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func historyTitle(
        _ state: ATHLTHArenaResultHistoryPresentation.State
    ) -> String {
        switch state {
        case .approved:
            ATHLTHLocalization.choose(english: "Approved", norwegian: "Godkjent")
        case .pending:
            ATHLTHLocalization.choose(english: "Awaiting approval", norwegian: "Avventer godkjenning")
        case .rejected:
            ATHLTHLocalization.choose(english: "Rejected", norwegian: "Avvist")
        case .expired:
            ATHLTHLocalization.choose(english: "Expired", norwegian: "Utløpt")
        case .unresolved:
            ATHLTHLocalization.choose(english: "Unresolved", norwegian: "Uavklart")
        }
    }

    private func historyIcon(
        _ state: ATHLTHArenaResultHistoryPresentation.State
    ) -> String {
        switch state {
        case .approved: "checkmark.seal.fill"
        case .pending: "clock.fill"
        case .rejected: "xmark.circle.fill"
        case .expired: "clock.badge.exclamationmark"
        case .unresolved: "questionmark.circle"
        }
    }

    private func historyColor(
        _ state: ATHLTHArenaResultHistoryPresentation.State
    ) -> Color {
        switch state {
        case .approved: .green
        case .pending: .orange
        case .rejected, .expired, .unresolved: ATHLTHTheme.mutedText
        }
    }

    /// Uses only authoritative round proposals and voted result status.
    /// A GPS activity or a pending result never turns the progress ring green.
    private var roundProgressCard: some View {
        let progress = roundProgress
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ATHLTHLocalization.choose(
                        english: "Rounds approved", norwegian: "Godkjente runder"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(ATHLTHLocalization.choose(
                        english: "Only unanimously accepted results count.",
                        norwegian: "Kun enstemmig godkjente resultater teller."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 8)
                Text("\(progress.approved) / \(progress.total)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            ProgressView(value: progress.approvedFraction)
                .tint(ATHLTHTheme.accentDeep)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Approved competition rounds",
                    norwegian: "Godkjente konkurranserunder"
                ))
                .accessibilityValue("\(progress.approved) / \(progress.total)")

            HStack(spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(english: "Approved", norwegian: "Godkjent") +
                    ": \(progress.approved)",
                    systemImage: "checkmark.seal.fill"
                )
                Label(
                    ATHLTHLocalization.choose(english: "Pending vote", norwegian: "Avventer") +
                    ": \(progress.pending)",
                    systemImage: "clock"
                )
                Label(
                    ATHLTHLocalization.choose(english: "Unresolved", norwegian: "Uavklart") +
                    ": \(progress.unresolved)",
                    systemImage: "circle.dotted"
                )
            }
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func resultRow(_ round: ATHLTHArenaRemoteProposal) -> some View {
        let result = results.first { $0.roundID == round.id && $0.status != "rejected" }
        let myVote = result.flatMap { record in
            votes.first { $0.resultID == record.id && $0.userID == session.profile.userID }
        }
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(round.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer()
                if let result {
                    Text(result.status == "approved"
                         ? ATHLTHLocalization.choose(english: "Approved", norwegian: "Godkjent")
                         : result.status == "expired"
                            ? ATHLTHLocalization.choose(english: "Expired", norwegian: "Utløpt")
                            : result.status == "rejected"
                              ? ATHLTHLocalization.choose(english: "Rejected", norwegian: "Avvist")
                              : ATHLTHLocalization.choose(english: "Pending", norwegian: "Venter"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.status == "approved"
                                         ? Color.green : ATHLTHTheme.accentDeep)
                }
            }
            let roundEvidence = linkedWorkouts.filter { $0.roundID == round.id }
            provisionalRanking(for: round, evidence: roundEvidence)
            if !roundEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ATHLTHLocalization.choose(
                        english: "Linked workout evidence",
                        norwegian: "Tilknyttede treningsøkter"
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    ForEach(roundEvidence) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            let athlete = rankedMembers.first { $0.slotID == entry.slotID }
                            Text(athlete.map(memberName) ??
                                 ATHLTHLocalization.choose(
                                    english: "Participant", norwegian: "Deltaker"
                                 ))
                                .font(.caption)
                            Spacer()
                            Text(workoutMetricLabel(entry))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            Text(workoutSourceLabel(entry))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if let result {
                Text(result.rankedSlots.compactMap { slotID in
                    rankedMembers.first { $0.slotID == slotID }.map(memberName)
                }.joined(separator: " · "))
                    .font(.subheadline)
                Text(result.evidenceNote)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                evidenceConsistencyNotice(for: result, round: round)
                if result.status == "pending" {
                    Text("\(votes.filter { $0.resultID == result.id && $0.accepted && acceptedIDs.contains($0.userID) }.count)/\(acceptedIDs.count) " +
                         ATHLTHLocalization.choose(english: "approvals", norwegian: "godkjenninger"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    if acceptedIDs.contains(session.profile.userID) && myVote == nil {
                        HStack {
                            Button {
                                Task { await vote(result.id, accept: true) }
                            } label: {
                                Text(ATHLTHLocalization.choose(english: "Approve", norwegian: "Godkjenn"))
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                Task { await vote(result.id, accept: false) }
                            } label: {
                                Text(ATHLTHLocalization.choose(english: "Reject", norwegian: "Avslå"))
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(writing)
                    }
                }
            } else if series.status == "active" && isOrganizer &&
                      (series.endsAt.map { Date() <= $0.addingTimeInterval(48 * 3_600) } ?? false) {
                Button {
                    roundToScore = round
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Propose result", norwegian: "Foreslå resultat"
                    ), systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .disabled(writing)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "Not scored yet", norwegian: "Ingen poeng ennå"
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
    }

    /// This only checks for a discrepancy in complete, unambiguous shared
    /// results. Manual exceptions remain possible and need consensus.
    @ViewBuilder
    private func evidenceConsistencyNotice(
        for result: ATHLTHArenaRoundResult,
        round: ATHLTHArenaRemoteProposal
    ) -> some View {
        let expected = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: round.template,
            scoring: series.scoring,
            roundID: round.id,
            requiredSlots: rankedMembers.map(\.slotID),
            evidence: linkedWorkouts
        )
        if let expected, expected != result.rankedSlots {
            Label(
                ATHLTHLocalization.choose(
                    english: "The proposed places differ from current shared workout results. Review the explanation before voting.",
                    norwegian: "De foreslåtte plasseringene avviker fra delte øktresultater. Kontroller forklaringen før du stemmer."
                ),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func provisionalRanking(
        for round: ATHLTHArenaRemoteProposal,
        evidence: [ATHLTHArenaWorkoutEvidence]
    ) -> some View {
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: round.template,
            roundID: round.id,
            evidence: evidence
        )
        if !standings.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Provisional workout ranking",
                        norwegian: "Foreløpig øktrangering"
                    ),
                    systemImage: "chart.bar.xaxis"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)

                ForEach(standings) { standing in
                    let position = standings.firstIndex { $0.id == standing.id } ?? 0
                    let athlete = rankedMembers.first { $0.slotID == standing.slotID }
                    HStack(spacing: 8) {
                        Text("\(position + 1).")
                            .font(.caption.weight(.semibold))
                            .frame(width: 22)
                        Text(athlete.map(memberName) ??
                             ATHLTHLocalization.choose(
                                english: "Participant", norwegian: "Deltaker"
                             ))
                            .font(.caption)
                        Spacer()
                        Text(provisionalMetric(
                            value: standing.result,
                            template: round.template
                        ))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    }
                }
                if ATHLTHArenaSuggestedRanking.hasTieAtTop(standings) {
                    Text(ATHLTHLocalization.choose(
                        english: "Equal result — group must resolve the ranking.",
                        norwegian: "Lik verdi – gruppen må avklare plasseringen."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Text(ATHLTHLocalization.choose(
                    english: "Based only on shared device data; not an official or automatically verified result.",
                    norwegian: "Kun basert på delte øktdata; ikke offisielt eller automatisk verifisert."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(11)
            .background(
                ATHLTHTheme.accentDeep.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
    }

    private func provisionalMetric(
        value: Double,
        template: ATHLTHArenaRoundTemplate
    ) -> String {
        switch template {
        case .fastest5K, .fastest1K, .fastestDistance, .fastestRoute:
            let seconds = Int(value.rounded())
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .mostDistance:
            return String(format: "%.2f km", value / 1_000)
        case .mostWorkouts:
            return "\(Int(value)) " + ATHLTHLocalization.choose(
                english: "workouts", norwegian: "økter"
            )
        case .mostRepetitions, .custom:
            return ""
        }
    }

    private func workoutSourceLabel(_ entry: ATHLTHArenaWorkoutEvidence) -> String {
        let source: String
        switch entry.source {
        case "apple_health": source = "Apple Health"
        case "iphone": source = "iPhone"
        default: source = "ATHLTH"
        }
        return ATHLTHLocalization.choose(
            english: "Reported: " + source,
            norwegian: "Oppgitt: " + source
        )
    }

    private func workoutMetricLabel(_ entry: ATHLTHArenaWorkoutEvidence) -> String {
        if entry.metricType == "distance_meters" {
            return String(format: "%.2f km", entry.metricValue / 1_000)
        }
        if entry.metricType == "elapsed_seconds" {
            let seconds = Int(entry.metricValue.rounded())
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        return ATHLTHLocalization.choose(english: "1 session", norwegian: "1 økt")
    }

    private func memberName(_ member: ATHLTHArenaRemoteMember) -> String {
        if member.isDeleted {
            return ATHLTHLocalization.choose(english: "Deleted user", norwegian: "Slettet bruker")
        }
        if member.userID == session.profile.userID {
            return ATHLTHLocalization.choose(english: "You", norwegian: "Du")
        }
        return (social.visibleProfiles + social.mutualFollows)
            .first { $0.userID == member.userID }?.resolvedName ??
            ATHLTHLocalization.choose(english: "Participant", norwegian: "Deltaker")
    }

    /// Keep the approval counter and standings current without requiring
    /// manual refresh. Subscriptions use the competition RLS policies.
    @MainActor
    private func listenForScoring(table: String) async {
        let channel = await SupabaseEnvironment.client.channel(
            "arena-scoring-\(table)-\(series.id.uuidString.lowercased())"
        )
        let changes = await channel.postgresChange(
            AnyAction.self, schema: "public", table: table
        )
        await channel.subscribe()
        for await _ in changes {
            if Task.isCancelled { break }
            await reload()
        }
        await channel.unsubscribe()
    }

    @MainActor
    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await cloud.loadRoundResults(seriesID: series.id)
            let loadedVotes = try await cloud.loadResultVotes(resultIDs: loaded.map(\.id))
            let loadedWorkouts = try await cloud.loadWorkoutEvidence(seriesID: series.id)
            guard !Task.isCancelled else { return }
            results = loaded
            votes = loadedVotes
            linkedWorkouts = loadedWorkouts
            resultsLoaded = true
            errorMessage = nil
        } catch {
            // Do not present last-known points progress as fresh on errors.
            resultsLoaded = false
            errorMessage = error.localizedDescription
        }
    }

    /// A newly completed Live Ghost race can only prepare a draft.
    /// Re-check the authoritative round status immediately before showing
    /// the editor; a competing device may have submitted a proposal already.
    @MainActor
    private func prepareLiveOutcome(
        _ draft: ATHLTHArenaLiveOutcomeDraft
    ) async {
        guard !checkingLiveProposal,
              !writing,
              series.status == "active",
              isOrganizer,
              let round = rounds.first(where: { $0.id == draft.roundID })
        else {
            liveOutcomeDraft = nil
            return
        }

        checkingLiveProposal = true
        defer { checkingLiveProposal = false }

        do {
            let latestResults = try await cloud.loadRoundResults(
                seriesID: series.id
            )
            guard !Task.isCancelled,
                  liveOutcomeDraft?.id == draft.id else { return }

            results = latestResults
            if latestResults.contains(where: {
                $0.roundID == round.id && $0.status != "rejected"
            }) {
                errorMessage = ATHLTHLocalization.choose(
                    english: "A result has already been submitted for this round. Review its status instead of proposing a duplicate.",
                    norwegian: "Det finnes allerede et resultatforslag for denne runden. Kontroller statusen i stedet for å sende et nytt."
                )
                liveOutcomeDraft = nil
                return
            }

            // A result editor only: the organizer must submit deliberately,
            // and all eligible athletes must approve before any points move.
            errorMessage = nil
            roundToScore = round
        } catch {
            errorMessage = ATHLTHLocalization.choose(
                english: "Could not check the latest round status. Try again before preparing a result.",
                norwegian: "Kunne ikke kontrollere siste rundestatus. Prøv igjen før du klargjør et resultat."
            ) + " " + error.localizedDescription
            liveOutcomeDraft = nil
        }
    }

    @MainActor
    private func start() async {
        guard !writing, startReady else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.startSeries(seriesID: series.id)
            errorMessage = nil
            await onChanged()
        } catch {
            // A participant may have changed their response or added a round
            // after the organizer opened the confirmation. Refresh the server
            // state instead of leaving an obsolete enabled Start button.
            errorMessage = error.localizedDescription
            await onChanged()
        }
    }

    @MainActor
    private func propose(
        round: ATHLTHArenaRemoteProposal,
        slots: [UUID],
        evidence: String
    ) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.proposeRoundOutcome(roundID: round.id, rankedSlots: slots, evidence: evidence)
            await reload()
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func vote(_ id: UUID, accept: Bool) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.voteRoundOutcome(resultID: id, accept: accept)
            await reload()
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ATHLTHArenaOutcomeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let round: ATHLTHArenaRemoteProposal
    let series: ATHLTHArenaRemoteSeries
    let members: [ATHLTHArenaRemoteMember]
    let suggestedSlots: [UUID]?
    let hasLiveEvidence: Bool
    let onPropose: ([UUID], String) -> Void

    @State private var slots: [UUID?]
    @State private var evidence = ""
    @State private var exerciseName = ""
    @State private var repetitionValues: [String]

    init(
        round: ATHLTHArenaRemoteProposal,
        series: ATHLTHArenaRemoteSeries,
        members: [ATHLTHArenaRemoteMember],
        suggestedSlots: [UUID]?,
        initialEvidence: String? = nil,
        onPropose: @escaping ([UUID], String) -> Void
    ) {
        self.round = round
        self.series = series
        self.members = members
        self.suggestedSlots = suggestedSlots
        self.hasLiveEvidence = initialEvidence != nil
        self.onPropose = onPropose
        let needed = series.scoring == .winner ? 1 : min(3, members.count)
        let suggestion = suggestedSlots ?? []
        let initial: [UUID?] = (0..<needed).map { index in
            index < suggestion.count ? suggestion[index] : nil
        }
        _slots = State(initialValue: initial)
        _evidence = State(initialValue: initialEvidence ?? "")
        _exerciseName = State(initialValue:
            ATHLTHArenaRepetitionResult.agreedExercise(in: round.rules) ?? ""
        )
        _repetitionValues = State(initialValue: Array(repeating: "", count: needed))
    }

    private func memberLabel(_ member: ATHLTHArenaRemoteMember) -> String {
        if member.isDeleted {
            return ATHLTHLocalization.choose(
                english: "Deleted user", norwegian: "Slettet bruker"
            )
        }
        if member.userID == session.profile.userID {
            return ATHLTHLocalization.choose(english: "You", norwegian: "Du")
        }
        return (social.visibleProfiles + social.mutualFollows)
            .first { $0.userID == member.userID }?.resolvedName ??
            ATHLTHLocalization.choose(english: "Participant", norwegian: "Deltaker")
    }

    @ViewBuilder
    private func rankingPicker(at index: Int) -> some View {
        let localizedPlace = ATHLTHLocalization.choose(
            english: "place", norwegian: "plass"
        )
        let caption = String(index + 1) + ". " + localizedPlace
        let choice = Binding<UUID?>(
            get: { slots[index] },
            set: { slots[index] = $0 }
        )
        Picker(caption, selection: choice) {
            Text(ATHLTHLocalization.choose(
                english: "Choose athlete", norwegian: "Velg utøver"
            ))
            .tag(nil as UUID?)
            ForEach(members) { member in
                Text(memberLabel(member))
                    .tag(member.slotID as UUID?)
            }
        }
    }

    private func repetitionsField(at index: Int) -> some View {
        let value = Binding<String>(
            get: { repetitionValues[index] },
            set: { repetitionValues[index] = $0 }
        )
        return TextField(
            "\(index + 1). " + ATHLTHLocalization.choose(
                english: "place: repetitions", norwegian: "plass: repetisjoner"
            ),
            text: value
        )
        .keyboardType(.numberPad)
    }

    private var submittedEvidence: String? {
        if round.template == .mostRepetitions {
            return ATHLTHArenaRepetitionResult.explanation(
                exercise: exerciseName,
                repetitions: repetitionValues,
                optionalNote: evidence
            )
        }
        let trimmed = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > 600 ? nil : trimmed
    }

    private var valid: Bool {
        let selected = slots.compactMap { $0 }
        return slots.count == (series.scoring == .winner ? 1 : min(3, members.count)) &&
            selected.count == slots.count &&
            Set(selected).count == slots.count &&
            submittedEvidence != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if suggestedSlots != nil {
                        Label(
                            hasLiveEvidence
                                ? ATHLTHLocalization.choose(
                                    english: "Prefilled from participant-reported Live Ghost times. Verify the result before submitting.",
                                    norwegian: "Forhåndsutfylt fra deltakerrapporterte Live Ghost-tider. Kontroller resultatet før du sender."
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Suggested from complete shared workout results. Review before submitting.",
                                    norwegian: "Foreslått fra komplette delte øktresultater. Kontroller plasseringene før du sender."
                                ),
                            systemImage: "checkmark.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(ATHLTHLocalization.choose(
                            english: "Select every place manually. Missing results or a tie prevent safe automatic suggestions.",
                            norwegian: "Velg alle plasseringer manuelt. Manglende øktresultater eller uavgjort hindrer automatiske forslag."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    ForEach(slots.indices, id: \.self) { index in
                        rankingPicker(at: index)
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Ranking", norwegian: "Plassering"
                    ))
                }

                if round.template == .mostRepetitions {
                    Section {
                        Text(ATHLTHLocalization.choose(
                            english: "Enter the specific exercise and measured repetitions for each ranked athlete. These are manual claims that need unanimous approval.",
                            norwegian: "Oppgi konkret øvelse og registrerte repetisjoner for hver plassering. Dette er manuelle resultater som må godkjennes av alle."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Exercise name", norwegian: "Øvelsesnavn"
                            ),
                            text: $exerciseName
                        )
                        .disabled(ATHLTHArenaRepetitionResult.agreedExercise(
                            in: round.rules
                        ) != nil)
                        ForEach(repetitionValues.indices, id: \.self) { index in
                            repetitionsField(at: index)
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Exercise-specific result",
                            norwegian: "Resultat for bestemt øvelse"
                        ))
                    }
                }
                Section {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Optional notes for repetitions; otherwise describe the result...",
                            norwegian: "Valgfri kommentar ved repetisjoner, ellers beskriv resultatet..."
                        ),
                        text: $evidence,
                        axis: .vertical
                    )
                    .lineLimit(3...7)
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Evidence / explanation", norwegian: "Resultatgrunnlag"
                    ))
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "Manual results are suggestions until every participant confirms.",
                        norwegian: "Manuelle resultater er bare forslag til alle deltakerne har godkjent."
                    ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(round.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Submit", norwegian: "Send forslag"
                    )) {
                        guard valid else { return }
                        guard let note = submittedEvidence else { return }
                        onPropose(slots.compactMap { $0 }, note)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        .environment(\.colorScheme, .light)
        .tint(ATHLTHArenaLightStyle.action)
        }
    }
}
