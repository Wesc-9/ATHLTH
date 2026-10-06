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

    private let heroHeight: CGFloat = 252

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
        GeometryReader { proxy in
            let safeTop =
                max(
                    proxy.safeAreaInsets.top,
                    48
                )

            ZStack(
                alignment: .top
            ) {
                Image(backgroundAsset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    // Keep the hero bound to the actual screen width.
                    // Without an explicit width, wide artwork can enlarge
                    // the whole conversation layout before clipping.
                    .frame(
                        width: proxy.size.width,
                        height: heroHeight
                    )
                    .scaleEffect(
                        1.08,
                        anchor: .center
                    )
                    .clipped()
                    .allowsHitTesting(false)

                LinearGradient(
                    stops: [
                        .init(
                            color:
                                Color.black
                                    .opacity(0.34),
                            location: 0
                        ),
                        .init(
                            color:
                                Color.black
                                    .opacity(0.08),
                            location: 0.46
                        ),
                        .init(
                            color:
                                Color.black
                                    .opacity(0.22),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

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
                                .opacity(0.18),
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
                                        .opacity(
                                            0.30
                                        ),
                                    lineWidth:
                                        0.8
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
                                    .opacity(
                                        0.16
                                    ),
                            radius: 7,
                            y: 3
                        )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(title)
                            .font(
                                .headline
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
                            .font(.caption)
                            .foregroundStyle(
                                Color.white
                                    .opacity(
                                        0.88
                                    )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(
                                0.80
                            )
                    }
                    .shadow(
                        color:
                            Color.black
                                .opacity(0.30),
                        radius: 5,
                        y: 2
                    )
                    .layoutPriority(1)

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
                // Places the conversation identity directly below the
                // Dynamic Island / status area while the artwork itself
                // remains full bleed all the way to the top edge.
                .padding(
                    .top,
                    safeTop + 10
                )
            }
            .frame(
                width: proxy.size.width,
                height: heroHeight
            )
            .clipped()
        }
        .frame(height: heroHeight)
        .clipped()
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
                            .opacity(0.995),
                        Color.white
                            .opacity(0.965),
                        ATHLTHTheme
                            .cardWarm
                            .opacity(0.28)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 32,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 32,
                    style: .continuous
                )
            )
            .overlay(
                alignment: .top
            ) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 32,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 32,
                    style: .continuous
                )
                .stroke(
                    Color.white
                        .opacity(0.92),
                    lineWidth: 1
                )
            }
            .shadow(
                color:
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.08),
                radius: 18,
                x: 0,
                y: -3
            )
    }

    func athlthConversationComposerChrome()
        -> some View {
        self
            .background(
                Color.white
                    .opacity(0.92)
            )
            .background(
                .ultraThinMaterial
            )
            .overlay(
                alignment: .top
            ) {
                Rectangle()
                    .fill(
                        Color.black
                            .opacity(0.055)
                    )
                    .frame(height: 0.7)
            }
    }
}
