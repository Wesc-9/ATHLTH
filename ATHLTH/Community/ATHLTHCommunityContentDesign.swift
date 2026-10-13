import SwiftUI

/// A shared content identity for Club events and Club challenges.
/// Presentation is shared; RSVP and competition rules deliberately remain separate.
enum ATHLTHCommunityContentKind {
    case publicEvent
    case event
    case challenge
    case trainTogether

    var localizedTitle: String {
        switch self {
        case .publicEvent:
            ATHLTHLocalization.choose(
                english: "Community event",
                norwegian: "Arrangement"
            )
        case .event:
            ATHLTHLocalization.choose(
                english: "Club event",
                norwegian: "Klubbarrangement"
            )
        case .challenge:
            ATHLTHLocalization.choose(
                english: "Club challenge",
                norwegian: "Klubbutfordring"
            )
        case .trainTogether:
            ATHLTHLocalization.choose(
                english: "Train together", norwegian: "Tren sammen"
            )
        }
    }

    var symbol: String {
        switch self {
        case .publicEvent: "calendar"
        case .event: "calendar.badge.clock"
        case .challenge: "trophy"
        case .trainTogether: "figure.run.circle"
        }
    }
}

/// Uses exactly the Training Plan palette and density, not a second
/// independently evolving Community visual language.
struct ATHLTHCommunityContextRibbon: View {
    let kind: ATHLTHCommunityContentKind
    let groupName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ATHLTHPlanDesign.accent)
                .frame(width: 40, height: 40)
                .background(ATHLTHPlanDesign.selectedSurface, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.localizedTitle.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                Text(groupName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .accessibilityElement(children: .combine)
    }
}

enum ATHLTHCommunityChallengeEditingPolicy {
    /// Once the start time has passed, rules and targets must remain stable
    /// for competitors. Server-side permissions still remain authoritative.
    static func canEdit(
        status: CommunityGroupContentStatus,
        startsAt: Date,
        now: Date = Date()
    ) -> Bool {
        (status == .draft || status == .upcoming) && startsAt > now
    }
}
