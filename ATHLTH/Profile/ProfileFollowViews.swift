import SwiftUI

enum ProfileFollowListMode: String, Identifiable {
    case followers
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followers:
            return ATHLTHLocalization.choose(
                english: "Followers",
                norwegian: "Følgere"
            )
        case .following:
            return ATHLTHLocalization.choose(
                english: "Following",
                norwegian: "Følger"
            )
        }
    }
}

struct ProfileFollowListView: View {
    @EnvironmentObject private var social: SocialStore

    let mode: ProfileFollowListMode

    private var profiles: [SocialProfileCard] {
        switch mode {
        case .followers: return social.followers
        case .following: return social.following
        }
    }

    private var expectedCount: Int {
        switch mode {
        case .followers: return social.followerCount
        case .following: return social.followingCount
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 14
            ) {
                premiumSummary

                if profiles.isEmpty {
                    premiumEmptyState
                } else {
                    ForEach(profiles) { profile in
                        premiumProfileRow(profile)
                    }
                }

                if expectedCount > profiles.count {
                    privateProfilesNote
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background {
            LinearGradient(
                colors: [
                    Color(
                        red: 0.965,
                        green: 0.965,
                        blue: 0.982
                    ),
                    Color(
                        red: 0.985,
                        green: 0.980,
                        blue: 0.970
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            .ultraThinMaterial,
            for: .navigationBar
        )
        .toolbarBackground(
            .visible,
            for: .navigationBar
        )
        .task {
            await social.refresh()
        }
        .refreshable {
            await social.refresh()
        }
    }

    private var premiumSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.12)
                    )

                Image(
                    systemName:
                        mode == .followers
                            ? "person.2.fill"
                            : "person.crop.circle.badge.checkmark"
                )
                .font(
                    .system(
                        size: 20,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.premiumGold
                )
            }
            .frame(width: 48, height: 48)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(mode.title)
                    .font(
                        .title3
                            .weight(.bold)
                    )

                Text(summaryDetail)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }

            Spacer()

            Text(expectedCount.formatted())
                .font(
                    .system(
                        size: 24,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.13),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 18,
            y: 8
        )
    }

    private var premiumEmptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.09)
                    )
                    .frame(
                        width: 76,
                        height: 76
                    )

                Image(
                    systemName:
                        mode == .followers
                            ? "person.2"
                            : "person.crop.circle.badge.checkmark"
                )
                .font(
                    .system(
                        size: 30,
                        weight: .light
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
            }

            Text(emptyTitle)
                .font(
                    .title3
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Text(emptyDetail)
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
        .background(
            Color.white.opacity(0.84),
            in: RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
    }

    private func premiumProfileRow(
        _ profile: SocialProfileCard
    ) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                FriendProfileView(
                    userID: profile.userID
                )
            } label: {
                HStack(spacing: 12) {
                    SocialAvatar(
                        profile: profile,
                        size: 50
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(profile.resolvedName)
                            .font(
                                .subheadline
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                            .lineLimit(1)

                        Text(profile.usernameLabel)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                    }

                    Spacer(minLength: 6)

                    Image(
                        systemName: "chevron.right"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                            .opacity(0.55)
                    )
                }
            }
            .buttonStyle(.plain)

            if mode == .following {
                Button {
                    Task {
                        await social.unfollow(
                            profile.userID
                        )
                    }
                } label: {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Following",
                            norwegian: "Følger"
                        )
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .background(
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.10),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            ATHLTHTheme
                                .premiumGold
                                .opacity(0.18),
                            lineWidth: 0.8
                        )
                }
            }
        }
        .padding(14)
        .background(
            Color.white.opacity(0.92),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.75),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.035),
            radius: 12,
            y: 5
        )
    }

    private var privateProfilesNote: some View {
        Label(
            privateProfilesDetail,
            systemImage: "lock.fill"
        )
        .font(.caption)
        .foregroundStyle(
            ATHLTHTheme.mutedText
        )
        .padding(.horizontal, 4)
    }

    private var summaryDetail: String {
        switch mode {
        case .followers:
            return ATHLTHLocalization.choose(
                english:
                    "People following your ATHLTH profile",
                norwegian:
                    "Personer som følger ATHLTH-profilen din"
            )
        case .following:
            return ATHLTHLocalization.choose(
                english:
                    "Profiles you have chosen to follow",
                norwegian:
                    "Profiler du har valgt å følge"
            )
        }
    }

    private var emptyTitle: String {
        switch mode {
        case .followers:
            return ATHLTHLocalization.choose(
                english: "No followers yet",
                norwegian: "Ingen følgere ennå"
            )
        case .following:
            return ATHLTHLocalization.choose(
                english:
                    "Not following anyone yet",
                norwegian:
                    "Du følger ingen ennå"
            )
        }
    }

    private var emptyDetail: String {
        switch mode {
        case .followers:
            return ATHLTHLocalization.choose(
                english:
                    "People who follow your ATHLTH profile will appear here.",
                norwegian:
                    "Personer som følger ATHLTH-profilen din vises her."
            )
        case .following:
            return ATHLTHLocalization.choose(
                english:
                    "Profiles you follow will appear here.",
                norwegian:
                    "Profiler du følger vises her."
            )
        }
    }

    private var privateProfilesDetail: String {
        let count =
            expectedCount - profiles.count

        return ATHLTHLocalization.choose(
            english:
                "\(count) private profile\(count == 1 ? "" : "s") are included in the count but cannot be opened.",
            norwegian:
                "\(count) privat\(count == 1 ? "" : "e") profil\(count == 1 ? "" : "er") er med i antallet, men kan ikke åpnes."
        )
    }
}
