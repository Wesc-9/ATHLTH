import SwiftUI

enum ATHLTHTheme {
    static let cornerRadius: CGFloat = 24
    static let smallCornerRadius: CGFloat = 16
    static let contentSpacing: CGFloat = 16
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
    var tint: Color = .green

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
