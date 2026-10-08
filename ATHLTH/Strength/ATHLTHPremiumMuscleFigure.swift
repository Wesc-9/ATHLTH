import SwiftUI

/// A fully native, resolution-independent ATHLTH muscle atlas.
///
/// All contours are vector paths, not a generated image. Inactive muscles
/// remain visible as sculpted neutral plates; only workout-backed regions
/// receive color. Source coordinates are shared by both body orientations
/// so thumbnails and full-size maps always agree.
struct ATHLTHPremiumMuscleFigure: View {
    let profile: StrengthMuscleProfile
    let isFront: Bool
    let activationTint: Color

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            ATHLTHPremiumMuscleAtlas.draw(
                context: &context,
                size: size,
                profile: profile,
                isFront: isFront,
                tint: activationTint
            )
        }
        .aspectRatio(0.57, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum ATHLTHPremiumMuscleAtlas {
    struct Panel: Sendable {
        let region: StrengthMuscleRegion
        let outline: Path
    }

    private static let baseWidth: CGFloat = 200
    private static let baseHeight: CGFloat = 360
    private static let skin = Color(red: 0.961, green: 0.963, blue: 0.960)
    private static let ink = Color(red: 0.56, green: 0.60, blue: 0.61)
    private static let neutral = Color(red: 0.899, green: 0.912, blue: 0.911)
    private static let warm = Color(red: 0.993, green: 0.976, blue: 0.964)

    /// Kept internal for the lightweight map-coverage regression test.
    static func coveredRegions(isFront: Bool) -> Set<StrengthMuscleRegion> {
        Set((isFront ? frontPanels : backPanels).map(\.region))
    }

    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        profile: StrengthMuscleProfile,
        isFront: Bool,
        tint: Color
    ) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(size.width / baseWidth, size.height / baseHeight)
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: (size.width - baseWidth * scale) / 2,
            ty: (size.height - baseHeight * scale) / 2
        )

        // Limbs behind torso, softly shaded. The atlas itself has no backdrop;
        // this lets Home/Details supply their own light premium background.
        for silhouette in body {
            let shape = silhouette.applying(transform)
            context.fill(
                shape,
                with: .linearGradient(
                    Gradient(colors: [skin, warm, skin]),
                    startPoint: CGPoint(x: 0, y: size.height * 0.20),
                    endPoint: CGPoint(x: size.width, y: size.height * 0.73)
                )
            )
            context.stroke(
                shape,
                with: .color(ink.opacity(0.42)),
                lineWidth: 0.85
            )
        }

        let panels = isFront ? frontPanels : backPanels
        for panel in panels {
            let path = panel.outline.applying(transform)
            let score = profile.intensity(for: panel.region)
            if score > 0.01 {
                let role = profile.highlightRole(for: panel.region)
                let primary = role == .primary
                let supporting = role == .secondary
                let opacity = primary ? (0.72 + 0.24 * score)
                    : supporting ? (0.27 + 0.23 * score)
                    : (0.46 + 0.30 * score)
                let secondaryTint = Color(
                    red: 0.971, green: 0.646, blue: 0.602
                )
                let base = supporting ? secondaryTint : tint
                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            base.opacity(opacity * 0.68),
                            base.opacity(opacity),
                            base.opacity(opacity * 0.79)
                        ]),
                        startPoint: CGPoint(x: size.width * 0.25, y: size.height * 0.18),
                        endPoint: CGPoint(x: size.width * 0.72, y: size.height * 0.78)
                    )
                )
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(primary ? 0.91 : 0.70)),
                    lineWidth: 0.90
                )
            } else {
                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.89),
                            neutral.opacity(0.74),
                            Color.white.opacity(0.80)
                        ]),
                        startPoint: CGPoint(x: size.width * 0.23, y: size.height * 0.13),
                        endPoint: CGPoint(x: size.width * 0.75, y: size.height * 0.85)
                    )
                )
                context.stroke(
                    path,
                    with: .color(ink.opacity(0.18)),
                    lineWidth: 0.62
                )
            }
        }

        for contour in isFront ? frontContours : backContours {
            context.stroke(
                contour.applying(transform),
                with: .color(ink.opacity(0.22)),
                style: StrokeStyle(lineWidth: 0.62, lineCap: .round)
            )
        }
    }

    private static func paired(
        _ region: StrengthMuscleRegion,
        _ data: String
    ) -> [Panel] {
        let left = path(data)
        let flip = CGAffineTransform(
            a: -1, b: 0, c: 0, d: 1, tx: baseWidth, ty: 0
        )
        return [
            Panel(region: region, outline: left),
            Panel(region: region, outline: left.applying(flip))
        ]
    }

    private static func solo(
        _ region: StrengthMuscleRegion,
        _ data: String
    ) -> [Panel] {
        [Panel(region: region, outline: path(data))]
    }

    // Paths are initialized once and reused across all cards. No runtime
    // rasterization assets, external parser or machine-learning service.
    private static let body: [Path] = {
        let center: [Path] = [
            path("M 90 45 C 92 51 88 55 78 58 C 79 67 87 71 100 73 C 113 71 121 67 122 58 C 112 55 108 51 110 45 Z"),
            path("M 99 9 C 83 9 80 20 81 32 C 80 44 89 52 100 52 C 111 52 120 44 119 32 C 120 20 116 9 101 9 Z"),
            path("M 81 56 C 69 55 61 59 59 67 C 56 82 65 104 71 121 C 76 134 80 146 79 157 C 76 170 71 180 74 190 C 77 200 89 204 100 205 C 111 204 123 200 126 190 C 129 180 124 170 121 157 C 120 146 124 134 129 121 C 135 104 144 82 141 67 C 139 59 131 55 119 56 C 113 68 107 72 100 72 C 93 72 87 68 81 56 Z"),
        ]
        let mirror = CGAffineTransform(
            a: -1, b: 0, c: 0, d: 1, tx: baseWidth, ty: 0
        )
        let limbs: [Path] = [
            path("M 56 64 C 47 64 43 74 41 89 C 39 105 36 123 36 137 C 34 154 29 170 24 189 C 22 198 20 206 19 216 C 18 224 23 231 28 230 C 35 227 36 215 35 204 C 39 186 47 159 49 144 C 53 128 58 107 62 90 C 65 76 64 67 56 64 Z"),
            path("M 76 185 C 66 188 63 205 64 229 C 64 244 68 260 72 272 C 72 281 69 300 69 320 C 68 327 65 336 63 344 C 62 349 71 351 82 349 C 90 349 91 345 89 340 C 86 328 87 311 88 302 C 90 290 87 272 88 264 C 94 247 98 218 98 201 C 93 194 83 187 76 185 Z"),
        ]
        return limbs + limbs.map { $0.applying(mirror) } + center
    }()

    private static let frontPanels: [Panel] = {
        [
            paired(.frontDelts, "M 60 61 C 50 58 45 64 44 74 C 43 87 49 93 55 97 C 61 91 67 74 69 66 C 67 63 64 62 60 61 Z"),
            paired(.sideDelts, "M 47 75 C 41 80 38 91 39 102 C 41 107 44 111 49 111 L 55 97 C 50 91 48 82 47 75 Z"),
            paired(.chest, "M 89 66 C 78 65 67 66 64 76 C 62 85 65 98 71 105 C 80 109 91 108 98 102 L 98 75 C 97 71 94 68 89 66 Z"),
            paired(.biceps, "M 43 106 C 38 111 35 129 37 144 C 39 147 43 149 46 146 C 50 136 52 118 50 110 C 48 107 46 105 43 106 Z"),
            paired(.forearms, "M 35 149 C 30 157 25 180 23 192 C 24 200 28 204 33 199 C 36 188 41 161 39 153 C 38 150 36 149 35 149 Z"),
            paired(.serratus, "M 70 108 C 69 116 76 124 79 129 C 83 126 84 120 84 113 C 79 112 74 109 70 108 Z"),
            paired(.obliques, "M 76 128 C 72 137 75 154 79 166 C 82 166 87 162 88 155 L 86 135 C 83 133 79 130 76 128 Z"),
            paired(.abs, "M 91 118 C 87 120 85 130 87 139 C 89 142 94 142 99 140 L 99 119 C 96 117 94 117 91 118 Z"),
            paired(.abs, "M 88 143 C 86 149 86 157 90 163 C 93 165 96 164 99 163 L 99 143 C 95 141 91 142 88 143 Z"),
            paired(.abs, "M 90 165 C 88 173 89 181 94 184 L 99 181 L 99 165 C 95 164 93 163 90 165 Z"),
            paired(.hipFlexors, "M 82 181 C 80 187 82 194 87 203 L 94 201 C 93 190 88 184 82 181 Z"),
            paired(.outerHip, "M 76 185 C 70 186 67 196 66 207 L 72 217 C 78 214 81 199 82 190 L 80 185 Z"),
            paired(.innerThigh, "M 90 203 C 85 209 81 221 81 237 C 83 241 87 243 90 239 L 95 211 Z"),
            paired(.quads, "M 76 204 C 68 209 66 223 68 239 C 69 250 72 254 76 258 C 79 249 82 220 80 207 Z"),
            paired(.quads, "M 82 210 C 78 224 77 240 79 260 C 82 265 85 266 89 261 C 89 247 90 220 88 211 Z"),
            paired(.quads, "M 89 212 C 88 224 91 243 92 257 C 95 257 98 251 98 242 L 95 214 Z"),
            paired(.calves, "M 71 275 C 65 286 64 308 69 319 C 73 326 77 324 78 318 C 79 298 76 285 74 277 Z"),
            paired(.shins, "M 82 277 C 78 286 80 312 81 326 C 84 327 88 318 88 310 C 88 296 85 284 82 277 Z"),
        ].flatMap { $0 }
    }()

    private static let backPanels: [Panel] = {
        [
            paired(.traps, "M 98 50 C 89 56 74 62 68 70 C 70 82 82 88 99 95 L 99 51 Z"),
            paired(.rearDelts, "M 61 66 C 48 65 43 74 43 86 C 45 95 51 99 55 99 C 64 92 69 79 69 70 Z"),
            paired(.sideDelts, "M 46 90 C 42 94 39 103 40 111 C 45 114 50 108 54 99 Z"),
            paired(.upperBack, "M 72 79 C 79 80 89 90 99 98 L 99 133 C 87 128 75 113 72 100 C 68 91 69 83 72 79 Z"),
            paired(.lats, "M 68 106 C 75 117 82 130 88 144 L 94 170 C 84 165 76 157 72 145 C 68 132 64 114 68 106 Z"),
            paired(.triceps, "M 43 110 C 37 117 35 135 38 147 C 41 150 46 146 48 142 C 52 129 53 114 49 110 Z"),
            paired(.forearms, "M 35 151 C 30 159 25 181 23 193 C 24 201 28 203 33 198 C 36 187 40 164 39 156 Z"),
            paired(.lowerBack, "M 88 147 C 87 157 79 167 78 181 C 86 184 94 186 99 185 L 99 146 C 95 146 92 147 88 147 Z"),
            paired(.glutes, "M 92 182 C 78 180 69 189 68 201 C 67 215 74 222 86 224 C 97 220 100 209 99 198 C 98 191 95 186 92 182 Z"),
            paired(.outerHip, "M 69 194 C 63 199 62 212 65 222 C 68 226 73 224 76 220 L 76 200 Z"),
            paired(.hamstrings, "M 73 226 C 66 239 66 259 70 272 C 74 273 79 269 80 259 C 81 247 80 234 78 227 Z"),
            paired(.hamstrings, "M 82 226 C 79 235 79 260 82 272 C 86 277 90 270 91 264 C 91 250 88 233 86 227 Z"),
            paired(.hamstrings, "M 91 225 C 90 240 92 252 94 266 C 98 262 99 249 99 239 L 97 225 Z"),
            paired(.calves, "M 72 275 C 64 282 65 306 69 317 C 74 326 79 323 80 315 C 81 300 77 284 74 275 Z"),
            paired(.calves, "M 82 282 C 80 295 80 316 84 324 C 88 322 90 310 89 300 C 88 290 86 283 82 282 Z"),
        ].flatMap { $0 }
    }()

    private static let frontContours: [Path] = [
        path("M 83 14 C 88 10 95 10 100 12"),
        path("M 90 49 C 92 54 95 57 99 58"),
        path("M 99 75 L 99 180"),
        path("M 71 111 C 72 118 74 122 77 126"),
        path("M 67 229 C 66 243 69 258 72 264"),
        path("M 72 273 C 75 275 81 277 87 274"),
        path("M 69 327 C 71 333 75 336 83 334"),
    ]

    private static let backContours: [Path] = [
        path("M 99 56 L 99 181"),
        path("M 77 80 C 85 83 92 88 99 96"),
        path("M 76 118 C 82 133 87 141 96 147"),
        path("M 72 227 C 74 242 72 261 76 271"),
        path("M 74 275 C 79 278 84 277 89 274")
    ]

    /// Minimal fixed-command cubic vector format, parsed only while the
    /// shared static atlas is initialized. Each command has explicit
    /// whitespace-separated coordinates.
    private static func path(_ commands: String) -> Path {
        let tokens = commands.split(whereSeparator: \.isWhitespace)
        var i = 0
        var result = Path()
        func value() -> CGFloat {
            guard i < tokens.count else { return 0 }
            defer { i += 1 }
            return CGFloat(Double(tokens[i]) ?? 0)
        }
        while i < tokens.count {
            let op = tokens[i]
            i += 1
            switch op {
            case "M":
                result.move(to: CGPoint(x: value(), y: value()))
            case "L":
                result.addLine(to: CGPoint(x: value(), y: value()))
            case "C":
                let p1 = CGPoint(x: value(), y: value())
                let p2 = CGPoint(x: value(), y: value())
                let end = CGPoint(x: value(), y: value())
                result.addCurve(to: end, control1: p1, control2: p2)
            case "Q":
                let p = CGPoint(x: value(), y: value())
                let end = CGPoint(x: value(), y: value())
                result.addQuadCurve(to: end, control: p)
            case "Z":
                result.closeSubpath()
            default:
                assertionFailure("Invalid ATHLTH muscle vector command")
                return Path()
            }
        }
        return result
    }
}


