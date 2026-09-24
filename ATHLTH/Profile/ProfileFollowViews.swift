import SwiftUI

enum ProfileFollowListMode: String, Identifiable {
    case followers
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
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
        List {
            if profiles.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: mode == .followers ? "person.2" : "person.crop.circle.badge.checkmark",
                    description: Text(emptyDetail)
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(profiles) { profile in
                    HStack(spacing: 10) {
                        NavigationLink {
                            FriendProfileView(userID: profile.userID)
                        } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(profile: profile, size: 46)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.resolvedName)
                                        .font(.subheadline.weight(.semibold))

                                    Text(profile.usernameLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if mode == .following {
                            Button("Following") {
                                Task { await social.unfollow(profile.userID) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            if expectedCount > profiles.count {
                Text(
                    "\(expectedCount - profiles.count) private profile\(expectedCount - profiles.count == 1 ? "" : "s") are included in the count but are not available to open."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await social.refresh()
        }
        .refreshable {
            await social.refresh()
        }
    }

    private var emptyTitle: String {
        switch mode {
        case .followers: return "No followers yet"
        case .following: return "Not following anyone yet"
        }
    }

    private var emptyDetail: String {
        switch mode {
        case .followers:
            return "People who follow your ATHLTH profile will appear here."
        case .following:
            return "Profiles you follow will appear here."
        }
    }
}
