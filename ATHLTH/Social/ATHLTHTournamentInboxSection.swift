import SwiftUI

/// Tournament conversations share their real tournament ID and existing
/// authenticated lobby messages. Nothing creates a second chat room.
struct ATHLTHTournamentInboxSection: View {
    @EnvironmentObject private var session: AppSessionStore

    let filterKey: String
    let onVisibleCountChanged: (Int) -> Void

    @State private var tournaments: [ATHLTHTournamentRemote] = []
    @State private var pendingIDs: Set<UUID> = []
    @State private var recentText: [UUID: String] = [:]
    @State private var loading = false
    @State private var error: String?

    private let cloud = ATHLTHTournamentCloudService()

    private var visible: [ATHLTHTournamentRemote] {
        guard ["all", "groups"].contains(filterKey) else { return [] }
        return tournaments.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !visible.isEmpty {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text("KONKURRANSECHATT")
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                    Spacer()
                    Text("\(visible.count)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            ForEach(visible) { tournament in
                NavigationLink {
                    ATHLTHTournamentGroupConversationView(
                        tournament: tournament
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 44, height: 44)
                            .background(ATHLTHTheme.accentDeep.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tournament.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(pendingIDs.contains(tournament.id)
                                 ? "Invitasjon · Godta eller avslå"
                                 : recentText[tournament.id] ??
                                   "Konkurransechat · \(tournament.format.title)")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(12)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
            }

            if let error, filterKey == "groups" {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: session.profile.userID) {
            await reload()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { await reload() }
            }
        }
        .task(id: filterKey) {
            onVisibleCountChanged(visible.count)
            if filterKey == "all" || filterKey == "groups" {
                await reload()
            }
        }
        .onChange(of: visible.count) { _, value in
            onVisibleCountChanged(value)
        }
    }

    @MainActor
    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let tournamentRecords = cloud.visibleTournaments()
            async let memberIDs = cloud.myTournamentIDs(
                userID: session.profile.userID
            )
            async let invitationIDs = cloud.pendingInvitationIDs(
                userID: session.profile.userID
            )
            let (items, mine, pending) = try await (
                tournamentRecords, memberIDs, invitationIDs
            )
            tournaments = items.filter {
                mine.contains($0.id) &&
                [.league, .groups, .cup].contains($0.format) &&
                $0.status != "cancelled"
            }
            pendingIDs = pending
            let preview = try await cloud.tournamentMessagePreviews(
                ids: tournaments.map(\.id)
            )
            recentText = preview
            error = nil
        } catch {
            self.error = error.localizedDescription
            tournaments = []
            pendingIDs = []
        }
    }
}
