import SwiftUI

enum ATHLTHBrandSize {
    case compact
    case watch
    case standard

    var markWidth: CGFloat {
        switch self {
        case .compact: return 30
        case .watch: return 36
        case .standard: return 48
        }
    }

    var markHeight: CGFloat {
        switch self {
        case .compact: return 22
        case .watch: return 26
        case .standard: return 34
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
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * x,
                y: rect.minY + rect.height * y
            )
        }

        var path = Path()

        // Left ribbon.
        path.move(to: p(0.04, 1.00))
        path.addLine(to: p(0.50, 0.00))
        path.addLine(to: p(0.61, 0.24))
        path.addLine(to: p(0.27, 1.00))
        path.closeSubpath()

        // Right ribbon with the slightly inset top edge that gives the
        // ATHLTH mark its folded-paper construction.
        path.move(to: p(0.50, 0.00))
        path.addLine(to: p(0.96, 1.00))
        path.addLine(to: p(0.73, 1.00))
        path.addLine(to: p(0.43, 0.34))
        path.closeSubpath()

        return path
    }
}

private struct ATHLTHFoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * x,
                y: rect.minY + rect.height * y
            )
        }

        var path = Path()
        path.move(to: p(0.55, 0.20))
        path.addLine(to: p(0.69, 0.49))
        path.addLine(to: p(0.61, 0.67))
        path.addLine(to: p(0.47, 0.37))
        path.closeSubpath()
        return path
    }
}

struct ATHLTHBrandMark: View {
    var size: ATHLTHBrandSize = .standard
    var showTagline = false

    var body: some View {
        VStack(spacing: size == .watch ? 2 : 3) {
            ZStack {
                ATHLTHMarkShape()
                    .fill(Color.primary)

                ATHLTHFoldShape()
                    .fill(Color.black.opacity(0.34))
            }
            .frame(width: size.markWidth, height: size.markHeight)
            .accessibilityHidden(true)

            Text("ATHLTH")
                .font(.system(size: size.wordmarkSize, weight: .black))
                .tracking(size.tracking)
                .lineLimit(1)
                .fixedSize()

            if showTagline {
                Text("PROGRESS LIVES HERE.")
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
