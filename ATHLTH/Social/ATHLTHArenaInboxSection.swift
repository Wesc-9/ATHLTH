import SwiftUI

/// The same Arena invitation rows are surfaced inside the regular Messages
/// inbox. Group series act as their own conversation and open the group room
/// after acceptance; duel invites open the agreed series lobby.
struct ATHLTHArenaInboxSection: View {
    @EnvironmentObject private var session: AppSessionStore

    /// priority, direct or groups; other filters hide Arena conversations.
    let filterKey: String
    let onVisibleCountChanged: (Int) -> Void

    private struct Entry: Identifiable {
        let series: ATHLTHArenaRemoteSeries
        let membership: ATHLTHArenaRemoteMember?
        let isGroup: Bool
        let isReplacement: Bool
        var id: UUID { series.id }
    }

    @State private var entries: [Entry] = []
    @State private var isLoading = false
    @State private var error: String?

    private let cloud = ATHLTHArenaCloudService()

    private var visible: [Entry] {
        entries.filter { entry in
            switch filterKey {
            case "priority":
                return entry.isReplacement ||
                    entry.membership?.response == "invited" ||
                    entry.membership?.response == "accepted"
            case "direct":
                return !entry.isGroup
            case "groups":
                return entry.isGroup
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !visible.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "ARENA INVITATIONS & GROUPS",
                        norwegian: "ARENA-INVITASJONER OG GRUPPER"
                    ))
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    Spacer()
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            ForEach(visible) { entry in
                NavigationLink {
                    if entry.isGroup && entry.membership != nil {
                        ATHLTHArenaGroupChatView(series: entry.series)
                    } else {
                        ATHLTHArenaOnlineDetailView(series: entry.series)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName:
                            entry.isGroup ? "person.3.fill" : "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 44, height: 44)
                            .background(
                                ATHLTHTheme.accentDeep.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.series.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)
                            Text(entry.isReplacement
                                ? ATHLTHLocalization.choose(
                                    english: "Replacement proposal — your approval needed",
                                    norwegian: "Forslag om erstatter – ditt svar trengs"
                                  )
                                : entry.membership?.response == "invited"
                                    ? ATHLTHLocalization.choose(
                                        english: "Competition invitation — tap to respond",
                                        norwegian: "Konkurranseinvitasjon – trykk for å svare"
                                      )
                                    : ATHLTHLocalization.choose(
                                        english: "Competition group chat",
                                        norwegian: "Konkurransens gruppechat"
                                      ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(12)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 17)
                    )
                }
                .buttonStyle(.plain)
            }
            if let error, filterKey == "groups" {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: session.profile.userID) { await reload() }
        .task(id: filterKey) {
            onVisibleCountChanged(visible.count)
            if filterKey == "priority" || filterKey == "groups" || filterKey == "direct" {
                await reload()
            }
        }
        .onChange(of: visible.count) { _, next in
            onVisibleCountChanged(next)
        }
    }

    @MainActor
    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let series = try await cloud.loadSeries()
            var next: [Entry] = []
            for item in series {
                let members = try await cloud.loadMembers(seriesID: item.id)
                let mine = members.first(where: {
                    $0.userID == session.profile.userID
                })
                var nominated = false
                if mine == nil {
                    let proposals = try await cloud.loadReplacements(seriesID: item.id)
                    nominated = proposals.contains {
                        $0.nomineeID == session.profile.userID &&
                        $0.status == "pending"
                    }
                }
                guard mine != nil || nominated else { continue }
                let group = members.count > 2
                next.append(Entry(
                    series: item,
                    membership: mine,
                    isGroup: group,
                    isReplacement: nominated
                ))
            }
            entries = next
            onVisibleCountChanged(visible.count)
            error = nil
        } catch { self.error = error.localizedDescription
        }
    }
}
