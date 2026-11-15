import SwiftUI

/// Home shows live, account-backed Club / Event / Challenge information.
/// All actions open the full iPad detail column; this view never owns a sheet.
struct ATHLTHStudioHomeCommunitySummary: View {
    let onOpenCommunity: (ATHLTHCommunityMainTab) -> Void
    let onOpenTrainTogether: () -> Void

    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private let ink = ATHLTHStudioStyle.ink
    private let gold = ATHLTHStudioStyle.gold
    private let canvas = ATHLTHStudioStyle.canvas
    private let outline = ATHLTHStudioStyle.outline

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var myClubs: [CommunityGroupRecord] {
        Array(groups.joinedGroups
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(3))
    }

    private var suggestedClubs: [CommunityGroupRecord] {
        Array(groups.groups.filter {
            ATHLTHStudioHomeCommunityDisplayPolicy.isDiscoverable(
                visibility: $0.visibility,
                isMember: groups.joinedGroupIDs.contains($0.id),
                hasPendingInvitation: groups.pendingInvite(for: $0.id) != nil
            )
        }.prefix(2))
    }

    private var nextEvents: [CommunityGroupEventRecord] {
        Array(groups.calendarEvents.filter {
            ATHLTHStudioHomeCommunityDisplayPolicy.isUpcoming(
                status: $0.status, start: $0.startsAt, now: .now
            )
        }.prefix(2))
    }

    private var clubInvites: [CommunityGroupInviteRecord] {
        groups.ownInvites.filter { $0.status == "pending" }
    }

    private var challengeInvites: [ATHLTHChallenge] {
        guard session.signedIn else { return [] }
        return challenges.incomingInvitations(for: session.profile.userID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Your community", "Ditt fellesskap"))
                        .font(.system(size: 27, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Clubs, training partners, events and invitations",
                        "Klubber, treningsvenner, arrangementer og invitasjoner"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    onOpenCommunity(.overview)
                } label: {
                    Label(tr("Explore", "Utforsk"), systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gold)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-ipad-community-explore")
            }

            if typeSize.isAccessibilitySize {
                VStack(spacing: 14) {
                    clubCard
                    activitiesCard
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        clubCard.frame(minWidth: 315)
                        activitiesCard.frame(minWidth: 315)
                    }
                    VStack(spacing: 14) {
                        clubCard
                        activitiesCard
                    }
                }
            }

            invitationsCard
        }
        .accessibilityIdentifier("athlth-ipad-home-community")
        .task(id: session.signedIn ? session.profile.userID.uuidString : "") {
            guard session.signedIn else { return }
            // Existing refreshes are bounded and cached. No independent
            // public-club search or repeated network request per row.
            await groups.refresh(force: false)
            guard !Task.isCancelled else { return }
            await groups.refreshCalendarContent()
            guard !Task.isCancelled else { return }
            await social.refreshIfStale(challengeStore: challenges)
        }
    }

