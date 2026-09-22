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
        .tint(.green)
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
                                tint: .green
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

                    HStack(alignment: .top, spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Train Today")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach([WorkoutKind.running, .walking, .strength, .custom]) { kind in
                                    VStack(spacing: 7) {
                                        Image(systemName: kind.systemImage)
                                            .font(.title2)
                                            .foregroundStyle(.green)
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
                                .tint(.green)
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
                                tint: .green
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
                    colors: [.blue.opacity(0.08), .green.opacity(0.05), .clear],
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
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @State private var selectedSection = 0
    @State private var showingFileImporter = false
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var watchTransferMessage: String?
    @State private var watchTransferError: String?
    @State private var selectedStrengthSession: PlannedSession?
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
                ) { captureDevice, trackingMode in
                    if captureDevice == .appleWatch {
                        Task { @MainActor in
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
                ATHLTHSectionHeader(title: "Today's Plan", actionTitle: plan.title)
                VStack(spacing: 14) {
                    ForEach(Array((plan.weeks.first?.days.flatMap(\.sessions) ?? []).prefix(3))) { workout in
                        HStack {
                            Image(systemName: workout.kind.systemImage)
                                .foregroundStyle(.green)
                                .frame(width: 34)
                            VStack(alignment: .leading) {
                                Text(workout.title)
                                    .font(.headline)
                                Text("\(workout.durationMinutes ?? 0) min · \(workout.kind.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Quick Start",
                actionTitle: watchConnection.isReady ? "Apple Watch" : "Connect Watch"
            )
            HStack {
                ForEach([WorkoutKind.running, .walking, .strength, .custom]) { kind in
                    Button {
                        startQuickWorkoutOnWatch(kind)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: kind.systemImage)
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text(kind.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        watchWorkoutKind(for: kind) == nil ||
                        !watchConnection.isReady ||
                        watchConnection.workoutLaunchInProgress
                    )
                    .opacity(
                        watchWorkoutKind(for: kind) == nil ||
                        !watchConnection.isReady ? 0.45 : 1
                    )
                }
            }
            .padding(.top, 10)
        }

        ATHLTHCard {
            HStack {
                ATHLTHSectionHeader(title: "Routes & Challenges", actionTitle: "See All")
                Spacer()
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import GPX", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            if let route = session.savedRoutes.first {
                Map(initialPosition: .region(routeRegion(route))) {
                    MapPolyline(coordinates: route.coordinates.map(\.coordinate))
                        .stroke(.green, lineWidth: 5)
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
                    if session.canAccess(.routeChallenges) {
                        if let challenge = session.challenges.first {
                            Label(challenge.title, systemImage: "trophy.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Label("ATHLTH+ challenges", systemImage: "lock.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
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
                    .tint(.green)
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
                    description: Text("Import a GPX route or create one later.")
                )
                .frame(height: 190)
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(title: "Exercises", actionTitle: "Library + Custom")
            HStack {
                exerciseChip(PreviewData.benchPress)
                exerciseChip(PreviewData.customExercise)
            }
            .padding(.top, 10)
        }

        if let workout = session.activePlan?.weeks.first?.days.first?.sessions.first {
            Button {
                if workout.kind == .strength {
                    selectedStrengthSession = workout
                } else {
                    startPlanSpotifyIfNeeded()
                    session.beginTrainingStatus(for: workout)
                }
            } label: {
                Label(
                    "Start Workout",
                    systemImage: "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
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

    @ViewBuilder
    private func exerciseChip(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: exercise.origin == .custom ? "person.crop.circle.badge.plus" : "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text(exercise.name)
                .font(.subheadline.weight(.semibold))
            Text(exercise.primaryMuscles.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                                        tint: .green
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
                                        .foregroundStyle(.green.gradient)
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
                                        .foregroundStyle(.green)
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

    @State private var period: ProgressPeriod = .week
    @State private var progressSnapshot: HealthProgressSnapshot?
    @State private var monthlySnapshot: HealthProgressSnapshot?
    @State private var consistencySnapshot: HealthProgressSnapshot?
    @State private var progressLoading = false
    @State private var progressError: String?

    private let green = Color(red: 0.16, green: 0.72, blue: 0.38)
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
        VStack(alignment: .leading, spacing: 13) {
            compactHeader("Personal Records")

            recordRow("Heaviest Squat", value: "100 kg", date: "Mar 28, 2025", icon: "dumbbell.fill")
            recordRow("Longest Run", value: "7.2 km", date: "Mar 22, 2025", icon: "figure.run")
            recordRow("Fastest 5K", value: "24:18", date: "Mar 10, 2025", icon: "stopwatch.fill")
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Achievements")
                    .font(.headline)
                Spacer()
                Text("See All")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(green)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                achievementBadge(icon: "dumbbell.fill", tint: green, title: "10", detail: "Workouts")
                achievementBadge(icon: "shoeprints.fill", tint: blue, title: "50K", detail: "Steps Week")
                achievementBadge(icon: "mountain.2.fill", tint: purple, title: "New PR", detail: "Strength")
            }

            Button {
            } label: {
                Text("View All Achievements")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(green.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goals")
                        .font(.title3.weight(.bold))
                    Text("Keep your biggest targets visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(green)
                        .frame(width: 34, height: 34)
                        .background(green.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
            }

            goalRow(
                icon: "flag.checkered",
                title: "Oslo Marathon",
                detail: "178 days left",
                progress: 0.34,
                progressText: "34%"
            )

            Divider().overlay(Color.black.opacity(0.05))

            goalRow(
                icon: "scalemass.fill",
                title: "Reach 82 kg",
                detail: "86.4 kg now",
                progress: 0.41,
                progressText: "41%"
            )

            Divider().overlay(Color.black.opacity(0.05))

            goalRow(
                icon: "stopwatch.fill",
                title: "5K under 25:00",
                detail: "Current best 27:12",
                progress: 0.68,
                progressText: "68%"
            )
        }
        .padding(18)
        .progressReferenceCard()
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

        monthlySnapshot = try? await monthly
        consistencySnapshot = try? await consistencyData
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

private extension View {
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        Circle()
                            .fill(.green.opacity(0.12))
                            .frame(width: 96, height: 96)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(.green)
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
                            .foregroundStyle(.green)
                        }

                        Spacer()
                    }

                    HStack {
                        profileStat("\(session.profile.followersCount)", "Followers")
                        profileStat("\(session.profile.followingCount)", "Following")
                        profileStat("\(session.profile.workoutsCount)", "Workouts")
                    }

                    HStack(spacing: 12) {
                        summaryCard(icon: "bookmark.fill", value: "12", title: "Saved Plans", tint: .green)
                        summaryCard(icon: "point.topleft.down.to.point.bottomright.curvepath", value: "\(session.savedRoutes.count)", title: "Saved Routes", tint: .blue)
                        summaryCard(icon: "trophy.fill", value: "14", title: "Achievements", tint: .orange)
                    }

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
                                    .background(.green.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.top, 10)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Recent Activities", actionTitle: "See All")
                        HStack {
                            recentActivity("Morning Run", icon: "figure.run", detail: "12.5 km")
                            recentActivity("Upper Body", icon: "dumbbell.fill", detail: "6 exercises")
                            recentActivity("Evening Walk", icon: "figure.walk", detail: "7.1 km")
                        }
                        .padding(.top, 10)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Friends", actionTitle: "Find Friends")
                        HStack {
                            ForEach(["Sara", "Erik", "Live", "Marcus"], id: \.self) { name in
                                VStack(spacing: 7) {
                                    Circle()
                                        .fill(.blue.opacity(0.1))
                                        .frame(width: 52, height: 52)
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    Text(name)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
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
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }

                    Button {
                    } label: {
                        Image(systemName: "pencil")
                    }

                    NavigationLink {
                        ATHLTHSettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
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
                .foregroundStyle(.green)
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
