import CoreLocation
import SwiftUI

private struct HomeRaceYourselfPreview: Equatable {
    let workoutID: UUID
    let startedAt: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let route: [CLLocationCoordinate2D]

    var distanceText: String {
        String(
            format: "%.2f km",
            distanceMeters / 1_000
        )
    }

    var durationText: String {
        let total = max(Int(duration.rounded()), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }

    var paceText: String {
        guard distanceMeters >= 100,
              duration > 0
        else {
            return "— /km"
        }

        let secondsPerKilometer =
            duration /
            (distanceMeters / 1_000)

        let rounded =
            max(
                Int(
                    secondsPerKilometer
                        .rounded()
                ),
                0
            )

        return String(
            format:
                "%d:%02d /km",
            rounded / 60,
            rounded % 60
        )
    }
}

struct HomeRaceYourselfCard: View {
    @EnvironmentObject private var health: HealthKitManager

    @State private var preview:
        HomeRaceYourselfPreview?

    @State private var isLoading =
        false

    var body: some View {
        NavigationLink {
            GhostRaceHubView()
        } label: {
            ZStack {
                background

                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    header

                    if let preview {
                        workoutPreview(
                            preview
                        )
                    } else {
                        emptyPreview
                    }

                    footer
                }
                .padding(18)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.72),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    Color.black.opacity(0.055),
                radius: 18,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .task(id: latestRunID) {
            await loadPreview()
        }
        .accessibilityElement(
            children: .combine
        )
        .accessibilityHint(
            "Opens Ghost Race"
        )
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(
                        red: 0.94,
                        green: 0.98,
                        blue: 0.97
                    ),
                    Color(
                        red: 0.98,
                        green: 0.97,
                        blue: 0.94
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    ATHLTHTheme.vitality
                        .opacity(0.10)
                )
                .frame(
                    width: 230,
                    height: 230
                )
                .blur(radius: 1)
                .offset(
                    x: 145,
                    y: -80
                )

            Circle()
                .fill(
                    ATHLTHTheme.premiumGold
                        .opacity(0.08)
                )
                .frame(
                    width: 170,
                    height: 170
                )
                .offset(
                    x: -150,
                    y: 120
                )
        }
    }

    private var header: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text("RACE YOURSELF")
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .tracking(1.8)
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                Text(
                    preview == nil
                        ? "Your next run can have a rival."
                        : "Same route. A faster you."
                )
                .font(
                    .system(
                        size: 23,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .multilineTextAlignment(
                    .leading
                )
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(
                        Color.white
                            .opacity(0.72)
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )

                Image(
                    systemName:
                        "figure.run.circle.fill"
                )
                .font(
                    .system(size: 31)
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
            }
        }
    }

