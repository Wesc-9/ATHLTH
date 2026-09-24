import SwiftUI

enum ATHLTHTheme {
    static let cornerRadius: CGFloat = 24
    static let smallCornerRadius: CGFloat = 16
    static let contentSpacing: CGFloat = 16

    // ATHLTH brand palette.
    // Slate is the primary interactive accent across iPhone and Apple Watch.
    // Champagne is reserved for ATHLTH+ / premium moments.
    static let accent = Color(red: 0.29, green: 0.34, blue: 0.43)
    static let accentDeep = Color(red: 0.20, green: 0.24, blue: 0.31)
    static let accentSoft = accent.opacity(0.10)
    static let premiumGold = Color(red: 0.72, green: 0.55, blue: 0.31)
    static let premiumGoldSoft = premiumGold.opacity(0.14)

    static let canvasTop = Color(red: 0.992, green: 0.989, blue: 0.984)
    static let canvasBottom = Color(red: 0.968, green: 0.964, blue: 0.958)
    static let card = Color.white.opacity(0.96)
    static let primaryText = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let mutedText = Color(red: 0.43, green: 0.46, blue: 0.53)
    static let border = Color.black.opacity(0.055)
    static let divider = Color.black.opacity(0.065)
}

struct ATHLTHCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ATHLTHTheme.cornerRadius))
    }
}

struct ATHLTHSectionHeader: View {
    let title: String
    var actionTitle: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let actionTitle {
                Text(actionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ATHLTHMetric: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = ATHLTHTheme.accent

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.title3)
            Text(value)
                .font(.title3.weight(.bold))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ATHLTHProgressRing: View {
    let title: String
    let value: String
    let progress: Double
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(value)
                        .font(.headline.weight(.bold))
                }
            }
            .frame(width: 92, height: 92)

            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ATHLTHPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ATHLTH")
                .font(.title3.weight(.black))
                .tracking(6)
            Text("MOVE BETTER · LIVE LONGER")
                .font(.caption2.weight(.medium))
                .tracking(2)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 8)

            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct ATHLTHTabHero: View {
    let imageName: String
    let title: String
    let subtitle: String
    var height: CGFloat = 190
    var alignment: Alignment = .leading
    var focalOffsetX: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: alignment
                    )
                    .scaleEffect(1.08)
                    .offset(x: focalOffsetX)
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.48),
                        Color.black.opacity(0.16),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.20),
                        Color.clear,
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text("ATHLTH")
                        .font(.system(size: 17, weight: .black))
                        .tracking(5.5)

                    Text("MOVE BETTER · LIVE LONGER")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.7)
                        .padding(.top, 2)

                    Spacer(minLength: 12)

                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.subheadline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .padding(.top, 2)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.30), radius: 5, x: 0, y: 2)
                .padding(.leading, 20)
                .padding(.trailing, 18)
                .padding(.top, 48)
                .padding(.bottom, 16)
                .frame(
                    maxWidth: proxy.size.width * 0.74,
                    maxHeight: .infinity,
                    alignment: .leading
                )
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
