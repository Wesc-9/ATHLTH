import SwiftUI

/// Premium training ring + compact online dot.
/// Both indicators are strictly reserved for mutual followers; the server
/// also enforces this independently through RLS.
struct ATHLTHSocialStatusAvatar: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    let profile: SocialProfileCard
    let size: CGFloat

    private var mutual: Bool {
        social.isMutualFollow(profile.userID)
    }

    private var training: Bool {
        mutual && realtime.isTrainingNow(profile.userID)
    }

    private var online: Bool {
        mutual && realtime.isOnline(profile.userID)
    }

    var body: some View {
        SocialAvatar(profile: profile, size: size)
            .padding(training ? 4 : 0)
            .overlay {
                if training {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.72, blue: 0.35),
                                    Color(red: 0.87, green: 0.46, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if online {
                    Circle()
                        .fill(Color(red: 0.24, green: 0.68, blue: 0.37))
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle().stroke(.white, lineWidth: 2)
                        }
                        .offset(x: 2, y: 1)
                }
            }
            .accessibilityLabel(
                profile.resolvedName + (
                    training
                        ? ATHLTHLocalization.choose(
                            english: ", training now",
                            norwegian: ", trener nå"
                        )
                        : online
                            ? ATHLTHLocalization.choose(
                                english: ", online",
                                norwegian: ", pålogget"
                            )
                            : ""
                )
            )
    }
}
