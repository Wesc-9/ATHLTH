import SwiftUI

/// A presentation-only agenda. The source records and their existing detail
/// screens stay authoritative; no migration or workout history rewrite needed.
struct ATHLTHCommunityAgendaEntry: Identifiable {
    enum Destination {
        case event(UUID)
        case clubEvent(group: CommunityGroupRecord, event: CommunityGroupEventRecord)
        case challenge(UUID)
    }

    let id: String
    let title: String
    let context: String
    let scheduledAt: Date
    let icon: String
    let destination: Destination

    @ViewBuilder
    var destinationView: some View {
        switch destination {
        case .event(let eventID):
            CommunityEventDetailView(eventID: eventID)
        case .clubEvent(let group, let event):
            CommunityGroupEventDetailView(group: group, event: event)
        case .challenge(let challengeID):
            ChallengeDetailView(challengeID: challengeID)
        }
    }
}

enum ATHLTHCommunityAgendaPolicy {
    static func includesClubEvent(
        startsAt: Date,
        status: String,
        creatorID: UUID,
        userID: UUID,
        rsvp: String?,
        now: Date
    ) -> Bool {
        guard startsAt >= now, status != "cancelled",
              status != "draft", status != "completed" else { return false }
        return creatorID == userID ||
            rsvp == "going" || rsvp == "maybe" || rsvp == "waitlist"
    }

    static func entries(
        events: [CommunityEventItem],
        clubEvents: [CommunityGroupEventRecord],
        clubRSVPs: [CommunityGroupEventRSVPRecord],
        clubs: [CommunityGroupRecord],
        challenges: [ATHLTHChallenge],
        userID: UUID,
        now: Date = Date()
    ) -> [ATHLTHCommunityAgendaEntry] {
        var result: [ATHLTHCommunityAgendaEntry] = []
        result.reserveCapacity(events.count + clubEvents.count + challenges.count)

        for item in events {
            let event = item.event
            guard event.status != "cancelled",
                  event.status != "completed",
                  event.startsAt >= now || event.status == "live" else {
                continue
            }
            result.append(ATHLTHCommunityAgendaEntry(
                id: "event:" + item.id.uuidString,
                title: item.event.title,
                context: ATHLTHLocalization.choose(
                    english: "Event", norwegian: "Arrangement"
                ),
                scheduledAt: max(item.event.startsAt, now),
                icon: "calendar",
                destination: .event(item.id)
            ))
        }

        let clubsByID = Dictionary(uniqueKeysWithValues: clubs.map { ($0.id, $0) })
        // Malformed or duplicate server rows should never crash Community.
        var rsvpByEvent: [UUID: String] = [:]
        for rsvp in clubRSVPs where rsvp.userID == userID {
            rsvpByEvent[rsvp.eventID] = rsvp.status
        }
        for event in clubEvents {
            guard let club = clubsByID[event.groupID],
                  includesClubEvent(
                    startsAt: event.startsAt,
                    status: event.status,
                    creatorID: event.creatorID,
                    userID: userID,
                    rsvp: rsvpByEvent[event.id],
                    now: now
                  ) else { continue }

            result.append(ATHLTHCommunityAgendaEntry(
                id: "club-event:" + event.id.uuidString,
                title: event.title,
                context: club.name,
                scheduledAt: event.startsAt,
                icon: "person.3.fill",
                destination: .clubEvent(group: club, event: event)
            ))
        }

        for challenge in challenges {
            guard challenge.status == .active ||
                    challenge.status == .upcoming else { continue }
            if let endsAt = challenge.rules.endsAt, endsAt < now {
                continue
            }
            result.append(ATHLTHCommunityAgendaEntry(
                id: "challenge:" + challenge.id.uuidString,
                title: challenge.title,
                context: ATHLTHLocalization.choose(
                    english: "Joined challenge",
                    norwegian: "Påmeldt utfordring"
                ),
                scheduledAt: max(challenge.rules.startsAt, now),
                icon: "trophy",
                destination: .challenge(challenge.id)
            ))
        }

        // Different domains may share an underlying ID: preserve source identity.
        return result.sorted {
            if $0.scheduledAt != $1.scheduledAt {
                return $0.scheduledAt < $1.scheduledAt
            }
            return $0.id < $1.id
        }
    }
}

struct ATHLTHCommunityAgendaView: View {
    let entries: [ATHLTHCommunityAgendaEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(ATHLTHLocalization.choose(
                    english: "Your upcoming activities",
                    norwegian: "Dine kommende aktiviteter"
                ))
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .padding(.top, 10)

                if entries.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "Nothing scheduled",
                            norwegian: "Ingenting planlagt"
                        ),
                        systemImage: "calendar",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Events and challenges you've joined will appear here.",
                            norwegian: "Arrangementer og utfordringer du deltar i vises her."
                        ))
                    )
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            entry.destinationView
                        } label: {
                            ATHLTHCommunityAgendaRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPremiumCanvas(accent: ATHLTHTheme.champagneSoft.opacity(0.16)))
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Upcoming", norwegian: "Kommende"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ATHLTHCommunityAgendaRow: View {
    let entry: ATHLTHCommunityAgendaEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ATHLTHPlanDesign.accent)
                .frame(width: 44, height: 44)
                .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.context.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .lineLimit(1)
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .lineLimit(2)
                Text(entry.scheduledAt.formatted(
                    .dateTime.day().month(.abbreviated).hour().minute()
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ATHLTHPlanDesign.surface,
            in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ATHLTHPlanDesign.cardRadius)
                .stroke(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
    }
}