    private func workoutPreview(
        _ preview:
            HomeRaceYourselfPreview
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: 16
        ) {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Text(
                    "Race your last GPS run"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    preview.startedAt
                        .formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                HStack(
                    spacing: 8
                ) {
                    metric(
                        preview.distanceText,
                        icon:
                            "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    metric(
                        preview.durationText,
                        icon: "stopwatch.fill"
                    )

                    metric(
                        preview.paceText,
                        icon:
                            "gauge.with.dots.needle.50percent"
                    )
                }
            }

            Spacer(minLength: 0)

            HomeGhostRoutePreview(
                coordinates:
                    preview.route
            )
            .frame(
                width: 126,
                height: 118
            )
        }
    }

    private var emptyPreview:
        some View {
        HStack(
            spacing: 15
        ) {
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                Text(
                    isLoading
                        ? "Finding your latest run…"
                        : "Complete an outdoor GPS run to create your first ghost."
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                Text(
                    "ATHLTH can replay your own pace on the same route."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            ZStack {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(
                    Color.white
                        .opacity(0.58)
                )

                Image(
                    systemName:
                        "person.fill.viewfinder"
                )
                .font(
                    .system(
                        size: 34,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                        .opacity(0.72)
                )
            }
            .frame(
                width: 104,
                height: 104
            )
        }
    }

    private var footer:
        some View {
        HStack(
            spacing: 10
        ) {
            Label(
                preview == nil
                    ? "Open Ghost Race"
                    : "Race this run",
                systemImage:
                    "flag.checkered"
            )
            .font(
                .subheadline
                    .weight(.semibold)
            )
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )

            Spacer()

            Text("Ghost Race")
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .caption2.bold()
            )
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
        }
        .padding(.top, 2)
    }

    private func metric(
        _ value: String,
        icon: String
    ) -> some View {
        Label(
            value,
            systemImage: icon
        )
        .font(
            .caption2
                .weight(.semibold)
        )
        .foregroundStyle(
            ATHLTHTheme.primaryText
        )
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(
            .horizontal,
            9
        )
        .padding(
            .vertical,
            6
        )
        .background(
            Color.white
                .opacity(0.68),
            in: Capsule()
        )
    }

    private var latestRunID:
        UUID? {
        health.workouts
            .filter {
                $0.activity == .running &&
                ($0.distanceMeters ?? 0) >= 250
            }
            .sorted {
                $0.startDate >
                $1.startDate
            }
            .first?
            .id
    }

    @MainActor
    private func loadPreview() async {
        guard let workout =
                health.workouts
                    .filter({
                        $0.activity == .running &&
                        ($0.distanceMeters ?? 0) >= 250
                    })
                    .sorted({
                        $0.startDate >
                        $1.startDate
                    })
                    .first
        else {
            preview = nil
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        let detail =
            await health.workoutDetail(
                for: workout
            )

        guard detail.route.count >= 2
        else {
            preview = nil
            return
        }

        let coordinates =
            detail.route
                .filter {
                    CLLocationCoordinate2DIsValid(
                        $0.coordinate
                    )
                }
                .map(
                    \.coordinate
                )

        guard coordinates.count >= 2
        else {
            preview = nil
            return
        }

        preview =
            HomeRaceYourselfPreview(
                workoutID:
                    workout.id,
                startedAt:
                    workout.startDate,
                duration:
                    workout.duration,
                distanceMeters:
                    workout.distanceMeters ?? 0,
                route:
                    downsample(
                        coordinates,
                        maximumPoints: 120
                    )
            )
    }

    private func downsample(
        _ coordinates:
            [CLLocationCoordinate2D],
        maximumPoints: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >
                maximumPoints
        else {
            return coordinates
        }

        let step =
            max(
                coordinates.count /
                maximumPoints,
                1
            )

        var sampled =
            coordinates
                .enumerated()
                .compactMap {
                    index,
                    coordinate
                    -> CLLocationCoordinate2D? in

                    guard
                        index == 0 ||
                        index ==
                            coordinates.count - 1 ||
                        index % step == 0
                    else {
                        return nil
                    }

                    return coordinate
                }

        if let last =
                coordinates.last,
           let sampledLast =
                sampled.last,
           sampledLast.latitude !=
                last.latitude ||
           sampledLast.longitude !=
                last.longitude {
            sampled.append(last)
        }

        return sampled
    }
}

private struct HomeGhostRoutePreview:
    View {
    let coordinates:
        [CLLocationCoordinate2D]

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .fill(
                Color.white
                    .opacity(0.58)
            )

            LinearGradient(
                colors: [
                    ATHLTHTheme
                        .vitality
                        .opacity(0.06),
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )

            HomeGhostRouteShape(
                coordinates:
                    coordinates
            )
            .stroke(
                Color.white
                    .opacity(0.95),
                style:
                    StrokeStyle(
                        lineWidth: 10,
                        lineCap: .round,
                        lineJoin: .round
                    )
            )

            HomeGhostRouteShape(
                coordinates:
                    coordinates
            )
            .stroke(
                LinearGradient(
                    colors: [
                        ATHLTHTheme
                            .vitality,
                        ATHLTHTheme
                            .accentDeep
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
                style:
                    StrokeStyle(
                        lineWidth: 5,
                        lineCap: .round,
                        lineJoin: .round
                    )
            )

            Image(
                systemName:
                    "figure.run"
            )
            .font(
                .caption
                    .weight(.bold)
            )
            .foregroundStyle(.white)
            .frame(
                width: 25,
                height: 25
            )
            .background(
                ATHLTHTheme.vitality,
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        .white,
                        lineWidth: 2
                    )
            }
            .offset(
                x: 28,
                y: -20
            )
        }
        .padding(4)
    }
}

private struct HomeGhostRouteShape:
    Shape {
    let coordinates:
        [CLLocationCoordinate2D]

    func path(
        in rect: CGRect
    ) -> Path {
        guard
            coordinates.count >= 2
        else {
            return Path()
        }

        let latitudes =
            coordinates.map(
                \.latitude
            )
        let longitudes =
            coordinates.map(
                \.longitude
            )

        guard
            let minLat =
                latitudes.min(),
            let maxLat =
                latitudes.max(),
            let minLon =
                longitudes.min(),
            let maxLon =
                longitudes.max()
        else {
            return Path()
        }

        let latSpan =
            max(
                maxLat - minLat,
                0.000001
            )
        let lonSpan =
            max(
                maxLon - minLon,
                0.000001
            )

        let inset =
            rect.insetBy(
                dx: 16,
                dy: 16
            )

        func point(
            _ coordinate:
                CLLocationCoordinate2D
        ) -> CGPoint {
            let x =
                (
                    coordinate.longitude -
                    minLon
                ) /
                lonSpan
            let y =
                (
                    coordinate.latitude -
                    minLat
                ) /
                latSpan

            return CGPoint(
                x:
                    inset.minX +
                    CGFloat(x) *
                    inset.width,
                y:
                    inset.maxY -
                    CGFloat(y) *
                    inset.height
            )
        }

        var path = Path()
        path.move(
            to: point(
                coordinates[0]
            )
        )

        for coordinate
            in coordinates.dropFirst() {
            path.addLine(
                to:
                    point(
                        coordinate
                    )
            )
        }

        return path
    }
}
