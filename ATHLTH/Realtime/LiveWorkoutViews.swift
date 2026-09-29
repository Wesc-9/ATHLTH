import MapKit
import SwiftUI

struct LiveWorkoutViewerView: View {
    @EnvironmentObject private var realtime: ATHLTHRealtimeStore

    let session: LiveWorkoutSessionRecord
    let athlete: SocialProfileCard?

    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                liveMap
                metrics
                privacyNote
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.vitality
                        .opacity(0.20)
            )
        )
        .navigationTitle("Live Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.id) {
            await realtime.watch(session)
        }
        .onDisappear {
            Task {
                await realtime.stopWatching()
            }
        }
        .onChange(of: realtime.watchedLocation) { _, location in
            guard let location,
                  location.sessionID == session.id
            else {
                return
            }

            mapPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.012,
                        longitudeDelta: 0.012
                    )
                )
            )
        }
    }

    private var header: some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                if let athlete {
                    SocialAvatar(
                        profile: athlete,
                        size: 48
                    )
                } else {
                    Image(systemName: "figure.run")
                        .font(.title2)
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                        .frame(
                            width: 48,
                            height: 48
                        )
                        .background(
                            ATHLTHTheme
                                .vitalitySoft,
                            in: Circle()
                        )
                }

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(
                                width: 8,
                                height: 8
                            )

                        Text(
                            session.isGhostRace
                                ? "LIVE GHOST RACE"
                                : "LIVE WORKOUT"
                        )
                        .font(
                            .caption2.weight(.bold)
                        )
                        .tracking(1.2)
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                    }

                    Text(
                        athlete?.resolvedName ??
                        session.title ??
                        "ATHLTH athlete"
                    )
                    .font(.headline)

                    Text(
                        session.startedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(
                    systemName:
                        session.isGhostRace
                            ? "figure.run.circle.fill"
                            : "location.fill.viewfinder"
                )
                .font(.title2)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }
        }
    }

    @ViewBuilder
    private var liveMap: some View {
        ATHLTHCard {
            if let location =
                    realtime.watchedLocation,
               location.sessionID == session.id {
                Map(position: $mapPosition) {
                    let trail =
                        realtime.watchedTrail
                            .filter {
                                $0.sessionID ==
                                    session.id
                            }
                            .map(\.coordinate)

                    if trail.count >= 2 {
                        MapPolyline(
                            coordinates: trail
                        )
                        .stroke(
                            ATHLTHTheme.vitality,
                            style: StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }

                    Annotation(
                        athlete?.resolvedName ??
                        "Live",
                        coordinate:
                            location.coordinate
                    ) {
                        ZStack {
                            Circle()
                                .fill(
                                    ATHLTHTheme
                                        .accentDeep
                                )
                                .frame(
                                    width: 30,
                                    height: 30
                                )

                            Image(
                                systemName:
                                    "figure.run"
                            )
                            .font(
                                .caption.weight(
                                    .bold
                                )
                            )
                            .foregroundStyle(.white)
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    .white,
                                    lineWidth: 3
                                )
                        }
                        .shadow(
                            color:
                                .black.opacity(0.14),
                            radius: 5,
                            y: 2
                        )
                    }
                }
                .mapStyle(
                    .standard(
                        elevation: .flat
                    )
                )
                .frame(height: 360)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .overlay(alignment: .topLeading) {
                    Label(
                        "Live · updated ",
                        systemImage:
                            "dot.radiowaves.left.and.right"
                    )
                    .font(
                        .caption2.weight(
                            .semibold
                        )
                    )
                    .padding(
                        .horizontal,
                        10
                    )
                    .padding(
                        .vertical,
                        7
                    )
                    .background(
                        .thinMaterial,
                        in: Capsule()
                    )
                    .overlay(alignment: .trailing) {
                        Text(
                            location
                                .capturedDate,
                            style: .relative
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                        .offset(x: 74)
                    }
                    .padding(10)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()

                    Text(
                        "Connecting to live GPS…"
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )

                    Text(
                        "The runner's next shared GPS point will appear here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(
                        .center
                    )
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 260
                )
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {
            metric(
                title: "Distance",
                value:
                    realtime.watchedLocation
                        .map {
                            String(
                                format: "%.2f km",
                                $0.distanceMeters /
                                    1_000
                            )
                        } ?? "—",
                icon: "location.fill"
            )

            metric(
                title: "Elapsed",
                value:
                    realtime.watchedLocation
                        .map {
                            durationText(
                                $0.elapsedTime
                            )
                        } ?? "—",
                icon: "stopwatch.fill"
            )

            if let progress =
                    realtime.watchedLocation?
                        .routeProgressPercent {
                metric(
                    title: "Route",
                    value:
                        String(
                            format: "%.0f%%",
                            progress
                        ),
                    icon:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
            }

            metric(
                title: "Status",
                value:
                    realtime.watchedLocation?
                        .state
                        .capitalized ??
                        session.status
                            .capitalized,
                icon:
                    realtime.watchedLocation?
                        .state == "paused"
                        ? "pause.fill"
                        : "figure.run"
            )
        }
    }

    private var privacyNote: some View {
        ATHLTHCard {
            Label(
                "Live GPS is ephemeral. ATHLTH keeps the session metadata, but not this location trail, after the workout ends.",
                systemImage: "lock.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
        }
    }

    private func metric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                Image(systemName: icon)
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                Text(value)
                    .font(
                        .title3.weight(.bold)
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private func durationText(
        _ duration: TimeInterval
    ) -> String {
        let total =
            max(
                Int(duration.rounded()),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
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
}
