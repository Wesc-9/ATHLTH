import SwiftUI

/// Original, royalty-free ATHLTH vector art made from simple geometry.
/// No third-party artwork, AI-derived source imagery, image downloads or
/// external packages. Distinct poses for each of the 20 new core movements.
/// Coordinates are normalized and the drawing is entirely device-local.
struct ATHLTHOriginalCoreArtwork: View {
    let slug: String

    private enum Equipment {
        case mat, ball, cable, band, weight, bench
    }

    private struct Pose {
        // head, shoulder, pelvis, left elbow/hand, right elbow/hand,
        // left knee/foot, right knee/foot
        let joints: [CGPoint]
        let equipment: Equipment
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, canvas in
            let pose = Self.pose(for: slug)
            let width = canvas.width
            let height = canvas.height
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * width, y: p.y * height)
            }

            let background = Path(roundedRect: CGRect(origin: .zero, size: canvas),
                                  cornerRadius: max(12, width * 0.17))
            context.fill(background, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.92, green: 0.97, blue: 0.96),
                    Color(red: 0.77, green: 0.89, blue: 0.87)
                ]), startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: width, y: height)))

            var floor = Path()
            floor.move(to: CGPoint(x: width * 0.08, y: height * 0.90))
            floor.addLine(to: CGPoint(x: width * 0.93, y: height * 0.90))
            context.stroke(floor, with: .color(Color(red: 0.32, green: 0.54, blue: 0.53)
                .opacity(0.28)), lineWidth: max(1, width * 0.012))

            func line(_ a: CGPoint, _ b: CGPoint, color: Color, thick: CGFloat) {
                var path = Path()
                path.move(to: point(a))
                path.addLine(to: point(b))
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: max(2, thick * width),
                                                  lineCap: .round, lineJoin: .round))
            }
            let deep = Color(red: 0.10, green: 0.24, blue: 0.28)
            let limb = Color(red: 0.15, green: 0.36, blue: 0.39)
            let highlight = Color(red: 0.18, green: 0.65, blue: 0.54)
            let j = pose.joints
            guard j.count == 11 else { return }

            switch pose.equipment {
            case .mat:
                let mat = CGRect(x: width * 0.13, y: height * 0.85,
                                 width: width * 0.76, height: height * 0.04)
                context.fill(Path(roundedRect: mat, cornerRadius: width * 0.014),
                             with: .color(highlight.opacity(0.32)))
            case .ball:
                let ball = CGRect(x: width * 0.22, y: height * 0.70,
                                  width: width * 0.23, height: height * 0.23)
                context.fill(Path(ellipseIn: ball),
                             with: .color(highlight.opacity(0.45)))
                context.stroke(Path(ellipseIn: ball), with: .color(highlight),
                               lineWidth: max(1.5, width * 0.02))
            case .cable:
                let pulley = CGPoint(x: width * 0.12, y: height * 0.11)
                line(CGPoint(x: 0.12, y: 0.11), j[4],
                     color: highlight.opacity(0.8), thick: 0.019)
                context.fill(Path(ellipseIn: CGRect(x: pulley.x - width * 0.035,
                                                     y: pulley.y - width * 0.035,
                                                     width: width * 0.07,
                                                     height: width * 0.07)),
                             with: .color(deep))
            case .band:
                line(CGPoint(x: 0.12, y: 0.17), j[4], color: highlight, thick: 0.018)
            case .weight:
                let hand = point(j[6])
                let weight = CGRect(x: hand.x - width * 0.07,
                                    y: hand.y - width * 0.03,
                                    width: width * 0.14, height: width * 0.07)
                context.fill(Path(roundedRect: weight, cornerRadius: width * 0.02),
                             with: .color(highlight))
            case .bench:
                context.fill(Path(roundedRect:
                    CGRect(x: width * 0.68, y: height * 0.52,
                           width: width * 0.27, height: height * 0.045),
                    cornerRadius: width * 0.02), with: .color(highlight))
                line(CGPoint(x: 0.74, y: 0.56), CGPoint(x: 0.74, y: 0.88),
                     color: deep, thick: 0.018)
            }

            // Draw legs, arms, torso, then head; no original body assets.
            line(j[2], j[7], color: limb, thick: 0.062)
            line(j[7], j[8], color: limb, thick: 0.055)
            line(j[2], j[9], color: deep, thick: 0.064)
            line(j[9], j[10], color: deep, thick: 0.055)
            line(j[1], j[3], color: limb, thick: 0.055)
            line(j[3], j[4], color: limb, thick: 0.046)
            line(j[1], j[5], color: deep, thick: 0.055)
            line(j[5], j[6], color: deep, thick: 0.046)
            line(j[1], j[2], color: deep, thick: 0.125)
            line(j[0], j[1], color: deep, thick: 0.032)
            let headCenter = point(j[0])
            context.fill(Path(ellipseIn:
                CGRect(x: headCenter.x - width * 0.063,
                       y: headCenter.y - width * 0.063,
                       width: width * 0.126, height: width * 0.126)),
                with: .color(deep))
            let center = point(CGPoint(x: j[1].x * 0.38 + j[2].x * 0.62,
                                       y: j[1].y * 0.38 + j[2].y * 0.62))
            context.fill(Path(ellipseIn:
                CGRect(x: center.x - width * 0.041,
                       y: center.y - width * 0.041,
                       width: width * 0.082, height: width * 0.082)),
                with: .color(highlight))
        }
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english: "ATHLTH original exercise illustration",
                norwegian: "Original øvelsesillustrasjon fra ATHLTH"
            )
        )
    }

    private static func pose(for slug: String) -> Pose {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x, y: y)
        }
        switch slug {
        case "athlth-core-plank-shoulder-tap":
            return Pose(joints: [p(0.17, 0.45), p(0.3, 0.53), p(0.61, 0.55), p(0.4, 0.38), p(0.31, 0.54), p(0.43, 0.7), p(0.48, 0.8), p(0.77, 0.57), p(0.91, 0.76), p(0.78, 0.54), p(0.92, 0.7)], equipment: .mat)
        case "athlth-core-plank-jack":
            return Pose(joints: [p(0.17, 0.45), p(0.3, 0.53), p(0.61, 0.55), p(0.31, 0.72), p(0.35, 0.81), p(0.43, 0.7), p(0.48, 0.8), p(0.82, 0.57), p(0.93, 0.91), p(0.82, 0.53), p(0.92, 0.65)], equipment: .mat)
        case "athlth-core-plank-walkout":
            return Pose(joints: [p(0.3, 0.39), p(0.41, 0.47), p(0.68, 0.46), p(0.42, 0.69), p(0.42, 0.81), p(0.5, 0.67), p(0.54, 0.79), p(0.77, 0.57), p(0.91, 0.76), p(0.78, 0.54), p(0.92, 0.7)], equipment: .mat)
        case "athlth-core-rkc-plank":
            return Pose(joints: [p(0.17, 0.45), p(0.3, 0.53), p(0.61, 0.55), p(0.3, 0.75), p(0.28, 0.81), p(0.43, 0.75), p(0.45, 0.8), p(0.77, 0.57), p(0.91, 0.76), p(0.78, 0.54), p(0.92, 0.7)], equipment: .mat)
        case "athlth-core-hollow-body-rock":
            return Pose(joints: [p(0.2, 0.61), p(0.33, 0.67), p(0.56, 0.71), p(0.25, 0.57), p(0.13, 0.48), p(0.28, 0.6), p(0.16, 0.53), p(0.73, 0.61), p(0.88, 0.52), p(0.73, 0.66), p(0.89, 0.59)], equipment: .mat)
        case "athlth-core-toe-touch-crunch":
            return Pose(joints: [p(0.19, 0.61), p(0.3, 0.66), p(0.55, 0.69), p(0.42, 0.47), p(0.72, 0.23), p(0.4, 0.52), p(0.66, 0.27), p(0.7, 0.43), p(0.74, 0.21), p(0.75, 0.48), p(0.8, 0.25)], equipment: .mat)
        case "athlth-core-standing-cable-woodchop":
            return Pose(joints: [p(0.52, 0.16), p(0.52, 0.33), p(0.52, 0.55), p(0.4, 0.39), p(0.27, 0.53), p(0.58, 0.39), p(0.3, 0.52), p(0.46, 0.75), p(0.45, 0.93), p(0.6, 0.76), p(0.63, 0.93)], equipment: .cable)
        case "athlth-core-half-kneeling-cable-chop":
            return Pose(joints: [p(0.54, 0.15), p(0.54, 0.32), p(0.55, 0.54), p(0.41, 0.39), p(0.28, 0.5), p(0.57, 0.39), p(0.3, 0.52), p(0.43, 0.74), p(0.34, 0.88), p(0.65, 0.74), p(0.67, 0.87)], equipment: .cable)
        case "athlth-core-pallof-step-out":
            return Pose(joints: [p(0.52, 0.16), p(0.52, 0.33), p(0.52, 0.55), p(0.62, 0.4), p(0.78, 0.42), p(0.61, 0.48), p(0.78, 0.44), p(0.43, 0.74), p(0.31, 0.91), p(0.67, 0.77), p(0.76, 0.91)], equipment: .cable)
        case "athlth-core-banded-dead-bug-pulldown":
            return Pose(joints: [p(0.18, 0.7), p(0.32, 0.7), p(0.57, 0.69), p(0.31, 0.51), p(0.27, 0.35), p(0.4, 0.51), p(0.36, 0.34), p(0.68, 0.5), p(0.8, 0.58), p(0.71, 0.51), p(0.76, 0.3)], equipment: .band)
        case "athlth-core-bird-dog-row":
            return Pose(joints: [p(0.24, 0.36), p(0.38, 0.45), p(0.62, 0.53), p(0.4, 0.68), p(0.41, 0.82), p(0.49, 0.51), p(0.55, 0.63), p(0.61, 0.75), p(0.6, 0.88), p(0.79, 0.5), p(0.94, 0.46)], equipment: .weight)
        case "athlth-core-side-plank-hip-dip":
            return Pose(joints: [p(0.2, 0.48), p(0.31, 0.53), p(0.62, 0.7), p(0.3, 0.71), p(0.31, 0.83), p(0.43, 0.48), p(0.52, 0.31), p(0.78, 0.65), p(0.9, 0.83), p(0.77, 0.62), p(0.88, 0.75)], equipment: .mat)
        case "athlth-core-side-plank-reach-through":
            return Pose(joints: [p(0.2, 0.48), p(0.31, 0.53), p(0.62, 0.62), p(0.3, 0.71), p(0.31, 0.83), p(0.51, 0.62), p(0.37, 0.76), p(0.78, 0.65), p(0.9, 0.8), p(0.77, 0.62), p(0.88, 0.75)], equipment: .mat)
        case "athlth-core-bear-plank-shoulder-tap":
            return Pose(joints: [p(0.22, 0.43), p(0.35, 0.49), p(0.6, 0.48), p(0.39, 0.42), p(0.35, 0.5), p(0.46, 0.64), p(0.51, 0.79), p(0.64, 0.73), p(0.66, 0.85), p(0.77, 0.7), p(0.81, 0.86)], equipment: .mat)
        case "athlth-core-windshield-wiper":
            return Pose(joints: [p(0.18, 0.7), p(0.32, 0.7), p(0.56, 0.68), p(0.26, 0.79), p(0.19, 0.8), p(0.34, 0.79), p(0.29, 0.84), p(0.68, 0.48), p(0.84, 0.27), p(0.7, 0.55), p(0.89, 0.33)], equipment: .mat)
        case "athlth-core-stir-the-pot":
            return Pose(joints: [p(0.17, 0.45), p(0.3, 0.53), p(0.61, 0.55), p(0.3, 0.7), p(0.3, 0.83), p(0.42, 0.7), p(0.42, 0.83), p(0.77, 0.57), p(0.91, 0.76), p(0.78, 0.54), p(0.92, 0.7)], equipment: .ball)
        case "athlth-core-swiss-ball-body-saw":
            return Pose(joints: [p(0.17, 0.46), p(0.3, 0.53), p(0.64, 0.54), p(0.3, 0.72), p(0.36, 0.81), p(0.42, 0.71), p(0.48, 0.8), p(0.77, 0.57), p(0.91, 0.76), p(0.78, 0.54), p(0.92, 0.7)], equipment: .ball)
        case "athlth-core-copenhagen-plank":
            return Pose(joints: [p(0.2, 0.48), p(0.31, 0.53), p(0.62, 0.62), p(0.3, 0.71), p(0.31, 0.83), p(0.43, 0.48), p(0.52, 0.31), p(0.78, 0.58), p(0.91, 0.54), p(0.75, 0.73), p(0.88, 0.83)], equipment: .bench)
        case "athlth-core-suitcase-march":
            return Pose(joints: [p(0.52, 0.16), p(0.52, 0.33), p(0.52, 0.55), p(0.43, 0.45), p(0.4, 0.66), p(0.62, 0.45), p(0.65, 0.63), p(0.47, 0.74), p(0.48, 0.9), p(0.65, 0.69), p(0.79, 0.72)], equipment: .weight)
        case "athlth-core-standing-knee-elbow-crunch":
            return Pose(joints: [p(0.52, 0.16), p(0.52, 0.33), p(0.52, 0.55), p(0.39, 0.29), p(0.43, 0.18), p(0.62, 0.31), p(0.6, 0.2), p(0.44, 0.74), p(0.44, 0.92), p(0.7, 0.66), p(0.64, 0.54)], equipment: .mat)
        default:
            return Pose(joints: [p(0.17, 0.45), p(0.3, 0.53), p(0.61, 0.55), p(0.31, 0.72), p(0.35, 0.81), p(0.43, 0.7), p(0.48, 0.8), p(0.77, 0.57), p(0.91, 0.76), p(0.78, 0.54), p(0.92, 0.7)],
                        equipment: .mat)
        }
    }
}
