import SwiftUI

/// Compact summaries use existing memberships and Community destinations.
struct ATHLTHStudioHomeCommunitySummary: View {
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var destination: ATHLTHCommunityMainTab?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var clubNames: String {
        let names = groups.joinedGroups
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(2).map(\.name)
        return names.isEmpty ? tr("Explore clubs", "Utforsk klubber") : names.joined(separator: " · ")
    }

    private var nextClubEvent: CommunityGroupEventRecord? {
        groups.calendarEvents.filter {
            groups.joinedGroupIDs.contains($0.groupID) &&
            $0.startsAt >= .now && !["cancelled", "draft", "completed"].contains($0.status)
        }.min { $0.startsAt < $1.startsAt }
    }

    var body: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize
                  ? [GridItem(.flexible())]
                  : [GridItem(.adaptive(minimum: 210), spacing: 12)],
                  alignment: .leading, spacing: 12) {
            clubs
            events
            friends
        }
        .sheet(item: $destination) { tab in
            ATHLTHCommunityV5View(initialTab: tab)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: session.signedIn ? session.profile.userID.uuidString : "") {
            guard session.signedIn else { return }
            await groups.refresh(force: false)
            guard !Task.isCancelled else { return }
            await groups.refreshCalendarContent()
            guard !Task.isCancelled else { return }
            await social.refreshIfStale(challengeStore: challenges)
        }
    }

    private var clubs: some View {
        tile(tr("My clubs", "Mine klubber"), detail: clubNames,
             symbol: "person.3", tab: .clubs)
    }

    private var events: some View {
        tile(tr("Events", "Arrangementer"),
             detail: nextClubEvent.map {
                $0.title + " · " + $0.startsAt.formatted(.dateTime.day().month(.abbreviated))
             } ?? tr("Explore upcoming events", "Utforsk kommende arrangementer"),
             symbol: "calendar", tab: .events)
    }

    private var friends: some View {
        tile(tr("Social", "Sosialt"),
             detail: social.mutualFollows.isEmpty
                ? tr("Find your community", "Finn ditt fellesskap")
                : tr("\(social.mutualFollows.count) friends · Open community",
                     "\(social.mutualFollows.count) venner · Åpne fellesskap"),
             symbol: "person.2", tab: .overview)
    }

    private func tile(_ title: String, detail: String, symbol: String,
                      tab: ATHLTHCommunityMainTab) -> some View {
        Button { destination = tab } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.caption)
                }
                .foregroundStyle(ATHLTHTrainDesign.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }
}
