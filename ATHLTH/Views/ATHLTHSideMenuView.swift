import SwiftUI

/// A light, premium slide-out menu that lives above the existing root tabs.
/// It does not create parallel copies of ATHLTH's workout or social screens.
struct ATHLTHSideMenuView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedTab: Int
    let onSelect: (ATHLTHSideMenuDestination) -> Void
    let onDismiss: () -> Void

    private let menuSurface = Color(red: 0.992, green: 0.984, blue: 0.969)
    private let warmDivider = Color(red: 0.84, green: 0.78, blue: 0.67).opacity(0.28)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button(action: onDismiss) {
                    Color.black.opacity(0.49)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close navigation menu",
                    norwegian: "Lukk sidemenyen"
                ))

                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 22)
                        .padding(.top, 10)

                    Rectangle()
                        .fill(warmDivider)
                        .frame(height: 1)
                        .padding(.horizontal, 22)
                        .padding(.top, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            menuSection(
                                english: "OVERVIEW",
                                norwegian: "OVERSIKT"
                            ) {
                                menuRow(.home, english: "Home", norwegian: "Hjem", icon: "house", selected: selectedTab == 0)
                                menuRow(.calendar, english: "Calendar", norwegian: "Kalender", icon: "calendar")
                                menuRow(.insights, english: "Insights", norwegian: "Innsikt", icon: "chart.xyaxis.line", selected: selectedTab == 2)
                            }

                            menuSection(
                                english: "TRAINING",
                                norwegian: "TRENING"
                            ) {
                                menuRow(.train, english: "Train", norwegian: "Tren", icon: "dumbbell", selected: selectedTab == 1)
                                menuRow(.plans, english: "Training plans", norwegian: "Treningsplaner", icon: "square.stack.3d.up")
                                menuRow(.explore, english: "Routes & explore", norwegian: "Ruter og Explore", icon: "map", selected: selectedTab == 3)
                            }

                            menuSection(
                                english: "COMMUNITY",
                                norwegian: "FELLESSKAP"
                            ) {
                                menuRow(.community, english: "Community", norwegian: "Fellesskap", icon: "person.3", selected: selectedTab == 4)
                                menuRow(.profile, english: "My profile & gear", norwegian: "Min profil og utstyr", icon: "person.crop.circle")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 24)
                    }
                    .scrollIndicators(.hidden)

                    footer
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
                .frame(
                    width: min(max(geometry.size.width * 0.84, 270), 390),
                    height: geometry.size.height
                )
                .background {
                    menuSurface
                        .ignoresSafeArea(edges: .vertical)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 25,
                        topTrailingRadius: 25
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 22, x: 9, y: 0)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("ATHLTH")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer(minLength: 10)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.045), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close navigation menu",
                    norwegian: "Lukk sidemenyen"
                ))
            }

            Button {
                onSelect(.profile)
            } label: {
                HStack(spacing: 13) {
                    profileImage

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.profile.displayName.isEmpty
                             ? "ATHLTH"
                             : session.profile.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(2)

                        if !session.profile.username.isEmpty {
                            Text("@\(session.profile.username)")
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .lineLimit(1)
                        }

                        Text(ATHLTHLocalization.choose(
                            english: "View my profile",
                            norwegian: "Se min profil"
                        ))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .frame(minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Open my ATHLTH profile",
                norwegian: "Åpne ATHLTH-profilen min"
            ))
        }
    }

    @ViewBuilder
    private var profileImage: some View {
        Group {
            if let avatarURL = session.profile.avatarURL {
                ATHLTHStorageImage(url: avatarURL, maxPixelSize: 160) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        profilePlaceholder
                    }
                }
            } else {
                profilePlaceholder
            }
        }
        .frame(width: 66, height: 66)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(ATHLTHTheme.premiumGold.opacity(0.68), lineWidth: 1.5)
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(ATHLTHTheme.premiumGoldSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
    }

    private func menuSection<Content: View>(
        english: String,
        norwegian: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ATHLTHLocalization.choose(
                english: english,
                norwegian: norwegian
            ))
            .font(.caption.weight(.semibold))
            .tracking(2)
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .padding(.leading, 13)

            VStack(spacing: 2, content: content)
        }
    }

    private func menuRow(
        _ destination: ATHLTHSideMenuDestination,
        english: String,
        norwegian: String,
        icon: String,
        selected: Bool = false
    ) -> some View {
        Button {
            onSelect(destination)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .accessibilityHidden(true)

                Text(ATHLTHLocalization.choose(
                    english: english, norwegian: norwegian
                ))
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 58 : 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(ATHLTHTheme.premiumGoldSoft.opacity(0.8))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(warmDivider)
                .frame(height: 1)

            Button {
                onSelect(.settings)
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Settings",
                        norwegian: "Innstillinger"
                    ),
                    systemImage: "gearshape"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 49)
                .foregroundStyle(.white)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            .buttonStyle(.plain)

            Text("YOUR BODY. YOUR DATA. YOUR PROGRESS.")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
