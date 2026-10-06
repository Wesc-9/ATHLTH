import SwiftUI

struct ATHLTHConversationHero<
    Avatar: View,
    Trailing: View
>: View {
    let title: String
    let subtitle: String
    let backgroundAsset: String
    let onBack: () -> Void

    private let avatar: Avatar
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        backgroundAsset: String = "GoalMountain",
        onBack: @escaping () -> Void,
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backgroundAsset = backgroundAsset
        self.onBack = onBack
        self.avatar = avatar()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Image(backgroundAsset)
                .resizable()
                .scaledToFill()
                // GoalMountain has a small baked presentation margin.
                // Crop into it so the chat hero is always full-bleed.
                .scaleEffect(1.14)
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 214)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black
                        .opacity(0.34),
                    Color.black
                        .opacity(0.06),
                    Color.black
                        .opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 10) {
                Button(
                    action: onBack
                ) {
                    Image(
                        systemName:
                            "chevron.left"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        Color.black
                            .opacity(0.16),
                        in: Circle()
                    )
                    .background(
                        .ultraThinMaterial,
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white
                                    .opacity(0.34),
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(.plain)

                avatar
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .shadow(
                        color:
                            Color.black
                                .opacity(0.12),
                        radius: 7,
                        y: 3
                    )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(title)
                        .font(
                            .title3
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            .white
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.78
                        )

                    Text(subtitle)
                        .font(
                            .subheadline
                        )
                        .foregroundStyle(
                            Color.white
                                .opacity(0.88)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.80
                        )
                }
                .shadow(
                    color:
                        Color.black
                            .opacity(0.28),
                    radius: 5,
                    y: 2
                )

                Spacer(
                    minLength: 8
                )

                trailing
                    .frame(
                        width: 42,
                        height: 42
                    )
            }
            .padding(
                .horizontal,
                14
            )
            .padding(
                .top,
                14
            )
        }
        .frame(height: 214)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.34),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.09),
            radius: 15,
            y: 7
        )
    }
}

extension View {
    func athlthConversationPanelChrome()
        -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        Color.white
                            .opacity(0.97),
                        ATHLTHTheme
                            .cardWarm
                            .opacity(0.76)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
            )
            .overlay(
                alignment: .top
            ) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
                .stroke(
                    Color.white
                        .opacity(0.78),
                    lineWidth: 0.8
                )
            }
    }

    func athlthConversationComposerChrome()
        -> some View {
        self
            .background(
                .ultraThinMaterial
            )
            .overlay(
                alignment: .top
            ) {
                Rectangle()
                    .fill(
                        Color.white
                            .opacity(0.66)
                    )
                    .frame(height: 0.8)
            }
    }
}
