import MapKit
import SwiftUI

struct ATHLTHLiveAthletesView: View {
    @EnvironmentObject private var livePresence:
        ATHLTHLivePresenceStore
    @EnvironmentObject private var social:
        SocialStore

    var body: some View {
        List {
            if livePresence.liveSessions.isEmpty {
                ContentUnavailableView(
                    "Nobody live right now",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(
                        "Live workout sharing is opt-in. Mutual follows and accepted Ghost Race opponents appear here while they are actively sharing."
                    )
                )
            } else {
                Section("Live now") {
                    ForEach(livePresence.liveSessions) {
                        session in
                        NavigationLink {
                            ATHLTHLiveWorkoutViewerView(
                                session: session
                            )
                        } label: {
                            liveRow(session)
                        }
                    }
                }
            }

            Section {
                Text(
                    "ATHLTH never exposes live location unless the athlete has enabled live workout sharing. Live GPS is short-lived and expires automatically."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Live athletes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await livePresence.refresh()
        }
        .task {
            await livePresence.refresh()
        }
    }

    private func liveRow(
        _ session: ATHLTHLiveWorkoutSession
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ATHLTHTheme.vitality)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(name(for: session.userID))
                    .font(.headline)

                Text(
                    "\(session.title) · \(session.startedAt.formatted(date: .omitted, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if session.ghostEnabled {
                Image(systemName: "figure.run")
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
            }
        }
    }

    private func name(
        for userID: UUID
    ) -> String {
        social.visibleProfiles
            .first {
                $0.userID == userID
            }?
            .resolvedName
            ?? "Athlete"
    }
}

struct ATHLTHLiveWorkoutViewerView: View {
    @EnvironmentObject private var livePresence:
        ATHLTHLivePresenceStore
    @EnvironmentObject private var social:
        SocialStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore

    let session: ATHLTHLiveWorkoutSession

    private var points:
        [ATHLTHLiveWorkoutPoint] {
        livePresence.pointsBySession[
            session.id
        ] ?? []
    }

    private var latest:
        ATHLTHLiveWorkoutPoint? {
        points.last
    }

    private var isSelectedGhost: Bool {
        livePresence
            .selectedLiveGhostSessionID ==
            session.id
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                liveMap
                summaryCard
                ghostCard
            }
            .padding(16)
        }
        .background(
            ATHLTHTheme.canvasTop
                .ignoresSafeArea()
        )
        .navigationTitle(
            athleteName
        )
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.id) {
            while !Task.isCancelled {
                await livePresence.refreshPoints(
                    for: session.id
                )

                try? await Task.sleep(
                    for: .seconds(3)
                )
            }
        }
    }

    private var liveMap: some View {
        Map {
            if points.count >= 2 {
                MapPolyline(
                    coordinates:
                        points.map(\.coordinate)
                )
                .stroke(
                    ATHLTHTheme.vitality,
                    lineWidth: 5
                )
            }

            if let latest {
                Marker(
                    "Live",
                    systemImage:
                        "location.fill",
                    coordinate:
                        latest.coordinate
                )
                .tint(
                    ATHLTHTheme.accentDeep
                )
            }
        }
        .frame(height: 330)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay(alignment: .topLeading) {
            Label(
                "LIVE",
                systemImage:
                    "dot.radiowaves.left.and.right"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .padding(12)
        }
    }

    private var summaryCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.title)
                    .font(.title3.bold())

                HStack(spacing: 18) {
                    metric(
                        "Distance",
                        latest.map {
                            String(
                                format: "%.2f km",
                                $0.distanceMeters /
                                    1_000
                            )
                        } ?? "—"
                    )

                    metric(
                        "Active",
                        latest.map {
                            Duration.seconds(
                                $0.elapsedSeconds
                            )
                            .formatted(
                                .time(
                                    pattern:
                                        .hourMinute
                                )
                            )
                        } ?? "—"
                    )

                    metric(
                        "Updated",
                        latest?.capturedAt
                            .formatted(
                                date: .omitted,
                                time: .shortened
                            )
                        ?? "—"
                    )
                }
            }
        }
    }

    private var ghostCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Live Ghost",
                    systemImage: "figure.run"
                )
                .font(.headline)

                if let active = phoneWorkout.active,
                   let delta =
                    livePresence
                        .liveGhostDeltaMeters(
                            ownDistanceMeters:
                                active.distanceMeters
                        ),
                   isSelectedGhost {
                    Text(
                        ghostDeltaText(delta)
                    )
                    .font(.title3.bold())
                    .foregroundStyle(
                        delta >= 0
                            ? ATHLTHTheme.vitality
                            : .orange
                    )
                } else {
                    Text(
                        "Select this athlete as your live ghost. If you start an iPhone run, ATHLTH compares your live distance with theirs."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button {
                    livePresence
                        .selectedLiveGhostSessionID =
                        isSelectedGhost
                            ? nil
                            : session.id
                } label: {
                    Label(
                        isSelectedGhost
                            ? "Stop Live Ghost"
                            : "Race this live run",
                        systemImage:
                            isSelectedGhost
                                ? "xmark.circle"
                                : "bolt.horizontal.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.vitality)
                .disabled(!session.ghostEnabled)
            }
        }
    }

    private var athleteName: String {
        social.visibleProfiles
            .first {
                $0.userID == session.userID
            }?
            .resolvedName
            ?? "Live workout"
    }

    private func metric(
        _ title: String,
        _ value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func ghostDeltaText(
        _ meters: Double
    ) -> String {
        let amount =
            Int(abs(meters).rounded())

        if abs(meters) < 5 {
            return "Side by side"
        }

        return meters >= 0
            ? "You are \(amount) m ahead"
            : "Ghost is \(amount) m ahead"
    }
}
