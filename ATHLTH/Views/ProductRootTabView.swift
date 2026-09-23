import Charts
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct ProductRootTabView: View {
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore

    var body: some View {
        TabView {
            ATHLTHHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            ATHLTHTrainView()
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }

            ATHLTHRecoveryView()
                .tabItem { Label("Recovery", systemImage: "leaf.fill") }

            ATHLTHProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }

            ATHLTHProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(ATHLTHTheme.accent)
        .sheet(
            isPresented: $workoutMirroring.isPresentationRequested,
            onDismiss: {
                if !workoutMirroring.hasActiveMirroredWorkout {
                    workoutMirroring.dismissSummary()
                }
            }
        ) {
            MirroredWorkoutLiveView()
                .environmentObject(workoutMirroring)
        }
    }
}

struct ATHLTHHomeView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore

    private var snapshot: HealthSnapshot {
        HealthSnapshot(
            activeCalories: PreviewData.healthSnapshot.activeCalories,
            activeCaloriesGoal: PreviewData.healthSnapshot.activeCaloriesGoal,
            steps: PreviewData.healthSnapshot.steps,
            sleepDuration: health.sleep.totalAsleep > 0
                ? health.sleep.totalAsleep
                : PreviewData.healthSnapshot.sleepDuration,
            restingHeartRate: health.heart.restingHeartRate ?? PreviewData.healthSnapshot.restingHeartRate,
            hrvMilliseconds: health.heart.hrvMilliseconds ?? PreviewData.healthSnapshot.hrvMilliseconds,
            recoveryScore: PreviewData.healthSnapshot.recoveryScore
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHPageHeader(
                        title: "Good morning, \(session.profile.displayName)",
                        subtitle: session.profile.presence.state == .training
                            ? "Training now · \(session.profile.presence.workoutTitle ?? "Workout")"
                            : "Ready to train"
                    )

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Today's Activity", actionTitle: "Apple Health")
                        HStack(spacing: 8) {
                            ATHLTHProgressRing(
                                title: "Move",
                                value: "\(Int(snapshot.activeCalories))",
                                progress: snapshot.activeCalories / max(snapshot.activeCaloriesGoal, 1),
                                icon: "figure.run",
                                tint: ATHLTHTheme.accent
                            )
                            ATHLTHProgressRing(
                                title: "Recovery",
                                value: "\(snapshot.recoveryScore ?? 0)%",
                                progress: Double(snapshot.recoveryScore ?? 0) / 100,
                                icon: "heart.fill",
                                tint: .blue
                            )
                            ATHLTHProgressRing(
                                title: "Sleep",
                                value: snapshot.sleepDuration.shortDuration,
                                progress: snapshot.sleepDuration / (8 * 3600),
                                icon: "moon.fill",
                                tint: .purple
                            )
                        }
                        .padding(.top, 14)
                    }

                    HomeActivitySection()

                    HStack(alignment: .top, spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Train Today")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach([WorkoutKind.running, .walking, .strength, .custom]) { kind in
                                    VStack(spacing: 7) {
                                        Image(systemName: kind.systemImage)
                                            .font(.title2)
                                            .foregroundStyle(ATHLTHTheme.accent)
                                        Text(kind.title)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 70)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                            .padding(.top, 10)
                        }

                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Next Workout")
                            if let workout = session.activePlan?.weeks.first?.days.first?.sessions.first {
                                Text(workout.title)
                                    .font(.headline)
                                    .padding(.top, 8)
                                Text("\(workout.durationMinutes ?? 0) min")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button {
                                    session.beginTrainingStatus(for: workout)
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ATHLTHTheme.accent)
                                .padding(.top, 8)
                            }
                        }
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Health Metrics")
                        HStack {
                            ATHLTHMetric(
                                title: "Heart Rate",
                                value: snapshot.restingHeartRate.map { "\(Int($0)) bpm" } ?? "—",
                                icon: "heart.fill",
                                tint: .red
                            )
                            ATHLTHMetric(
                                title: "Sleep",
                                value: snapshot.sleepDuration.shortDuration,
                                icon: "moon.fill",
                                tint: .purple
                            )
                            ATHLTHMetric(
                                title: "Steps",
                                value: snapshot.steps.formatted(),
                                icon: "shoeprints.fill",
                                tint: .blue
                            )
                            ATHLTHMetric(
                                title: "Recovery",
                                value: "\(snapshot.recoveryScore ?? 0)",
                                icon: "leaf.fill",
                                tint: ATHLTHTheme.accent
                            )
                        }
                        .padding(.top, 10)
                    }

                    HStack(spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Consistency")
                            Text("5/7")
                                .font(.largeTitle.weight(.bold))
                                .padding(.top, 6)
                            Text("sessions this week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Insights")
                            Text("Sleep is trending up.")
                                .font(.headline)
                                .padding(.top, 6)
                            Text("Keep the routine consistent and use recovery to guide intensity.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [.blue.opacity(0.08), ATHLTHTheme.accent.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .refreshable { await health.refreshAll() }
        }
    }
}