    private var clubCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                tr("My clubs", "Mine klubber"),
                detail: tr(
                    "\(groups.joinedGroupIDs.count) memberships",
                    "\(groups.joinedGroupIDs.count) medlemskap"
                ),
                symbol: "person.3",
                action: { onOpenCommunity(.clubs) }
            )

            if myClubs.isEmpty {
                Label(
                    tr("You have not joined a club yet.", "Du er ikke medlem av en klubb ennå."),
                    systemImage: "person.3.sequence"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                ForEach(myClubs) { club in
                    Button { onOpenCommunity(.clubs) } label: {
                        HStack(spacing: 10) {
                            symbolTile("person.3.fill")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(club.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                Text(club.locationName.isEmpty
                                    ? tr("My club", "Min klubb") : club.locationName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 43)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(outline.opacity(0.65)).frame(height: 1)

            HStack(spacing: 8) {
                Text(tr("Discover public clubs", "Finn offentlige klubber"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
            }

            if suggestedClubs.isEmpty {
                Text(tr(
                    "Explore available clubs and join a training community.",
                    "Utforsk tilgjengelige klubber og bli med i et treningsfellesskap."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(suggestedClubs) { club in
                    Button { onOpenCommunity(.clubs) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(gold)
                            Text(club.name)
                                .font(.subheadline)
                                .foregroundStyle(ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(tr("Explore", "Utforsk"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(gold)
                        }
                        .frame(minHeight: 38)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            actionLink(tr("See all clubs", "Se alle klubber"), symbol: "arrow.up.right") {
                onOpenCommunity(.clubs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(outline.opacity(0.55), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private var activitiesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                tr("Events", "Arrangementer"),
                detail: tr("Coming up in your clubs", "Kommende i klubbene dine"),
                symbol: "calendar",
                action: { onOpenCommunity(.events) }
            )

            if nextEvents.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    symbolTile("calendar.badge.plus")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("No upcoming club events", "Ingen kommende klubbarrangementer"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                        Text(tr(
                            "See other public events in Community.",
                            "Oppdag flere åpne arrangementer i Fellesskap."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 5)
            } else {
                ForEach(nextEvents) { event in
                    Button { onOpenCommunity(.events) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            symbolTile("calendar")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(2)
                                Text(event.startsAt.formatted(
                                    .dateTime.weekday(.wide).day().month(.abbreviated).hour().minute()
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(gold)
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(outline.opacity(0.65)).frame(height: 1)

            HStack(spacing: 11) {
                symbolTile("figure.run")
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Train together", "Tren sammen"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(social.mutualFollows.isEmpty
                        ? tr("Find a training partner", "Finn noen å trene med")
                        : tr(
                            "\(social.mutualFollows.count) training friends",
                            "\(social.mutualFollows.count) treningsvenner"
                        ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            actionLink(tr("Find a workout or partner", "Finn økt eller treningspartner"),
                       symbol: "arrow.up.right") {
                onOpenTrainTogether()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(outline.opacity(0.55), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private var invitationsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                symbolTile("envelope.badge")
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Invitations and challenges", "Invitasjoner og utfordringer"))
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text(tr(
                        "Only invitations that are still awaiting a response",
                        "Kun invitasjoner som fortsatt venter på svar"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !clubInvites.isEmpty || !challengeInvites.isEmpty {
                    Text("\(clubInvites.count + challengeInvites.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(canvas, in: Capsule())
                        .accessibilityLabel(tr(
                            "\(clubInvites.count + challengeInvites.count) pending invitations",
                            "\(clubInvites.count + challengeInvites.count) ventende invitasjoner"
                        ))
                }
            }

            if clubInvites.isEmpty && challengeInvites.isEmpty {
                Text(tr(
                    "No pending invitations. Explore challenges or join a club.",
                    "Ingen ventende invitasjoner. Utforsk utfordringer eller bli med i en klubb."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                ForEach(Array(clubInvites.prefix(2)), id: \.groupID) { invite in
                    Button { onOpenCommunity(.clubs) } label: {
                        inviteRow(
                            tr("Club invitation", "Klubbinvitasjon"),
                            subtitle: groups.groups.first(where: { $0.id == invite.groupID })?.name
                                ?? tr("Open club invitation", "Åpne klubbinvitasjonen"),
                            symbol: "person.3"
                        )
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(challengeInvites.prefix(2))) { challenge in
                    Button { onOpenCommunity(.arena) } label: {
                        inviteRow(
                            tr("Challenge invitation", "Utfordringsinvitasjon"),
                            subtitle: challenge.title,
                            symbol: "trophy"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    actionLink(tr("Explore challenges", "Utforsk utfordringer"),
                               symbol: "trophy") {
                        onOpenCommunity(.arena)
                    }
                    actionLink(tr("All invitations", "Alle invitasjoner"),
                               symbol: "arrow.up.right") {
                        onOpenCommunity(clubInvites.isEmpty ? .arena : .clubs)
                    }
                }
                VStack(spacing: 8) {
                    actionLink(tr("Explore challenges", "Utforsk utfordringer"),
                               symbol: "trophy") {
                        onOpenCommunity(.arena)
                    }
                    actionLink(tr("All invitations", "Alle invitasjoner"),
                               symbol: "arrow.up.right") {
                        onOpenCommunity(clubInvites.isEmpty ? .arena : .clubs)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(outline.opacity(0.55), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private func symbolTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(gold)
            .frame(width: 40, height: 40)
            .background(canvas, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private func cardHeader(
        _ title: String, detail: String, symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            symbolTile(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(gold)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Open \(title)", "Åpne \(title)"))
        }
    }

    private func inviteRow(
        _ title: String, subtitle: String, symbol: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(gold)
                Text(subtitle).font(.subheadline).foregroundStyle(ink).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func actionLink(
        _ title: String, symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(gold)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum ATHLTHStudioHomeCommunityDisplayPolicy {
    static func isDiscoverable(
        visibility: String, isMember: Bool, hasPendingInvitation: Bool
    ) -> Bool {
        visibility == "public" && !isMember && !hasPendingInvitation
    }

    static func isUpcoming(
        status: String, start: Date, now: Date
    ) -> Bool {
        start >= now && !["cancelled", "draft", "completed"].contains(status)
    }
}
