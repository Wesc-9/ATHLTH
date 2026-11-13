import SwiftUI

/// Responsive recent-workout feed layout. The media fills the card on
/// compact iPhones, while wide iPad windows show media and details side by side.
enum ATHLTHRecentActivityLayoutPolicy {
    static func isHorizontal(
        availableWidth: CGFloat,
        accessibilityText: Bool = false
    ) -> Bool {
        availableWidth >= 650 && !accessibilityText
    }

    static func artworkHeight(horizontal: Bool) -> CGFloat {
        horizontal ? 194 : 170
    }

    static func artworkWidth(for width: CGFloat, horizontal: Bool) -> CGFloat {
        horizontal ? width * 0.43 : width
    }
}

/// Keeps navigation links for the artwork and the author's profile separate.
/// No new image requests or route renderers are created by the layout.
struct ATHLTHRecentActivityCardLayout<Artwork: View, Details: View>: View {
    let availableWidth: CGFloat
    @ViewBuilder let artwork: Artwork
    @ViewBuilder let details: Details

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isHorizontal: Bool {
        ATHLTHRecentActivityLayoutPolicy.isHorizontal(
            availableWidth: availableWidth,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var mediaHeight: CGFloat {
        ATHLTHRecentActivityLayoutPolicy.artworkHeight(horizontal: isHorizontal)
    }

    var body: some View {
        Group {
            if isHorizontal {
                HStack(alignment: .center, spacing: 0) {
                    artwork
                        .frame(
                            width: ATHLTHRecentActivityLayoutPolicy.artworkWidth(
                                for: availableWidth,
                                horizontal: true
                            ),
                            height: mediaHeight
                        )
                        .clipped()

                    details
                        .padding(.horizontal, 17)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: mediaHeight,
                               alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    artwork
                        .frame(maxWidth: .infinity)
                        .frame(height: mediaHeight)
                        .clipped()

                    details
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.98),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.35), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }
}
