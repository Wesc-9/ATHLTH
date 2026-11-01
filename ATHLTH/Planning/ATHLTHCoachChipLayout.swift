import SwiftUI

/// A true chip flow, not a compressed three-column grid. Labels retain their
/// natural width and wrap to the next line on small phones and with larger text.
struct ATHLTHCoachChipLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let width = max(proposal.width ?? 350, 1)
        let layout = positions(for: subviews, width: width)
        return CGSize(width: width, height: layout.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout ()
    ) {
        let layout = positions(for: subviews, width: max(bounds.width, 1))
        for (i, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + layout.points[i].x,
                    y: bounds.minY + layout.points[i].y
                ),
                proposal: ProposedViewSize(layout.sizes[i])
            )
        }
    }

    private func positions(
        for subviews: Subviews, width: CGFloat
    ) -> (points: [CGPoint], sizes: [CGSize], height: CGFloat) {
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let natural = subview.sizeThatFits(.unspecified)
            let w = min(natural.width, width)
            let size = subview.sizeThatFits(
                ProposedViewSize(width: w, height: nil)
            )
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (points, sizes, y + rowHeight)
    }
}

struct ATHLTHCoachSelectChip: View {
    let title: String
    let selected: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? .white : ATHLTHTrainDesign.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .frame(minHeight: 43)
                .background(
                    selected ? ATHLTHTrainDesign.bronze : ATHLTHTrainDesign.canvas,
                    in: Capsule()
                )
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
