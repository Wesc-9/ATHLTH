import MapKit
import SwiftUI

struct ATHLTHOnlineAvatar: View {
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        SocialAvatar(
            profile: profile,
            size: size
        )
        .overlay(alignment: .bottomTrailing) {
            if realtime.isOnline(profile.userID) {
                Circle()
                    .fill(Color.green)
                    .frame(
                        width: max(size * 0.24, 11),
                        height: max(size * 0.24, 11)
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white,
                                lineWidth: 2
                            )
                    }
                    .accessibilityLabel("Online")
            }
        }
    }
}

struct ATHLTHLiveWorkoutMapView: View {
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var social: SocialStore

    let session: ATHLTHLiveWorkoutSession

    var body: some View {
        VStack(spacing: 0) {
            Map {
                ForEach(
                    Array(
                        realtime
                            .liveTrails
                            .keys
                    ),
                    id: \.self
                ) { userID in
                    if let coordinates =
                        realtime.liveTrails[userID],
                       coordinates.count >= 2 {
                        MapPolyline(
                            coordinates:
                                coordinates
                        )
                        .stroke(
                            trailColor(userID)
                                .opacity(0.62),
                            style:
                                StrokeStyle(
                                    lineWidth: 5,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                        )
                    }
                }

                ForEach(realtime.liveLocations) { location in
                    Annotation(
                        displayName(location.userID),
                        coordinate: location.coordinate
                    ) {
                        VStack(spacing: 4) {
                            Image(
                                systemName:
                                    location.userID ==
                                    session.ownerID
                                        ? "figure.run.circle.fill"
                                        : "person.crop.circle.fill"
                            )
                            .font(.system(size: 30))
                            .foregroundStyle(
                                location.userID ==
                                session.ownerID
                                    ? ATHLTHTheme.vitality
                                    : ATHLTHTheme.accent
                            )
                            .background(
                                Color.white,
                                in: Circle()
                            )

                            Text(displayName(location.userID))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    .thinMaterial,
                                    in: Capsule()
                                )
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay {
                if realtime.liveLocations.isEmpty {
                    ContentUnavailableView(
                        "Waiting for live position",
                        systemImage: "location.circle",
                        description: Text(
                            "The map updates only while a participant is actively sharing a supported outdoor workout."
                        )
                    )
                    .padding()
                    .background(.thinMaterial)
                }
            }

            liveSummary
                .padding(16)
                .background(.regularMaterial)
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.id) {
            realtime.startWatching(session)
        }
        .onDisappear {
            // Keep the lightweight watcher alive only when this session was
            // explicitly selected as the user's Live Ghost. Ordinary map
            // viewing stops immediately when the view closes.
            if realtime.selectedLiveGhostSessionID !=
                session.id {
                realtime.stopWatching()
            }
        }
    }

    private var liveSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    session.ghostChallengeID == nil
                        ? "LIVE WORKOUT"
                        : "LIVE GHOST RUN",
                    systemImage:
                        session.ghostChallengeID == nil
                            ? "dot.radiowaves.left.and.right"
                            : "figure.run"
                )
                .font(.caption.bold())
                .foregroundStyle(ATHLTHTheme.vitality)

                Spacer()

                Text(
                    session.startedAt.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(
                realtime.liveLocations
                    .sorted {
                        $0.distanceMeters >
                        $1.distanceMeters
                    }
            ) { location in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName(location.userID))
                            .font(.subheadline.weight(.semibold))

                        Text(
                            String(
                                format:
                                    "%.2f km · %@",
                                location.distanceMeters / 1_000,
                                elapsedText(location.elapsedSeconds)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let heartRate =
                                location.heartRateBPM,
                           heartRate > 0 {
                            Label(
                                "\(Int(heartRate.rounded())) bpm",
                                systemImage:
                                    "heart.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    Spacer()

                    Text(
                        freshnessText(location.updatedAt)
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            if currentUserIsParticipant {
                Divider()

                HStack(spacing: 12) {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text("Share my live position")
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )

                        Text(
                            "You can turn this off without stopping the workout."
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    Toggle(
                        "",
                        isOn:
                            Binding(
                                get: {
                                    realtime
                                        .isSharingLiveLocation
                                },
                                set: { enabled in
                                    Task {
                                        await realtime
                                            .setCurrentLiveLocationSharing(
                                                enabled
                                            )
                                    }
                                }
                            )
                    )
                    .labelsHidden()
                }
            }

            if session.ghostChallengeID != nil,
               realtime.liveLocations.count >= 2 {
                let ordered =
                    realtime.liveLocations
                        .sorted {
                            $0.distanceMeters >
                            $1.distanceMeters
                        }

                if let leader = ordered.first,
                   let second = ordered.dropFirst().first {
                    let delta =
                        max(
                            leader.distanceMeters -
                            second.distanceMeters,
                            0
                        )

                    Label(
                        String(
                            format:
                                "%@ is %.0f m ahead",
                            displayName(leader.userID),
                            delta
                        ),
                        systemImage:
                            "flag.checkered"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                }
            }
        }
    }

    private var currentUserIsParticipant: Bool {
        guard let currentUserID =
                realtime.currentUserID
        else {
            return false
        }

        return session.ownerID ==
            currentUserID ||
            session.opponentUserID ==
            currentUserID
    }

    private func trailColor(
        _ userID: UUID
    ) -> Color {
        if userID ==
            realtime.currentUserID {
            return ATHLTHTheme.vitality
        }

        if userID ==
            session.ownerID {
            return ATHLTHTheme.accent
        }

        return ATHLTHTheme.premiumGold
    }

    private func displayName(
        _ userID: UUID
    ) -> String {
        social.visibleProfiles
            .first(
                where: {
                    $0.userID == userID
                }
            )?
            .resolvedName ??
        social.following
            .first(
                where: {
                    $0.userID == userID
                }
            )?
            .resolvedName ??
        (
            userID == realtime.currentUserID
                ? "You"
                : "ATHLTH Athlete"
        )
    }

    private func elapsedText(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            remainder
        )
    }

    private func freshnessText(
        _ updatedAt: Date
    ) -> String {
        let age =
            max(
                Int(
                    Date()
                        .timeIntervalSince(
                            updatedAt
                        )
                        .rounded()
                ),
                0
            )

        return age < 5
            ? "Now"
            : "\(age)s ago"
    }
}
