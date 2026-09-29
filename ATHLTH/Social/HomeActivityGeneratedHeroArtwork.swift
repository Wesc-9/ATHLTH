import CoreLocation
import SwiftUI

struct HomeActivityHeroArtwork: View {
    let imageURL: URL?
    let recipe: WorkoutVisualRecipe
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        ZStack {
            HomeActivityGeneratedHeroArtwork(
                recipe: recipe,
                coordinates: coordinates
            )

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .empty:
                        Color.clear
                    case .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .clipped()

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        .clear,
                        Color.black.opacity(0.13)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if coordinates.count >= 2 {
                    routeRibbon
                        .padding(
                            EdgeInsets(
                                top: 44,
                                leading: 92,
                                bottom: 34,
                                trailing: 22
                            )
                        )
                }
            }
        }
        .animation(
            .easeInOut(duration: 0.28),
            value: imageURL
        )
    }

    private var routeRibbon: some View {
        ZStack {
            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                Color.black.opacity(0.20),
                style: StrokeStyle(
                    lineWidth: 18,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                Color.white.opacity(0.92),
                style: StrokeStyle(
                    lineWidth: 12,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.35,
                            green: 0.96,
                            blue: 0.68
                        ),
                        Color.mint,
                        Color.cyan
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(
                    lineWidth: 7,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                Color.white.opacity(0.44),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .shadow(
            color: Color.mint.opacity(0.30),
            radius: 10
        )
    }
}

struct HomeActivityGeneratedHeroArtwork: View {
    let recipe: WorkoutVisualRecipe
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                sky

                scene(
                    size: geometry.size
                )

                atmosphere

                if coordinates.count >= 2 {
                    routeRibbon
                        .padding(
                            EdgeInsets(
                                top: 44,
                                leading: 92,
                                bottom: 34,
                                trailing: 22
                            )
                        )
                }

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        .clear,
                        Color.black.opacity(0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var sky: some View {
        LinearGradient(
            colors: skyColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func scene(
        size: CGSize
    ) -> some View {
        switch recipe.scene {
        case "coast":
            coastScene(size: size)
        case "forest":
            forestScene(size: size)
        case "city":
            cityScene(size: size)
        case "track":
            trackScene(size: size)
        case "studio":
            studioScene(size: size)
        default:
            mountainScene(size: size)
        }
    }

    private func mountainScene(
        size: CGSize
    ) -> some View {
        ZStack {
            HomeActivityMountainShape(
                phase: CGFloat(recipe.variant) * 0.13,
                depth: 0.56
            )
            .fill(
                LinearGradient(
                    colors: [
                        scenePrimary.opacity(0.72),
                        sceneDeep.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: size.height * 0.68)
            .offset(y: size.height * 0.21)

            HomeActivityMountainShape(
                phase: CGFloat(recipe.variant) * 0.19 + 0.22,
                depth: 0.42
            )
            .fill(
                sceneDeep.opacity(0.43)
            )
            .frame(height: size.height * 0.54)
            .offset(
                x: size.width * 0.11,
                y: size.height * 0.33
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    sceneDeep.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: size.height * 0.30)
            .frame(
                maxHeight: .infinity,
                alignment: .bottom
            )
        }
    }

    private func coastScene(
        size: CGSize
    ) -> some View {
        ZStack {
            HomeActivityMountainShape(
                phase: CGFloat(recipe.variant) * 0.12,
                depth: 0.37
            )
            .fill(
                sceneDeep.opacity(0.62)
            )
            .frame(height: size.height * 0.49)
            .frame(
                maxHeight: .infinity,
                alignment: .top
            )
            .offset(y: size.height * 0.19)

            LinearGradient(
                colors: [
                    Color.cyan.opacity(0.24),
                    Color.blue.opacity(0.34),
                    sceneDeep.opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: size.height * 0.44)
            .frame(
                maxHeight: .infinity,
                alignment: .bottom
            )

            HomeActivityWaveShape(
                phase: CGFloat(recipe.variant) * 0.17
            )
            .stroke(
                Color.white.opacity(0.16),
                style: StrokeStyle(
                    lineWidth: 1.2,
                    lineCap: .round
                )
            )
            .frame(height: size.height * 0.34)
            .frame(
                maxHeight: .infinity,
                alignment: .bottom
            )
        }
    }

    private func forestScene(
        size: CGSize
    ) -> some View {
        ZStack {
            HomeActivityMountainShape(
                phase: CGFloat(recipe.variant) * 0.11,
                depth: 0.43
            )
            .fill(
                scenePrimary.opacity(0.48)
            )
            .frame(height: size.height * 0.48)
            .offset(y: size.height * 0.18)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<18, id: \.self) { index in
                    Image(systemName: "tree.fill")
                        .font(
                            .system(
                                size:
                                    18 +
                                    CGFloat(
                                        (index * 7 +
                                         recipe.variant * 5) %
                                        24
                                    )
                            )
                        )
                        .foregroundStyle(
                            sceneDeep.opacity(
                                0.32 +
                                Double(index % 4) * 0.07
                            )
                        )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
            .padding(.bottom, 3)

            LinearGradient(
                colors: [
                    .clear,
                    sceneDeep.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func cityScene(
        size: CGSize
    ) -> some View {
        ZStack {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<15, id: \.self) { index in
                    RoundedRectangle(
                        cornerRadius: 3,
                        style: .continuous
                    )
                    .fill(
                        sceneDeep.opacity(
                            0.25 +
                            Double(index % 4) * 0.08
                        )
                    )
                    .frame(
                        width:
                            size.width /
                            22,
                        height:
                            size.height *
                            (
                                0.19 +
                                CGFloat(
                                    (index * 11 +
                                     recipe.variant * 9) %
                                    27
                                ) / 100
                            )
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
            .padding(.horizontal, 5)

            LinearGradient(
                colors: [
                    .clear,
                    sceneDeep.opacity(0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func trackScene(
        size: CGSize
    ) -> some View {
        ZStack {
            Ellipse()
                .stroke(
                    sceneDeep.opacity(0.25),
                    lineWidth: 26
                )
                .frame(
                    width: size.width * 1.05,
                    height: size.height * 0.66
                )
                .rotationEffect(.degrees(-9))
                .offset(
                    x: size.width * 0.16,
                    y: size.height * 0.27
                )

            Ellipse()
                .stroke(
                    Color.white.opacity(0.26),
                    lineWidth: 2
                )
                .frame(
                    width: size.width * 0.98,
                    height: size.height * 0.58
                )
                .rotationEffect(.degrees(-9))
                .offset(
                    x: size.width * 0.16,
                    y: size.height * 0.27
                )

            LinearGradient(
                colors: [
                    .clear,
                    sceneDeep.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func studioScene(
        size: CGSize
    ) -> some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.34),
                    scenePrimary.opacity(0.22),
                    sceneDeep.opacity(0.30)
                ],
                center: .center,
                startRadius: 8,
                endRadius: max(
                    size.width,
                    size.height
                ) * 0.74
            )

            Image(
                systemName:
                    "figure.strengthtraining.traditional"
            )
            .font(
                .system(
                    size: min(
                        size.width,
                        size.height
                    ) * 0.53,
                    weight: .ultraLight
                )
            )
            .foregroundStyle(
                Color.white.opacity(0.12)
            )
            .offset(
                x: size.width * 0.21,
                y: size.height * 0.06
            )
        }
    }

    private var atmosphere: some View {
        ZStack {
            RadialGradient(
                colors: [
                    lightColor.opacity(
                        recipe.energy == "energetic"
                            ? 0.42
                            : 0.30
                    ),
                    .clear
                ],
                center:
                    recipe.variant.isMultiple(of: 2)
                        ? .topTrailing
                        : .topLeading,
                startRadius: 8,
                endRadius: 210
            )

            HomeActivityContourLines(
                variant: recipe.variant
            )
            .stroke(
                Color.white.opacity(0.12),
                style: StrokeStyle(
                    lineWidth: 0.9,
                    lineCap: .round
                )
            )
            .padding(12)
        }
    }

    private var routeRibbon: some View {
        ZStack {
            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                Color.black.opacity(0.20),
                style: StrokeStyle(
                    lineWidth: 18,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                Color.white.opacity(0.92),
                style: StrokeStyle(
                    lineWidth: 12,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                routeGradient,
                style: StrokeStyle(
                    lineWidth: 7,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            HomeActivityNormalizedRouteShape(
                coordinates: coordinates
            )
            .stroke(
                Color.white.opacity(0.44),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .shadow(
            color: routeAccent.opacity(0.28),
            radius: 10
        )
    }

    private var routeGradient: LinearGradient {
        LinearGradient(
            colors: [
                routeAccent.opacity(0.96),
                Color.mint.opacity(0.96),
                Color.cyan.opacity(0.90)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var routeAccent: Color {
        switch recipe.palette {
        case "ocean":
            return .cyan
        case "amber":
            return .mint
        case "violet":
            return .cyan
        case "rose":
            return .mint
        case "slate":
            return .mint
        default:
            return Color(
                red: 0.35,
                green: 0.96,
                blue: 0.68
            )
        }
    }

    private var scenePrimary: Color {
        switch recipe.palette {
        case "ocean":
            return Color(
                red: 0.22,
                green: 0.55,
                blue: 0.68
            )
        case "amber":
            return Color(
                red: 0.70,
                green: 0.46,
                blue: 0.23
            )
        case "violet":
            return Color(
                red: 0.38,
                green: 0.34,
                blue: 0.67
            )
        case "rose":
            return Color(
                red: 0.69,
                green: 0.39,
                blue: 0.45
            )
        case "slate":
            return Color(
                red: 0.24,
                green: 0.29,
                blue: 0.36
            )
        default:
            return Color(
                red: 0.30,
                green: 0.57,
                blue: 0.42
            )
        }
    }

    private var sceneDeep: Color {
        switch recipe.palette {
        case "ocean":
            return Color(
                red: 0.10,
                green: 0.27,
                blue: 0.35
            )
        case "amber":
            return Color(
                red: 0.30,
                green: 0.22,
                blue: 0.14
            )
        case "violet":
            return Color(
                red: 0.20,
                green: 0.18,
                blue: 0.34
            )
        case "rose":
            return Color(
                red: 0.29,
                green: 0.18,
                blue: 0.23
            )
        case "slate":
            return Color(
                red: 0.10,
                green: 0.13,
                blue: 0.17
            )
        default:
            return Color(
                red: 0.10,
                green: 0.26,
                blue: 0.19
            )
        }
    }

    private var lightColor: Color {
        switch recipe.light {
        case "sunrise":
            return Color.yellow
        case "golden_hour":
            return Color.orange
        case "dusk":
            return Color.indigo
        default:
            return Color.white
        }
    }

    private var skyColors: [Color] {
        switch recipe.light {
        case "sunrise":
            return [
                Color(
                    red: 0.92,
                    green: 0.74,
                    blue: 0.55
                ),
                Color(
                    red: 0.63,
                    green: 0.79,
                    blue: 0.80
                ),
                scenePrimary
            ]
        case "golden_hour":
            return [
                Color(
                    red: 0.93,
                    green: 0.66,
                    blue: 0.40
                ),
                scenePrimary.opacity(0.90),
                sceneDeep
            ]
        case "dusk":
            return [
                Color(
                    red: 0.20,
                    green: 0.24,
                    blue: 0.39
                ),
                scenePrimary.opacity(0.82),
                sceneDeep
            ]
        default:
            return [
                Color(
                    red: 0.67,
                    green: 0.82,
                    blue: 0.85
                ),
                scenePrimary.opacity(0.88),
                sceneDeep.opacity(0.92)
            ]
        }
    }
}

private struct HomeActivityNormalizedRouteShape:
    Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        let points =
            sampled(
                coordinates,
                maximumCount: 90
            )

        guard points.count >= 2 else {
            return Path()
        }

        let minLatitude =
            points.map(\.latitude).min() ?? 0
        let maxLatitude =
            points.map(\.latitude).max() ?? 1
        let minLongitude =
            points.map(\.longitude).min() ?? 0
        let maxLongitude =
            points.map(\.longitude).max() ?? 1

        let latitudeSpan =
            max(
                maxLatitude - minLatitude,
                0.000001
            )
        let longitudeSpan =
            max(
                maxLongitude - minLongitude,
                0.000001
            )

        var path = Path()

        for (index, coordinate)
            in points.enumerated() {
            let normalizedX =
                (
                    coordinate.longitude -
                    minLongitude
                ) / longitudeSpan

            let normalizedY =
                1 -
                (
                    coordinate.latitude -
                    minLatitude
                ) / latitudeSpan

            let point = CGPoint(
                x:
                    rect.minX +
                    rect.width *
                    (
                        0.05 +
                        normalizedX * 0.90
                    ),
                y:
                    rect.minY +
                    rect.height *
                    (
                        0.08 +
                        normalizedY * 0.84
                    )
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func sampled(
        _ values: [CLLocationCoordinate2D],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard values.count > maximumCount,
              maximumCount > 2
        else {
            return values
        }

        let lastIndex = values.count - 1
        let step =
            Double(lastIndex) /
            Double(maximumCount - 1)

        return (0..<maximumCount).map {
            index in
            values[
                min(
                    Int(
                        (
                            Double(index) *
                            step
                        )
                        .rounded()
                    ),
                    lastIndex
                )
            ]
        }
    }
}

private struct HomeActivityMountainShape:
    Shape {
    let phase: CGFloat
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.maxY
            )
        )

        let peaks = 6

        for index in 0...peaks {
            let progress =
                CGFloat(index) /
                CGFloat(peaks)

            let wave =
                sin(
                    (
                        progress +
                        phase
                    ) *
                    .pi *
                    2
                )

            let secondWave =
                sin(
                    (
                        progress * 2.35 +
                        phase * 0.7
                    ) *
                    .pi *
                    2
                )

            let y =
                rect.maxY -
                rect.height *
                (
                    depth +
                    wave * 0.17 +
                    secondWave * 0.07
                )

            path.addLine(
                to: CGPoint(
                    x:
                        rect.minX +
                        rect.width *
                        progress,
                    y: y
                )
            )
        }

        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: rect.maxY
            )
        )
        path.closeSubpath()

        return path
    }
}

private struct HomeActivityWaveShape:
    Shape {
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for band in 0..<4 {
            let offset =
                CGFloat(band) *
                rect.height * 0.16

            var bandPath = Path()

            for index in 0...32 {
                let progress =
                    CGFloat(index) / 32

                let x =
                    rect.minX +
                    rect.width *
                    progress

                let y =
                    rect.minY +
                    rect.height * 0.18 +
                    offset +
                    sin(
                        (
                            progress * 2.2 +
                            phase +
                            CGFloat(band) *
                            0.12
                        ) *
                        .pi *
                        2
                    ) *
                    rect.height * 0.07

                if index == 0 {
                    bandPath.move(
                        to: CGPoint(
                            x: x,
                            y: y
                        )
                    )
                } else {
                    bandPath.addLine(
                        to: CGPoint(
                            x: x,
                            y: y
                        )
                    )
                }
            }

            path.addPath(bandPath)
        }

        return path
    }
}

private struct HomeActivityContourLines:
    Shape {
    let variant: Int

    func path(in rect: CGRect) -> Path {
        var result = Path()

        for band in 0..<6 {
            var path = Path()
            let base =
                CGFloat(band) /
                6

            for index in 0...28 {
                let progress =
                    CGFloat(index) / 28

                let x =
                    rect.minX +
                    rect.width * progress

                let y =
                    rect.minY +
                    rect.height *
                    (
                        0.18 +
                        base * 0.68
                    ) +
                    sin(
                        (
                            progress * 1.65 +
                            CGFloat(band) * 0.12 +
                            CGFloat(variant) * 0.09
                        ) *
                        .pi *
                        2
                    ) *
                    rect.height * 0.028

                if index == 0 {
                    path.move(
                        to: CGPoint(
                            x: x,
                            y: y
                        )
                    )
                } else {
                    path.addLine(
                        to: CGPoint(
                            x: x,
                            y: y
                        )
                    )
                }
            }

            result.addPath(path)
        }

        return result
    }
}
