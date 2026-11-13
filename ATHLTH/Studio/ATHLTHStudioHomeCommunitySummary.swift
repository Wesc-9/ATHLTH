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


/// A single focused social entry point beside the upcoming workout on iPad.
/// Counts come from the signed-in user's real mutual-follow relationships.
struct ATHLTHStudioHomeSocialHighlight: View {
    @EnvironmentObject private var social: SocialStore
    @State private var showingCommunity = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        Button { showingCommunity = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.title3)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    Spacer(minLength: 6)
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }

                Text(tr("Train together", "Tren sammen"))
                    .font(.system(size: 23, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)

                Text(social.mutualFollows.isEmpty
                    ? tr("Find people to train with and make every workout more social.",
                         "Finn treningsvenner og gjør øktene mer sosiale.")
                    : tr("\(social.mutualFollows.count) training friends in your network",
                         "\(social.mutualFollows.count) treningsvenner i nettverket ditt"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Label(tr("Explore community", "Utforsk fellesskapet"),
                      systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 246, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-ipad-home-social-highlight")
        .sheet(isPresented: $showingCommunity) {
            ATHLTHCommunityV5View(initialTab: .overview)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