struct ATHLTHTrainView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningWorkoutLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var social: SocialStore

    @State private var selectedSection = 0
    @State private var showingFileImporter = false
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var watchTransferMessage: String?
    @State private var watchTransferError: String?
    @State private var selectedStrengthSession: PlannedSession?
    @State private var pendingQuickStartKind: WorkoutKind?
    @State private var showingStrengthWorkout = false

    private let gpxImporter = GPXRouteImporter()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHPageHeader(title: "Train", subtitle: "Build a stronger, healthier you.")

                    Picker("Training section", selection: $selectedSection) {
                        Text("Today").tag(0)
                        Text("Calendar").tag(1)
                        Text("Plans").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch selectedSection {
                    case 1:
                        ATHLTHPlusFeatureGate(
                            feature: .advancedTrainingPlans,
                            title: "Advanced Calendar",
                            message: "Multi-week planning and advanced scheduling are included with ATHLTH+."
                        ) {
                            AdvancedPlannerView()
                        }
                    case 2:
                        ATHLTHPlusFeatureGate(
                            feature: .advancedTrainingPlans,
                            title: "Advanced Training Plans",
                            message: "Build, copy and manage advanced training plans with ATHLTH+."
                        ) {
                            TrainingPlanManagerView()
                        }
                    default:
                        todayContent
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .sheet(item: $selectedStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    watchConnected: watchConnection.isReady,
                    defaultCapture: settings.preferredWorkoutCapture,
                    defaultTracking: settings.defaultStrengthTracking,
                    linkedSpotifyPlaylist: session.activePlan?.spotifyPlaylist,
                    spotifyAutoplayEnabled:
                        settings.spotifyAutoplayLinkedPlaylists &&
                        (session.activePlan?.spotifyAutoplayOnWorkoutStart ?? false)
                ) { captureDevice, trackingMode, selectedFriends in
                    Task { @MainActor in
                        await social.beginWorkoutWithFriends(
                            title: workout.title,
                            kind: .strength,
                            friends: selectedFriends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username
                        )

                        if captureDevice == .appleWatch {
                            do {
                                try await watchConnection.startWorkoutOnWatch(.strength)
                                startPlanSpotifyIfNeeded()
                                session.beginTrainingStatus(for: workout)
                                strengthWorkout.start(
                                    session: workout,
                                    watchSessionID: UUID(),
                                    trackingMode: trackingMode,
                                    captureDevice: .appleWatch
                                )
                                showingStrengthWorkout = true
                            } catch {
                                watchTransferError = error.localizedDescription
                            }
                        } else {
                            startPlanSpotifyIfNeeded()
                            session.beginTrainingStatus(for: workout)
                            strengthWorkout.start(
                                session: workout,
                                watchSessionID: nil,
                                trackingMode: trackingMode,
                                captureDevice: .iPhone
                            )
                            showingStrengthWorkout = true
                        }
                    }
                }
            }
            .sheet(item: $pendingQuickStartKind) { kind in
                QuickWorkoutStartSheet(
                    kind: kind,
                    watchConnected: watchConnection.isReady
                ) { selectedFriends in
                    Task { @MainActor in
                        await social.beginWorkoutWithFriends(
                            title: kind.title,
                            kind: kind,
                            friends: selectedFriends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username
                        )
                        startQuickWorkoutOnWatch(kind)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingStrengthWorkout) {
                ActiveStrengthWorkoutView()
                    .environmentObject(strengthWorkout)
                    .environmentObject(session)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.xml, .data],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await importGPX(result)
                }
            }
            .task {
                await exerciseLibrary.refresh()
            }
            .alert("ATHLTH", isPresented: Binding(
                get: {
                    importMessage != nil ||
                    importError != nil ||
                    watchTransferMessage != nil ||
                    watchTransferError != nil
                },
                set: { newValue in
                    if !newValue {
                        importMessage = nil
                        importError = nil
                        watchTransferMessage = nil
                        watchTransferError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    importMessage = nil
                    importError = nil
                    watchTransferMessage = nil
                    watchTransferError = nil
                }
            } message: {
                Text(
                    watchTransferError ??
                    importError ??
                    watchTransferMessage ??
                    importMessage ??
                    ""
                )
            }
        }
    }

    @ViewBuilder
    private var todayContent: some View {
        if let plan = session.activePlan {
            ATHLTHCard {
                ATHLTHSectionHeader(
                    title: "Today's Plan",
                    actionTitle: plan.title
                )

                let sessions = todaySessions(in: plan)

                if sessions.isEmpty {
                    Label(
                        "No session planned today",
                        systemImage: "leaf"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                } else {
                    VStack(spacing: 14) {
                        ForEach(sessions) { workout in
                            HStack {
                                Image(systemName: workout.kind.systemImage)
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .frame(width: 34)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.title)
                                        .font(.headline)

                                    Text(todaySessionSummary(workout))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if workout.kind == .strength {
                                    Button("Start") {
                                        selectedStrengthSession = workout
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Quick Start",
                actionTitle: watchConnection.isReady ? "Apple Watch" : "Connect Watch"
            )
            HStack {
                ForEach([WorkoutKind.running, .walking, .strength]) { kind in
                    Button {
                        handleQuickStart(kind)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: kind.systemImage)
                                .font(.title2)
                                .foregroundStyle(ATHLTHTheme.accent)
                            Text(kind.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                    }
                    .buttonStyle(.plain)
                    .disabled(!quickStartAvailable(kind))
                    .opacity(quickStartAvailable(kind) ? 1 : 0.45)
                }
            }
            .padding(.top, 10)
        }

        if !session.savedWorkoutTemplates.isEmpty {
            ATHLTHCard {
                ATHLTHSectionHeader(
                    title: "Saved Workouts",
                    actionTitle: "From you & friends"
                )

                VStack(spacing: 13) {
                    ForEach(session.savedWorkoutTemplates.prefix(4)) { workout in
                        HStack(spacing: 12) {
                            Image(systemName: workout.kind.systemImage)
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 11)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(todaySessionSummary(workout))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if workout.kind == .strength {
                                Button("Start") {
                                    selectedStrengthSession = workout
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text("Saved")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }

        ATHLTHCard {
            HStack(spacing: 10) {
                Text("Routes & Challenges")
                    .font(.title3.weight(.semibold))

                Spacer()

                NavigationLink {
                    SavedRoutesView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                }

                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)

                Button {
                    showingFileImporter = true
                } label: {
                    Label("GPX", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            if let route = session.savedRoutes.first {
                Map(initialPosition: .region(routeRegion(route))) {
                    MapPolyline(coordinates: route.coordinates.map(\.coordinate))
                        .stroke(ATHLTHTheme.accent, lineWidth: 5)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.top, 10)

                HStack {
                    VStack(alignment: .leading) {
                        Text(route.title)
                            .font(.headline)
                        Text("\(route.distanceKilometers, specifier: "%.1f") km · \(Int(route.elevationGainMeters ?? 0)) m ascent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let challenge = challengeStore.visibleChallenges.first(where: {
                        $0.status == .active || $0.status == .upcoming || $0.status == .invited
                    }) {
                        NavigationLink {
                            ChallengeDetailView(challengeID: challenge.id)
                        } label: {
                            Label(challenge.title, systemImage: "trophy.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHTheme.accent)
                                .lineLimit(1)
                        }
                    } else {
                        NavigationLink {
                            ChallengeHubView()
                        } label: {
                            Label("Challenges", systemImage: "person.2.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    Button {
                        sendRouteToWatch(route)
                    } label: {
                        Label("Send to Apple Watch", systemImage: "applewatch")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .disabled(!watchConnection.isReady)

                    if !watchConnection.isReady {
                        Text(watchConnection.state.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 8)
            } else {
                ContentUnavailableView(
                    "No routes yet",
                    systemImage: "map",
                    description: Text("Create an A-to-B running route or import GPX.")
                )
                .frame(height: 190)
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Workout Builder",
                actionTitle: "Library"
            )

            HStack(spacing: 10) {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    builderTile(
                        title: "Exercises",
                        subtitle: exerciseLibrary.repDBExercises.isEmpty
                            ? "RepDB + Custom"
                            : "\(exerciseLibrary.repDBExercises.count) + custom",
                        icon: "dumbbell.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RunningWorkoutLibraryView()
                } label: {
                    builderTile(
                        title: "Running",
                        subtitle: "\(runningWorkoutLibrary.allTemplates.count) workouts",
                        icon: "figure.run"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }


    }

    private func watchWorkoutKind(
        for kind: WorkoutKind
    ) -> WatchWorkoutKind? {
        switch kind {
        case .running:
            return .running
        case .walking:
            return .walking
        case .strength:
            return .strength
        case .mobility, .recovery, .custom:
            return nil
        }
    }

    private func quickStartAvailable(_ kind: WorkoutKind) -> Bool {
        if kind == .strength {
            return strengthWorkout.activeWorkout == nil
        }

        return watchWorkoutKind(for: kind) != nil &&
            watchConnection.isReady &&
            !watchConnection.workoutLaunchInProgress
    }

    private func handleQuickStart(_ kind: WorkoutKind) {
        if kind == .strength {
            selectedStrengthSession = PlannedSession(
                id: UUID(),
                title: "Freestyle Strength",
                kind: .strength,
                scheduledStart: nil,
                durationMinutes: nil,
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil,
                exercises: [],
                notes: "Freestyle gym session",
                runningWorkout: nil
            )
            return
        }

        pendingQuickStartKind = kind
    }

    private func startQuickWorkoutOnWatch(_ kind: WorkoutKind) {
        guard let watchKind = watchWorkoutKind(for: kind) else { return }

        Task {
            do {
                try await watchConnection.startWorkoutOnWatch(watchKind)
                watchTransferMessage = "\(watchKind.title) started on Apple Watch."
            } catch {
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func sendRouteToWatch(_ route: TrainingRoute) {
        do {
            try watchConnection.sendRoute(route)
            watchTransferMessage = "Sent \(route.title) to Apple Watch."
        } catch {
            watchTransferError = error.localizedDescription
        }
    }

    private func startPlanSpotifyIfNeeded() {
        guard
            let plan = session.activePlan,
            plan.spotifyAutoplayOnWorkoutStart,
            let playlist = plan.spotifyPlaylist
        else {
            return
        }

        Task {
            await spotifyPlayback.startLinkedPlaylist(
                playlist,
                settings: settings
            )
        }
    }

    private func todaySessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let dayIndex = ((weekday + 5) % 7) + 1

        let week: TrainingPlanWeek?
        if let startDate = plan.startDate {
            let start = calendar.startOfDay(for: startDate)
            let today = calendar.startOfDay(for: Date())
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: today
                ).day ?? 0,
                0
            )
            let weekIndex = min(
                days / 7,
                max(plan.weeks.count - 1, 0)
            )
            week = plan.weeks.indices.contains(weekIndex)
                ? plan.weeks[weekIndex]
                : plan.weeks.first
        } else {
            week = plan.weeks.first
        }

        return week?
            .days
            .first(where: { $0.dayIndex == dayIndex })?
            .sessions ?? []
    }

    private func todaySessionSummary(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let running = workout.runningWorkout {
            parts.append(running.type.title)
            parts.append("\(running.blocks.count) blocks")
        } else if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
        }

        if !workout.exercises.isEmpty {
            parts.append("\(workout.exercises.count) exercises")
        }

        if workout.routeID != nil {
            parts.append("Route")
        }

        return parts.isEmpty
            ? workout.kind.title
            : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func builderTile(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(ATHLTHTheme.accent)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 100,
            alignment: .leading
        )
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func routeRegion(_ route: TrainingRoute) -> MKCoordinateRegion {
        guard let first = route.coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 66.3126, longitude: 14.1428),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        }

        return MKCoordinateRegion(
            center: first.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    }

    private func importGPX(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let route = try await gpxImporter.importGPX(data: data, filename: url.lastPathComponent)

            await MainActor.run {
                session.addImportedRoute(route)
                importMessage = "Imported \(route.title) · \(String(format: "%.1f", route.distanceKilometers)) km"
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
            }
        }
    }
}

struct ATHLTHRecoveryView: View {
    private let recovery = PreviewData.recoverySnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHPageHeader(
                        title: "Recovery",
                        subtitle: "Use sleep and recovery signals to guide today's load."
                    )

                    ATHLTHPlusFeatureGate(
                        feature: .advancedRecovery,
                        title: "Advanced Recovery",
                        message: "Recovery scoring, trends and training guidance are included with ATHLTH+."
                    ) {
                        VStack(spacing: 18) {
                            ATHLTHCard {
                                ATHLTHSectionHeader(title: "Recovery Score", actionTitle: "Today")
                                HStack(spacing: 24) {
                                    ATHLTHProgressRing(
                                        title: recovery.readinessText,
                                        value: "\(recovery.score)",
                                        progress: Double(recovery.score) / 100,
                                        icon: "leaf.fill",
                                        tint: ATHLTHTheme.accent
                                    )
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Well recovered")
                                            .font(.title2.weight(.bold))
                                        Text("Your sleep and HRV support a normal training session today.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 12)
                            }

                            HStack(spacing: 12) {
                                ATHLTHCard {
                                    ATHLTHSectionHeader(title: "Sleep")
                                    ATHLTHMetric(
                                        title: "Sleep quality",
                                        value: recovery.sleepDuration.shortDuration,
                                        icon: "moon.fill",
                                        tint: .purple
                                    )
                                    .padding(.top, 10)
                                }

                                ATHLTHCard {
                                    ATHLTHSectionHeader(title: "Heart & HRV")
                                    HStack {
                                        ATHLTHMetric(
                                            title: "HRV",
                                            value: recovery.hrvMilliseconds.map { "\(Int($0)) ms" } ?? "—",
                                            icon: "waveform.path.ecg",
                                            tint: .blue
                                        )
                                        ATHLTHMetric(
                                            title: "Resting HR",
                                            value: recovery.restingHeartRate.map { "\(Int($0)) bpm" } ?? "—",
                                            icon: "heart.fill",
                                            tint: .red
                                        )
                                    }
                                    .padding(.top, 10)
                                }
                            }

                            ATHLTHCard {
                                ATHLTHSectionHeader(title: "Recovery Trend")
                                Chart {
                                    ForEach(Array([72, 75, 81, 84, 79, 86, 82].enumerated()), id: \.offset) { index, value in
                                        BarMark(
                                            x: .value("Day", index),
                                            y: .value("Recovery", value)
                                        )
                                        .foregroundStyle(ATHLTHTheme.accent.gradient)
                                    }
                                }
                                .frame(height: 170)
                                .padding(.top, 12)
                            }

                            HStack(spacing: 12) {
                                ATHLTHCard {
                                    ATHLTHSectionHeader(title: "Breathing & Mobility")
                                    Label("5 min box breathing", systemImage: "wind")
                                        .font(.headline)
                                        .padding(.top, 10)
                                    Text("Calm down and reset before training.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                ATHLTHCard {
                                    ATHLTHSectionHeader(title: "Today's Training")
                                    Label("Moderate intensity", systemImage: "dumbbell.fill")
                                        .font(.headline)
                                        .foregroundStyle(ATHLTHTheme.accent)
                                        .padding(.top, 10)
                                    Text("Recovery looks good. Keep some reserve.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private enum ProgressPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"
    case year = "Year"

    var id: String { rawValue }
}

struct ATHLTHProgressView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var trophyStore: TrophyStore

    @State private var period: ProgressPeriod = .week
    @State private var progressSnapshot: HealthProgressSnapshot?
    @State private var monthlySnapshot: HealthProgressSnapshot?
    @State private var consistencySnapshot: HealthProgressSnapshot?
    @State private var personalRecords: [HealthPersonalRecord] = []
    @State private var showingGoalCreation = false
    @State private var progressLoading = false
    @State private var progressError: String?

    private let green = ATHLTHTheme.accent
    private let blue = Color(red: 0.20, green: 0.56, blue: 0.96)
    private let purple = Color(red: 0.42, green: 0.36, blue: 0.95)
    private let canvas = Color(red: 0.965, green: 0.972, blue: 0.968)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    progressHero
                        .padding(.horizontal, -16)
                        .padding(.top, -14)

                    periodPicker
                        .padding(.top, -42)
                        .zIndex(2)

                    weeklyOverview

                    HStack(alignment: .top, spacing: 12) {
                        workoutsCompletedCard
                        dailyStepsCard
                    }

                    HStack(alignment: .top, spacing: 12) {
                        consistencyCard
                        personalRecordsCard
                    }

                    HStack(alignment: .top, spacing: 12) {
                        monthlyStatsCard
                        achievementsCard
                    }

                    goalsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(canvas.ignoresSafeArea())
            .refreshable {
                async let selected: Void = loadProgressData()
                async let support: Void = loadSupportingProgressData()
                _ = await (selected, support)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: period) {
            await loadProgressData()
        }
        .task {
            await loadSupportingProgressData()
            await goalStore.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            await trophyStore.refresh(
                health: health,
                strength: strengthWorkout,
                goals: goalStore
            )
        }
        .sheet(isPresented: $showingGoalCreation) {
            GoalCreationView()
        }
    }

    private var progressHero: some View {
        ZStack(alignment: .bottomLeading) {
            Image("OnboardingHero")
                .resizable()
                .scaledToFill()
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.82),
                    canvas
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.42),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ATHLTH")
                            .font(.system(size: 27, weight: .black))
                            .tracking(7)

                        Text("MOVE BETTER · LIVE LONGER")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(2.0)
                            .foregroundStyle(.black.opacity(0.58))
                    }

                    Spacer()

                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.12), in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.35), lineWidth: 1)
                            }

                        Circle()
                            .fill(.red)
                            .frame(width: 9, height: 9)
                            .overlay {
                                Circle().stroke(.white, lineWidth: 2)
                            }
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    Text("Your Progress")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.black.opacity(0.92))

                    HStack(spacing: 8) {
                        Circle()
                            .fill(green)
                            .frame(width: 8, height: 8)

                        Text("Small steps. Big results.")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.58))
                    }
                }
                .padding(.bottom, 68)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .frame(height: 320)
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProgressPeriod.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        period = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(period == option ? .semibold : .medium))
                        .foregroundStyle(period == option ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            period == option ? green : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.96), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(overviewTitle)
                    .font(.title3.weight(.bold))

                Spacer()

                Text(periodDateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                overviewMetric(
                    icon: "dumbbell.fill",
                    tint: green,
                    value: progressSnapshot.map { String($0.workoutCount) } ?? "—",
                    title: "Workouts",
                    change: progressSnapshot?.workoutChangePercent,
                    footer: comparisonLabel
                )

                overviewDivider

                overviewMetric(
                    icon: "shoeprints.fill",
                    tint: blue,
                    value: formattedSteps(progressSnapshot?.averageDailySteps),
                    title: "Steps/Day",
                    change: progressSnapshot?.stepsChangePercent,
                    footer: comparisonLabel
                )

                overviewDivider

                overviewMetric(
                    icon: "moon.fill",
                    tint: purple,
                    value: progressSnapshot?.averageSleepDuration.map { $0.shortDuration } ?? "—",
                    title: "Sleep/Day",
                    change: progressSnapshot?.sleepChangePercent,
                    footer: comparisonLabel
                )

                overviewDivider

                overviewMetric(
                    icon: "leaf.fill",
                    tint: green,
                    value: "Soon",
                    title: "Recovery",
                    change: nil,
                    footer: "ATHLTH score"
                )
            }

            if progressLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else if let progressError {
                Label(progressError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private var workoutsCompletedCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            compactHeader("Workouts Completed")

            HStack(alignment: .top, spacing: 10) {
                if let snapshot = progressSnapshot, !snapshot.buckets.isEmpty {
                    Chart(snapshot.buckets) { bucket in
                        BarMark(
                            x: .value("Period", bucketAxisLabel(bucket.startDate)),
                            y: .value("Workouts", bucket.workoutCount)
                        )
                        .foregroundStyle(green.gradient)
                        .cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(Color.black.opacity(0.045))
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .chartXAxis {
                        AxisMarks {
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .frame(height: 120)
                } else {
                    chartPlaceholder(icon: "figure.run")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(progressSnapshot.map { String($0.workoutCount) } ?? "—")
                        .font(.title2.weight(.bold))
                    Text(periodSummaryLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    changeIndicator(progressSnapshot?.workoutChangePercent)
                        .padding(.top, 7)

                    Text(comparisonLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 66, alignment: .leading)
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var dailyStepsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            compactHeader("Daily Steps")

            HStack(alignment: .top, spacing: 10) {
                if let snapshot = progressSnapshot, !snapshot.buckets.isEmpty {
                    Chart(snapshot.buckets) { bucket in
                        BarMark(
                            x: .value("Period", bucketAxisLabel(bucket.startDate)),
                            y: .value("Steps", bucket.averageDailySteps ?? 0)
                        )
                        .foregroundStyle(blue.gradient)
                        .cornerRadius(4)
                    }
                    .chartYScale(domain: 0...stepsChartUpperBound)
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(Color.black.opacity(0.045))
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .chartXAxis {
                        AxisMarks {
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .frame(height: 120)
                } else {
                    chartPlaceholder(icon: "shoeprints.fill")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedSteps(progressSnapshot?.averageDailySteps))
                        .font(.title2.weight(.bold))
                        .minimumScaleFactor(0.70)
                        .lineLimit(1)
                    Text("avg. steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    changeIndicator(progressSnapshot?.stepsChangePercent)
                        .padding(.top, 7)

                    Text(comparisonLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 70, alignment: .leading)
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            compactHeader("Consistency Streak")

            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(green.opacity(0.08))
                        .frame(width: 78, height: 78)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(workoutStreak > 0 ? green : Color.secondary.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(workoutStreak > 0 ? "\(workoutStreak) days" : "No streak")
                        .font(.title2.weight(.bold))
                    Text(workoutStreak > 0 ? "Keep it going!" : "A workout today starts one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 6) {
                ForEach(currentWeekDays, id: \.self) { day in
                    VStack(spacing: 5) {
                        Image(systemName: isWorkoutDay(day) ? "checkmark" : "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 27, height: 27)
                            .background(
                                isWorkoutDay(day)
                                    ? green
                                    : Color.black.opacity(0.055),
                                in: Circle()
                            )

                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("\(workoutDaysThisWeek) active \(workoutDaysThisWeek == 1 ? "day" : "days") this week")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var personalRecordsCard: some View {
        let healthRecords = Array(personalRecords.prefix(2))
        let strengthRecords = Array(
            strengthWorkout.personalRecords
                .filter { $0.kind == .heaviestSet }
                .prefix(2)
        )
        let totalRecordCount = personalRecords.count + strengthWorkout.personalRecords.count

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Personal Records")
                    .font(.headline)
                Spacer()

                if totalRecordCount > healthRecords.count + strengthRecords.count {
                    Text("+\(totalRecordCount - healthRecords.count - strengthRecords.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if healthRecords.isEmpty && strengthRecords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "trophy")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("No records yet")
                        .font(.caption.weight(.semibold))

                    Text("ATHLTH will surface verified records from Apple Health and strength workouts you log in ATHLTH.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(healthRecords) { record in
                    recordRow(
                        record.kind.title,
                        value: record.formattedValue,
                        date: record.date.formatted(.dateTime.month(.abbreviated).day().year()),
                        icon: record.kind.systemImage
                    )
                }

                if !healthRecords.isEmpty && !strengthRecords.isEmpty {
                    Divider()
                        .overlay(Color.black.opacity(0.05))
                }

                ForEach(strengthRecords) { record in
                    recordRow(
                        record.title,
                        value: record.value,
                        date: record.date.formatted(.dateTime.month(.abbreviated).day().year()),
                        icon: record.kind.systemImage
                    )
                }
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var monthlyStatsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Monthly Stats")
                    .font(.headline)
                Spacer()
                Text(Date().formatted(.dateTime.month(.wide).year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 14
            ) {
                statTile(
                    icon: "dumbbell.fill",
                    tint: green,
                    value: monthlySnapshot.map { String($0.workoutCount) } ?? "—",
                    label: "Workouts",
                    change: monthlySnapshot?.workoutChangePercent
                )

                statTile(
                    icon: "shoeprints.fill",
                    tint: blue,
                    value: formattedSteps(monthlySnapshot?.totalSteps),
                    label: "Steps",
                    change: monthlySnapshot?.totalStepsChangePercent
                )

                statTile(
                    icon: "moon.fill",
                    tint: purple,
                    value: monthlySnapshot?.averageSleepDuration.map { $0.shortDuration } ?? "—",
                    label: "Avg. Sleep",
                    change: monthlySnapshot?.sleepChangePercent
                )

                statTile(
                    icon: "clock.fill",
                    tint: green,
                    value: monthlySnapshot.map { $0.trainingDuration.shortDuration } ?? "—",
                    label: "Training",
                    change: monthlySnapshot?.trainingDurationChangePercent
                )
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var achievementsCard: some View {
        TrophyProgressCard()
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goals")
                        .font(.title3.weight(.bold))
                    Text("Your biggest targets, connected to real progress.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    GoalsHubView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(green)
                }

                Button {
                    showingGoalCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(green)
                        .frame(width: 34, height: 34)
                        .background(green.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if let primary = goalStore.primaryGoal {
                Text("PRIMARY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    GoalDetailView(goalID: primary.id)
                } label: {
                    progressGoalRow(primary)
                }
                .buttonStyle(.plain)

                let secondary = goalStore.activeGoals
                    .filter { !$0.isPrimary }
                    .prefix(2)

                ForEach(Array(secondary)) { goal in
                    Divider().overlay(Color.black.opacity(0.05))

                    NavigationLink {
                        GoalDetailView(goalID: goal.id)
                    } label: {
                        progressGoalRow(goal)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundStyle(green)

                    Text("Create your first goal")
                        .font(.subheadline.weight(.semibold))

                    Text("Set a target, deadline, image and milestones. ATHLTH can verify selected milestones from Apple Health or ATHLTH workouts, while manual check-off always stays available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Add Goal") {
                        showingGoalCreation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private func progressGoalRow(_ goal: ATHLTHGoal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.category.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(green)
                .frame(width: 38, height: 38)
                .background(
                    green.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int((goal.progress * 100).rounded()))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(green)
                }

                HStack {
                    Text(goalDeadlineText(goal))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(goal.completedMilestones)/\(goal.milestones.count) milestones")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.055))
                        Capsule()
                            .fill(green)
                            .frame(width: proxy.size.width * goal.progress)
                    }
                }
                .frame(height: 6)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func goalDeadlineText(_ goal: ATHLTHGoal) -> String {
        guard let deadline = goal.deadline else {
            return goal.dataSource.title
        }

        if deadline < Date() {
            return "Deadline passed"
        }

        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: deadline)
        ).day ?? 0

        if days == 0 { return "Today" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(width: 1, height: 100)
    }

    private func compactHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func overviewMetric(
        icon: String,
        tint: Color,
        value: String,
        title: String,
        change: Double?,
        footer: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.68)
                .lineLimit(1)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let change {
                changeIndicator(change)
            } else {
                Text("—")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(footer)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func changeIndicator(_ change: Double?) -> some View {
        if let change {
            HStack(spacing: 2) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                Text("\(abs(change), specifier: "%.0f")%")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(change >= 0 ? green : Color.orange)
        } else {
            Text("—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func formattedSteps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Int(value.rounded()).formatted()
    }

    private var overviewTitle: String {
        switch period {
        case .week: return "Weekly Overview"
        case .month: return "Monthly Overview"
        case .threeMonths: return "3 Month Overview"
        case .year: return "Year Overview"
        }
    }

    private var comparisonLabel: String {
        switch period {
        case .week: return "vs. last week"
        case .month: return "vs. last month"
        case .threeMonths: return "vs. prior 3 mo."
        case .year: return "vs. last year"
        }
    }

    private var periodSummaryLabel: String {
        switch period {
        case .week: return "this week"
        case .month: return "this month"
        case .threeMonths: return "3 months"
        case .year: return "this year"
        }
    }

    private var periodDateLabel: String {
        let range = progressRange
        let start = range.start.formatted(.dateTime.month(.abbreviated).day())
        let end = range.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private var stepsChartUpperBound: Double {
        let maximum = progressSnapshot?.buckets
            .compactMap(\.averageDailySteps)
            .max() ?? 0
        let rounded = ceil(maximum / 5_000) * 5_000
        return max(10_000, rounded)
    }

    private func bucketAxisLabel(_ date: Date) -> String {
        switch period {
        case .week:
            return date.formatted(.dateTime.weekday(.narrow))
        case .month, .threeMonths:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .year:
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    @ViewBuilder
    private func chartPlaceholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.025))
            .frame(height: 120)
            .overlay {
                Image(systemName: icon)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
    }

    private var progressGrouping: HealthProgressGrouping {
        switch period {
        case .week:
            return .day
        case .month, .threeMonths:
            return .week
        case .year:
            return .month
        }
    }

    private var progressRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()

        let start: Date
        let previousStart: Date

        switch period {
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
            previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: start)
                ?? start.addingTimeInterval(-604_800)

        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
            previousStart = calendar.date(byAdding: .month, value: -1, to: start)
                ?? start.addingTimeInterval(-2_592_000)

        case .threeMonths:
            let currentMonth = calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
            start = calendar.date(byAdding: .month, value: -2, to: currentMonth)
                ?? currentMonth
            previousStart = calendar.date(byAdding: .month, value: -3, to: start)
                ?? start.addingTimeInterval(-7_776_000)

        case .year:
            start = calendar.dateInterval(of: .year, for: now)?.start
                ?? calendar.startOfDay(for: now)
            previousStart = calendar.date(byAdding: .year, value: -1, to: start)
                ?? start.addingTimeInterval(-31_536_000)
        }

        let elapsed = now.timeIntervalSince(start)
        let previousBoundary: Date

        switch period {
        case .week:
            previousBoundary = calendar.date(byAdding: .weekOfYear, value: 1, to: previousStart) ?? start
        case .month:
            previousBoundary = calendar.date(byAdding: .month, value: 1, to: previousStart) ?? start
        case .threeMonths:
            previousBoundary = calendar.date(byAdding: .month, value: 3, to: previousStart) ?? start
        case .year:
            previousBoundary = calendar.date(byAdding: .year, value: 1, to: previousStart) ?? start
        }

        let previousEnd = min(
            previousStart.addingTimeInterval(elapsed),
            previousBoundary
        )

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: previousEnd
        )
    }

    private var currentWeekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? calendar.startOfDay(for: Date())

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var workoutDaysThisWeek: Int {
        currentWeekDays.filter(isWorkoutDay).count
    }

    private func isWorkoutDay(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return consistencySnapshot?.activeWorkoutDays.contains {
            calendar.isDate($0, inSameDayAs: day)
        } ?? false
    }

    private var workoutStreak: Int {
        guard let days = consistencySnapshot?.activeWorkoutDays, !days.isEmpty else {
            return 0
        }

        let calendar = Calendar.current
        let active = Set(days.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: Date())

        var cursor: Date
        if active.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  active.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0

        while active.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }

        return streak
    }

    private var monthlyRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.dateInterval(of: .month, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: start)
            ?? start.addingTimeInterval(-2_592_000)
        let elapsed = now.timeIntervalSince(start)
        let previousBoundary = calendar.date(byAdding: .month, value: 1, to: previousStart)
            ?? start
        let previousEnd = min(
            previousStart.addingTimeInterval(elapsed),
            previousBoundary
        )

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: previousEnd
        )
    }

    private var consistencyRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-7_776_000)
        let previousStart = calendar.date(byAdding: .day, value: -90, to: start)
            ?? start.addingTimeInterval(-7_776_000)

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: start
        )
    }

    private func loadSupportingProgressData() async {
        guard health.healthDataAvailable, health.hasRequestedAuthorization else {
            monthlySnapshot = nil
            consistencySnapshot = nil
            personalRecords = []
            return
        }

        let month = monthlyRange
        let consistency = consistencyRange

        async let monthly = health.progressSnapshot(
            startDate: month.start,
            endDate: month.end,
            previousStartDate: month.previousStart,
            previousEndDate: month.previousEnd,
            grouping: .week
        )

        async let consistencyData = health.progressSnapshot(
            startDate: consistency.start,
            endDate: consistency.end,
            previousStartDate: consistency.previousStart,
            previousEndDate: consistency.previousEnd,
            grouping: .day
        )

        async let records = health.personalRecords()

        monthlySnapshot = try? await monthly
        consistencySnapshot = try? await consistencyData
        personalRecords = (try? await records) ?? []
    }

    private func loadProgressData() async {
        guard health.healthDataAvailable else {
            progressSnapshot = nil
            progressError = "Apple Health is unavailable on this device."
            return
        }

        guard health.hasRequestedAuthorization else {
            progressSnapshot = nil
            progressError = "Connect Apple Health to show your progress."
            return
        }

        progressLoading = true
        progressError = nil
        defer { progressLoading = false }

        let range = progressRange

        do {
            progressSnapshot = try await health.progressSnapshot(
                startDate: range.start,
                endDate: range.end,
                previousStartDate: range.previousStart,
                previousEndDate: range.previousEnd,
                grouping: progressGrouping
            )
        } catch {
            progressSnapshot = nil
            progressError = error.localizedDescription
        }
    }

    private func recordRow(
        _ title: String,
        value: String,
        date: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(date)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.caption.weight(.bold))
        }
    }

    private func statTile(
        icon: String,
        tint: Color,
        value: String,
        label: String,
        change: Double?
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                if let change {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        Text("\(abs(change), specifier: "%.0f")%")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(change >= 0 ? green : Color.orange)
                } else {
                    Text("—")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func achievementBadge(
        icon: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(45))

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 58)

            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func goalRow(
        icon: String,
        title: String,
        detail: String,
        progress: Double,
        progressText: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(green)
                .frame(width: 34, height: 34)
                .background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(progressText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(green)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.055))
                        Capsule()
                            .fill(green)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

extension View {
    func progressReferenceCard() -> some View {
        self
            .background(
                Color.white.opacity(0.97),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, x: 0, y: 7)
    }
}

struct ATHLTHProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var performanceStats: ProfilePerformanceStats?
    @State private var performanceStatsLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        Circle()
                            .fill(ATHLTHTheme.accent.opacity(0.12))
                            .frame(width: 96, height: 96)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(ATHLTHTheme.accent)
                            }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.profile.displayName)
                                .font(.title.weight(.bold))
                            Text("@\(session.profile.username)")
                                .foregroundStyle(.secondary)

                            Label(
                                session.profile.presence.state == .training
                                    ? "Training now"
                                    : "Ready to train",
                                systemImage: session.profile.presence.state == .training
                                    ? "figure.run"
                                    : "circle.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accent)
                        }

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        NavigationLink {
                            SocialHubView(initialTab: .friends)
                        } label: {
                            profileStat("\(social.friends.count)", "Friends")
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SocialHubView(initialTab: .messages)
                        } label: {
                            profileStat(
                                "\(messaging.unreadCount + messaging.messageRequestCount)",
                                "Messages"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        summaryCard(icon: "target", value: "\(goalStore.goals.count)", title: "Goals", tint: ATHLTHTheme.accent)
                        summaryCard(icon: "point.topleft.down.to.point.bottomright.curvepath", value: "\(session.savedRoutes.count)", title: "Saved Routes", tint: .blue)
                        summaryCard(icon: "trophy.fill", value: "\(trophyStore.unlockedCount)", title: "Trophies", tint: .orange)
                    }

                    ATHLTHCard {
                        HStack(spacing: 14) {
                            Image(systemName: "map.fill")
                                .font(.title3)
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 44, height: 44)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Route Privacy")
                                    .font(.headline)

                                Text(
                                    settings.hideRouteStartAndEnd
                                        ? "Hide roughly 250 m at the start and end when sharing routes."
                                        : "Full route start and end points are included when sharing."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Toggle(
                                "Hide route start and end",
                                isOn: $settings.hideRouteStartAndEnd
                            )
                            .labelsHidden()
                            .tint(ATHLTHTheme.accent)
                        }
                    }

                    ProfileFriendsSection()

                    TrophyCabinetSection()

                    ProfilePerformanceSection(
                        stats: performanceStats,
                        isLoading: performanceStatsLoading
                    )

                    WorkoutHistoryPreviewSection()

                    ProfileChallengesSection()

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Share Your Plans")
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Public, friends or private")
                                    .font(.headline)
                                Text("Plan visibility is stored per plan and can be changed at any time.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let plan = session.activePlan {
                                Text(plan.visibility.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ATHLTHTheme.accent.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.top, 10)
                    }

                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ATHLTH")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await loadPerformanceStats(forceRefresh: true)
                await social.refresh()
                await social.syncOwnPerformance(performanceStats)
                await social.syncOwnTrophies(trophyStore.showcaseTrophies)
            }
            .task {
                await loadPerformanceStats()
                await social.refresh()
                await social.syncOwnPerformance(performanceStats)
                await social.syncOwnTrophies(trophyStore.showcaseTrophies)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        ATHLTHNotificationCenterView()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notifications.unreadCount > 0 ? "bell.fill" : "bell")

                            if notifications.unreadCount > 0 {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .overlay {
                                        Circle().stroke(.white, lineWidth: 1.5)
                                    }
                                    .offset(x: 4, y: -3)
                            }
                        }
                    }
                    .accessibilityLabel(
                        notifications.unreadCount > 0
                            ? "Notifications, \(notifications.unreadCount) unread"
                            : "Notifications"
                    )

                    NavigationLink {
                        ATHLTHSettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
    }

    @MainActor
    private func loadPerformanceStats(forceRefresh: Bool = false) async {
        guard health.hasRequestedAuthorization else {
            performanceStats = nil
            return
        }

        performanceStatsLoading = true
        defer { performanceStatsLoading = false }

        performanceStats = try? await health.profilePerformanceStats(
            forceRefresh: forceRefresh
        )
    }

    @ViewBuilder
    private func profileStat(_ value: String, _ title: String) -> some View {
        VStack {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func summaryCard(icon: String, value: String, title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func recentActivity(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(ATHLTHTheme.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
