import SwiftUI

enum ATHLTHBrandSize {
    case compact
    case watch
    case standard

    var markWidth: CGFloat {
        switch self {
        case .compact: return 28
        case .watch: return 34
        case .standard: return 44
        }
    }

    var markHeight: CGFloat {
        switch self {
        case .compact: return 19
        case .watch: return 23
        case .standard: return 30
        }
    }

    var wordmarkSize: CGFloat {
        switch self {
        case .compact: return 12
        case .watch: return 11
        case .standard: return 15
        }
    }

    var tracking: CGFloat {
        switch self {
        case .compact: return 3.2
        case .watch: return 3.0
        case .standard: return 4.2
        }
    }
}

struct ATHLTHMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let strokeWidth = max(rect.width * 0.16, 2)
        let inset = strokeWidth / 2

        path.move(to: CGPoint(x: inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.midX, y: inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))

        return path.strokedPath(
            .init(
                lineWidth: strokeWidth,
                lineCap: .butt,
                lineJoin: .miter
            )
        )
    }
}

struct ATHLTHBrandMark: View {
    var size: ATHLTHBrandSize = .standard
    var showTagline = false

    var body: some View {
        VStack(spacing: size == .watch ? 2 : 3) {
            ATHLTHMarkShape()
                .fill(Color.primary)
                .frame(width: size.markWidth, height: size.markHeight)
                .accessibilityHidden(true)

            Text("VTHLTH")
                .font(.system(size: size.wordmarkSize, weight: .black))
                .tracking(size.tracking)
                .lineLimit(1)
                .fixedSize()

            if showTagline {
                Text("MOVE BETTER   LIVE LONGER")
                    .font(.system(size: 6.5, weight: .semibold))
                    .tracking(1.55)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ATHLTH")
    }
}
