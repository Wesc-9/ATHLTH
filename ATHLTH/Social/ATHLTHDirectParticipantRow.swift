import SwiftUI

/// The same locked, single-recipient presentation is used when starting a
/// direct Challenge or Train Together flow from a friend's profile.
struct ATHLTHDirectParticipantRow: View {
    let recipient: SocialProfileCard?
    let fallbackTitle: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            if let recipient {
                SocialAvatar(profile: recipient, size: 38)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(recipient?.resolvedName ?? fallbackTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: "lock.shield.fill")
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.accent)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Recipient locked", norwegian: "Mottaker låst"
                ))
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