#if DEBUG
/// Xcode canvas fixture. No hard-coded activations are used in the shipped app.
private struct ATHLTHPremiumMuscleFigure_Previews: PreviewProvider {
    private static var sample: StrengthMuscleProfile {
        StrengthMuscleProfile(
        activations: [
            StrengthMuscleActivation(region: .glutes, score: 4.0),
            StrengthMuscleActivation(region: .hamstrings, score: 3.7),
            StrengthMuscleActivation(region: .quads, score: 3.5),
            StrengthMuscleActivation(region: .calves, score: 1.2),
            StrengthMuscleActivation(region: .abs, score: 0.8)
        ],
        primaryRegions: [.glutes, .hamstrings, .quads],
        secondaryRegions: [.calves, .abs]
        )
    }

    static var previews: some View {
        HStack(alignment: .top, spacing: 14) {
            ATHLTHPremiumMuscleFigure(
                profile: sample,
                isFront: true,
                activationTint: Color(red: 0.93, green: 0.32, blue: 0.22)
            )
            ATHLTHPremiumMuscleFigure(
                profile: sample,
                isFront: false,
                activationTint: Color(red: 0.93, green: 0.32, blue: 0.22)
            )
        }
        .frame(width: 316, height: 275)
        .padding(20)
        .background(Color(red: 0.98, green: 0.98, blue: 0.975))
        .previewDisplayName("ATHLTH – styrke, front og bak")
    }
}
#endif
