import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Activity Center V2
//
// Home deliberately uses one premium activity card at a time. The previous
// Activity Center started several enrichment jobs and rendered realistic 3D
// MapKit snapshots for multiple workouts directly inside the Home feed. This
// replacement keeps the same workout data and detail destinations, but makes
// the Home surface deterministic, light and defensive around GPS input.

struct HomeActivityCenterV2: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    @State private var showingPublish = false
    @State private var selectedPublishWorkoutID: UUID?
    @State private var latestWorkoutDetail: WorkoutDetail?
    @State private var latestWorkoutDetailID: UUID?

    private var workouts: [SocialPublishableWorkout] {
        let localStrength =
            strength.workoutHistory
                .filter(\.isFinished)
                .map(
                    SocialPublishableWorkout.init
                )

        let localStrengthIDs =
            Set(localStrength.map(\.id))

        let healthWorkouts =
            health.workouts
                .map(
                    SocialPublishableWorkout.init
                )
                .filter {
                    !(
                        $0.activity == .strength &&
                        localStrengthIDs.contains(
                            $0.id
                        )
                    )
                }

        return (healthWorkouts + localStrength)
            .sorted {
                $0.startDate > $1.startDate
            }
    }

    private var latestWorkout:
        SocialPublishableWorkout? {
        workouts.first
    }

    private var friendActivity: [SocialFeedItem] {
        guard let currentUserID = social.currentUserID else {
            return Array(social.feed.prefix(2))
        }

        return Array(
            social.feed.lazy
                .filter {
                    $0.actor.userID != currentUserID
                }
                .prefix(2)
        )
    }

    private var liveFriendSessions:
        [ATHLTHLiveWorkoutSession] {
        Array(
            realtime.visibleLiveSessions.lazy
                .filter {
                    $0.ownerID != social.currentUserID
                }
                .prefix(3)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            activitySectionShell(
                title: "Following",
                subtitle:
                    Text(
                        followingSectionSubtitle
                    ),
                icon: "person.2.fill",
                tint:
                    ATHLTHTheme.recoveryBlue
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 11
                ) {
                    if social.pendingRequestCount > 0 {
                        pendingRequests
                    }

                    if !liveFriendSessions.isEmpty {
                        liveNowSection
                    }

                    if let featured =
                            friendActivity.first {
                        HomeActivityFriendFeatureCardV3(
                            item: featured
                        )

                        ForEach(
                            Array(
                                friendActivity
                                    .dropFirst()
                                    .prefix(2)
                            )
                        ) { item in
                            HomeActivityFriendCompactCardV3(
                                item: item
                            )
                        }
                    } else {
                        quietFriendsState
                    }
                }
            }

            activitySectionShell(
                title: "You",
                subtitle:
                    Text(
                        "Your latest training, kept close."
                    ),
                icon:
                    "figure.run.circle.fill",
                tint:
                    ATHLTHTheme.vitality
            ) {
                if let latestWorkout {
                    ownLatestSection(
                        latestWorkout
                    )
                } else {
                    ownEmptyState
                }
            }
        }
        .sheet(
            isPresented: $showingPublish,
            onDismiss: {
                selectedPublishWorkoutID = nil
            }
        ) {
            WorkoutPublishView(
                initialWorkoutID:
                    selectedPublishWorkoutID
            )
        }
        .task(id: latestWorkout?.id) {
            async let liveRefresh: Void =
                realtime
                    .refreshVisibleLiveSessions()

            await loadLatestWorkoutDetail()
            _ = await liveRefresh
        }
    }

    private var header: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: 12
        ) {
            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text("Activity Center")
                    .font(
                        .system(
                            size: 27,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text(
                    "Your training circle, without the noise."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            NavigationLink {
                SocialHubView(
                    initialTab: .feed
                )
            } label: {
                Image(
                    systemName:
                        "arrow.up.right"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    width: 36,
                    height: 36
                )
                .background(
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.86),
                    in: Circle()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Open activity feed"
            )
        }
        .padding(.horizontal, 2)
    }

    private var followingSectionSubtitle:
        String {
        if !liveFriendSessions.isEmpty {
            return
                "\(liveFriendSessions.count) " +
                (
                    liveFriendSessions.count == 1
                        ? "person training now"
                        : "people training now"
                )
        }

        if !friendActivity.isEmpty {
            return "Latest from people you follow"
        }

        return "Shared training from your circle"
    }

    private func activitySectionShell<
        Content: View
    >(
        title: LocalizedStringKey,
        subtitle: Text,
        icon: String,
        tint: Color,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(tint)
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .background(
                        tint.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )

                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    Text(title)
                        .font(
                            .headline.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                    subtitle
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                }

                Spacer()
            }

            content()
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.065),
                    Color.white.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 27,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 27,
                style: .continuous
            )
            .stroke(
                tint.opacity(0.10),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.035),
            radius: 12,
            y: 5
        )
    }

    private var pendingRequests: some View {
        NavigationLink {
            SocialHubView(
                initialTab: .requests
            )
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName:
                        "person.crop.circle.badge.clock"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)

                Text(
                    social.pendingRequestCount == 1
                        ? "1 request needs your attention"
                        : "\(social.pendingRequestCount) requests need your attention"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(
                Color.orange.opacity(0.08),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var liveNowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)

                Text("LIVE NOW")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Spacer()

                Text(
                    liveFriendSessions.count == 1
                        ? "1 live"
                        : "\(liveFriendSessions.count) live"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
            .padding(.horizontal, 2)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 10) {
                    ForEach(
                        liveFriendSessions
                    ) { session in
                        HomeActivityLiveCardV3(
                            session: session,
                            profile:
                                profile(
                                    for:
                                        session.ownerID
                                )
                        )
                        .frame(width: 238)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var quietFriendsState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Image(
                    systemName:
                        social.followingIDs.isEmpty
                            ? "person.2.badge.plus"
                            : "figure.run.circle"
                )
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 46, height: 46)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        social.followingIDs.isEmpty
                            ? "Build your training circle"
                            : "Your circle is quiet"
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        social.followingIDs.isEmpty
                            ? "Follow athletes and their shared training will appear here."
                            : "New workouts from people you follow will appear here automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer()
            }

            NavigationLink {
                SocialHubView(
                    initialTab:
                        social.followingIDs.isEmpty
                            ? .discover
                            : .friends
                )
            } label: {
                Label(
                    social.followingIDs.isEmpty
                        ? "Find athletes"
                        : "View following",
                    systemImage:
                        social.followingIDs.isEmpty
                            ? "magnifyingglass"
                            : "person.2"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            Color.white.opacity(0.86),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
    }

    @ViewBuilder
    private func ownLatestSection(
        _ workout: SocialPublishableWorkout
    ) -> some View {
        if workout.activity
            .isActivityCenterOutdoor {
            ownOutdoorFeatureCard(workout)
        } else {
            ownCompactFeatureCard(workout)
        }
    }

    private func ownOutdoorFeatureCard(
        _ workout: SocialPublishableWorkout
    ) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                ownWorkoutDestination(
                    workout
                )
            } label: {
                ZStack(
                    alignment: .bottomLeading
                ) {
                    HomeActivityRoutePreviewV2(
                        coordinates:
                            ownRouteCoordinates,
                        highestAltitudeMeters:
                            ownHighestAltitude
                    )
                    .frame(height: 176)

                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black
                                .opacity(0.60)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        HStack(spacing: 6) {
                            Label(
                                workout.activity
                                    .rawValue
                                    .uppercased(),
                                systemImage:
                                    workout.activity.icon
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .tracking(1.0)
                            .foregroundStyle(
                                Color.white
                                    .opacity(0.90)
                            )

                            if isPublished(workout) {
                                Text("SHARED")
                                    .font(
                                        .system(
                                            size: 8,
                                            weight: .bold
                                        )
                                    )
                                    .tracking(0.8)
                                    .foregroundStyle(
                                        Color.white
                                    )
                                    .padding(
                                        .horizontal,
                                        7
                                    )
                                    .frame(height: 22)
                                    .background(
                                        Color.black
                                            .opacity(0.28),
                                        in: Capsule()
                                    )
                            }
                        }

                        Text(workout.title)
                            .font(
                                .system(
                                    size: 21,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                Color.white
                            )
                            .lineLimit(1)

                        HStack(spacing: 10) {
                            Text(
                                ownDistanceText(
                                    workout
                                )
                            )

                            Text(
                                HomeActivityRouteMetrics
                                    .durationText(
                                        workout.duration
                                    )
                            )

                            if let heartRate =
                                    latestWorkoutDetail?
                                        .averageHeartRate,
                               heartRate.isFinite,
                               heartRate > 0 {
                                Text(
                                    "\(Int(heartRate.rounded())) bpm"
                                )
                            }
                        }
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            Color.white
                                .opacity(0.82)
                        )
                    }
                    .padding(14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        workout.startDate.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        ownRouteCoordinates
                            .count >= 2
                            ? "GPS route · cached preview"
                            : workout.summaryText
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                }

                Spacer()

                Button {
                    selectedPublishWorkoutID =
                        workout.id
                    showingPublish = true
                } label: {
                    Image(
                        systemName:
                            isPublished(workout)
                                ? "square.and.arrow.up.fill"
                                : "square.and.arrow.up"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .background(
                        ATHLTHTheme
                            .accentSoft,
                        in: Circle()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isPublished(workout)
                        ? "Update shared workout"
                        : "Share workout"
                )
            }
            .padding(12)
            .background(
                Color.white.opacity(0.96)
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.vitality
                    .opacity(0.10),
                lineWidth: 0.8
            )
        }
    }

    private func ownCompactFeatureCard(
        _ workout: SocialPublishableWorkout
    ) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                ownWorkoutDestination(
                    workout
                )
            } label: {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            workout.activity.icon
                    )
                    .font(
                        .system(
                            size: 19,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.white
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme
                                    .accentDeep,
                                ATHLTHTheme
                                    .vitality
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(workout.title)
                            .font(
                                .subheadline
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)

                        Text(
                            workout.summaryText
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)

                        Text(
                            workout.startDate,
                            style: .relative
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                selectedPublishWorkoutID =
                    workout.id
                showingPublish = true
            } label: {
                Image(
                    systemName:
                        isPublished(workout)
                            ? "checkmark.circle.fill"
                            : "square.and.arrow.up"
                )
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    width: 40,
                    height: 40
                )
                .background(
                    Color.white.opacity(0.88),
                    in: Circle()
                )
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(
            Color.white.opacity(0.92),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }

    private var ownEmptyState:
        some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "figure.run.circle"
            )
            .font(
                .system(
                    size: 22,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .frame(
                width: 46,
                height: 46
            )
            .background(
                ATHLTHTheme
                    .vitalitySoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text("Nothing here yet")
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    "Your latest completed workout will appear here automatically."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(13)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
    }

    private var ownRouteCoordinates:
        [CLLocationCoordinate2D] {
        HomeActivityRouteSanitizer
            .sampledCoordinates(
                from:
                    latestWorkoutDetail?
                        .route ?? [],
                maximumCount: 80
            )
    }

    private var ownHighestAltitude:
        Double? {
        HomeActivityRouteMetrics
            .highestAltitude(
                in:
                    HomeActivityRouteSanitizer
                        .validLocations(
                            latestWorkoutDetail?
                                .route ?? []
                        )
            )
    }

    private func ownDistanceText(
        _ workout:
            SocialPublishableWorkout
    ) -> String {
        guard let distance =
                workout.distanceMeters,
              distance.isFinite,
              distance > 0
        else {
            return workout.activity.rawValue
        }

        return String(
            format: "%.2f km",
            distance / 1_000
        )
    }

    @MainActor
    private func loadLatestWorkoutDetail()
        async {
        guard let latestWorkout,
              latestWorkout.activity
                .isActivityCenterOutdoor
        else {
            latestWorkoutDetail = nil
            latestWorkoutDetailID = nil
            return
        }

        guard latestWorkoutDetailID !=
                latestWorkout.id
        else {
            return
        }

        latestWorkoutDetailID =
            latestWorkout.id
        latestWorkoutDetail =
            await health.workoutDetail(
                for: latestWorkout.id
            )
    }

    @ViewBuilder
    private func ownWorkoutDestination(
        _ workout: SocialPublishableWorkout
    ) -> some View {
        if workout.activity == .strength {
            HomeActivityStrengthDetailView(
                workout: workout,
                strengthWorkout:
                    strength.workoutHistory
                        .first {
                            $0.id == workout.id ||
                            $0
                                .healthMetrics
                                .healthKitWorkoutUUID ==
                                workout.id
                        }
            )
        } else if workout.activity
            .isActivityCenterOutdoor {
            HomeActivityRunDetailView(
                workout: workout,
                initialDetail: nil,
                initialAIInsight: nil
            )
        } else {
            WorkoutHistoryDetailView(
                workout: workout
            )
        }
    }

    private func profile(
        for userID: UUID
    ) -> SocialProfileCard? {
        if let feedProfile =
            social.feed.first(
                where: {
                    $0.actor.userID ==
                        userID
                }
            )?.actor {
            return feedProfile
        }

        return social.visibleProfiles.first {
            $0.userID == userID
        }
    }

    private func isPublished(
        _ workout: SocialPublishableWorkout
    ) -> Bool {
        social.feed.contains { item in
            item.actor.userID ==
                social.currentUserID &&
            item.activity.kind == "workout" &&
            item.activity.metadata?[
                "workout_id"
            ] == workout.id.uuidString
        }
    }
}

private struct HomeActivityLiveCardV3: View {
    let session: ATHLTHLiveWorkoutSession
    let profile: SocialProfileCard?

    var body: some View {
        NavigationLink {
            ATHLTHLiveWorkoutMapView(
                session: session
            )
        } label: {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack(spacing: 10) {
                    if let profile {
                        SocialAvatar(
                            profile: profile,
                            size: 38
                        )
                    } else {
                        Image(
                            systemName:
                                "person.fill"
                        )
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(
                            width: 38,
                            height: 38
                        )
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: Circle()
                        )
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            profile?.resolvedName ??
                            "ATHLTH athlete"
                        )
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.red)
                                .frame(
                                    width: 6,
                                    height: 6
                                )

                            Text("LIVE")
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .bold
                                    )
                                )
                                .tracking(0.8)
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer()

                    Image(
                        systemName:
                            session
                                .ghostChallengeID ==
                                nil
                                ? liveActivityIcon
                                : "flag.checkered"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(liveSubtitle)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(1)
                }

                HStack {
                    Label(
                        session.startedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        ),
                        systemImage: "clock"
                    )

                    Spacer()

                    Label(
                        "View live",
                        systemImage:
                            "location.fill"
                    )
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }
            .padding(14)
            .frame(
                maxWidth: .infinity,
                minHeight: 148,
                alignment: .topLeading
            )
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.94),
                        ATHLTHTheme.vitalitySoft
                            .opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.vitality
                        .opacity(0.14),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var liveSubtitle: String {
        if let routeTitle =
            session.routeTitle?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
           !routeTitle.isEmpty {
            return routeTitle
        }

        return
            session.ghostChallengeID == nil
                ? "Live workout"
                : "Live Ghost training"
    }

    private var liveActivityIcon: String {
        let activity =
            session.activity.lowercased()

        if activity.contains("walk") {
            return "figure.walk"
        }

        if activity.contains("strength") ||
            activity.contains("functional") {
            return "dumbbell.fill"
        }

        if activity.contains("cycle") {
            return "figure.outdoor.cycle"
        }

        return "figure.run"
    }
}

private struct HomeActivityFriendFeatureCardV3:
    View {
    @EnvironmentObject private var social:
        SocialStore

    let item: SocialFeedItem

    private var workoutActivity:
        WorkoutActivity? {
        guard item.activity.kind == "workout",
              let raw =
                item.activity.metadata?["kind"]
        else {
            return nil
        }

        return WorkoutActivity(
            rawValue: raw
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                NavigationLink {
                    FriendProfileView(
                        userID:
                            item.actor.userID
                    )
                } label: {
                    SocialAvatar(
                        profile: item.actor,
                        size: 43
                    )
                }
                .buttonStyle(.plain)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    NavigationLink {
                        FriendProfileView(
                            userID:
                                item.actor.userID
                        )
                    } label: {
                        Text(
                            item.actor
                                .resolvedName
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                    }
                    .buttonStyle(.plain)

                    Text(
                        item.activity.createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                if item.activity.kind ==
                    "workout" {
                    Text(
                        activityLabel
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .tracking(1.0)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
                }
            }
            .padding(15)

            activityArtwork
                .frame(height: 142)

            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                Text(item.activity.title)
                    .font(
                        .title3.weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(2)

                if let subtitle =
                    item.activity.subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(2)
                }

                if let names =
                    item.activity
                        .metadata?["with_names"],
                   !names.isEmpty {
                    Label(
                        "with \(names)",
                        systemImage:
                            "person.2.fill"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .lineLimit(1)
                }

                if let caption =
                    item.activity
                        .metadata?["caption"],
                   !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                                .opacity(0.82)
                        )
                        .lineLimit(3)
                }

                HomeActivityReactionBarV3(
                    item: item
                )
                .padding(.top, 2)
            }
            .padding(15)
        }
        .background(Color.white.opacity(0.94))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.05),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.055),
            radius: 13,
            y: 7
        )
    }

    private var activityArtwork:
        some View {
        ZStack {
            LinearGradient(
                colors: artworkColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HomeActivityMotionArtworkV3(
                activity: workoutActivity
            )

            HStack(
                alignment: .bottom
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(activityLabel)
                        .font(
                            .caption2.weight(
                                .bold
                            )
                        )
                        .tracking(1.7)
                        .foregroundStyle(
                            Color.white
                                .opacity(0.72)
                        )

                    Text(
                        artworkHeadline
                    )
                    .font(
                        .system(
                            size: 24,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        Color.white
                    )
                    .lineLimit(1)
                }

                Spacer()
            }
            .padding(16)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var artworkColors:
        [Color] {
        switch workoutActivity {
        case .running:
            return [
                ATHLTHTheme.vitality,
                ATHLTHTheme.accentDeep
            ]
        case .walking, .hiking:
            return [
                ATHLTHTheme.recoveryBlue,
                ATHLTHTheme.accentDeep
            ]
        case .strength:
            return [
                ATHLTHTheme.primaryText,
                ATHLTHTheme.accentDeep
            ]
        case .cycling:
            return [
                Color.blue.opacity(0.88),
                ATHLTHTheme.primaryText
            ]
        case .swimming:
            return [
                Color.cyan.opacity(0.82),
                Color.blue.opacity(0.90)
            ]
        default:
            return [
                ATHLTHTheme.accentDeep,
                ATHLTHTheme.primaryText
            ]
        }
    }

    private var artworkHeadline:
        String {
        switch workoutActivity {
        case .running:
            return "Run complete"
        case .walking:
            return "Walk complete"
        case .hiking:
            return "Trail time"
        case .strength:
            return "Strength work"
        case .cycling:
            return "Ride complete"
        case .swimming:
            return "Swim complete"
        default:
            switch item.activity.kind {
            case "personal_record":
                return "New milestone"
            case "challenge":
                return "Challenge update"
            case "trophy":
                return "Achievement"
            case "goal":
                return "Goal progress"
            default:
                return "Activity"
            }
        }
    }

    private var activityLabel:
        String {
        if let workoutActivity {
            return workoutActivity.rawValue
                .uppercased()
        }

        switch item.activity.kind {
        case "personal_record":
            return "PERSONAL RECORD"
        case "challenge":
            return "CHALLENGE"
        case "trophy":
            return "TROPHY"
        case "goal":
            return "GOAL"
        default:
            return "ACTIVITY"
        }
    }
}

private struct HomeActivityMotionArtworkV3:
    View {
    let activity: WorkoutActivity?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    Color.white.opacity(0.07)
                )
                .frame(
                    width: 178,
                    height: 178
                )
                .offset(
                    x: 118,
                    y: -34
                )

            Circle()
                .stroke(
                    Color.white.opacity(0.10),
                    lineWidth: 18
                )
                .frame(
                    width: 112,
                    height: 112
                )
                .offset(
                    x: -122,
                    y: 62
                )

            if activity == .running ||
                activity == .walking ||
                activity == .hiking ||
                activity == .cycling {
                Canvas { context, size in
                    var path = Path()
                    path.move(
                        to: CGPoint(
                            x: size.width * 0.13,
                            y: size.height * 0.68
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: size.width * 0.48,
                            y: size.height * 0.42
                        ),
                        control1: CGPoint(
                            x: size.width * 0.23,
                            y: size.height * 0.32
                        ),
                        control2: CGPoint(
                            x: size.width * 0.38,
                            y: size.height * 0.70
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: size.width * 0.86,
                            y: size.height * 0.34
                        ),
                        control1: CGPoint(
                            x: size.width * 0.62,
                            y: size.height * 0.18
                        ),
                        control2: CGPoint(
                            x: size.width * 0.73,
                            y: size.height * 0.63
                        )
                    )

                    context.stroke(
                        path,
                        with: .color(
                            Color.white
                                .opacity(0.50)
                        ),
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }

            HStack {
                Spacer()

                Image(
                    systemName:
                        activity?.icon ??
                        "sparkles"
                )
                .font(
                    .system(
                        size: 64,
                        weight: .light
                    )
                )
                .symbolRenderingMode(
                    .hierarchical
                )
                .foregroundStyle(
                    Color.white.opacity(0.20)
                )
                .padding(.trailing, 24)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HomeActivityFriendCompactCardV3:
    View {
    let item: SocialFeedItem

    private var workoutActivity:
        WorkoutActivity? {
        guard item.activity.kind == "workout",
              let raw =
                item.activity.metadata?["kind"]
        else {
            return nil
        }

        return WorkoutActivity(
            rawValue: raw
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                FriendProfileView(
                    userID: item.actor.userID
                )
            } label: {
                SocialAvatar(
                    profile: item.actor,
                    size: 43
                )
            }
            .buttonStyle(.plain)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                HStack(spacing: 5) {
                    Text(
                        item.actor.resolvedName
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                    Text("·")
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(
                        item.activity.createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Text(item.activity.title)
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                            .opacity(0.86)
                    )
                    .lineLimit(1)

                if let subtitle =
                    item.activity.subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(spacing: 6) {
                Image(
                    systemName:
                        workoutActivity?.icon ??
                        fallbackIcon
                )
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Circle()
                )

                if !item.reactions.isEmpty {
                    Text(
                        "\(item.reactions.count)"
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(0.88),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.8
            )
        }
    }

    private var fallbackIcon: String {
        switch item.activity.kind {
        case "personal_record":
            return "bolt.fill"
        case "challenge":
            return "flag.checkered"
        case "trophy":
            return "trophy.fill"
        case "goal":
            return "target"
        default:
            return "sparkles"
        }
    }
}

private struct HomeActivityReactionBarV3:
    View {
    @EnvironmentObject private var social:
        SocialStore

    let item: SocialFeedItem

    var body: some View {
        HStack(spacing: 7) {
            ForEach(
                SocialActivityReaction.allCases
            ) { reaction in
                Button {
                    let mine =
                        item.reactions.first {
                            $0.userID ==
                                social.currentUserID
                        }

                    Task {
                        await social.setReaction(
                            activityID: item.id,
                            reaction:
                                mine?.reaction ==
                                reaction
                                    ? nil
                                    : reaction
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(reaction.emoji)

                        let count =
                            item.reactions
                                .filter {
                                    $0.reaction ==
                                        reaction
                                }
                                .count

                        if count > 0 {
                            Text("\(count)")
                                .font(
                                    .caption2.bold()
                                )
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(
                        hasCurrentUserReaction(
                            reaction
                        )
                            ? ATHLTHTheme
                                .accentSoft
                            : Color.black
                                .opacity(0.035),
                        in: Capsule()
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            NavigationLink {
                FriendProfileView(
                    userID: item.actor.userID
                )
            } label: {
                Image(
                    systemName: "chevron.right"
                )
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .frame(
                    width: 30,
                    height: 30
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func hasCurrentUserReaction(
        _ reaction: SocialActivityReaction
    ) -> Bool {
        item.reactions.contains {
            $0.userID ==
                social.currentUserID &&
            $0.reaction == reaction
        }
    }
}

private struct HomeActivityCommunityRowV2: View {
    let item: SocialFeedItem

    var body: some View {
        NavigationLink {
            FriendProfileView(
                userID: item.actor.userID
            )
        } label: {
            HStack(spacing: 11) {
                SocialAvatar(
                    profile: item.actor,
                    size: 42
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    HStack(spacing: 5) {
                        Text(
                            item.actor.resolvedName
                        )
                        .font(
                            .subheadline.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text("·")
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                        Text(
                            item.activity.createdAt,
                            style: .relative
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    Text(item.activity.title)
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                                .opacity(0.82)
                        )
                        .lineLimit(1)

                    if let subtitle =
                        item.activity.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: activityIcon)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )
            }
            .padding(13)
            .background(
                Color.white.opacity(0.92),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    Color.black.opacity(0.045),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var activityIcon: String {
        switch item.activity.kind {
        case "workout":
            return "figure.run"
        case "trophy":
            return "trophy.fill"
        case "goal":
            return "target"
        case "challenge":
            return "person.2.fill"
        case "personal_record":
            return "bolt.fill"
        default:
            return "sparkles"
        }
    }
}

// MARK: - Outdoor card

private struct HomeActivityOutdoorCardV2: View {
    let workout: SocialPublishableWorkout
    let detail: WorkoutDetail?
    let isPublished: Bool

    private var routeLocations: [CLLocation] {
        HomeActivityRouteSanitizer.validLocations(
            detail?.route ?? []
        )
    }

    private var routeCoordinates:
        [CLLocationCoordinate2D] {
        HomeActivityRouteSanitizer.sampledCoordinates(
            from: routeLocations,
            maximumCount: 96
        )
    }

    private var elevationGainMeters: Double? {
        HomeActivityRouteMetrics.elevationGain(
            from: routeLocations
        )
    }

    private var highestAltitudeMeters: Double? {
        HomeActivityRouteMetrics.highestAltitude(
            in: routeLocations
        )
    }

    private var paceRange:
        HomeActivityPaceRange? {
        HomeActivityRouteMetrics.paceRange(
            from: routeLocations,
            fallbackAverage:
                averagePaceSecondsPerKilometer
        )
    }

    private var averagePaceSecondsPerKilometer:
        Double? {
        guard let distance =
                workout.distanceMeters,
              distance.isFinite,
              distance > 1,
              workout.duration.isFinite,
              workout.duration > 0
        else {
            return nil
        }

        let value =
            workout.duration /
            (distance / 1_000)

        guard value.isFinite,
              value >= 120,
              value <= 1_800
        else {
            return nil
        }

        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            workoutHeader

            routeHero

            summaryPanel

            intensityPanel
        }
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.075),
            radius: 14,
            x: 0,
            y: 7
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
    }

    private var workoutHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: workout.activity.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle)
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer(minLength: 46)

            if isPublished {
                Text("SHARED")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private var routeHero: some View {
        ZStack(alignment: .topLeading) {
            HomeActivityRoutePreviewV2(
                coordinates: routeCoordinates,
                highestAltitudeMeters:
                    highestAltitudeMeters
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    .clear,
                    Color.black.opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                Image(
                    systemName: "square.3.layers.3d"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .frame(width: 38, height: 38)
                .background(
                    .ultraThinMaterial,
                    in: Circle()
                )

                Spacer()

                if let highestAltitudeMeters,
                   highestAltitudeMeters > 0 {
                    HStack(spacing: 5) {
                        Image(
                            systemName: "mountain.2.fill"
                        )
                        Text(
                            "\(Int(highestAltitudeMeters.rounded())) m"
                        )
                    }
                    .font(
                        .caption.weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(
                        .ultraThinMaterial,
                        in: Capsule()
                    )
                }
            }
            .padding(13)
        }
        .frame(height: 260)
        .clipped()
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        activityTitle,
                        systemImage: workout.activity.icon
                    )
                    .font(
                        .caption.weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Text(distanceText)
                        .font(
                            .system(
                                size: 36,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }

                if let ascentText {
                    Text("▲ \(ascentText)")
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                        .padding(.bottom, 5)
                }

                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    metric(
                        value: durationText,
                        title: "Time"
                    )
                    metricDivider
                    metric(
                        value: paceText,
                        title: "/km"
                    )
                    metricDivider
                    metric(
                        value: heartRateText,
                        title: "Avg HR",
                        suffix: "bpm"
                    )
                    metricDivider
                    metric(
                        value: ascentMetricText,
                        title: "Elevation"
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 12
                ) {
                    metric(
                        value: durationText,
                        title: "Time"
                    )
                    metric(
                        value: paceText,
                        title: "Pace"
                    )
                    metric(
                        value: heartRateText,
                        title: "Avg HR",
                        suffix: "bpm"
                    )
                    metric(
                        value: ascentMetricText,
                        title: "Elevation"
                    )
                }
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.98)
        )
    }

    private var intensityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    "Pace / intensity",
                    systemImage: "waveform.path.ecg"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Spacer()

                if let paceRange {
                    Text(
                        "\(paceText(paceRange.fast)) – \(paceText(paceRange.slow)) /km"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }

            LinearGradient(
                colors: [
                    Color(
                        red: 0.04,
                        green: 0.65,
                        blue: 0.56
                    ),
                    Color(
                        red: 0.32,
                        green: 0.79,
                        blue: 0.42
                    ),
                    Color(
                        red: 0.78,
                        green: 0.86,
                        blue: 0.24
                    ),
                    Color(
                        red: 0.99,
                        green: 0.66,
                        blue: 0.10
                    ),
                    Color(
                        red: 0.93,
                        green: 0.22,
                        blue: 0.22
                    )
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 10)
            .clipShape(Capsule())

            if let paceRange {
                HStack(alignment: .top) {
                    legendValue(
                        "Faster",
                        paceText(paceRange.fast)
                    )

                    Spacer()

                    legendValue(
                        "Average",
                        paceText(
                            paceRange.average
                        )
                    )

                    Spacer()

                    legendValue(
                        "Slower",
                        paceText(paceRange.slow),
                        alignment: .trailing
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 16)
        .background(
            ATHLTHTheme.cardWarm.opacity(0.54)
        )
    }

    private func metric(
        value: String,
        title: String,
        suffix: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(
                alignment: .firstTextBaseline,
                spacing: 3
            ) {
                Text(value)
                    .font(
                        .system(
                            size: 17,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let suffix {
                    Text(suffix)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 7)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.075))
            .frame(width: 1, height: 42)
    }

    private func legendValue(
        _ title: String,
        _ value: String,
        alignment: HorizontalAlignment =
            .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            Text("\(value) /km")
                .font(
                    .caption2.weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
        }
    }

    private var activityTitle: String {
        switch workout.activity {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .cycling:
            return "Cycling"
        case .hiking:
            return "Hiking"
        default:
            return workout.activity.rawValue
        }
    }

    private var distanceText: String {
        guard let distance =
                workout.distanceMeters,
              distance.isFinite,
              distance > 0
        else {
            return "—"
        }

        return String(
            format: "%.2f km",
            distance / 1_000
        )
    }

    private var durationText: String {
        HomeActivityRouteMetrics.durationText(
            workout.duration
        )
    }

    private var paceText: String {
        guard let pace =
                averagePaceSecondsPerKilometer
        else {
            return "—"
        }

        return paceText(pace)
    }

    private func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        HomeActivityRouteMetrics.paceText(
            secondsPerKilometer
        )
    }

    private var heartRateText: String {
        guard let value =
                detail?.averageHeartRate,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return String(
            format: "%.0f",
            value
        )
    }

    private var ascentText: String? {
        guard let elevationGainMeters,
              elevationGainMeters > 0
        else {
            return nil
        }

        return String(
            format: "%.0f m",
            elevationGainMeters
        )
    }

    private var ascentMetricText: String {
        ascentText ?? "—"
    }
}

// MARK: - Strength card

private struct HomeActivityStrengthCardV2: View {
    let workout: SocialPublishableWorkout
    let summary: StrengthMuscleSessionSummary
    let isPublished: Bool

    private var topMuscles:
        [StrengthMuscleActivation] {
        Array(
            summary.profile
                .topActivations
                .prefix(4)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        Color.indigo.opacity(0.09),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Strength")
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        workout.startDate.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer(minLength: 46)

                if isPublished {
                    Text("SHARED")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            ATHLTHTheme.champagneSoft,
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.95,
                            green: 0.95,
                            blue: 0.98
                        ),
                        Color.white,
                        ATHLTHTheme.cardWarm
                            .opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                StrengthMuscleMapView(
                    profile: summary.profile,
                    compact: true
                )
                .padding(.vertical, 18)
                .padding(.horizontal, 58)
            }
            .frame(height: 250)
            .clipped()

            VStack(alignment: .leading, spacing: 13) {
                Text(displayTitle)
                    .font(
                        .system(
                            size: 25,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                HStack(spacing: 0) {
                    strengthMetric(
                        HomeActivityRouteMetrics.durationText(
                            workout.duration
                        ),
                        "Time"
                    )
                    metricDivider
                    strengthMetric(
                        "\(summary.exercises.count)",
                        "Exercises"
                    )
                    metricDivider
                    strengthMetric(
                        "\(summary.totalSets)",
                        "Sets"
                    )
                    metricDivider
                    strengthMetric(
                        volumeText,
                        "Volume"
                    )
                }

                if !topMuscles.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(topMuscles) {
                            activation in

                            Text(
                                activation.region.title
                            )
                            .font(
                                .caption2.weight(
                                    .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Color.indigo.opacity(0.07),
                                in: Capsule()
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.075),
            radius: 14,
            x: 0,
            y: 7
        )
    }

    private var displayTitle: String {
        let trimmed =
            workout.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !trimmed.isEmpty,
           trimmed.lowercased() != "strength" {
            return trimmed
        }

        return "Strength session"
    }

    private var volumeText: String {
        guard summary.totalVolumeKilograms > 0
        else {
            return "—"
        }

        if summary.totalVolumeKilograms >= 1_000 {
            return String(
                format: "%.1f t",
                summary.totalVolumeKilograms /
                    1_000
            )
        }

        return String(
            format: "%.0f kg",
            summary.totalVolumeKilograms
        )
    }

    private func strengthMetric(
        _ value: String,
        _ title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(
                    .system(
                        size: 16,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 7)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.075))
            .frame(width: 1, height: 40)
    }
}

// MARK: - Generic card

private struct HomeActivityGenericCardV2: View {
    let workout: SocialPublishableWorkout
    let isPublished: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.activity.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .frame(width: 52, height: 52)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.activity.rawValue)
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Text(workout.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 42)

            if isPublished {
                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
            }
        }
        .padding(16)
        .background(
            Color.white,
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Crash-safe route preview

enum HomeActivityRouteSanitizer {
    static func validLocations(
        _ locations: [CLLocation]
    ) -> [CLLocation] {
        locations.filter {
            isValid($0.coordinate)
        }
    }

    static func sampledCoordinates(
        from locations: [CLLocation],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        sampled(
            validLocations(locations)
                .map(\.coordinate),
            maximumCount: maximumCount
        )
    }

    static func sampled(
        _ coordinates:
            [CLLocationCoordinate2D],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        let valid =
            coordinates.filter(isValid)

        guard maximumCount > 1,
              valid.count > maximumCount
        else {
            return valid
        }

        let lastIndex = valid.count - 1
        let step =
            Double(lastIndex) /
            Double(maximumCount - 1)

        return (0..<maximumCount).map {
            index in

            valid[
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

    static func isValid(
        _ coordinate:
            CLLocationCoordinate2D
    ) -> Bool {
        coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        CLLocationCoordinate2DIsValid(
            coordinate
        )
    }
}

private struct HomeActivityRoutePreviewV2: View {
    let coordinates:
        [CLLocationCoordinate2D]
    let highestAltitudeMeters: Double?

    @State private var image: UIImage?

    private var safeCoordinates:
        [CLLocationCoordinate2D] {
        HomeActivityRouteSanitizer.sampled(
            coordinates,
            maximumCount: 96
        )
    }

    private var cacheKey: String {
        HomeActivityRouteSnapshotRendererV2
            .cacheKey(
                coordinates:
                    safeCoordinates
            )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(
                        red: 0.83,
                        green: 0.89,
                        blue: 0.82
                    ),
                    Color(
                        red: 0.88,
                        green: 0.86,
                        blue: 0.72
                    ),
                    Color(
                        red: 0.72,
                        green: 0.83,
                        blue: 0.86
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if safeCoordinates.count >= 2 {
                ZStack {
                    Image(
                        systemName:
                            "map.fill"
                    )
                    .font(
                        .system(
                            size: 46,
                            weight: .light
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                            .opacity(0.14)
                    )

                    RoundedRectangle(
                        cornerRadius: 999,
                        style: .continuous
                    )
                    .fill(
                        Color.white
                            .opacity(0.34)
                    )
                    .frame(
                        width: 108,
                        height: 4
                    )
                    .rotationEffect(
                        .degrees(-18)
                    )
                }
            } else {
                VStack(spacing: 10) {
                    Image(
                        systemName:
                            "mountain.2.fill"
                    )
                    .font(
                        .system(
                            size: 58,
                            weight: .light
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                            .opacity(0.48)
                    )

                    Text("Route appears when GPS data is available")
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }
        }
        .task(id: cacheKey) {
            image = nil

            guard safeCoordinates.count >= 2
            else {
                return
            }

            let rendered =
                await HomeActivityRouteSnapshotRendererV2
                    .shared
                    .image(
                        coordinates:
                            safeCoordinates
                    )

            guard !Task.isCancelled else {
                return
            }

            image = rendered
        }
    }
}

@MainActor
private final class
    HomeActivityRouteSnapshotRendererV2 {
    static let shared =
        HomeActivityRouteSnapshotRendererV2()

    private let cache =
        NSCache<NSString, UIImage>()

    private init() {
        // Home only ever needs a handful of recent previews. Keep this cache
        // deliberately small so Activity Center cannot become a scrolling
        // memory sink.
        cache.countLimit = 3
        cache.totalCostLimit =
            3 * 1_024 * 1_024
    }

    static func cacheKey(
        coordinates:
            [CLLocationCoordinate2D]
    ) -> String {
        let sampled =
            HomeActivityRouteSanitizer.sampled(
                coordinates,
                maximumCount: 12
            )

        guard !sampled.isEmpty else {
            return "activity-v3-empty"
        }

        return "activity-v3|" +
            sampled.map {
                String(
                    format: "%.4f,%.4f",
                    $0.latitude,
                    $0.longitude
                )
            }
            .joined(separator: "|")
    }

    func image(
        coordinates:
            [CLLocationCoordinate2D]
    ) async -> UIImage? {
        let points =
            HomeActivityRouteSanitizer.sampled(
                coordinates,
                maximumCount: 96
            )

        guard points.count >= 2,
              !Task.isCancelled
        else {
            return nil
        }

        let key =
            Self.cacheKey(
                coordinates: points
            ) as NSString

        if let cached =
            cache.object(forKey: key) {
            return cached
        }

        let size =
            CGSize(
                width: 360,
                height: 210
            )

        let options =
            MKMapSnapshotter.Options()
        options.size = size
        options.scale = 1.25
        options.region =
            Self.safeRegion(
                for: points
            )
        options.traitCollection =
            UITraitCollection(
                userInterfaceStyle: .light
            )

        // A muted standard snapshot gives geographic context without the
        // visual weight, memory pressure and GPU cost of an interactive map.
        let configuration =
            MKStandardMapConfiguration(
                elevationStyle: .flat,
                emphasisStyle: .muted
            )
        configuration.showsTraffic = false
        configuration.pointOfInterestFilter =
            .excludingAll
        options.preferredConfiguration =
            configuration

        do {
            let snapshot =
                try await MKMapSnapshotter(
                    options: options
                )
                .start()

            guard !Task.isCancelled else {
                return nil
            }

            let format =
                UIGraphicsImageRendererFormat
                    .default()
            format.scale = 1.25
            format.opaque = true

            let renderer =
                UIGraphicsImageRenderer(
                    size: size,
                    format: format
                )

            let rendered =
                renderer.image { context in
                    snapshot.image.draw(
                        in: CGRect(
                            origin: .zero,
                            size: size
                        )
                    )

                    let overlay =
                        UIColor.white
                            .withAlphaComponent(
                                0.08
                            )
                    overlay.setFill()
                    context.cgContext.fill(
                        CGRect(
                            origin: .zero,
                            size: size
                        )
                    )

                    Self.drawRoute(
                        points,
                        on: snapshot
                    )
                }

            guard !Task.isCancelled else {
                return nil
            }

            let cost =
                Int(
                    rendered.size.width *
                    rendered.size.height *
                    rendered.scale *
                    rendered.scale *
                    4
                )

            cache.setObject(
                rendered,
                forKey: key,
                cost: cost
            )

            return rendered
        } catch {
            return nil
        }
    }

    private static func safeRegion(
        for points:
            [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard let first = points.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 63.4305,
                        longitude: 10.3951
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.08,
                        longitudeDelta: 0.08
                    )
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for point in points.dropFirst() {
            minLatitude =
                min(
                    minLatitude,
                    point.latitude
                )
            maxLatitude =
                max(
                    maxLatitude,
                    point.latitude
                )
            minLongitude =
                min(
                    minLongitude,
                    point.longitude
                )
            maxLongitude =
                max(
                    maxLongitude,
                    point.longitude
                )
        }

        let center =
            CLLocationCoordinate2D(
                latitude:
                    (minLatitude +
                     maxLatitude) / 2,
                longitude:
                    (minLongitude +
                     maxLongitude) / 2
            )

        let latitudeDelta =
            min(
                max(
                    (
                        maxLatitude -
                        minLatitude
                    ) * 1.55,
                    0.008
                ),
                90
            )

        let longitudeDelta =
            min(
                max(
                    (
                        maxLongitude -
                        minLongitude
                    ) * 1.55,
                    0.008
                ),
                180
            )

        return MKCoordinateRegion(
            center: center,
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        latitudeDelta,
                    longitudeDelta:
                        longitudeDelta
                )
        )
    }

    private static func drawRoute(
        _ points:
            [CLLocationCoordinate2D],
        on snapshot:
            MKMapSnapshotter.Snapshot
    ) {
        let renderedPoints =
            points.map {
                snapshot.point(for: $0)
            }

        guard renderedPoints.count >= 2
        else {
            return
        }

        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for (
            index,
            point
        ) in renderedPoints.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        // ATHLTH route ribbon: soft shadow, white separation and a single
        // calm accent line. It stays readable without implying pace zones.
        UIColor.black
            .withAlphaComponent(0.18)
            .setStroke()
        path.lineWidth = 11
        path.stroke()

        UIColor.white
            .withAlphaComponent(0.96)
            .setStroke()
        path.lineWidth = 7
        path.stroke()

        UIColor(
            red: 0.10,
            green: 0.61,
            blue: 0.45,
            alpha: 1
        )
        .setStroke()
        path.lineWidth = 4.5
        path.stroke()

        drawStart(
            renderedPoints.first
        )
        drawCourseMarker(
            renderedPoints[
                renderedPoints.count / 2
            ]
        )
        drawFinish(
            renderedPoints.last
        )
    }

    private static func drawStart(
        _ point: CGPoint?
    ) {
        guard let point else {
            return
        }

        UIColor.white.setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 8,
                y: point.y - 8,
                width: 16,
                height: 16
            )
        )
        .fill()

        UIColor(
            red: 0.02,
            green: 0.64,
            blue: 0.53,
            alpha: 1
        )
        .setFill()

        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 4.5,
                y: point.y - 4.5,
                width: 9,
                height: 9
            )
        )
        .fill()
    }

    private static func drawCourseMarker(
        _ point: CGPoint
    ) {
        let outer =
            UIBezierPath()
        outer.move(
            to: CGPoint(
                x: point.x,
                y: point.y - 7
            )
        )
        outer.addLine(
            to: CGPoint(
                x: point.x + 7,
                y: point.y
            )
        )
        outer.addLine(
            to: CGPoint(
                x: point.x,
                y: point.y + 7
            )
        )
        outer.addLine(
            to: CGPoint(
                x: point.x - 7,
                y: point.y
            )
        )
        outer.close()

        UIColor.white
            .withAlphaComponent(0.98)
            .setFill()
        outer.fill()

        let inner =
            UIBezierPath()
        inner.move(
            to: CGPoint(
                x: point.x,
                y: point.y - 4
            )
        )
        inner.addLine(
            to: CGPoint(
                x: point.x + 4,
                y: point.y
            )
        )
        inner.addLine(
            to: CGPoint(
                x: point.x,
                y: point.y + 4
            )
        )
        inner.addLine(
            to: CGPoint(
                x: point.x - 4,
                y: point.y
            )
        )
        inner.close()

        UIColor(
            red: 0.08,
            green: 0.23,
            blue: 0.18,
            alpha: 1
        )
        .setFill()
        inner.fill()
    }

    private static func drawFinish(
        _ point: CGPoint?
    ) {
        guard let point else {
            return
        }

        UIColor.white.setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 8,
                y: point.y - 8,
                width: 16,
                height: 16
            )
        )
        .fill()

        UIColor.black
            .withAlphaComponent(0.90)
            .setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 5,
                y: point.y - 5,
                width: 10,
                height: 10
            )
        )
        .fill()
    }

    private static func interpolatedColor(
        palette: [UIColor],
        progress: CGFloat
    ) -> UIColor {
        guard palette.count > 1 else {
            return palette.first ??
                .systemGreen
        }

        let clamped =
            min(max(progress, 0), 1)
        let scaled =
            clamped *
            CGFloat(
                palette.count - 1
            )
        let lower =
            min(
                Int(floor(scaled)),
                palette.count - 1
            )
        let upper =
            min(
                lower + 1,
                palette.count - 1
            )
        let fraction =
            scaled -
            CGFloat(lower)

        return interpolate(
            palette[lower],
            palette[upper],
            fraction: fraction
        )
    }

    private static func interpolate(
        _ from: UIColor,
        _ to: UIColor,
        fraction: CGFloat
    ) -> UIColor {
        let t =
            min(max(fraction, 0), 1)

        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        var tr: CGFloat = 0
        var tg: CGFloat = 0
        var tb: CGFloat = 0
        var ta: CGFloat = 0

        guard from.getRed(
                &fr,
                green: &fg,
                blue: &fb,
                alpha: &fa
              ),
              to.getRed(
                &tr,
                green: &tg,
                blue: &tb,
                alpha: &ta
              )
        else {
            return from
        }

        return UIColor(
            red:
                fr + (tr - fr) * t,
            green:
                fg + (tg - fg) * t,
            blue:
                fb + (tb - fb) * t,
            alpha:
                fa + (ta - fa) * t
        )
    }
}

// MARK: - Metrics

private struct HomeActivityPaceRange {
    let fast: Double
    let average: Double
    let slow: Double
}

private enum HomeActivityRouteMetrics {
    static func durationText(
        _ duration: TimeInterval
    ) -> String {
        guard duration.isFinite,
              duration > 0
        else {
            return "—"
        }

        let totalSeconds =
            max(
                Int(duration.rounded()),
                0
            )
        let hours =
            totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600) / 60
        let seconds =
            totalSeconds % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
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

    static func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        guard secondsPerKilometer
                .isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let seconds =
            max(
                Int(
                    secondsPerKilometer
                        .rounded()
                ),
                0
            )

        return String(
            format:
                "%d:%02d",
            seconds / 60,
            seconds % 60
        )
    }

    static func elevationGain(
        from locations: [CLLocation]
    ) -> Double? {
        guard locations.count >= 2 else {
            return nil
        }

        var gain = 0.0

        for index in
            1..<locations.count {
            let previous =
                locations[index - 1]
            let current =
                locations[index]

            guard previous.altitude.isFinite,
                  current.altitude.isFinite
            else {
                continue
            }

            let delta =
                current.altitude -
                previous.altitude

            // Ignore obvious GPS altitude spikes in a Home summary.
            if delta > 0,
               delta < 120 {
                gain += delta
            }
        }

        return gain > 0
            ? gain
            : nil
    }

    static func highestAltitude(
        in locations: [CLLocation]
    ) -> Double? {
        locations
            .map(\.altitude)
            .filter {
                $0.isFinite &&
                $0 > -500 &&
                $0 < 9_500
            }
            .max()
    }

    static func paceRange(
        from locations: [CLLocation],
        fallbackAverage: Double?
    ) -> HomeActivityPaceRange? {
        var paces: [Double] = []

        if locations.count >= 2 {
            for index in
                1..<locations.count {
                let previous =
                    locations[index - 1]
                let current =
                    locations[index]

                let seconds =
                    current.timestamp
                        .timeIntervalSince(
                            previous.timestamp
                        )
                let meters =
                    current.distance(
                        from: previous
                    )

                guard seconds.isFinite,
                      meters.isFinite,
                      seconds > 1,
                      meters >= 5
                else {
                    continue
                }

                let pace =
                    seconds /
                    (meters / 1_000)

                if pace.isFinite,
                   pace >= 120,
                   pace <= 1_200 {
                    paces.append(pace)
                }
            }
        }

        if paces.count >= 4 {
            let sorted =
                paces.sorted()

            let fastIndex =
                min(
                    Int(
                        Double(
                            sorted.count - 1
                        ) * 0.15
                    ),
                    sorted.count - 1
                )
            let slowIndex =
                min(
                    Int(
                        Double(
                            sorted.count - 1
                        ) * 0.85
                    ),
                    sorted.count - 1
                )

            let average =
                sorted.reduce(
                    0,
                    +
                ) /
                Double(sorted.count)

            return HomeActivityPaceRange(
                fast: sorted[fastIndex],
                average: average,
                slow: sorted[slowIndex]
            )
        }

        guard let fallbackAverage,
              fallbackAverage.isFinite,
              fallbackAverage > 0
        else {
            return nil
        }

        return HomeActivityPaceRange(
            fast:
                max(
                    fallbackAverage * 0.84,
                    120
                ),
            average: fallbackAverage,
            slow:
                min(
                    fallbackAverage * 1.18,
                    1_200
                )
        )
    }
}

private extension WorkoutActivity {
    var isActivityCenterOutdoor: Bool {
        switch self {
        case .running,
             .walking,
             .cycling,
             .hiking:
            return true
        default:
            return false
        }
    }
}
