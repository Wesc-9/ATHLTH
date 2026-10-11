import Foundation
import SwiftUI

/// Server-backed collaboration is a pre-start lobby, not a scored competition.
/// Round results and series activation remain disabled until their verification
/// and final-scoring backend has been implemented.
struct ATHLTHArenaOnlineSection: View {
    @EnvironmentObject private var session: AppSessionStore

    @State private var series: [ATHLTHArenaRemoteSeries] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private let cloud = ATHLTHArenaCloudService()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.circle.fill")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Shared series", norwegian: "Delte konkurranser"
                ))
                .font(.headline)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Refresh series", norwegian: "Oppdater konkurranser"
                    ))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if series.isEmpty && !loading {
                Text(ATHLTHLocalization.choose(
                    english: "Published series and received invitations will appear here.",
                    norwegian: "Publiserte serier og invitasjoner vises her."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 17))
            }

            ForEach(series) { item in
                NavigationLink {
                    ATHLTHArenaOnlineDetailView(series: item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)
                            Text(item.scope.title + " · " +
                                 ATHLTHLocalization.choose(
                                    english: "Awaiting agreement",
                                    norwegian: "Avventer enighet"
                                 ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(13)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: session.profile.userID) {
            await refresh()
        }
    }

    @MainActor
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            series = try await cloud.loadSeries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ATHLTHArenaOnlineDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let series: ATHLTHArenaRemoteSeries

    @State private var members: [ATHLTHArenaRemoteMember] = []
    @State private var rounds: [ATHLTHArenaRemoteProposal] = []
    @State private var approvals: [ATHLTHArenaRemoteApproval] = []
    @State private var loading = false
    @State private var writing = false
    @State private var message: String?
    @State private var showingRoundCreator = false
    @State private var latestSeries: ATHLTHArenaRemoteSeries?
    @State private var remoteRevision = UUID()

    private var currentSeries: ATHLTHArenaRemoteSeries {
        latestSeries ?? series
    }

    private let cloud = ATHLTHArenaCloudService()

    private var ownMembership: ATHLTHArenaRemoteMember? {
        members.first { $0.userID == session.profile.userID }
    }

    private var canParticipate: Bool {
        ownMembership?.response == "accepted"
    }

    private var outstandingInvitations: Int {
        members.filter { $0.response == "invited" }.count
    }

    private var acceptedMembers: [ATHLTHArenaRemoteMember] {
        members.filter { $0.response == "accepted" && $0.userID != nil }
    }

    private var isOrganizer: Bool {
        if series.ownerID == session.profile.userID { return true }
        guard series.ownerID == nil else { return false }
        return acceptedMembers
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.slotID.uuidString < $1.slotID.uuidString
            }
            .first?.userID == session.profile.userID
    }

    private var isGroupSeries: Bool {
        members.count > 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                if ownMembership?.response == "invited" {
                    invitationActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Participants", norwegian: "Deltakere"
                        ))
                        .font(.headline)
                        Spacer()
                        Text("\(members.count)")
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    ForEach(members) { member in
                        HStack(spacing: 10) {
                            Image(systemName: member.isDeleted
                                  ? "person.crop.circle.badge.xmark"
                                  : member.userID == series.ownerID
                                      ? "crown.fill" : "person.crop.circle")
                                .foregroundStyle(
                                    member.isDeleted ? Color.gray : ATHLTHTheme.accentDeep
                                )
                            Text(displayName(for: member.userID))
                                .font(.subheadline)
                                .foregroundStyle(
                                    member.isDeleted ? Color.gray : ATHLTHTheme.primaryText
                                )
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(member.points.formatted()) p")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        member.isDeleted ? Color.gray : ATHLTHTheme.primaryText
                                    )
                                Text(responseTitle(member.response))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        .padding(11)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                ATHLTHArenaScoringSection(
                    series: currentSeries,
                    members: members,
                    rounds: rounds,
                    isOrganizer: isOrganizer,
                    onChanged: { await refresh() },
                    approvedRules: Dictionary(grouping: approvals, by: \.roundID)
                )
                .id(remoteRevision)

                if currentSeries.status == "active" && canParticipate {
                    ATHLTHArenaEvidenceSection(
                        series: currentSeries,
                        rounds: rounds
                    )
                    .id(remoteRevision)
                }

                ATHLTHArenaReplacementSection(
                    series: currentSeries,
                    members: members,
                    isOrganizer: isOrganizer,
                    onChanged: { await refresh() }
                )
                .id(remoteRevision)

                if isGroupSeries && canParticipate {
                    NavigationLink {
                        ATHLTHArenaGroupChatView(series: series)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Competition group chat",
                                    norwegian: "Konkurransens gruppechat"
                                ))
                                .font(.subheadline.weight(.semibold))
                                Text(ATHLTHLocalization.choose(
                                    english: "Discuss proposals with the group",
                                    norwegian: "Diskuter forslag med gruppen"
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .padding(16)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Proposed rounds",
                            norwegian: "Foreslåtte runder"
                        ))
                        .font(.headline)
                        Spacer()
                        if canParticipate && currentSeries.status == "draft" {
                            Button {
                                showingRoundCreator = true
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Suggest", norwegian: "Foreslå"
                                ), systemImage: "plus")
                            }
                            .font(.caption.weight(.semibold))
                            .disabled(writing)
                        }
                    }

                    if rounds.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No rounds have been suggested yet.",
                            norwegian: "Ingen runder er foreslått ennå."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    ForEach(rounds) { round in
                        roundCard(round)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        currentSeries.status == "draft"
                            ? ATHLTHLocalization.choose(
                                english: "Waiting for agreement",
                                norwegian: "Avventer godkjenning"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Group-verified scoring",
                                norwegian: "Poeng godkjennes av gruppen"
                            ),
                        systemImage: "lock.shield"
                    )
                        .font(.subheadline.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "Accepted athletes approve each result before it awards points. Automatic activity verification remains in development.",
                        norwegian: "Alle aktive deltakere godkjenner hvert resultat før poeng deles ut. Automatisk aktivitetsverifisering kommer senere."
                    ))
                    .font(.footnote)
                }
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(16)
                .background(ATHLTHTheme.accentDeep.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 17))

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPremiumCanvas(
            accent: ATHLTHTheme.champagneSoft.opacity(0.16)
        ))
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .task(id: series.id) {
            await refresh()
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showingRoundCreator) {
            ATHLTHArenaAddRoundView { round in
                Task { await propose(round) }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("ATHLTH ARENA", systemImage: "trophy.fill")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(series.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Text(series.scope.title + " · " +
                 "\(series.durationDays) " +
                 ATHLTHLocalization.choose(english: "days", norwegian: "dager"))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Text(series.scoring.title)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Text(currentSeries.status == "completed"
                ? ATHLTHLocalization.choose(english: "Completed", norwegian: "Fullført")
                : currentSeries.status == "active"
                    ? ATHLTHLocalization.choose(english: "Active", norwegian: "Aktiv")
                    : ATHLTHLocalization.choose(english: "Pending agreement", norwegian: "Avventer enighet"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            if outstandingInvitations > 0 {
                Label(
                    "\(outstandingInvitations) " +
                    ATHLTHLocalization.choose(
                        english: "invitations pending",
                        norwegian: "invitasjoner venter"
                    ),
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 22))
    }

    private var invitationActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ATHLTHLocalization.choose(
                english: "You're invited to this series.",
                norwegian: "Du er invitert til denne konkurranseserien."
            ))
            .font(.subheadline.weight(.semibold))
            HStack {
                Button {
                    Task { await respond(accept: true) }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Accept", norwegian: "Godta"
                    ), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(writing)
                Button {
                    Task { await respond(accept: false) }
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Decline", norwegian: "Avslå"
                    ))
                }
                .buttonStyle(.bordered)
                .disabled(writing)
            }
        }
        .padding(15)
        .background(ATHLTHTheme.accentDeep.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    private func roundCard(_ round: ATHLTHArenaRemoteProposal) -> some View {
        let acceptedIDs = Set(acceptedMembers.compactMap(\.userID))
        let approvedIDs = Set(
            approvals.filter { $0.roundID == round.id }.map(\.userID)
        )
        let voteCount = approvedIDs.intersection(acceptedIDs).count
        let fullyApproved = outstandingInvitations == 0 &&
            !acceptedIDs.isEmpty &&
            acceptedIDs.isSubset(of: approvedIDs)
        let alreadyVoted = approvedIDs.contains(session.profile.userID)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(round.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer()
                if fullyApproved {
                    Label(ATHLTHLocalization.choose(
                        english: "Agreed", norwegian: "Godkjent"
                    ), systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                }
            }
            Text(round.rules)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Text("\(voteCount)/\(acceptedIDs.count) " +
                 ATHLTHLocalization.choose(
                    english: "accepted members approved",
                    norwegian: "aktive deltakere har godkjent"
                 ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)

            if currentSeries.status == "draft" && canParticipate && !alreadyVoted && !fullyApproved {
                Button {
                    Task { await approve(roundID: round.id) }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Approve round", norwegian: "Godkjenn runde"
                    ), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(writing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 17))
    }

    private func responseTitle(_ response: String) -> String {
        switch response {
        case "accepted":
            return ATHLTHLocalization.choose(english: "Accepted", norwegian: "Godtatt")
        case "declined":
            return ATHLTHLocalization.choose(english: "Declined", norwegian: "Avslått")
        case "deleted":
            return ATHLTHLocalization.choose(english: "Deleted", norwegian: "Slettet")
        default:
            return ATHLTHLocalization.choose(english: "Invited", norwegian: "Invitert")
        }
    }

    private func displayName(for userID: UUID?) -> String {
        guard let userID else {
            return ATHLTHLocalization.choose(
                english: "Deleted user", norwegian: "Slettet bruker"
            )
        }
        if userID == session.profile.userID {
            return ATHLTHLocalization.choose(english: "You", norwegian: "Du")
        }
        return (social.visibleProfiles + social.mutualFollows)
            .first { $0.userID == userID }?.resolvedName ??
            ATHLTHLocalization.choose(
                english: "Participant", norwegian: "Deltaker"
            )
    }

    @MainActor
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let loadedSeries = cloud.loadSeries()
            async let loadedMembers = cloud.loadMembers(seriesID: series.id)
            async let loadedRounds = cloud.loadProposals(seriesID: series.id)
            let memberRows = try await loadedMembers
            let roundRows = try await loadedRounds
            let approvalRows = try await cloud.loadApprovals(
                roundIDs: roundRows.map(\.id)
            )
            let seriesRows = try await loadedSeries
            latestSeries = seriesRows.first { $0.id == series.id }
            members = memberRows
            rounds = roundRows
            approvals = approvalRows
            remoteRevision = UUID()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func respond(accept: Bool) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.respond(seriesID: series.id, accept: accept)
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func approve(roundID: UUID) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.approve(roundID: roundID)
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func propose(_ round: ATHLTHArenaRoundDraft) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.propose(
                seriesID: series.id,
                round: round,
                position: rounds.count
            )
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }
}
