import SwiftUI

/// Compact profile-only record shelf. Editing and record values remain owned
/// by the existing record catalogue and picker.
struct ATHLTHProfileRecordShelf<Content: View>: View {
    let destination: AnyView
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "rosette")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 33, height: 33)
                    .background(
                        ATHLTHTheme.premiumGoldSoft.opacity(0.58),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(ATHLTHLocalization.choose(
                        english: "YOUR BEST", norwegian: "DINE BESTE"
                    ))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                    Text(ATHLTHLocalization.choose(
                        english: "Personal records", norwegian: "Personlige rekorder"
                    ))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                }

                Spacer(minLength: 8)

                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: 4) {
                        Text(ATHLTHLocalization.choose(english: "See all", norwegian: "Se alle"))
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            content
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.98),
                    ATHLTHTheme.premiumGoldSoft.opacity(0.17)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 21, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(ATHLTHTheme.premiumGold.opacity(0.17), lineWidth: 0.8)
        }
    }
}
