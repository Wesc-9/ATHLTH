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
        func p(
            _ x: CGFloat,
            _ y: CGFloat
        ) -> CGPoint {
            CGPoint(
                x:
                    rect.minX +
                    rect.width * x,
                y:
                    rect.minY +
                    rect.height * y
            )
        }

        let lineWidth =
            min(
                rect.width,
                rect.height
            ) * 0.155

        var centerline =
            Path()

        // 2026 pulse-A mark.
        centerline.move(
            to: p(0.08, 0.67)
        )
        centerline.addLine(
            to: p(0.28, 0.67)
        )
        centerline.addCurve(
            to: p(0.50, 0.08),
            control1:
                p(0.34, 0.67),
            control2:
                p(0.43, 0.20)
        )
        centerline.addCurve(
            to: p(0.72, 0.58),
            control1:
                p(0.57, 0.11),
            control2:
                p(0.64, 0.55)
        )
        centerline.addLine(
            to: p(0.84, 0.58)
        )

        centerline.move(
            to: p(0.49, 0.49)
        )
        centerline.addLine(
            to: p(0.59, 0.88)
        )
        centerline.addLine(
            to: p(0.69, 0.65)
        )
        centerline.addLine(
            to: p(0.92, 0.65)
        )

        return centerline
            .strokedPath(
                StrokeStyle(
                    lineWidth:
                        lineWidth,
                    lineCap:
                        .round,
                    lineJoin:
                        .round
                )
            )
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
            ATHLTHMarkShape()
                .fill(Color.primary)
                .frame(
                    width:
                        size.markWidth,
                    height:
                        size.markHeight
                )
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
