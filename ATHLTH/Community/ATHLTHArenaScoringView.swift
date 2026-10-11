import Foundation
import SwiftUI

/// Arena scoring is confirmed by the whole group. Manual evidence is never
/// labelled as HealthKit/GPS verified; there is no silent point allocation.
struct ATHLTHArenaScoringSection: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let series: ATHLTHArenaRemoteSeries
    let members: [ATHLTHArenaRemoteMember]
    let rounds: [ATHLTHArenaRemoteProposal]
    let isOrganizer: Bool
    let onChanged: () async -> Void

    @State private var results: [ATHLTHArenaRoundResult] = []
    @State private var votes: [ATHLTHArenaRoundResultVote] = []
    @State private var linkedWorkouts: [ATHLTHArenaWorkoutEvidence] = []
    @State private var loading = false
    @State private var writing = false
    @State private var errorMessage: String?
    @State private var confirmStart = false
    @State private var roundToScore: ATHLTHArenaRemoteProposal?

    private let cloud = ATHLTHArenaCloudService()

    private var acceptedIDs: Set<UUID> {
        Set(members.filter { $0.response == "accepted" }.compactMap(\.userID))
    }

    private var rankedMembers: [ATHLTHArenaRemoteMember] {
        members.filter { $0.response == "accepted" || $0.response == "deleted" }
            .sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                return $0.createdAt < $1.createdAt
            }
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

            ForEach(rankedMembers) { member in
                let index = rankedMembers.firstIndex { $0.id == member.id } ?? 0
                HStack(spacing: 12) {
                    Text("\(index + 1).")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(width: 27)
                    Image(systemName: member.isDeleted
                          ? "person.crop.circle.badge.xmark"
                          : index == 0 ? "trophy.fill" : "person.crop.circle.fill")
                        .foregroundStyle(member.isDeleted ? Color.gray : ATHLTHTheme.accentDeep)
                    Text(memberName(member))
                        .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                        .foregroundStyle(member.isDeleted ? Color.gray : ATHLTHTheme.primaryText)
                    Spacer()
                    Text("\(member.points.formatted()) p")
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

            if series.status == "completed", let first = rankedMembers.first {
                let champions = rankedMembers.filter { $0.points == first.points }
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        champions.count == 1
                            ? ATHLTHLocalization.choose(english: "Champion", norwegian: "Mester")
                            : ATHLTHLocalization.choose(english: "Joint champions", norwegian: "Delt seier"),
                        systemImage: "crown.fill"
                    )
                    .font(.subheadline.weight(.bold))
                    Text(champions.map(memberName).joined(separator: " · "))
                        .font(.title3.weight(.bold))
                }
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }

            if series.status != "draft" {
                Text(ATHLTHLocalization.choose(
                    english: "Round results · approved by participants",
                    norwegian: "Runderesultater · godkjennes av deltakerne"
                ))
                .font(.headline)

                ForEach(rounds) { round in
                    resultRow(round)
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
        .sheet(item: $roundToScore) { round in
            ATHLTHArenaOutcomeEditor(
                round: round,
                series: series,
                members: rankedMembers
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
                            Text(entry.source == "apple_health"
                                 ? "Health" : entry.source == "iphone" ? "iPhone" : "ATHLTH")
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
            } else if series.status == "active" && isOrganizer {
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
        case .fastest5K, .fastest1K:
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

    @MainActor
    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await cloud.loadRoundResults(seriesID: series.id)
            results = loaded
            votes = try await cloud.loadResultVotes(resultIDs: loaded.map(\.id))
            linkedWorkouts = try await cloud.loadWorkoutEvidence(seriesID: series.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func start() async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.startSeries(seriesID: series.id)
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
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
    let onPropose: ([UUID], String) -> Void

    @State private var slots: [UUID]
    @State private var evidence = ""

    init(
        round: ATHLTHArenaRemoteProposal,
        series: ATHLTHArenaRemoteSeries,
        members: [ATHLTHArenaRemoteMember],
        onPropose: @escaping ([UUID], String) -> Void
    ) {
        self.round = round
        self.series = series
        self.members = members
        self.onPropose = onPropose
        let needed = series.scoring == .winner ? 1 : min(3, members.count)
        _slots = State(initialValue: Array(members.prefix(needed).map(\.slotID)))
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
        let choice = Binding<UUID>(
            get: { slots[index] },
            set: { slots[index] = $0 }
        )
        Picker(caption, selection: choice) {
            ForEach(members) { member in
                Text(memberLabel(member))
                    .tag(member.slotID)
            }
        }
    }

    private var valid: Bool {
        slots.count == (series.scoring == .winner ? 1 : min(3, members.count)) &&
        Set(slots).count == slots.count &&
        !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(ATHLTHLocalization.choose(
                    english: "Ranking", norwegian: "Plassering"
                )) {
                    ForEach(slots.indices, id: \.self) { index in
                        rankingPicker(at: index)
                    }
                }

                Section {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "E.g. final times and distance...",
                            norwegian: "For eksempel tider og distanse..."
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
                        onPropose(slots, evidence)
                        dismiss()
                    }
                    .disabled(!valid || evidence.count > 600)
                }
            }
        }
    }
}
