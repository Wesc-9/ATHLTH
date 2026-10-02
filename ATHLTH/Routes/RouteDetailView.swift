import Foundation
import MapKit
import SwiftUI

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var publicTrailDiscovery:
        PublicTrailDiscoveryStore

    @StateObject private var attempts = RouteAttemptStore()
    @StateObject private var publicTrailAttempts =
        PublicTrailAttemptStore()
    @StateObject private var discovery = RouteDiscoveryStore()

    let route: TrainingRoute

    @State private var showingDeleteConfirmation = false
    @State private var showingFullLeaderboard = false
    @State private var editingTitle = false
    @State private var draftTitle = ""
    @State private var watchMessage: String?
    @State private var watchError: String?
    @State private var startingRoute = false
    @State private var startingGhostAttemptID: UUID?
    @State private var showingTargetGhost = false
    @State private var publicTrailMetadata: PublicTrailRecord?
    @State private var similarTrails: [PublicTrailRecord] = []
    @State private var loadingSimilarTrails = false
    @State private var showingSimilarTrails = false
    @State private var routeToStart: TrainingRoute?

    private var currentRoute: TrainingRoute {
        session.savedRoutes.first {
            $0.id == route.id
        } ?? route
    }

    private var isOwner: Bool {
        currentRoute.ownerID == session.profile.userID
    }

    private var isPublicTrail: Bool {
        currentRoute.routeSource == "openstreetmap" ||
        currentRoute.routeSource == "kartverket_turrutebasen" ||
        currentRoute.ownerID ==
            PublicTrailRecord.publicSourceOwnerID ||
        currentRoute.sharedSourceOwnerID ==
            PublicTrailRecord.publicSourceOwnerID
    }

    private var publicTrailID: UUID {
        currentRoute.sharedSourceRouteID ??
            currentRoute.id
    }

    private var attemptCount: Int {
        isPublicTrail
            ? publicTrailAttempts.attempts.count
            : attempts.attempts.count
    }

    private var isSyncingAttempts: Bool {
        isPublicTrail
            ? publicTrailAttempts.isSyncingHealth
            : attempts.isSyncingHealth
    }

    private var attemptErrorMessage: String? {
        isPublicTrail
            ? publicTrailAttempts.errorMessage
            : attempts.errorMessage
    }

    private var leaderboardAvailable: Bool {
        !isPublicTrail ||
            publicTrailAttempts.leaderboardEnabled
    }

    private var savedCopy: TrainingRoute? {
        if isOwner {
            return currentRoute
        }

        return session.savedRoutes.first {
            $0.sharedSourceRouteID == currentRoute.id
        }
    }

    private var leaderboard: [RouteAttemptRecord] {
        isPublicTrail
            ? publicTrailAttempts.leaderboard()
            : attempts.leaderboard()
    }

    private var topThree: [RouteAttemptRecord] {
        Array(leaderboard.prefix(3))
    }

    private var ownAttempts: [RouteAttemptRecord] {
        isPublicTrail
            ? publicTrailAttempts.attempts(
                for: session.profile.userID
            )
            : attempts.attempts(
                for: session.profile.userID
            )
    }

    private var ownBest: RouteAttemptRecord? {
        isPublicTrail
            ? publicTrailAttempts.bestAttempt(
                for: session.profile.userID
            )
            : attempts.bestAttempt(
                for: session.profile.userID
            )
    }

    private var ownLatest: RouteAttemptRecord? {
        isPublicTrail
            ? publicTrailAttempts.latestAttempt(
                for: session.profile.userID
            )
            : attempts.latestAttempt(
                for: session.profile.userID
            )
    }

    private var ownRank: Int? {
        guard let index = leaderboard.firstIndex(
            where: { $0.userID == session.profile.userID }
        ) else {
            return nil
        }

        return index + 1
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                mapCard
                overviewCard

                if isPublicTrail {
                    trailIntelligenceCard
                }

                if isOwner {
                    privacyCard
                }

                performanceCard
                leaderboardCard
                attemptsCard
                actionsCard
            }
            .padding()
            .padding(.bottom, 80)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(currentRoute.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            draftTitle = currentRoute.title
                            editingTitle = true
                        } label: {
                            Label(
                                "Rename Route",
                                systemImage: "pencil"
                            )
                        }

                        NavigationLink {
                            ChallengeCreationView(
                                preselectedRouteID: currentRoute.id
                            )
                        } label: {
                            Label(
                                "Create Challenge",
                                systemImage: "trophy.fill"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(
                                "Delete Route",
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: currentRoute.id) {
            await prepareRouteData()
        }
        .refreshable {
            await prepareRouteData(forceHealthSync: true)
        }
        .confirmationDialog(
            "Delete \(currentRoute.title)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Route", role: .destructive) {
                Task {
                    await deleteRoute()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The saved route will be removed. Planned workouts keep their workout data, but the deleted route will no longer be attached."
            )
        }
        .alert(
            "Rename Route",
            isPresented: $editingTitle
        ) {
            TextField("Route name", text: $draftTitle)

            Button("Save") {
                updateTitle()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the name shown in Routes and challenges.")
        }
        .sheet(
            isPresented:
                $showingTargetGhost
        ) {
            NavigationStack {
                TargetGhostSetupView(
                    route: currentRoute
                )
            }
        }
        .sheet(
            isPresented:
                $showingSimilarTrails
        ) {
            NavigationStack {
                List(similarTrails) { trail in
                    NavigationLink {
                        RouteDetailView(
                            route: trail.trainingRoute
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName: "map.fill"
                            )
                            .foregroundStyle(
                                ATHLTHTheme.vitality
                            )
                            .frame(width: 34, height: 34)
                            .background(
                                ATHLTHTheme.vitalitySoft,
                                in: RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(trail.name)
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                Text(
                                    similarTrailSubtitle(
                                        trail
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle("Similar Routes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(
                        placement: .topBarTrailing
                    ) {
                        Button("Done") {
                            showingSimilarTrails = false
                        }
                    }
                }
            }
            .presentationDetents([
                .medium,
                .large
            ])
        }
        .sheet(item: $routeToStart) { route in
            RunQuickStartSheet(
                trainingDeviceProvider:
                    watchConnection.isReady
                        ? .appleWatch
                        : .none,
                watchConnected: watchConnection.isReady,
                initialRoute: route
            ) { configuration in
                launchRunFromDetails(configuration)
            }
        }
        .sheet(isPresented: $showingFullLeaderboard) {
            NavigationStack {
                fullLeaderboard
                    .navigationTitle("Leaderboard")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingFullLeaderboard = false
                            }
                        }
                    }
            }
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: {
                    watchMessage != nil ||
                    watchError != nil ||
                    attemptErrorMessage != nil ||
                    discovery.errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        watchMessage = nil
                        watchError = nil
                        attempts.errorMessage = nil
                        publicTrailAttempts.errorMessage = nil
                        discovery.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                watchError ??
                attemptErrorMessage ??
                discovery.errorMessage ??
                watchMessage ??
                ""
            )
        }
    }

    private var mapCard: some View {
        ATHLTHCard {
            if currentRoute.coordinates.count >= 2 {
                Map(
                    initialPosition: .region(
                        region(for: currentRoute)
                    )
                ) {
                    MapPolyline(
                        coordinates:
                            currentRoute.coordinates.map(\.coordinate)
                    )
                    .stroke(
                        ATHLTHTheme.accent,
                        lineWidth: 6
                    )

                    if let first = currentRoute.coordinates.first {
                        Marker(
                            currentRoute.startName ?? "Start",
                            coordinate: first.coordinate
                        )
                        .tint(ATHLTHTheme.accent)
                    }

                    if let last = currentRoute.coordinates.last {
                        Marker(
                            currentRoute.endName ?? "Finish",
                            coordinate: last.coordinate
                        )
                        .tint(.red)
                    }
                }
                .frame(height: 270)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
            }
        }
    }

    private var overviewCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    if isPublicTrail {
                        Label(
                            "PUBLIC TRAIL",
                            systemImage: "map.fill"
                        )
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: Capsule()
                        )
                    }

                    if publicTrailMetadata?.athlthVerified == true {
                        Label(
                            "ATHLTH VERIFIED",
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            ATHLTHTheme.premiumGoldSoft,
                            in: Capsule()
                        )
                    }

                    Spacer()

                    if !isPublicTrail {
                        visibilityBadge(currentRoute.visibility)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(currentRoute.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let start = currentRoute.startName,
                       let end = currentRoute.endName {
                        Text("\(start) → \(end)")
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    } else if let description =
                                publicTrailMetadata?.osmDescription,
                              !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .lineLimit(3)
                    }
                }

                HStack(spacing: 0) {
                    premiumRouteMetric(
                        value: String(
                            format: "%.1f km",
                            currentRoute.distanceKilometers
                        ),
                        label: "Distance",
                        icon: "figure.run"
                    )

                    premiumMetricDivider

                    premiumRouteMetric(
                        value:
                            resolvedElevationGain.map {
                                "\(Int($0.rounded())) m"
                            } ?? "—",
                        label: "Ascent",
                        icon: "mountain.2.fill"
                    )

                    premiumMetricDivider

                    premiumRouteMetric(
                        value:
                            publicTrailMetadata?.routeShape ??
                            "Route",
                        label: "Type",
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    if let runSeconds =
                        publicTrailMetadata?.estimatedRunSeconds {
                        premiumMetricDivider

                        premiumRouteMetric(
                            value:
                                compactDuration(runSeconds),
                            label: "Est. run",
                            icon: "clock.fill"
                        )
                    }
                }

                let characteristics =
                    trailCharacteristics
                if !characteristics.isEmpty {
                    ScrollView(
                        .horizontal,
                        showsIndicators: false
                    ) {
                        HStack(spacing: 7) {
                            ForEach(
                                characteristics,
                                id: \.self
                            ) { value in
                                Text(value)
                                    .font(
                                        .caption2
                                            .weight(.semibold)
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .accentDeep
                                    )
                                    .padding(
                                        .horizontal,
                                        10
                                    )
                                    .frame(height: 28)
                                    .background(
                                        Color.white
                                            .opacity(0.62),
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: ATHLTHTheme.cornerRadius,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.premiumGold.opacity(0.24),
                        ATHLTHTheme.vitality.opacity(0.16),
                        Color.white.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }

    private var resolvedElevationGain: Double? {
        publicTrailMetadata?.elevationGainMeters ??
            currentRoute.elevationGainMeters
    }

    private var trailCharacteristics: [String] {
        guard let metadata = publicTrailMetadata else {
            return []
        }

        var values: [String] = []

        if let shape = metadata.routeShape,
           !shape.isEmpty {
            values.append(shape)
        }

        if let surface = metadata.surfaceSummary,
           !surface.isEmpty {
            values.append(surface)
        }

        if let difficulty = metadata.difficulty,
           !difficulty.isEmpty {
            values.append(difficulty)
        }

        if !metadata.routeKind.isEmpty {
            values.append(
                metadata.routeKind
                    .replacingOccurrences(
                        of: "_",
                        with: " "
                    )
                    .capitalized
            )
        }

        if let network = metadata.network,
           !network.isEmpty {
            values.append(
                networkLabel(network)
            )
        }

        return values.reduce(into: [String]()) {
            partialResult,
            value in
            if !partialResult.contains(value) {
                partialResult.append(value)
            }
        }
    }

    private var premiumMetricDivider: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(width: 1, height: 46)
            .padding(.horizontal, 8)
    }

    private func premiumRouteMetric(
        value: String,
        label: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailIntelligenceCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 15) {
                ATHLTHSectionHeader(
                    title: "Trail intelligence",
                    actionTitle:
                        publicTrailMetadata?.athlthVerified == true
                            ? "VERIFIED"
                            : "OPEN DATA"
                )

                if let metadata = publicTrailMetadata {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum: 135
                                ),
                                spacing: 10
                            )
                        ],
                        spacing: 10
                    ) {
                        trailInfoTile(
                            title: "Route type",
                            value:
                                metadata.routeShape ??
                                "Unknown",
                            icon:
                                "point.topleft.down.to.point.bottomright.curvepath"
                        )

                        trailInfoTile(
                            title: "Run estimate",
                            value:
                                metadata
                                    .estimatedRunSeconds
                                    .map(compactDuration) ??
                                "—",
                            icon: "figure.run"
                        )

                        trailInfoTile(
                            title: "Walk estimate",
                            value:
                                metadata
                                    .estimatedWalkSeconds
                                    .map(compactDuration) ??
                                "—",
                            icon: "figure.walk"
                        )

                        if let surface =
                            metadata.surfaceSummary,
                           !surface.isEmpty {
                            trailInfoTile(
                                title: "Surface",
                                value: surface,
                                icon: "leaf.fill"
                            )
                        }

                        if let difficulty =
                            metadata.difficulty,
                           !difficulty.isEmpty {
                            trailInfoTile(
                                title: "Difficulty",
                                value: difficulty,
                                icon: "chart.bar.fill"
                            )
                        }

                        if let high =
                            metadata.maxElevationMeters {
                            trailInfoTile(
                                title: "High point",
                                value:
                                    "\(Int(high.rounded())) m",
                                icon: "mountain.2"
                            )
                        }

                        if let descent =
                            metadata.elevationLossMeters {
                            trailInfoTile(
                                title: "Descent",
                                value:
                                    "\(Int(descent.rounded())) m",
                                icon: "arrow.down.right"
                            )
                        }

                        if let low =
                            metadata.minElevationMeters {
                            trailInfoTile(
                                title: "Low point",
                                value:
                                    "\(Int(low.rounded())) m",
                                icon: "arrow.down.to.line"
                            )
                        }

                        if let averageGrade =
                            metadata.averageGradePercent {
                            trailInfoTile(
                                title: "Avg. grade",
                                value:
                                    String(
                                        format: "%.1f%%",
                                        averageGrade
                                    ),
                                icon: "angle"
                            )
                        }

                        if let grade =
                            metadata.maxGradePercent {
                            trailInfoTile(
                                title: "Max grade",
                                value:
                                    String(
                                        format: "%.0f%%",
                                        grade
                                    ),
                                icon:
                                    "arrow.up.right"
                            )
                        }

                        trailInfoTile(
                            title: "ATHLTH attempts",
                            value: "\(attemptCount)",
                            icon:
                                "arrow.trianglehead.2.clockwise.rotate.90"
                        )

                        trailInfoTile(
                            title: "Leaderboard",
                            value: "\(leaderboard.count)",
                            icon: "trophy.fill"
                        )
                    }

                    if let profile =
                        metadata.elevationProfile,
                       profile.count >= 2 {
                        VStack(
                            alignment: .leading,
                            spacing: 8
                        ) {
                            Text("Elevation profile")
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )

                            elevationProfileView(
                                profile
                            )
                        }
                    }

                    if metadata.reference != nil ||
                        metadata.operatorName != nil ||
                        metadata.symbol != nil {
                        Divider()

                        VStack(
                            alignment: .leading,
                            spacing: 8
                        ) {
                            if let reference =
                                metadata.reference,
                               !reference.isEmpty {
                                trailSourceRow(
                                    title: "Route",
                                    value: reference,
                                    icon: "number"
                                )
                            }

                            if let symbol =
                                metadata.symbol,
                               !symbol.isEmpty {
                                trailSourceRow(
                                    title: "Marking",
                                    value: symbol,
                                    icon: "signpost.right.fill"
                                )
                            }

                            if let operatorName =
                                metadata.operatorName,
                               !operatorName.isEmpty {
                                trailSourceRow(
                                    title: "Maintained by",
                                    value: operatorName,
                                    icon: "building.2.fill"
                                )
                            }
                        }
                    }

                    if metadata.source ==
                        "kartverket_turrutebasen" {
                        Link(
                            "Route geometry and trail metadata: © Kartverket",
                            destination: URL(
                                string:
                                    "https://www.kartverket.no"
                            )!
                        )
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    } else {
                        Text(
                            "Route geometry and trail metadata: OpenStreetMap contributors."
                        )
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                } else {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading trail details…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func trailInfoTile(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.vitality)
                .frame(width: 32, height: 32)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            ATHLTHTheme.surfaceSage.opacity(0.62),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private func elevationProfileView(
        _ samples: [Double]
    ) -> some View {
        let minimum =
            samples.min() ?? 0
        let maximum =
            samples.max() ?? minimum
        let range =
            max(maximum - minimum, 1)

        return GeometryReader { geometry in
            Path { path in
                for index in samples.indices {
                    let progress =
                        samples.count == 1
                            ? 0
                            : Double(index) /
                                Double(
                                    samples.count - 1
                                )
                    let x =
                        geometry.size.width *
                        progress
                    let normalized =
                        (samples[index] - minimum) /
                        range
                    let y =
                        geometry.size.height *
                        (1 - normalized)

                    if index == samples.startIndex {
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
            }
            .stroke(
                ATHLTHTheme.vitality,
                style: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .frame(height: 88)
        .padding(12)
        .background(
            ATHLTHTheme.surfaceSage.opacity(0.58),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay(alignment: .topLeading) {
            Text(
                "\(Int(maximum.rounded())) m"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            Text(
                "\(Int(minimum.rounded())) m"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .padding(8)
        }
    }

    private func trailSourceRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.vitality)
                .frame(width: 22)

            Text(title)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var privacyCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Route visibility")
                    .font(.headline)

                Text(
                    "Choose who can discover this route and appear with you on its leaderboard."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Picker(
                    "Visibility",
                    selection: Binding(
                        get: { currentRoute.visibility },
                        set: { updateVisibility($0) }
                    )
                ) {
                    Label(
                        "Only me",
                        systemImage: "lock.fill"
                    )
                    .tag(ProfileVisibility.privateOnly)

                    Label(
                        "Friends",
                        systemImage: "person.2.fill"
                    )
                    .tag(ProfileVisibility.friends)

                    Label(
                        "Public",
                        systemImage: "globe.europe.africa.fill"
                    )
                    .tag(ProfileVisibility.publicProfile)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var performanceCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your performance")
                            .font(.headline)

                        Text(
                            "GPS route adherence from your latest matched attempt."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSyncingAttempts {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let latest = ownLatest {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 10
                    ) {
                        metric(
                            title: "Route followed",
                            value: String(
                                format: "%.0f%%",
                                latest.routeMatchPercent
                            ),
                            icon: "checkmark.circle.fill",
                            tint: routeMatchTint(
                                latest.routeMatchPercent
                            )
                        )

                        metric(
                            title: "Deviation",
                            value: String(
                                format: "%.0f%%",
                                latest.deviationPercent
                            ),
                            icon: "arrow.triangle.branch",
                            tint: latest.deviationPercent <= 15
                                ? ATHLTHTheme.vitality
                                : .orange
                        )

                        metric(
                            title: "Avg off route",
                            value: latest.averageDeviationMeters.map {
                                "\(Int($0.rounded())) m"
                            } ?? "—",
                            icon: "ruler"
                        )

                        metric(
                            title: "Time",
                            value: clock(latest.durationSeconds),
                            icon: "stopwatch.fill"
                        )
                    }

                    Button {
                    showingTargetGhost = true
                } label: {
                    Label(
                        "Race Target Time",
                        systemImage:
                            "timer.circle.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(
                    settings
                        .trainingDeviceProvider !=
                        .appleWatch ||
                    !watchConnection.isReady
                )

                if let best = ownBest {
                        HStack {
                            Label(
                                "Best: \(clock(best.durationSeconds))",
                                systemImage: "medal.fill"
                            )

                            Spacer()

                            if let ownRank {
                                Text("#\(ownRank)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(ATHLTHTheme.accent)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                    }

                    if latest.routeMatchPercent < 85 {
                        Label(
                            "85% route match is required for leaderboard ranking.",
                            systemImage: "info.circle"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "location.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("No matched attempt yet")
                                .font(.subheadline.weight(.semibold))

                            Text(
                                "Run or walk this route with GPS. ATHLTH will compare the recorded path with the saved route."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var leaderboardCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Leaderboard")
                            .font(.headline)

                        Text(
                            leaderboardSubtitle
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if leaderboard.count > 3 {
                        Button("View all") {
                            showingFullLeaderboard = true
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHTheme.accent)
                    }
                }

                if !leaderboardAvailable {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "trophy")
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                        Text(
                            "Leaderboard is not enabled for this public trail."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if topThree.isEmpty {
                    Text(
                        isPublicTrail
                            ? "No qualifying public trail attempts yet. Complete at least 85% of the trail to set the first time."
                            : "No qualifying route attempts yet. Be the first to complete at least 85% of the route."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(topThree.enumerated()),
                            id: \.element.id
                        ) { index, attempt in
                            leaderboardRow(
                                attempt,
                                rank: index + 1
                            )

                            if index < topThree.count - 1 {
                                Divider()
                            }
                        }
                    }

                    if let ownRank,
                       ownRank > 3,
                       let ownBest {
                        Divider()

                        leaderboardRow(
                            ownBest,
                            rank: ownRank,
                            emphasize: true
                        )
                    }
                }
            }
        }
    }

    private var attemptsCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your attempts")
                        .font(.headline)

                    Spacer()

                    Text("\(ownAttempts.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                if ownAttempts.isEmpty {
                    Text("No attempts recorded on this route yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(ownAttempts.prefix(5).enumerated()),
                        id: \.element.id
                    ) { index, attempt in
                        attemptRow(attempt)

                        if index < min(ownAttempts.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        ATHLTHCard {
            VStack(spacing: 10) {
                if !isOwner {
                    Button {
                        if let savedCopy {
                            session.deleteSavedRoute(
                                savedCopy.id
                            )
                            watchMessage =
                                "Route removed from My Routes."
                        } else {
                            session.saveSharedRoute(
                                currentRoute,
                                sourceOwnerID:
                                    currentRoute.ownerID,
                                sourceRouteID:
                                    currentRoute.id
                            )
                            watchMessage =
                                "Route saved to My Routes."
                        }
                    } label: {
                        Label(
                            savedCopy == nil
                                ? "Save Route"
                                : "Saved · Remove",
                            systemImage:
                                savedCopy == nil
                                    ? "bookmark"
                                    : "bookmark.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(
                        savedCopy == nil
                            ? ATHLTHTheme.accent
                            : ATHLTHTheme.vitality
                    )
                    .controlSize(.large)
                }

                if isPublicTrail {
                    Button {
                        Task {
                            await loadSimilarTrails()
                        }
                    } label: {
                        if loadingSimilarTrails {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                "Show 10 Similar Routes",
                                systemImage:
                                    "square.stack.3d.up.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(loadingSimilarTrails)
                }

                if let best = ownBest {
                    Button {
                        Task {
                            await startGhostRace(
                                attempt: best
                            )
                        }
                    } label: {
                        if startingGhostAttemptID == best.id {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                "Race Your Best",
                                systemImage: "medal.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.vitality)
                    .controlSize(.large)
                    .disabled(
                        startingGhostAttemptID != nil ||
                        phoneWorkout.active != nil
                    )
                }

                if let latest = ownLatest,
                   latest.id != ownBest?.id {
                    Button {
                        Task {
                            await startGhostRace(
                                attempt: latest
                            )
                        }
                    } label: {
                        if startingGhostAttemptID == latest.id {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                "Race Last Attempt",
                                systemImage: "clock.arrow.circlepath"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(
                        startingGhostAttemptID != nil ||
                        phoneWorkout.active != nil
                    )
                }

                if isPublicTrail {
                    Button {
                        routeToStart = currentRoute
                    } label: {
                        Label(
                            "Start Route",
                            systemImage: "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .controlSize(.large)
                } else if settings.trainingDeviceProvider ==
                    .appleWatch {
                    Button {
                        Task {
                            await startRouteOnWatch()
                        }
                    } label: {
                        if startingRoute {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                "Start Route",
                                systemImage: "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .controlSize(.large)
                    .disabled(
                        startingRoute ||
                        !watchConnection.isReady
                    )
                }

                if let challengeRoute = isOwner
                    ? Optional(currentRoute)
                    : savedCopy {
                    NavigationLink {
                        ChallengeCreationView(
                            preselectedRouteID:
                                challengeRoute.id
                        )
                    } label: {
                        Label(
                            "Challenge Friends",
                            systemImage: "trophy.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
    }

    private var fullLeaderboard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if leaderboard.isEmpty {
                    ContentUnavailableView(
                        "No leaderboard yet",
                        systemImage: "trophy",
                        description: Text(
                            "Qualifying attempts need at least 85% route match."
                        )
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(
                        Array(leaderboard.enumerated()),
                        id: \.element.id
                    ) { index, attempt in
                        leaderboardRow(
                            attempt,
                            rank: index + 1
                        )
                        .padding(.horizontal)

                        Divider()
                            .padding(.leading, 70)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(ATHLTHTheme.canvasTop)
    }

    private func leaderboardRow(
        _ attempt: RouteAttemptRecord,
        rank: Int,
        emphasize: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(
                    rank <= 3
                        ? ATHLTHTheme.accent
                        : ATHLTHTheme.mutedText
                )
                .frame(width: 28)

            routeAttemptAvatar(attempt)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    attempt.userID == session.profile.userID
                        ? "You"
                        : attempt.athleteName
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    String(
                        format: "%.0f%% route · %.2f km",
                        attempt.routeMatchPercent,
                        attempt.distanceMeters / 1_000
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(clock(attempt.durationSeconds))
                    .font(.subheadline.monospacedDigit().weight(.bold))

                Text(pace(attempt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, emphasize ? 10 : 0)
        .background(
            emphasize
                ? ATHLTHTheme.accentSoft.opacity(0.45)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func attemptRow(
        _ attempt: RouteAttemptRecord
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .foregroundStyle(
                    routeMatchTint(
                        attempt.routeMatchPercent
                    )
                )
                .frame(width: 34, height: 34)
                .background(
                    routeMatchTint(
                        attempt.routeMatchPercent
                    )
                    .opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    attempt.startedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    String(
                        format: "%.0f%% followed · %.0f%% deviation",
                        attempt.routeMatchPercent,
                        attempt.deviationPercent
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(clock(attempt.durationSeconds))
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func routeAttemptAvatar(
        _ attempt: RouteAttemptRecord
    ) -> some View {
        if let avatar = attempt.avatarURL,
           let url = URL(string: avatar) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    avatarFallback
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            avatarFallback
                .frame(width: 38, height: 38)
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }

    private func metric(
        title: String,
        value: String,
        icon: String,
        tint: Color = ATHLTHTheme.accent
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func visibilityBadge(
        _ visibility: ProfileVisibility
    ) -> some View {
        Label(
            visibilityLabel(visibility),
            systemImage: visibilityIcon(visibility)
        )
        .font(.caption2.weight(.semibold))
        .foregroundStyle(ATHLTHTheme.accentDeep)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            ATHLTHTheme.accentSoft,
            in: Capsule()
        )
    }

    private var leaderboardSubtitle: String {
        if isPublicTrail {
            return "Fastest qualifying times on this public trail."
        }

        switch currentRoute.visibility {
        case .privateOnly:
            return "Only your qualifying attempts are visible."
        case .friends:
            return "Best qualifying times from you and friends."
        case .publicProfile:
            return "Best qualifying times from the ATHLTH community."
        }
    }

    private func prepareRouteData(
        forceHealthSync: Bool = false
    ) async {
        if isPublicTrail {
            publicTrailMetadata =
                await publicTrailDiscovery.trail(
                    id: publicTrailID
                )

            if forceHealthSync ||
                health.hasRequestedAuthorization {
                await publicTrailAttempts
                    .syncHealthAttempts(
                        for: currentRoute,
                        trailID: publicTrailID,
                        userID: session.profile.userID,
                        health: health
                    )
            } else {
                await publicTrailAttempts.refresh(
                    trailID: publicTrailID
                )
            }

            return
        }

        if isOwner {
            await discovery.publish(currentRoute)
        }

        if forceHealthSync ||
            health.hasRequestedAuthorization {
            await attempts.syncHealthAttempts(
                for: currentRoute,
                userID: session.profile.userID,
                health: health
            )
        } else {
            await attempts.refresh(
                routeID: currentRoute.id
            )
        }
    }

    @MainActor
    private func loadSimilarTrails() async {
        loadingSimilarTrails = true
        defer {
            loadingSimilarTrails = false
        }

        similarTrails =
            await publicTrailDiscovery.similar(
                to: publicTrailID,
                limit: 10
            )

        showingSimilarTrails = true
    }

    private func similarTrailSubtitle(
        _ trail: PublicTrailRecord
    ) -> String {
        var parts = [
            String(
                format: "%.1f km",
                trail.distanceKilometers
            )
        ]

        if let shape = trail.routeShape,
           !shape.isEmpty {
            parts.append(shape)
        }

        if let difficulty = trail.difficulty,
           !difficulty.isEmpty {
            parts.append(difficulty)
        }

        if let network = trail.network,
           !network.isEmpty {
            parts.append(networkLabel(network))
        }

        return parts.joined(separator: " · ")
    }

    private func compactDuration(
        _ seconds: TimeInterval
    ) -> String {
        let totalMinutes =
            max(
                Int(
                    (seconds / 60)
                        .rounded()
                ),
                1
            )

        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        return minutes == 0
            ? "\(hours) h"
            : "\(hours) h \(minutes) min"
    }

    private func networkLabel(
        _ network: String
    ) -> String {
        switch network.lowercased() {
        case "lwn":
            return "Local network"
        case "rwn":
            return "Regional network"
        case "nwn":
            return "National network"
        case "iwn":
            return "International network"
        default:
            return network.uppercased()
        }
    }

    private func updateVisibility(
        _ visibility: ProfileVisibility
    ) {
        guard isOwner,
              visibility != currentRoute.visibility
        else {
            return
        }

        session.updateSavedRoute(
            currentRoute.id,
            visibility: visibility
        )

        if let updated = session.savedRoutes.first(
            where: { $0.id == currentRoute.id }
        ) {
            Task {
                await discovery.publish(updated)
                await attempts.refresh(routeID: updated.id)
            }
        }
    }

    private func updateTitle() {
        let clean = draftTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !clean.isEmpty else {
            return
        }

        session.updateSavedRoute(
            currentRoute.id,
            title: clean
        )

        if let updated = session.savedRoutes.first(
            where: { $0.id == currentRoute.id }
        ) {
            Task {
                await discovery.publish(updated)
            }
        }
    }

    private func deleteRoute() async {
        guard isOwner else {
            return
        }

        await discovery.remove(routeID: currentRoute.id)

        guard discovery.errorMessage == nil else {
            return
        }

        session.deleteSavedRoute(currentRoute.id)
        dismiss()
    }

    private func launchRunFromDetails(
        _ configuration: RunQuickStartConfiguration
    ) {
        Task { @MainActor in
            await social.beginWorkoutWithFriends(
                title: configuration.title,
                kind: .running,
                friends: configuration.friends,
                creatorName: session.profile.displayName,
                creatorUsername: session.profile.username
            )

            do {
                try await WorkoutLaunchCoordinator
                    .startRunQuick(
                        configuration: configuration,
                        session: session,
                        settings: settings,
                        gear: gear,
                        phoneWorkout: phoneWorkout,
                        watchConnection:
                            watchConnection,
                        spotify: spotify,
                        ghostRace: ghostRace
                    )

                watchMessage =
                    "\(configuration.title) started" +
                    (
                        configuration.captureDevice ==
                            .appleWatch
                            ? " on Apple Watch."
                            : " on iPhone."
                    )
            } catch {
                await social.cancelActiveWorkout()
                watchError =
                    error.localizedDescription
            }
        }
    }

    @MainActor
    private func startGhostRace(
        attempt: RouteAttemptRecord
    ) async {
        let captureDevice:
            WorkoutCaptureDevice =
                settings.trainingDeviceProvider ==
                    .appleWatch &&
                watchConnection.isReady
                    ? .appleWatch
                    : .iPhone

        if captureDevice == .iPhone,
           phoneWorkout.active != nil {
            watchError =
                "Finish the active iPhone workout before starting Ghost Race."
            return
        }

        startingGhostAttemptID = attempt.id
        defer {
            startingGhostAttemptID = nil
        }

        do {
            try await GhostRaceStartService.start(
                attempt: attempt,
                route: currentRoute,
                health: health,
                ownerID: session.profile.userID,
                ghostRace: ghostRace,
                watchConnection: watchConnection,
                phoneWorkout: phoneWorkout,
                captureDevice:
                    captureDevice,
                settings: settings
            )
        } catch {
            watchError = error.localizedDescription
        }
    }

    private func startRouteOnWatch() async {
        guard watchConnection.isReady else {
            watchError = "Apple Watch is not ready."
            return
        }

        startingRoute = true
        defer { startingRoute = false }

        do {
            try watchConnection.sendRoute(currentRoute)
            watchConnection.sendWorkoutRouteSelection(
                currentRoute.id
            )
            try await watchConnection.startWorkoutOnWatch(
                .running
            )
            watchConnection.sendRunningWorkout(
                WatchRunningWorkoutTransfer(
                    title: currentRoute.title,
                    steps: [],
                    routeAlerts:
                        settings.routeAlertConfiguration
                )
            )
            watchMessage =
                "\(currentRoute.title) started on Apple Watch."
        } catch {
            watchError = error.localizedDescription
        }
    }

    private func routeMatchTint(
        _ match: Double
    ) -> Color {
        if match >= 90 {
            return ATHLTHTheme.vitality
        }

        if match >= 75 {
            return .orange
        }

        return .red
    }

    private func visibilityLabel(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "Only me"
        case .friends:
            return "Friends"
        case .publicProfile:
            return "Public"
        }
    }

    private func visibilityIcon(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "lock.fill"
        case .friends:
            return "person.2.fill"
        case .publicProfile:
            return "globe.europe.africa.fill"
        }
    }

    private func clock(
        _ duration: TimeInterval
    ) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

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

    private func pace(
        _ attempt: RouteAttemptRecord
    ) -> String {
        guard attempt.distanceMeters > 0 else {
            return "— /km"
        }

        let secondsPerKilometer =
            attempt.durationSeconds /
            (attempt.distanceMeters / 1_000)
        let minutes = Int(secondsPerKilometer) / 60
        let seconds = Int(secondsPerKilometer) % 60

        return String(
            format: "%d:%02d /km",
            minutes,
            seconds
        )
    }

    private func region(
        for route: TrainingRoute
    ) -> MKCoordinateRegion {
        let coordinates = route.coordinates.map(\.coordinate)

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 63.43,
                    longitude: 10.40
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.08,
                    longitudeDelta: 0.08
                )
            )
        }

        let lats = coordinates.map(\.latitude)
        let longs = coordinates.map(\.longitude)
        let minLat = lats.min() ?? first.latitude
        let maxLat = lats.max() ?? first.latitude
        let minLong = longs.min() ?? first.longitude
        let maxLong = longs.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLong + maxLong) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    (maxLat - minLat) * 1.35,
                    0.01
                ),
                longitudeDelta: max(
                    (maxLong - minLong) * 1.35,
                    0.01
                )
            )
        )
    }
}
