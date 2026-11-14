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
    @StateObject private var downloaded = ATHLTHDownloadedRouteStore()
    @StateObject private var routeLocation = HomeLocationStore()

    let route: TrainingRoute

    @State private var showingDeleteConfirmation = false
    @State private var showingFullLeaderboard = false
    @State private var showingAllPersonalAttempts = false
    @State private var showingOfflineMap = false
    @State private var showingInteractiveMap = false
    @State private var routeDetailScrolling = false
    @State private var snapshotScrollID = UUID()
    @State private var cachedOfflinePreview: UIImage?
    @State private var routeHasTurnaround = false
    @State private var gpxShareFile: ATHLTHRouteShareFile?
    @State private var gpxExportError: String?
    @State private var editingTitle = false
    @State private var draftTitle = ""
    @State private var watchMessage: String?
    @State private var watchError: String?
    @State private var startingGhostAttemptID: UUID?
    @State private var showingTargetGhost = false
    @State private var publicTrailMetadata: PublicTrailRecord?
    @State private var similarTrails: [PublicTrailRecord] = []
    @State private var loadingSimilarTrails = false
    @State private var showingSimilarTrails = false
    @State private var routeToStart: TrainingRoute?
    @State private var selectedAttemptDirection: ATHLTHRouteAttemptDirection = .forward
    @State private var showingMetadataEditor = false
    @State private var draftTags: [String] = []
    @State private var draftSurfaces: [String: Int] = [:]

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

    private var allRouteAttempts: [RouteAttemptRecord] {
        isPublicTrail ? publicTrailAttempts.attempts : attempts.attempts
    }

    private var leaderboard: [RouteAttemptRecord] {
        ATHLTHRouteAttemptDirectionPolicy.bestByAthlete(
            allRouteAttempts,
            direction: selectedAttemptDirection
        )
    }

    private var topThree: [RouteAttemptRecord] {
        Array(leaderboard.prefix(3))
    }

    private var ownAttempts: [RouteAttemptRecord] {
        allRouteAttempts
            .filter {
                $0.userID == session.profile.userID &&
                $0.direction == selectedAttemptDirection
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var historicalAttemptsWithoutDirection: [RouteAttemptRecord] {
        allRouteAttempts
            .filter {
                $0.userID == session.profile.userID &&
                ($0.direction ?? .unknown) == .unknown
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var personalProgress:
        (best: RouteAttemptRecord?, latest: RouteAttemptRecord?, gainSeconds: Double?) {
        ATHLTHRouteAttemptDirectionPolicy.personalProgress(
            allRouteAttempts,
            direction: selectedAttemptDirection,
            userID: session.profile.userID
        )
    }

    private var ownBest: RouteAttemptRecord? { personalProgress.best }

    private var ownLatest: RouteAttemptRecord? { personalProgress.latest }

    private var ownRank: Int? {
        guard let index = leaderboard.firstIndex(
            where: { $0.userID == session.profile.userID }
        ) else { return nil }
        return index + 1
    }

    private var routePrimaryContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                mapCard
                offlineAndExportCard
                overviewCard
                startDirectionsCard
                elevationCard
                tagsAndSurfacesCard

                if isPublicTrail {
                    trailIntelligenceCard
                }

                if isOwner {
                    privacyCard
                }

                attemptDirectionCard
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
        .onScrollPhaseChange { _, phase in
            routeDetailScrolling = phase.isScrolling
            RouteMapSnapshotCache.setScrolling(
                phase.isScrolling, owner: snapshotScrollID
            )
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

                        if currentRoute.sharedSourceRouteID == nil && !isPublicTrail {
                        Button {
                            beginMetadataEdit()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Edit tags and surface",
                                    norwegian: "Rediger tags og underlag"
                                ),
                                systemImage: "tag"
                            )
                        }
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
    }

    var body: some View {
        routePrimaryContent
        .tint(ATHLTHTheme.accentDeep)
        .task(id: currentRoute.id) {
            downloaded.load(userID: session.profile.userID)
            refreshOfflinePreview()
            let coordinates = currentRoute.coordinates.sorted {
                $0.sequence < $1.sequence
            }.map(\.coordinate)
            routeHasTurnaround =
                ATHLTHRouteDirectionGeometry.turnaroundIndex(coordinates) != nil
            routeLocation.start()
            await prepareRouteData()
        }
        .onDisappear {
            routeLocation.stop()
            RouteMapSnapshotCache.setScrolling(false, owner: snapshotScrollID)
        }
        .onChange(of: session.profile.userID) { _, userID in
            downloaded.load(userID: userID)
            refreshOfflinePreview()
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
        .sheet(isPresented: $showingMetadataEditor) {
            NavigationStack {
                ScrollView {
                    ATHLTHRouteMetadataForm(
                        tags: $draftTags,
                        surfacePercentages: $draftSurfaces
                    )
                }
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Route details", norwegian: "Rutedetaljer"
                ))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avbryt"
                        )) { showingMetadataEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Save", norwegian: "Lagre"
                        )) { saveRouteMetadata() }
                    }
                }
            }
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
        .fullScreenCover(isPresented: $showingInteractiveMap) {
            SavedRouteFullscreenMap(route: directedRoute)
        }
        .sheet(item: $gpxShareFile) { file in
            ATHLTHRouteShareSheet(url: file.url)
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
                return nil
            }
        }
        .sheet(isPresented: $showingAllPersonalAttempts) {
            NavigationStack {
                List {
                    ForEach(
                        allRouteAttempts
                            .filter { $0.userID == session.profile.userID }
                            .sorted { $0.startedAt > $1.startedAt }
                    ) { attempt in
                        VStack(alignment: .leading, spacing: 4) {
                            attemptRow(attempt)
                            Text((attempt.direction ?? .unknown).title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "My attempts", norwegian: "Mine forsøk"
                ))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Done", norwegian: "Ferdig"
                        )) { showingAllPersonalAttempts = false }
                    }
                }
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
                    discovery.errorMessage != nil ||
                    downloaded.errorMessage != nil ||
                    gpxExportError != nil
                },
                set: { visible in
                    if !visible {
                        watchMessage = nil
                        watchError = nil
                        attempts.errorMessage = nil
                        publicTrailAttempts.errorMessage = nil
                        discovery.errorMessage = nil
                        downloaded.errorMessage = nil
                        gpxExportError = nil
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
                downloaded.errorMessage ??
                gpxExportError ??
                watchMessage ??
                ""
            )
        }
    }

    private var directedRoute: TrainingRoute {
        selectedAttemptDirection == .reverse
            ? ATHLTHExploreRoutePolicy.reversedForWorkout(currentRoute)
            : currentRoute
    }

    private var routeStartCoordinate: CLLocationCoordinate2D? {
        ATHLTHRouteDetailsPolicy.ordered(directedRoute).first?.coordinate
    }

    private var routeEndCoordinate: CLLocationCoordinate2D? {
        ATHLTHRouteDetailsPolicy.ordered(directedRoute).last?.coordinate
    }

    private var distanceToStartKilometers: Double? {
        guard let location = routeLocation.location,
              let start = routeStartCoordinate,
              CLLocationCoordinate2DIsValid(start) else { return nil }
        return location.distance(from: CLLocation(
            latitude: start.latitude, longitude: start.longitude
        )) / 1_000
    }

    private var startDistanceLabel: String {
        guard let distance = distanceToStartKilometers,
              let location = routeLocation.location else {
            return ATHLTHLocalization.choose(
                english: "Location unavailable",
                norwegian: "Posisjon utilgjengelig"
            )
        }
        if location.horizontalAccuracy < 0 ||
           location.horizontalAccuracy >= 500 {
            return ATHLTHLocalization.choose(
                english: String(format: "About %.0f km", distance),
                norwegian: String(format: "Ca. %.0f km", distance)
            )
        }
        return String(format: "%.1f km", distance)
    }

    private var resolvedProfileSamples: [Double] {
        if let profile = publicTrailMetadata?.elevationProfile,
           profile.count >= 2 {
            return profile.filter { $0.isFinite }
        }
        return ATHLTHRouteDetailsPolicy.elevationSamples(currentRoute)
    }

    private var resolvedWalkEstimate: TimeInterval? {
        if let seconds = publicTrailMetadata?.estimatedWalkSeconds,
           seconds > 0 { return seconds }
        if let seconds = currentRoute.expectedTravelTimeSeconds,
           seconds > 0,
           currentRoute.routeSource?.contains("apple_maps_walking") == true {
            return seconds
        }
        return ATHLTHRouteDetailsPolicy.estimateSeconds(
            distanceKilometers: currentRoute.distanceKilometers,
            running: false
        )
    }

    private var resolvedRunEstimate: TimeInterval? {
        if let seconds = publicTrailMetadata?.estimatedRunSeconds,
           seconds > 0 { return seconds }
        return ATHLTHRouteDetailsPolicy.estimateSeconds(
            distanceKilometers: currentRoute.distanceKilometers,
            running: true
        )
    }

    private var routeTypeTitle: String {
        if let shape = publicTrailMetadata?.routeShape?.lowercased() {
            switch shape {
            case "loop", "circuit": return ATHLTHRouteDetailsPolicy.Shape.loop.label
            case "out-and-back", "out_and_back", "return":
                return ATHLTHRouteDetailsPolicy.Shape.outAndBack.label
            case "point-to-point", "point_to_point", "linear":
                return ATHLTHRouteDetailsPolicy.Shape.pointToPoint.label
            default: break
            }
        }
        return ATHLTHRouteDetailsPolicy.shape(currentRoute).label
    }

    private func beginMetadataEdit() {
        guard isOwner, !isPublicTrail,
              currentRoute.sharedSourceRouteID == nil else { return }
        draftTags = currentRoute.tags ?? []
        draftSurfaces = currentRoute.surfacePercentages ?? [:]
        showingMetadataEditor = true
    }

    private func saveRouteMetadata() {
        guard isOwner, !isPublicTrail,
              currentRoute.sharedSourceRouteID == nil else { return }
        session.updateSavedRouteMetadata(
            currentRoute.id,
            tags: draftTags,
            surfacePercentages: draftSurfaces
        )
        showingMetadataEditor = false
        if let updated = session.savedRoutes.first(where: { $0.id == currentRoute.id }) {
            Task {
                await discovery.publish(updated)
            }
        }
    }

    private func openDirectionsToStart() {
        guard let start = routeStartCoordinate,
              CLLocationCoordinate2DIsValid(start) else { return }
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: start))
        destination.name = currentRoute.startName ?? currentRoute.title
        _ = destination.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ]
        )
    }

    private var offlineRouteSnapshot: UIImage? {
        // The downloaded bitmap is read once, not decoded every time a
        // location or performance metric causes SwiftUI to recompute cards.
        selectedAttemptDirection == .forward ? cachedOfflinePreview : nil
    }

    private func refreshOfflinePreview() {
        guard downloaded.has(currentRoute) else {
            cachedOfflinePreview = nil
            return
        }
        let id = downloaded.downloadedIDs.contains(currentRoute.id)
            ? currentRoute.id : (currentRoute.sharedSourceRouteID ?? currentRoute.id)
        cachedOfflinePreview = ATHLTHDownloadedRouteStore.snapshot(
            routeID: id, userID: session.profile.userID
        )
    }

    private var offlineAndExportCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: downloaded.has(currentRoute)
                        ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Offline route", norwegian: "Rute uten nett"
                        ))
                        .font(.headline)
                        Text(downloaded.has(currentRoute)
                            ? ATHLTHLocalization.choose(
                                english: "GPS track saved on this device",
                                norwegian: "GPS-sporet er lagret på denne enheten"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Save GPS and a static map preview before you leave",
                                norwegian: "Lagre GPS og statisk kartforhåndsvisning før turen"
                            ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 9) {
                    Button {
                        if downloaded.has(currentRoute) {
                            showingOfflineMap.toggle()
                        } else {
                            Task { await downloadRouteToDevice() }
                        }
                    } label: {
                        if downloaded.downloadingRouteID != nil {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 43)
                        } else {
                            Label(
                                downloaded.has(currentRoute)
                                    ? (showingOfflineMap
                                        ? ATHLTHLocalization.choose(
                                            english: "Interactive map", norwegian: "Vanlig kart"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Offline map", norwegian: "Offlinekart"
                                        ))
                                    : ATHLTHLocalization.choose(
                                        english: "Download route", norwegian: "Last ned rute"
                                    ),
                                systemImage: downloaded.has(currentRoute)
                                    ? "map" : "arrow.down.to.line"
                            )
                            .frame(maxWidth: .infinity, minHeight: 43)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(downloaded.downloadingRouteID != nil)

                    Button(action: exportGPX) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Export GPX", norwegian: "Eksporter GPX"
                            ),
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity, minHeight: 43)
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentRoute.coordinates.count < 2)
                }
                if downloaded.has(currentRoute) {
                    Button(role: .destructive) {
                        downloaded.remove(currentRoute)
                        cachedOfflinePreview = nil
                        showingOfflineMap = false
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Remove offline download",
                            norwegian: "Fjern nedlastingen"
                        ))
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                Text(ATHLTHLocalization.choose(
                    english: "The offline preview and GPS trace work without service. Interactive street maps may still need network access.",
                    norwegian: "Forhåndsvisning og GPS-spor virker uten dekning. Interaktive gatekart kan fortsatt kreve nett."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func downloadRouteToDevice() async {
        guard await downloaded.download(
            currentRoute,
            for: session.profile.userID
        ) else { return }
        // For remote routes, a private saved copy also makes the GPS track
        // available from My Routes after relaunching without internet.
        if !isOwner && savedCopy == nil {
            session.saveSharedRoute(
                currentRoute,
                sourceOwnerID: currentRoute.ownerID,
                sourceRouteID: currentRoute.id
            )
        }
        refreshOfflinePreview()
        showingOfflineMap = true
    }

    private func exportGPX() {
        do {
            let url = try ATHLTHRouteGPXExport.temporaryFile(directedRoute)
            gpxShareFile = ATHLTHRouteShareFile(url: url)
        } catch {
            gpxExportError = error.localizedDescription
        }
    }

    private var mapCard: some View {
        ATHLTHCard {
            if currentRoute.coordinates.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    if showingOfflineMap && downloaded.has(currentRoute) {
                        Group {
                            if let image = offlineRouteSnapshot {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RouteMapSnapshotThumbnail(
                                    route: directedRoute,
                                    height: 270,
                                    allowsLiveSnapshot: false
                                )
                            }
                        }
                        .frame(height: 270)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        // A static route snapshot inside the scrolling page
                        // avoids MapKit competing with the page's gestures.
                        // The full interactive map is one tap away.
                        RouteMapSnapshotThumbnail(
                            route: directedRoute,
                            height: 270,
                            allowsLiveSnapshot: !routeDetailScrolling
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { showingInteractiveMap = true }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Open interactive route map",
                            norwegian: "Åpne interaktivt rutekart"
                        ))
                    }

                    Button {
                        showingInteractiveMap = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Open interactive map",
                                norwegian: "Åpne interaktivt kart"
                            ),
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accentDeep)

                    if routeHasTurnaround {
                        HStack(spacing: 14) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Outbound", norwegian: "Ut"
                                ),
                                systemImage: "arrow.up.right"
                            )
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Return", norwegian: "Retur"
                                ),
                                systemImage: "arrow.down.left"
                            )
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            Spacer(minLength: 4)
                            Text(ATHLTHLocalization.choose(
                                english: "Follow the arrows",
                                norwegian: "Følg pilene"
                            ))
                            .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                    }
                }
            }
        }
    }

    private var startDirectionsCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Start and finish", norwegian: "Start og mål"
                    ),
                    systemImage: "mappin.and.ellipse"
                )
                .font(.headline)

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "START", norwegian: "START"
                        ))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        Text(directedRoute.startName ?? ATHLTHLocalization.choose(
                            english: "GPS start point", norwegian: "Startpunkt på kartet"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .padding(.top, 9)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "FINISH", norwegian: "MÅL"
                        ))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        Text(ATHLTHRouteDetailsPolicy.shape(currentRoute) == .loop
                            ? (directedRoute.startName ?? "Start")
                            : (directedRoute.endName ?? ATHLTHLocalization.choose(
                                english: "Finish point on map",
                                norwegian: "Målpunkt på kartet"
                            )))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Image(systemName: "location")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(startDistanceLabel)
                        .font(.subheadline.weight(.bold))
                        Text(ATHLTHLocalization.choose(
                            english: "Straight-line distance to route start",
                            norwegian: "Avstand i luftlinje til rutens start"
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                }
                .padding(11)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 13)
                )

                Button(action: openDirectionsToStart) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Directions to start",
                            norwegian: "Veibeskrivelse til start"
                        ),
                        systemImage: "arrow.up.right"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(routeStartCoordinate.map(CLLocationCoordinate2DIsValid) != true)
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Opens walking directions in Apple Maps",
                    norwegian: "Åpner gangveibeskrivelse i Apple Kart"
                ))
            }
        }
    }

    private var elevationCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Elevation profile", norwegian: "Høydeprofil"
                    ),
                    systemImage: "mountain.2"
                )
                .font(.headline)

                let samples = resolvedProfileSamples
                if samples.count >= 2 {
                    elevationProfileView(samples)
                    HStack(spacing: 10) {
                        if let minimum = samples.min() {
                            metric(
                                title: ATHLTHLocalization.choose(
                                    english: "Lowest", norwegian: "Lavest"
                                ),
                                value: "\(Int(minimum.rounded())) m",
                                icon: "arrow.down"
                            )
                        }
                        if let maximum = samples.max() {
                            metric(
                                title: ATHLTHLocalization.choose(
                                    english: "Highest", norwegian: "Høyest"
                                ),
                                value: "\(Int(maximum.rounded())) m",
                                icon: "arrow.up"
                            )
                        }
                    }
                    if let ascent = resolvedElevationGain {
                        Text(ATHLTHLocalization.choose(
                            english: "Total ascent: \(Int(ascent.rounded())) m",
                            norwegian: "Samlet stigning: \(Int(ascent.rounded())) m"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                } else {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "No measured elevation profile is available for this route.",
                            norwegian: "Ingen målt høydeprofil er tilgjengelig for denne ruten."
                        ),
                        systemImage: "info.circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tagsAndSurfacesCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Surface and tags",
                            norwegian: "Underlag og emneknagger"
                        ),
                        systemImage: "tag"
                    )
                    .font(.headline)
                    Spacer(minLength: 4)
                    if isOwner && !isPublicTrail &&
                       currentRoute.sharedSourceRouteID == nil {
                        Button {
                            beginMetadataEdit()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Edit", norwegian: "Rediger"
                                ),
                                systemImage: "pencil"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }

                let surfaces = ATHLTHRouteDetailsPolicy.cleanedSurfaces(
                    currentRoute.surfacePercentages ?? [:]
                )
                let unknown = ATHLTHRouteDetailsPolicy.unclassifiedPercent(surfaces)
                if !surfaces.isEmpty {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(ATHLTHRouteSurface.allCases) { surface in
                                let percent = surfaces[surface.rawValue] ?? 0
                                if percent > 0 {
                                    Rectangle()
                                        .fill(surfaceTint(surface))
                                        .frame(
                                            width: max(0, geometry.size.width *
                                                CGFloat(percent) / 100)
                                        )
                                }
                            }
                            if unknown > 0 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.32))
                                    .frame(width: geometry.size.width *
                                        CGFloat(unknown) / 100)
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 12)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 112), spacing: 9)],
                        alignment: .leading,
                        spacing: 9
                    ) {
                        ForEach(ATHLTHRouteSurface.allCases) { surface in
                            if let percent = surfaces[surface.rawValue], percent > 0 {
                                Label("\(surface.title) \(percent) %",
                                      systemImage: "circle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(surfaceTint(surface))
                            }
                        }
                        if unknown > 0 {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Unknown \(unknown) %",
                                    norwegian: "Ukjent \(unknown) %"
                                ),
                                systemImage: "circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } else if let summary = publicTrailMetadata?.surfaceSummary,
                          !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline.weight(.medium))
                    Text(ATHLTHLocalization.choose(
                        english: "Source describes the surface but not its percentage.",
                        norwegian: "Kilden angir underlag, men ikke prosentfordeling."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Surface unknown",
                        norwegian: "Underlag ukjent"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                let tags = ATHLTHRouteDetailsPolicy.cleanedTags(currentRoute.tags ?? [])
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        ATHLTHTheme.accentSoft,
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                } else if isOwner && !isPublicTrail {
                    Text(ATHLTHLocalization.choose(
                        english: "No tags yet. Edit the route to add them.",
                        norwegian: "Ingen emneknagger. Rediger ruten for å legge til."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func surfaceTint(_ surface: ATHLTHRouteSurface) -> Color {
        switch surface {
        case .asphalt: ATHLTHTheme.accentDeep
        case .gravel: ATHLTHTheme.premiumGold
        case .trail: ATHLTHTheme.accent
        case .dirt: .brown
        case .track: .orange
        case .other: .gray
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

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 146), spacing: 10)],
                    spacing: 12
                ) {
                    premiumRouteMetric(
                        value: String(
                            format: "%.1f km",
                            currentRoute.distanceKilometers
                        ),
                        label: ATHLTHLocalization.choose(
                            english: "Distance", norwegian: "Distanse"
                        ),
                        icon: "figure.run"
                    )
                    premiumRouteMetric(
                        value: resolvedElevationGain.map {
                            "\(Int($0.rounded())) m"
                        } ?? "—",
                        label: ATHLTHLocalization.choose(
                            english: "Ascent", norwegian: "Stigning"
                        ),
                        icon: "mountain.2.fill"
                    )
                    premiumRouteMetric(
                        value: routeTypeTitle,
                        label: ATHLTHLocalization.choose(
                            english: "Route type", norwegian: "Rutetype"
                        ),
                        icon: "arrow.triangle.branch"
                    )
                    premiumRouteMetric(
                        value: resolvedWalkEstimate.map(compactDuration) ?? "—",
                        label: ATHLTHLocalization.choose(
                            english: "Est. walk", norwegian: "Est. gange"
                        ),
                        icon: "figure.walk"
                    )
                    premiumRouteMetric(
                        value: resolvedRunEstimate.map(compactDuration) ?? "—",
                        label: ATHLTHLocalization.choose(
                            english: "Est. run", norwegian: "Est. løping"
                        ),
                        icon: "figure.run"
                    )
                }
                Text(ATHLTHLocalization.choose(
                    english: "Times are estimates, not a personalized pace guarantee.",
                    norwegian: "Tidene er estimater, ikke en garanti for personlig tempo."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)

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
            currentRoute.elevationGainMeters ??
            ATHLTHRouteDetailsPolicy.ascentDescent(resolvedProfileSamples)?.ascent
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

    private var attemptDirectionCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(ATHLTHLocalization.choose(
                    english: "Results by direction", norwegian: "Resultater etter retning"
                ))
                .font(.headline)
                Picker(
                    ATHLTHLocalization.choose(english: "Direction", norwegian: "Retning"),
                    selection: $selectedAttemptDirection
                ) {
                    Text(ATHLTHLocalization.choose(
                        english: "Original", norwegian: "Normal"
                    )).tag(ATHLTHRouteAttemptDirection.forward)
                    Text(ATHLTHLocalization.choose(
                        english: "Reverse", norwegian: "Motsatt"
                    )).tag(ATHLTHRouteAttemptDirection.reverse)
                }
                .pickerStyle(.segmented)
                Text(ATHLTHLocalization.choose(
                    english: "Only GPS-verified attempts in this direction count towards these rankings.",
                    norwegian: "Kun GPS-bekreftede forsøk i valgt retning teller på disse ledertavlene."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if !historicalAttemptsWithoutDirection.isEmpty {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "\(historicalAttemptsWithoutDirection.count) older attempts have unverified direction and are excluded from rankings.",
                            norwegian: "\(historicalAttemptsWithoutDirection.count) eldre forsøk har ubekreftet retning og teller ikke på ledertavlen."
                        ),
                        systemImage: "info.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
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

                if let progress = personalProgress.gainSeconds {
                    HStack(spacing: 8) {
                        Image(systemName: progress >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(progress >= 0
                            ? ATHLTHLocalization.choose(
                                english: "Faster than last time: \(clock(progress))",
                                norwegian: "Raskere enn sist: \(clock(progress))"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Slower than last time: \(clock(-progress))",
                                norwegian: "Saktere enn sist: \(clock(-progress))"
                            ))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(progress >= 0
                        ? ATHLTHTheme.vitality : ATHLTHTheme.mutedText)
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
                    Text(ATHLTHLocalization.choose(
                        english: "Your attempts", norwegian: "Mine forsøk"
                    ))
                    .font(.headline)
                    Spacer()
                    Text("\(ownAttempts.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                    Button {
                        showingAllPersonalAttempts = true
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "View all", norwegian: "Se alle"
                        ))
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(allRouteAttempts.allSatisfy {
                        $0.userID != session.profile.userID
                    })
                }

                if ownAttempts.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "No qualified attempts in this direction yet.",
                        norwegian: "Ingen kvalifiserte forsøk i denne retningen ennå."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ownAttempts.prefix(5).enumerated()),
                            id: \.element.id) { index, attempt in
                        attemptRow(attempt)
                        if index < min(ownAttempts.count, 5) - 1 { Divider() }
                    }
                }
                if !historicalAttemptsWithoutDirection.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(ATHLTHLocalization.choose(
                            english: "\(historicalAttemptsWithoutDirection.count) historical attempts · direction unverified",
                            norwegian: "\(historicalAttemptsWithoutDirection.count) historiske forsøk · retning ubekreftet"
                        ))
                        .font(.caption)
                    }
                    .foregroundStyle(ATHLTHTheme.mutedText)
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
                    .tint(ATHLTHTheme.accentDeep)
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
                    .tint(ATHLTHTheme.accentDeep)
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

                Button {
                    routeToStart = directedRoute
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Start Route",
                            norwegian: "Start rute"
                        ),
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .controlSize(.large)
                .disabled(phoneWorkout.active != nil)

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
            ATHLTHStorageImage(url: url) { phase in
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
                route: directedRoute,
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
