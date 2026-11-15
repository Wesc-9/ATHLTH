import SwiftUI

/// Small, consistent anatomical pictograms for muscle-group choices.
/// A muted body outline and a highlighted muscle region are more precise
/// than unrelated workout symbols (or a hand icon for forearms).
struct ATHLTHMuscleGroupIcon: View {
    let group: ExerciseMuscleGroup
    var size: CGFloat = 30
    var tint: Color = ATHLTHPlanDesign.accentInk

    var body: some View {
        Canvas { context, canvasSize in
            let sx = canvasSize.width / 40
            let sy = canvasSize.height / 40
            let base = tint.opacity(0.43)

            func ellipse(_ x: CGFloat, _ y: CGFloat,
                         _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(ellipseIn: CGRect(
                    x: x * sx, y: y * sy, width: w * sx, height: h * sy
                ))
            }

            var outline = Path()
            outline.addEllipse(in: CGRect(x: 16 * sx, y: 1 * sy,
                                          width: 8 * sx, height: 8 * sy))
            outline.move(to: CGPoint(x: 15 * sx, y: 12 * sy))
            outline.addLine(to: CGPoint(x: 25 * sx, y: 12 * sy))
            outline.move(to: CGPoint(x: 15 * sx, y: 12 * sy))
            outline.addLine(to: CGPoint(x: 14 * sx, y: 24 * sy))
            outline.addLine(to: CGPoint(x: 17 * sx, y: 27 * sy))
            outline.addLine(to: CGPoint(x: 23 * sx, y: 27 * sy))
            outline.addLine(to: CGPoint(x: 26 * sx, y: 24 * sy))
            outline.addLine(to: CGPoint(x: 25 * sx, y: 12 * sy))
            outline.move(to: CGPoint(x: 14 * sx, y: 14 * sy))
            outline.addLine(to: CGPoint(x: 10 * sx, y: 21 * sy))
            outline.addLine(to: CGPoint(x: 7 * sx, y: 31 * sy))
            outline.move(to: CGPoint(x: 26 * sx, y: 14 * sy))
            outline.addLine(to: CGPoint(x: 30 * sx, y: 21 * sy))
            outline.addLine(to: CGPoint(x: 33 * sx, y: 31 * sy))
            outline.move(to: CGPoint(x: 17 * sx, y: 27 * sy))
            outline.addLine(to: CGPoint(x: 15 * sx, y: 38 * sy))
            outline.move(to: CGPoint(x: 23 * sx, y: 27 * sy))
            outline.addLine(to: CGPoint(x: 25 * sx, y: 38 * sy))
            context.stroke(outline, with: .color(base),
                           style: StrokeStyle(
                               lineWidth: max(0.95, 1.7 * sx),
                               lineCap: .round, lineJoin: .round
                           ))

            func muscle(_ x: CGFloat, _ y: CGFloat,
                        _ w: CGFloat, _ h: CGFloat) {
                context.fill(ellipse(x, y, w, h), with: .color(tint))
            }

            switch group {
            case .chest:
                muscle(15, 15, 10, 5)
            case .back:
                muscle(15.5, 16, 9, 9)
            case .shoulders:
                muscle(11, 12, 5.5, 5.5)
                muscle(23.5, 12, 5.5, 5.5)
            case .biceps:
                muscle(10, 17, 4.5, 6.2)
                muscle(25.5, 17, 4.5, 6.2)
            case .triceps:
                muscle(9.2, 19.5, 3.6, 5.6)
                muscle(27.2, 19.5, 3.6, 5.6)
            case .forearms:
                muscle(6.1, 25, 4.3, 6.8)
                muscle(29.6, 25, 4.3, 6.8)
            case .core:
                muscle(17.2, 21.2, 5.6, 5)
            case .glutes:
                muscle(15.2, 25, 5, 4.6)
                muscle(19.8, 25, 5, 4.6)
            case .quads:
                muscle(14.7, 29.3, 4.3, 6.7)
                muscle(21, 29.3, 4.3, 6.7)
            case .hamstrings:
                muscle(16.2, 29.7, 3.6, 6.7)
                muscle(20.2, 29.7, 3.6, 6.7)
            case .calves:
                muscle(12.4, 34.8, 4.5, 4.3)
                muscle(23.1, 34.8, 4.5, 4.3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(group.title)
    }
}
