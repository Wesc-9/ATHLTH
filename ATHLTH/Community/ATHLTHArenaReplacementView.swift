import SwiftUI

/// Replacement decisions require every surviving accepted participant AND
/// the incoming athlete to approve. The server moves the user into the
/// existing score slot atomically and keeps all earned points unchanged.
struct ATHLTHArenaReplacementSection: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let series: ATHLTHArenaRemoteSeries
    let members: [ATHLTHArenaRemoteMember]
    let isOrganizer: Bool
    let onChanged: () async -> Void

    @State private var proposals: [ATHLTHArenaReplacement] = []
    @State private var votes: [UUID: [ATHLTHArenaReplacementVote]] = [:]
    @State private var selectedSlotID: UUID?
    @State private var busy = false
    @State private var error: String?

    private let cloud = ATHLTHArenaCloudService()

    private var acceptedIDs: Set<UUID> {
        Set(members.filter { $0.response == "accepted" }.compactMap(\.userID))
    }

    private var availableFriends: [SocialProfileCard] {
        social.mutualFollows.filter { !members.compactMap(\.userID).contains($0.userID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if members.contains(where: \.isDeleted) || !proposals.isEmpty {
                Label(ATHLTHLocalization.choose(
                    english: "Member replacement",
                    norwegian: "Bytte av deltaker"
                ), systemImage: "person.crop.circle.badge.clock")
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
            }

            ForEach(members.filter(\.isDeleted)) { member in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .foregroundStyle(.gray)
                        Text(ATHLTHLocalization.choose(
                            english: "Deleted user", norwegian: "Slettet bruker"
                        ))
                        .foregroundStyle(.gray)
                        Spacer()
                        Text("\(member.points.formatted()) p")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.gray)
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "This place and its points are preserved. Replacing it requires unanimous approval.",
                        norwegian: "Denne plassen og poengene er bevart. Alle gjenværende deltakere må godkjenne en erstatter."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    if isOrganizer &&
                        !proposals.contains(where: { $0.slotID == member.slotID && $0.status == "pending" }) {
                        Button {
                            selectedSlotID = member.slotID
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Propose a replacement",
                                norwegian: "Foreslå erstatter"
                            ), systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(busy || availableFriends.isEmpty)
                    }
                }
                .padding(14)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 17))
            }

            ForEach(proposals.filter { $0.status == "pending" }) { proposal in
                let votingIDs = acceptedIDs.union(
                    proposal.nomineeID.map { Set([$0]) } ?? []
                )
                let recorded = votes[proposal.id] ?? []
                let yes = recorded.filter(\.accepted).count
                let canVote = votingIDs.contains(session.profile.userID) &&
                    !recorded.contains { $0.voterID == session.profile.userID }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: "person.2.badge.gearshape.fill")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(ATHLTHLocalization.choose(
                            english: "Replacement proposal",
                            norwegian: "Forslag til erstatter"
                        ))
                        .font(.subheadline.weight(.semibold))
                    }
                    Text(name(for: proposal.nomineeID))
                        .font(.subheadline)
                    if let slot = members.first(where: { $0.slotID == proposal.slotID }) {
                        Text(ATHLTHLocalization.choose(
                            english: "Takes over the existing \(slot.points.formatted()) points.",
                            norwegian: "Overtar de eksisterende \(slot.points.formatted()) poengene."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Text("\(yes)/\(votingIDs.count) " + ATHLTHLocalization.choose(
                        english: "approvals", norwegian: "godkjenninger"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    if canVote {
                        HStack {
                            Button {
                                Task { await vote(proposal.id, approve: true) }
                            } label: {
                                Text(ATHLTHLocalization.choose(
                                    english: "Approve", norwegian: "Godkjenn"
                                ))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)
                            Button {
                                Task { await vote(proposal.id, approve: false) }
                            } label: {
                                Text(ATHLTHLocalization.choose(
                                    english: "Reject", norwegian: "Avslå"
                                ))
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy)
                        }
                    }
                }
                .padding(14)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 17))
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: series.id) { await reload() }
        .sheet(item: Binding(
            get: { selectedSlotID.map { ATHLTHArenaSelectedSlot(id: $0) } },
            set: { selectedSlotID = $0?.id }
        )) { selection in
            NavigationStack {
                List(availableFriends, id: \.userID) { profile in
                    Button {
                        selectedSlotID = nil
                        Task { await propose(slotID: selection.id, nomineeID: profile.userID) }
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle")
                            Text(profile.resolvedName)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    }
                }
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Select replacement", norwegian: "Velg erstatter"
                ))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avbryt"
                        )) {
                            selectedSlotID = nil
                        }
                    }
                }
            }
        }
    }

    private func name(for userID: UUID?) -> String {
        guard let userID else {
            return ATHLTHLocalization.choose(
                english: "Deleted nominee", norwegian: "Slettet kandidat"
            )
        }
        return (social.visibleProfiles + social.mutualFollows)
            .first { $0.userID == userID }?.resolvedName ??
            ATHLTHLocalization.choose(
                english: "Invited athlete", norwegian: "Invitert utøver"
            )
    }

    @MainActor
    private func reload() async {
        do {
            let loaded = try await cloud.loadReplacements(seriesID: series.id)
            var allVotes: [UUID: [ATHLTHArenaReplacementVote]] = [:]
            for proposal in loaded where proposal.status == "pending" {
                allVotes[proposal.id] = try await cloud.loadReplacementVotes(proposalID: proposal.id)
            }
            proposals = loaded
            votes = allVotes
            error = nil
        } catch { self.error = error.localizedDescription
        }
    }

    @MainActor
    private func propose(slotID: UUID, nomineeID: UUID) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.proposeReplacement(slotID: slotID, nomineeID: nomineeID)
            await reload()
            await onChanged()
        } catch { self.error = error.localizedDescription }
    }

    @MainActor
    private func vote(_ proposalID: UUID, approve: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.voteReplacement(proposalID: proposalID, approve: approve)
            await reload()
            await onChanged()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ATHLTHArenaSelectedSlot: Identifiable {
    let id: UUID
}
