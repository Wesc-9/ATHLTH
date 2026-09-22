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

struct ATHLTHProgressView: View {
    private let accent = Color(red: 0.20, green: 0.66, blue: 0.42)
    private let warmAccent = Color(red: 0.79, green: 0.61, blue: 0.42)
    private let canvas = Color(red: 0.965, green: 0.972, blue: 0.968)

    private let performance: [ProgressTrendPoint] = [
        .init(label: "W1", value: 18.2),
        .init(label: "W2", value: 21.4),
        .init(label: "W3", value: 19.8),
        .init(label: "W4", value: 26.6),
        .init(label: "W5", value: 24.1),
        .init(label: "W6", value: 29.8),
        .init(label: "W7", value: 31.2),
        .init(label: "W8", value: 32.4)
    ]

    private let consistency: [ProgressConsistencyDay] = [
        .init(day: "M", completed: true),
        .init(day: "T", completed: true),
        .init(day: "W", completed: false),
        .init(day: "T", completed: true),
        .init(day: "F", completed: true),
        .init(day: "S", completed: true),
        .init(day: "S", completed: false)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    progressHeader
                    primaryGoalCard
                    weeklySnapshot
                    performanceCard
                    HStack(alignment: .top, spacing: 12) {
                        personalBestsCard
                        consistencyCard
                    }
                    milestonesCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("ATHLTH")
                        .font(.title3.weight(.black))
                        .tracking(6)

                    Text("MOVE BETTER · LIVE LONGER")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.88), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    }
            }

            Text("Progress")
                .font(.system(size: 34, weight: .bold))
                .padding(.top, 14)

            Text("Your goals. Your momentum.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryGoalCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("PRIMARY GOAL")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                    Text("ON TRACK")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Oslo Marathon")
                        .font(.title2.weight(.bold))

                    Text("19 Sep 2027 · Marathon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("178")
                        .font(.title2.weight(.bold))
                    Text("days left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Plan progress")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("34%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.06))

                        Capsule()
                            .fill(accent)
                            .frame(width: proxy.size.width * 0.34)
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 8) {
                goalMetric("3 / 4", "Runs this week")
                goalMetric("16 km", "Long run")
                goalMetric("32.4 km", "Weekly volume")
            }

            Divider()
                .overlay(Color.black.opacity(0.06))

            VStack(spacing: 10) {
                secondaryGoalRow(
                    icon: "scalemass.fill",
                    title: "Reach 82 kg",
                    detail: "86.4 kg now",
                    progress: "41%"
                )

                secondaryGoalRow(
                    icon: "stopwatch.fill",
                    title: "5K under 25:00",
                    detail: "Current best 27:12",
                    progress: "68%"
                )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [.white, Color(red: 0.985, green: 0.992, blue: 0.987)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.055), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.055), radius: 22, x: 0, y: 10)
    }

    private var weeklySnapshot: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week")
                    .font(.title3.weight(.bold))

                Spacer()

                Text("MON – SUN")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                progressMetric(icon: "figure.run", value: "5", label: "Workouts")
                progressMetric(icon: "point.topleft.down.to.point.bottomright.curvepath", value: "32.4", label: "km")
                progressMetric(icon: "clock.fill", value: "4h 38m", label: "Training")
                progressMetric(icon: "checkmark.circle.fill", value: "86%", label: "Consistency")
            }
        }
        .padding(18)
        .progressSurface()
    }

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Performance")
                        .font(.title3.weight(.bold))
                    Text("Weekly running distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("32.4 km")
                        .font(.headline)
                    Text("↑ 8% vs last week")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }

            Chart(performance) { point in
                AreaMark(
                    x: .value("Week", point.label),
                    y: .value("Distance", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.24),
                            accent.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Week", point.label),
                    y: .value("Distance", point.value)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Week", point.label),
                    y: .value("Distance", point.value)
                )
                .foregroundStyle(accent)
                .symbolSize(18)
            }
            .chartYScale(domain: 0...36)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic) {
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.035))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 180)

            HStack(spacing: 8) {
                Label("8 week trend", systemImage: "calendar")
                Spacer()
                Label("Best week · 32.4 km", systemImage: "arrow.up.right")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .progressSurface()
    }

    private var personalBestsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Personal bests")
                    .font(.headline)
                Spacer()
                Image(systemName: "trophy.fill")
                    .foregroundStyle(warmAccent)
            }

            recordRow("5K", value: "27:12", icon: "stopwatch.fill")
            recordRow("Longest run", value: "18.6 km", icon: "figure.run")
            recordRow("Squat", value: "100 kg", icon: "dumbbell.fill")
        }
        .padding(16)
        .progressSurface()
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Consistency")
                    .font(.headline)
                Spacer()
                Text("12 day streak")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            }

            HStack(spacing: 7) {
                ForEach(consistency) { item in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.completed ? accent : Color.black.opacity(0.055))
                            .frame(height: item.completed ? 42 : 25)
                            .frame(maxHeight: 44, alignment: .bottom)

                        Text(item.day)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 58, alignment: .bottom)
                }
            }

            Text("5 of 7 planned sessions completed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .progressSurface()
    }

    private var milestonesCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Recent milestones")
                    .font(.headline)
                Spacer()
                Text("3 NEW")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(accent)
            }

            HStack(spacing: 10) {
                milestone(icon: "flame.fill", title: "12 day", detail: "streak")
                milestone(icon: "figure.run", title: "100 km", detail: "this month")
                milestone(icon: "trophy.fill", title: "New PR", detail: "5K")
            }
        }
        .padding(18)
        .progressSurface()
    }

    private func goalMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func secondaryGoalRow(
        icon: String,
        title: String,
        detail: String,
        progress: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(warmAccent)
                .frame(width: 30, height: 30)
                .background(warmAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(progress)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
        }
    }

    private func progressMetric(
        icon: String,
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
            Text(value)
                .font(.subheadline.weight(.bold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func recordRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 27, height: 27)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.bold))
        }
    }

    private func milestone(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.09), in: Circle())

            Text(title)
                .font(.caption.weight(.bold))
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProgressTrendPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

private struct ProgressConsistencyDay: Identifiable {
    let id = UUID()
    let day: String
    let completed: Bool
}

private extension View {
    func progressSurface() -> some View {
        self
            .background(
                Color.white,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 16, x: 0, y: 7)
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
