import SwiftUI

/// Native artwork asset. Only the photographic stadium background is bundled;
/// all identity, messaging, buttons and text remain native SwiftUI.
/// Asset provenance: stadium photograph by Heber Vazquez (Pexels),
/// https://www.pexels.com/photo/stands-by-running-track-at-stadium-19753619/
/// Attribution stays with the source instead of appearing as a chat action.
enum ATHLTHConversationArtwork {
    static let directMessageHeader = "ConversationStadiumHero"
}

/// Compact gold-branded title shared by message and attachment pickers.
/// Visual photography, when selected, remains a separate asset decision.
struct ATHLTHMessagingCompactHeader: View {
    let eyebrow: String
    let title: String
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(ATHLTHTheme.premiumGold)

                Text(title)
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .minimumScaleFactor(0.78)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(ATHLTHTheme.premiumGold)
                .frame(width: 55, height: 55)
                .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.champagneSoft,
                            ATHLTHTheme.premiumGoldSoft
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(ATHLTHTheme.premiumGold.opacity(0.24), lineWidth: 1)
                }
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct ATHLTHConversationHero<
    Avatar: View,
    Trailing: View
>: View {
    let title: String
    let subtitle: String
    let backgroundAsset: String?
    let onBack: () -> Void
    let onProfileTap: (() -> Void)?

    private let avatar: Avatar
    private let trailing: Trailing

    private let heroHeight: CGFloat = 252

    init(
        title: String,
        subtitle: String,
        backgroundAsset: String? = nil,
        onBack: @escaping () -> Void,
        onProfileTap: (() -> Void)? = nil,
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backgroundAsset = backgroundAsset
        self.onBack = onBack
        self.onProfileTap = onProfileTap
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
                if let backgroundAsset {
                    // Preserve photographic resolution: aspect-fill at the
                    // view's exact display size, no thumbnail or screenshots.
                    Image(backgroundAsset)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: heroHeight)
                        .clipped()
                        .accessibilityHidden(true)
                } else {
                    // Conversation headers should not borrow the library's
                    // mountain hero. Use restrained brand tones instead.
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.accentDeep,
                            Color(red: 0.28, green: 0.29, blue: 0.31),
                            ATHLTHPlanDesign.outgoingMessage
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: proxy.size.width, height: heroHeight)
                    .overlay(alignment: .bottomTrailing) {
                        ATHLTHMarkShape()
                            .fill(ATHLTHTheme.champagne.opacity(0.13))
                            .frame(width: 180, height: 126)
                            .offset(x: 24, y: 16)
                            .accessibilityHidden(true)
                    }
                }

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

                    Button {
                        onProfileTap?()
                    } label: {
                        HStack(spacing: 10) {
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
    
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(onProfileTap == nil)
                    .accessibilityLabel(
                        onProfileTap == nil ? title :
                            ATHLTHLocalization.choose(
                                english: "\(title) · View profile",
                                norwegian: "\(title) · Vis profil"
                            )
                    )

                    Spacer(
                        minLength: 8
                    )

                    trailing
                        .frame(
                            width: 48,
                            height: 48
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
