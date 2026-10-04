import MapKit
import SwiftUI

private enum GhostRaceHubMode:
    String,
    CaseIterable,
    Identifiable
{
    case live
    case past
    case target

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live"
        case .past: return "Past runs"
        case .target: return "Target"
        }
    }

    var subtitle: String {
        switch self {
        case .live:
            return "Race someone now"
        case .past:
            return "Race a previous run"
        case .target:
            return "Choose your finish time"
        }
    }

    var icon: String {
        switch self {
        case .live:
            return "dot.radiowaves.left.and.right"
        case .past:
            return "clock.arrow.circlepath"
        case .target:
            return "timer.circle.fill"
        }
    }
}

struct GhostRaceHubView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var publicTrailDiscovery:
        PublicTrailDiscoveryStore

    @State private var recentRuns: [WorkoutSummary] = []
    @State private var loading = false
    @State private var startingWorkoutID: UUID?
    @State private var liveStartingSessionID: UUID?
    @State private var selectedMode:
        GhostRaceHubMode = .live
    @State private var errorMessage: String?
    @State private var captureDevice:
        WorkoutCaptureDevice = .iPhone

    private var canStartRace: Bool {
        switch captureDevice {
        case .iPhone:
            return phoneWorkout.active == nil
        case .appleWatch:
            return watchConnection.isReady &&
                !watchConnection
                    .workoutLaunchInProgress
        }
    }

    private var selectedLiveSession:
        ATHLTHLiveWorkoutSession? {
        realtime.selectedLiveGhostSession
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                hero
                workoutDeviceCard
                modeOverview
                modeContent
                audioCoachCard
            }
            .padding()
            .padding(.bottom, 36)
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
        .navigationTitle("Ghost Race")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let runs: Void =
                loadRuns()
            async let live: Void =
                realtime
                    .refreshVisibleLiveSessions()
            _ = await (runs, live)
        }
        .onChange(
            of: selectedMode
        ) { _, mode in
            if mode != .live {
                realtime
                    .selectLiveGhost(nil)
            }
        }
        .refreshable {
            async let runs: Void =
                loadRuns()
            async let live: Void =
                realtime
                    .refreshVisibleLiveSessions()
            _ = await (runs, live)
        }
        .alert(
            "Ghost Race",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in
                    if !visible {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hero: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("GHOST RACE")
                            .font(.caption2.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(ATHLTHTheme.vitality)

                        Text("One race. Three ways to chase.")
                            .font(.system(
                                size: 30,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                    }

                    Spacer()

                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(ATHLTHTheme.vitality)
                }

                Text(
                    "Race someone live, chase one of your own previous runs, or create a target ghost for the exact finish time you want."
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    statusChip(
                        title: "Live",
                        icon:
                            "dot.radiowaves.left.and.right"
                    )
                    statusChip(
                        title: "Replay",
                        icon:
                            "clock.arrow.circlepath"
                    )
                    statusChip(
                        title: "Target",
                        icon:
                            "timer.circle.fill"
                    )
                }

            }
        }
    }

    private var workoutDeviceCard: some View {
        QuickStartWorkoutDeviceCard(
            selection: $captureDevice,
            watchConnected:
                watchConnection.isReady &&
                !watchConnection
                    .workoutLaunchInProgress,
            iPhoneEnabled:
                phoneWorkout.active == nil,
            iPhoneSubtitle:
                phoneWorkout.active == nil
                    ? ATHLTHLocalization.choose(
                        english:
                            "Record Ghost with iPhone GPS. The iPhone owns the workout while Apple Watch can still be used as a companion display.",
                        norwegian:
                            "Registrer Ghost med GPS på iPhone. iPhone eier økten, mens Apple Watch fortsatt kan brukes som companion-skjerm."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Finish the active iPhone workout before starting Ghost.",
                        norwegian:
                            "Fullfør den aktive iPhone-økten før du starter Ghost."
                    )
        )
    }

    private var modeOverview: some View {
        HStack(spacing: 9) {
            ForEach(
                GhostRaceHubMode.allCases
            ) { mode in
                Button {
                    withAnimation(
                        .easeInOut(
                            duration: 0.20
                        )
                    ) {
                        selectedMode = mode
                    }
                } label: {
                    modeTile(
                        mode,
                        selected:
                            selectedMode == mode
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch selectedMode {
        case .live:
            liveModeIntro

            if let selectedLiveSession {
                selectedLiveGhostCard(
                    selectedLiveSession
                )
            }

            liveNowSection

            liveFriendEntry

        case .past:
            pastSelfSection
            routeSection
            friendSection

        case .target:
            targetGhostSection
        }
    }

    private var liveModeIntro: some View {
        ATHLTHCard {
            HStack(
                alignment: .top,
                spacing: 13
            ) {
                Image(
                    systemName:
                        "dot.radiowaves.left.and.right"
                )
                .font(.title2)
                .foregroundStyle(
                    Color.green
                )
                .frame(
                    width: 48,
                    height: 48
                )
                .background(
                    Color.green
                        .opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text("Live Ghost")
                        .font(.headline)

                    Text(
                        "Choose a runner who is active now. When they share a route, ATHLTH loads the same course and compares your positions along it. If route data is unavailable, Live Ghost safely falls back to distance."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                    Text(
                        "Route-aware races ignore detours when calculating who is ahead."
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }
        }
    }

    private func selectedLiveGhostCard(
        _ liveSession:
            ATHLTHLiveWorkoutSession
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 13
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("READY TO RACE")
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .tracking(1.4)
                            .foregroundStyle(
                                ATHLTHTheme.vitality
                            )

                        Text(
                            liveRunnerSubtitle(
                                liveSession
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                        if let routeTitle =
                                liveSession.routeTitle,
                           !routeTitle.isEmpty {
                            Label(
                                routeTitle,
                                systemImage:
                                    "point.topleft.down.to.point.bottomright.curvepath"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .lineLimit(1)
                        }

                        liveGhostConnectionBadge
                    }

                    Spacer()

                    Button {
                        realtime.selectLiveGhost(
                            nil
                        )
                    } label: {
                        Image(
                            systemName: "xmark"
                        )
                        .font(
                            .caption
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .frame(
                            width: 30,
                            height: 30
                        )
                        .background(
                            Color.primary
                                .opacity(0.04),
                            in: Circle()
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task {
                        await startLiveGhost(
                            liveSession
                        )
                    }
                } label: {
                    if liveStartingSessionID ==
                        liveSession.id {
                        ProgressView()
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                    } else {
                        Label(
                            "Start Live Ghost",
                            systemImage:
                                "figure.run"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                    }
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .controlSize(.large)
                .disabled(
                    !canStartRace ||
                    liveStartingSessionID !=
                        nil
                )

                NavigationLink {
                    ATHLTHLiveWorkoutMapView(
                        session:
                            liveSession
                    )
                } label: {
                    Label(
                        "Preview live runner",
                        systemImage:
                            "map.fill"
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }
        }
    }

    @ViewBuilder
    private var liveGhostConnectionBadge:
        some View {
        switch realtime
            .liveGhostConnectionState {
        case .live:
            Label(
                ATHLTHLocalization.choose(
                    english: "Live GPS",
                    norwegian: "Live GPS"
                ),
                systemImage:
                    "dot.radiowaves.left.and.right"
            )
            .foregroundStyle(
                ATHLTHTheme.vitality
            )

        case .delayed(let seconds):
            Label(
                ATHLTHLocalization.format(
                    english:
                        "Delayed · %d s ago",
                    norwegian:
                        "Forsinket · %d s siden",
                    seconds
                ),
                systemImage:
                    "clock.badge.exclamationmark"
            )
            .foregroundStyle(.orange)

        case .reconnecting(let seconds):
            Label(
                ATHLTHLocalization.format(
                    english:
                        "Reconnecting · last GPS %d s ago",
                    norwegian:
                        "Kobler til på nytt · siste GPS for %d s siden",
                    seconds
                ),
                systemImage:
                    "arrow.triangle.2.circlepath"
            )
            .foregroundStyle(.orange)

        case .waiting:
            Label(
                ATHLTHLocalization.choose(
                    english:
                        "Waiting for live GPS",
                    norwegian:
                        "Venter på live GPS"
                ),
                systemImage:
                    "location.slash"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var liveFriendEntry: some View {
        NavigationLink {
            GhostFriendRaceHubView()
        } label: {
            ATHLTHCard {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            "person.2.wave.2.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        ATHLTHTheme.accentSoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Race a friend",
                                norwegian: "Konkurrer mot en venn"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Use an existing friend Ghost challenge when you want a shared head-to-head session.",
                                norwegian:
                                    "Bruk en eksisterende Ghost-utfordring med en venn når du vil ha en delt én-mot-én-økt."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english: "Race a friend",
                norwegian: "Konkurrer mot en venn"
            )
        )
        .accessibilityHint(
            ATHLTHLocalization.choose(
                english:
                    "Open friend Ghost Races",
                norwegian:
                    "Åpner Ghost Race med venner"
            )
        )
    }

    @ViewBuilder
    private var liveNowSection: some View {
        let sessions =
            realtime.visibleLiveSessions
                .filter {
                    $0.activity == "running" &&
                    $0.ownerID !=
                        realtime.currentUserID
                }

        if !sessions.isEmpty {
            ATHLTHCard {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Live now")
                            .font(
                                .title3.weight(
                                    .bold
                                )
                            )

                        Text(
                            "Watch a visible runner, or use their live distance as a lightweight Ghost while you run."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    Image(
                        systemName:
                            "dot.radiowaves.left.and.right"
                    )
                    .foregroundStyle(
                        Color.green
                    )
                }

                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            sessions.prefix(6)
                        )
                    ) { liveSession in
                        NavigationLink {
                            ATHLTHLiveWorkoutMapView(
                                session:
                                    liveSession
                            )
                        } label: {
                            HStack(
                                spacing: 12
                            ) {
                                Image(
                                    systemName:
                                        liveSession
                                            .ghostChallengeID ==
                                            nil
                                            ? "figure.run.circle.fill"
                                            : "flag.checkered.circle.fill"
                                )
                                .font(
                                    .system(
                                        size: 20,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    liveSession
                                        .ghostChallengeID ==
                                        nil
                                        ? ATHLTHTheme
                                            .vitality
                                        : ATHLTHTheme
                                            .premiumGold
                                )
                                .frame(
                                    width: 40,
                                    height: 40
                                )
                                .background(
                                    Color.primary
                                        .opacity(
                                            0.035
                                        ),
                                    in:
                                        RoundedRectangle(
                                            cornerRadius:
                                                12
                                        )
                                )

                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        liveSession
                                            .title
                                    )
                                    .font(
                                        .subheadline
                                            .weight(
                                                .semibold
                                            )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )
                                    .lineLimit(1)

                                    Text(
                                        liveRunnerSubtitle(
                                            liveSession
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                    .lineLimit(1)
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(
                                    .caption.bold()
                                )
                                .foregroundStyle(
                                    .tertiary
                                )
                            }
                            .padding(
                                .vertical,
                                8
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            if realtime
                                .selectedLiveGhostSessionID ==
                                liveSession.id {
                                realtime
                                    .selectLiveGhost(
                                        nil
                                    )
                            } else {
                                realtime
                                    .selectLiveGhost(
                                        liveSession
                                    )
                            }
                        } label: {
                            HStack {
                                Label(
                                    realtime
                                        .selectedLiveGhostSessionID ==
                                        liveSession.id
                                        ? "Live Ghost selected"
                                        : "Use as Live Ghost",
                                    systemImage:
                                        realtime
                                            .selectedLiveGhostSessionID ==
                                            liveSession.id
                                            ? "checkmark.circle.fill"
                                            : "figure.run.circle"
                                )

                                Spacer()

                                if realtime
                                    .selectedLiveGhostSessionID ==
                                    liveSession.id {
                                    Text("iPhone")
                                        .font(.caption2)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                }
                            }
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )
                            .foregroundStyle(
                                realtime
                                    .selectedLiveGhostSessionID ==
                                    liveSession.id
                                    ? ATHLTHTheme
                                        .vitality
                                    : ATHLTHTheme
                                        .accentDeep
                            )
                            .padding(
                                .vertical,
                                7
                            )
                        }
                        .buttonStyle(.plain)

                        if liveSession.id !=
                            sessions
                                .prefix(6)
                                .last?
                                .id {
                            Divider()
                                .padding(
                                    .leading,
                                    52
                                )
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func liveRunnerSubtitle(
        _ liveSession:
            ATHLTHLiveWorkoutSession
    ) -> String {
        let ownerName =
            social.visibleProfiles
                .first {
                    $0.userID ==
                        liveSession.ownerID
                }?
                .resolvedName ??
            social.following
                .first {
                    $0.userID ==
                        liveSession.ownerID
                }?
                .resolvedName ??
            "ATHLTH athlete"

        let kind =
            liveSession.ghostChallengeID ==
            nil
                ? "Live run"
                : "Live Ghost Run"

        if let routeTitle =
                liveSession.routeTitle,
           !routeTitle.isEmpty {
            return
                ownerName +
                " · " +
                kind +
                " · " +
                routeTitle
        }

        return
            ownerName +
            " · " +
            kind
    }

    private var audioCoachCard: some View {
        NavigationLink {
            ATHLTHGhostUpdatesSettingsView()
        } label: {
            ATHLTHCard {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            "waveform.and.person.filled"
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.vitalitySoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 12
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Ghost Updates")
                            .font(
                                .headline
                            )

                        Text(
                            settings
                                .ghostRaceAudioEnabled
                                ? "Race status and lead changes · tap to adjust"
                                : "Silent · live comparison remains visible"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .multilineTextAlignment(
                            .leading
                        )
                    }

                    Spacer()

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var targetGhostSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            "timer.circle.fill"
                    )
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
                        in:
                            RoundedRectangle(
                                cornerRadius: 14
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Target time ghost")
                            .font(.headline)

                        Text(
                            "Choose a route and a finish time. ATHLTH creates a synthetic pacer to follow all the way to the finish."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()
                }

                NavigationLink {
                    TargetGhostRoutePickerView()
                } label: {
                    Label(
                        "Choose route & target time",
                        systemImage:
                            "arrow.right.circle.fill"
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .controlSize(.large)
            }
        }
    }

    private var pastSelfSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Race past self")
                            .font(.headline)
                        Text("Choose a previous GPS run to use as the ghost.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if recentRuns.isEmpty && !loading {
                    ContentUnavailableView(
                        "No running history",
                        systemImage: "figure.run",
                        description: Text(
                            "Outdoor runs from Apple Health will appear here when a GPS route is available."
                        )
                    )
                    .frame(minHeight: 150)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentRuns.prefix(8)) { workout in
                            runRow(workout)

                            if workout.id !=
                                recentRuns.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var routeSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Race your best")
                            .font(.headline)
                        Text(
                            "Open one of your saved routes and race your best or latest matched attempt."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    NavigationLink {
                        RouteLibraryListView(
                            source: .mine
                        )
                    } label: {
                        Text("All routes")
                            .font(.caption.weight(.semibold))
                    }
                }

                if session.savedRoutes.isEmpty {
                    Text(
                        "Save or create a route first. ATHLTH will match your Apple Health attempts to it."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        session.savedRoutes
                            .sorted {
                                $0.createdAt >
                                $1.createdAt
                            }
                            .prefix(4)
                    ) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill")
                                    .foregroundStyle(ATHLTHTheme.vitality)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        ATHLTHTheme.vitalitySoft,
                                        in: RoundedRectangle(
                                            cornerRadius: 12
                                        )
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(route.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)

                                    Text(
                                        String(
                                            format: "%.2f km",
                                            route.distanceKilometers
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var friendSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 13
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Race a friend")
                            .font(.headline)

                        Text(
                            "Send a privacy-filtered ghost from one of your runs, or accept a friend’s ghost and race it live."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                NavigationLink {
                    GhostFriendRaceHubView()
                } label: {
                    Label(
                        "Open friend Ghost Races",
                        systemImage: "figure.run.square.stack.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.vitality)
                .controlSize(.large)

                NavigationLink {
                    ChallengeCreationView()
                } label: {
                    Label(
                        "Standard challenge",
                        systemImage: "trophy.fill"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHTheme.accent)
            }
        }
    }

    private func runRow(
        _ workout: WorkoutSummary
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.vitality)
                .frame(width: 42, height: 42)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 12
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    if let distance =
                        workout.distanceKilometers {
                        Text(
                            String(
                                format: "%.2f km",
                                distance
                            )
                        )
                    }

                    Text(clock(workout.duration))

                    if let pace =
                        workout.paceMinutesPerKilometer {
                        Text(paceText(pace))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await start(workout)
                }
            } label: {
                if startingWorkoutID == workout.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 54)
                } else {
                    Text("Race")
                        .font(.caption.weight(.bold))
                        .frame(width: 54)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.vitality)
            .disabled(
                !canStartRace ||
                startingWorkoutID != nil
            )
        }
        .padding(.vertical, 8)
    }

    private func start(
        _ workout: WorkoutSummary
    ) async {
        guard canStartRace else {
            errorMessage = deviceRequirementText
            return
        }

        startingWorkoutID = workout.id
        defer {
            startingWorkoutID = nil
        }

        let detail =
            await health.workoutDetail(
                for: workout
            )

        do {
            realtime.selectLiveGhost(nil)

            try await GhostRaceStartService.start(
                workout: workout,
                detail: detail,
                ownerID: session.profile.userID,
                ghostRace: ghostRace,
                watchConnection: watchConnection,
                phoneWorkout: phoneWorkout,
                captureDevice:
                    captureDevice,
                settings: settings
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func startLiveGhost(
        _ liveSession:
            ATHLTHLiveWorkoutSession
    ) async {
        guard canStartRace else {
            errorMessage =
                deviceRequirementText
            return
        }

        liveStartingSessionID =
            liveSession.id
        defer {
            liveStartingSessionID = nil
        }

        realtime.selectLiveGhost(
            liveSession
        )

        let sharedRoute =
            await resolveLiveGhostRoute(
                liveSession
            )

        do {
            try await GhostRaceStartService
                .startLive(
                    title:
                        liveSession.routeTitle ??
                        liveSession.title,
                    route:
                        sharedRoute,
                    ghostRace:
                        ghostRace,
                    watchConnection:
                        watchConnection,
                    phoneWorkout:
                        phoneWorkout,
                    captureDevice:
                        captureDevice,
                    settings:
                        settings
                )
        } catch {
            realtime.selectLiveGhost(
                nil
            )
            errorMessage =
                error.localizedDescription
        }
    }

    @MainActor
    private func resolveLiveGhostRoute(
        _ liveSession:
            ATHLTHLiveWorkoutSession
    ) async -> TrainingRoute? {
        guard let routeKey =
                liveSession.routeKey
        else {
            return nil
        }

        if let saved =
                session.savedRoutes.first(
                    where: {
                        (
                            $0.sharedSourceRouteID ??
                            $0.id
                        ) == routeKey
                    }
                ) {
            return saved
        }

        if let publicTrail =
                await publicTrailDiscovery
                    .trail(id: routeKey) {
            return publicTrail.trainingRoute
        }

        return nil
    }

    private func loadRuns() async {
        loading = true
        defer {
            loading = false
        }

        guard health.hasRequestedAuthorization else {
            recentRuns = []
            return
        }

        let history =
            (try? await health.workoutHistory()) ??
            health.workouts

        recentRuns =
            history
                .filter {
                    $0.activity == .running &&
                    ($0.distanceMeters ?? 0) >= 250
                }
                .sorted {
                    $0.startDate >
                    $1.startDate
                }
    }

    private var deviceRequirementText: String {
        switch captureDevice {
        case .iPhone:
            if phoneWorkout.active != nil {
                return "Finish the active iPhone workout before starting Ghost Race."
            }
            return "iPhone is ready."

        case .appleWatch:
            if !watchConnection.isReady {
                return "Connect Apple Watch or choose iPhone."
            }

            if watchConnection
                .workoutLaunchInProgress {
                return "Apple Watch is already preparing a workout."
            }

            return "Apple Watch is ready."
        }
    }

    private func statusChip(
        title: String,
        icon: String
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                ATHLTHTheme.surfaceSage,
                in: Capsule()
            )
    }

    private func modeTile(
        _ mode: GhostRaceHubMode,
        selected: Bool
    ) -> some View {
        VStack(spacing: 7) {
            Image(
                systemName: mode.icon
            )
            .font(.headline)

            Text(mode.title)
                .font(
                    .caption
                        .weight(.semibold)
                )

            Text(mode.subtitle)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(
            selected
                ? Color.white
                : ATHLTHTheme.primaryText
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            selected
                ? ATHLTHTheme.vitality
                : ATHLTHTheme.card,
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                selected
                    ? Color.clear
                    : ATHLTHTheme.border,
                lineWidth: 0.8
            )
        }
    }

    private func clock(
        _ seconds: TimeInterval
    ) -> String {
        let total = max(
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

    private func paceText(
        _ minutesPerKilometer: Double
    ) -> String {
        let seconds =
            max(
                Int(
                    (
                        minutesPerKilometer *
                        60
                    ).rounded()
                ),
                0
            )

        return String(
            format: "%d:%02d /km",
            seconds / 60,
            seconds % 60
        )
    }
}

struct GhostRaceLivePanel: View {
    @EnvironmentObject private var ghostRace: GhostRaceStore

    let snapshot: WatchWorkoutLiveSnapshot

    var body: some View {
        if let reference = ghostRace.reference {
            VStack(spacing: 14) {
                statusCard(
                    reference: reference
                )

                if let comparison =
                    ghostRace.comparison {
                    mapCard(
                        reference: reference,
                        comparison: comparison
                    )
                    metrics(
                        comparison: comparison
                    )
                    progressCard(
                        comparison: comparison
                    )
                } else if ghostRace.result == nil {
                    ATHLTHCard {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Waiting for live GPS")
                                    .font(.subheadline.weight(.semibold))
                                Text(
                                    "ATHLTH will place you and your ghost on the route as soon as Apple Watch sends the first GPS point."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                if let result =
                    ghostRace.result {
                    resultCard(
                        result
                    )
                }
            }
        }
    }

    private func statusCard(
        reference: GhostRaceReference
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.vitality)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.vitalitySoft,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("GHOST RACE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(mainStatus)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        reference.startedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(
                    snapshot.state == .paused
                        ? "PAUSED"
                        : "LIVE"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    snapshot.state == .paused
                        ? .orange
                        : ATHLTHTheme.vitality
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    (
                        snapshot.state == .paused
                            ? Color.orange
                            : ATHLTHTheme.vitality
                    ).opacity(0.11),
                    in: Capsule()
                )
            }
        }
    }

    private func mapCard(
        reference: GhostRaceReference,
        comparison: GhostRaceComparison
    ) -> some View {
        ATHLTHCard {
            Map(
                initialPosition:
                    .region(
                        region(
                            reference: reference
                        )
                    )
            ) {
                MapPolyline(
                    coordinates:
                        reference.points.map(
                            \.coordinate
                        )
                )
                .stroke(
                    ATHLTHTheme.vitality
                        .opacity(0.45),
                    lineWidth: 5
                )

                Annotation(
                    "You",
                    coordinate:
                        comparison
                            .userCoordinate
                ) {
                    ZStack {
                        Circle()
                            .fill(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .frame(
                                width: 24,
                                height: 24
                            )
                        Circle()
                            .stroke(
                                .white,
                                lineWidth: 3
                            )
                            .frame(
                                width: 24,
                                height: 24
                            )
                    }
                }

                Annotation(
                    "Ghost",
                    coordinate:
                        comparison
                            .ghostCoordinate
                ) {
                    Image(systemName: "figure.run")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
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
                }
            }
            .mapStyle(.standard(
                elevation: .flat
            ))
            .frame(height: 250)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
            )

            if comparison.routeDeviationMeters > 80 {
                Label(
                    ATHLTHLocalization.format(
                    english: "You are about %d m from the ghost route.",
                    norwegian: "Du er omtrent %d m fra Ghost-ruten.",
                    Int(comparison.routeDeviationMeters.rounded())
                ),
                    systemImage: "location.slash.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 10)
            }
        }
    }

    private func metrics(
        comparison: GhostRaceComparison
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {
            ghostMetric(
                title: "Distance",
                value: String(
                    format: "%.2f km",
                    snapshot.distanceMeters /
                    1_000
                ),
                icon: "location.fill"
            )

            ghostMetric(
                title: "Elapsed",
                value:
                    clock(
                        snapshot.elapsedTime
                    ),
                icon: "stopwatch.fill"
            )

            ghostMetric(
                title: "Avg pace",
                value:
                    averagePaceText,
                icon: "gauge.with.dots.needle.50percent"
            )

            ghostMetric(
                title: "Vs ghost",
                value:
                    signedTimeText(
                        comparison
                            .signedTimeSeconds
                    ),
                icon:
                    comparison
                        .signedTimeSeconds >= 0
                        ? "arrow.down.right"
                        : "arrow.up.right"
            )
        }
    }

    private func progressCard(
        comparison: GhostRaceComparison
    ) -> some View {
        ATHLTHCard {
            VStack(spacing: 13) {
                progressRow(
                    title: "You",
                    progress:
                        comparison.userProgress,
                    detail:
                        String(
                            format: "%.0f%%",
                            comparison
                                .userProgress *
                                100
                        ),
                    tint:
                        ATHLTHTheme.accentDeep
                )

                Divider()

                progressRow(
                    title: "Ghost",
                    progress:
                        comparison.ghostProgress,
                    detail:
                        distanceDeltaText(
                            comparison
                                .signedDistanceMeters
                        ),
                    tint:
                        ATHLTHTheme.vitality
                )
            }
        }
    }

    private func resultCard(
        _ result: GhostRaceResult
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    resultTitle(result),
                    systemImage:
                        result.beatGhost == true
                            ? "trophy.fill"
                            : "flag.checkered"
                )
                .font(.headline)
                .foregroundStyle(
                    result.beatGhost == true
                        ? ATHLTHTheme.vitality
                        : ATHLTHTheme.primaryText
                )

                Text(
                    resultSubtitle(result)
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if result.maximumLeadMeters > 0 ||
                    result.maximumDeficitMeters > 0 ||
                    result.leadChangeCount > 0 {
                    Divider()

                    HStack(spacing: 10) {
                        resultMetric(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Best lead",
                                    norwegian: "Største ledelse"
                                ),
                            value:
                                "\(Int(result.maximumLeadMeters.rounded())) m"
                        )

                        resultMetric(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Largest gap",
                                    norwegian: "Største etterslep"
                                ),
                            value:
                                "\(Int(result.maximumDeficitMeters.rounded())) m"
                        )

                        resultMetric(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Lead changes",
                                    norwegian: "Lederskifter"
                                ),
                            value:
                                "\(result.leadChangeCount)"
                        )
                    }
                }
            }
        }
    }

    private func resultMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(value)
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .monospacedDigit()

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var mainStatus: String {
        guard let comparison =
                ghostRace.comparison
        else {
            return "Finding your position…"
        }

        let meters =
            Int(
                abs(
                    comparison
                        .signedDistanceMeters
                ).rounded()
            )

        if meters < 8 {
            return "Neck and neck"
        }

        if comparison.userIsAhead {
            return "You are \(meters) m ahead"
        }

        return "Ghost is \(meters) m ahead"
    }

    private var averagePaceText: String {
        guard snapshot.distanceMeters >= 100,
              snapshot.elapsedTime > 0
        else {
            return "— /km"
        }

        let seconds =
            snapshot.elapsedTime /
            (snapshot.distanceMeters / 1_000)

        let total =
            max(Int(seconds.rounded()), 0)

        return String(
            format: "%d:%02d /km",
            total / 60,
            total % 60
        )
    }

    private func ghostMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(ATHLTHTheme.vitality)

                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private func progressRow(
        title: String,
        progress: Double,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value:
                    min(max(progress, 0), 1)
            )
            .tint(tint)
        }
    }

    private func distanceDeltaText(
        _ meters: Double
    ) -> String {
        let rounded =
            Int(abs(meters).rounded())

        if rounded < 8 {
            return "even"
        }

        return meters >= 0
            ? "+\(rounded) m you"
            : "+\(rounded) m ghost"
    }

    private func signedTimeText(
        _ seconds: TimeInterval
    ) -> String {
        let rounded =
            Int(abs(seconds).rounded())
        let prefix =
            seconds >= 0 ? "−" : "+"
        return prefix +
            clock(
                TimeInterval(rounded)
            )
    }

    private func resultTitle(
        _ result: GhostRaceResult
    ) -> String {
        guard result.completedRoute,
              let beat = result.beatGhost
        else {
            return "Ghost Race finished"
        }

        return beat
            ? "You beat your ghost"
            : "Ghost wins this one"
    }

    private func resultSubtitle(
        _ result: GhostRaceResult
    ) -> String {
        guard result.completedRoute,
              let delta =
                result.signedTimeSeconds
        else {
            return "ATHLTH could not confirm enough of the route to compare the finish time reliably."
        }

        let amount =
            clock(abs(delta))

        if abs(delta) < 1 {
            return "You matched your previous time."
        }

        return delta > 0
            ? "You reached the finish \(amount) faster than the reference run."
            : "The reference run reached the finish \(amount) faster."
    }

    private func clock(
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

    private func region(
        reference: GhostRaceReference
    ) -> MKCoordinateRegion {
        let coordinates =
            reference.points.map(
                \.coordinate
            )

        guard let first =
                coordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.02,
                        longitudeDelta: 0.02
                    )
            )
        }

        let latitudes =
            coordinates.map(\.latitude)
        let longitudes =
            coordinates.map(\.longitude)

        let minLatitude =
            latitudes.min() ??
            first.latitude
        let maxLatitude =
            latitudes.max() ??
            first.latitude
        let minLongitude =
            longitudes.min() ??
            first.longitude
        let maxLongitude =
            longitudes.max() ??
            first.longitude

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (
                            minLatitude +
                            maxLatitude
                        ) / 2,
                    longitude:
                        (
                            minLongitude +
                            maxLongitude
                        ) / 2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        max(
                            (
                                maxLatitude -
                                minLatitude
                            ) * 1.35,
                            0.008
                        ),
                    longitudeDelta:
                        max(
                            (
                                maxLongitude -
                                minLongitude
                            ) * 1.35,
                            0.008
                        )
                )
        )
    }
}


// Keeps fixed Ghost, Live Ghost, live sharing and Watch presentation in sync
// independently of which workout screen is currently visible.
struct ATHLTHGhostRuntimeObserver: View {
    @EnvironmentObject private var ghostRace:
        GhostRaceStore
    @EnvironmentObject private var realtime:
        ATHLTHRealtimeSocialStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    @EnvironmentObject private var mirroring:
        WorkoutMirroringStore
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore
    @EnvironmentObject private var settings:
        AppSettingsStore
    @EnvironmentObject private var social:
        SocialStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onChange(
                of:
                    mirroring
                        .snapshot?
                        .capturedAt
            ) { _, _ in
                Task { @MainActor in
                    await syncWatchRuntime()
                }
            }
            .onChange(
                of:
                    phoneWorkout
                        .active?
                        .points
                        .count
            ) { _, _ in
                Task { @MainActor in
                    await syncPhoneRuntime()
                }
            }
            .onChange(
                of:
                    realtime
                        .liveLocations
            ) { _, _ in
                Task { @MainActor in
                    await syncGhostComparisons()
                }
            }
            .onChange(
                of:
                    realtime
                        .selectedLiveGhostSessionID
            ) { _, _ in
                Task { @MainActor in
                    await syncGhostComparisons()
                }
            }
            .onChange(
                of:
                    phoneWorkout
                        .completionStartedWorkout?
                        .id
            ) { _, _ in
                finalizePhoneGhostIfNeeded()
            }
            .onChange(
                of:
                    phoneWorkout
                        .active?
                        .id
            ) { _, activeID in
                guard activeID == nil
                else {
                    return
                }

                Task { @MainActor in
                    if realtime.currentSession != nil {
                        await realtime
                            .leaveCurrentLiveWorkout()
                    }

                    if realtime
                        .selectedLiveGhostSessionID != nil {
                        realtime
                            .selectLiveGhost(nil)
                    }

                    clearLiveGhostContext(
                        sendToWatch: false
                    )
                }
            }
    }

    @MainActor
    private func syncWatchRuntime() async {
        guard let snapshot =
                mirroring.snapshot
        else {
            return
        }

        if ghostRace.reference != nil,
           snapshot.kind == .running {
            ghostRace.update(
                with: snapshot
            )
        }

        if snapshot.state == .completed ||
            snapshot.state == .failed {
            if realtime.currentSession != nil {
                await realtime
                    .leaveCurrentLiveWorkout()
            }

            if realtime
                .selectedLiveGhostSessionID != nil {
                realtime.selectLiveGhost(nil)
            }

            clearLiveGhostContext(
                sendToWatch: true
            )
            return
        }

        guard snapshot.state == .running ||
                snapshot.state == .paused
        else {
            return
        }

        await publishWatchLocation(
            snapshot
        )
        await syncWatchLiveGhost(
            snapshot
        )
    }

    @MainActor
    private func syncPhoneRuntime() async {
        guard let workout =
                phoneWorkout.active
        else {
            return
        }

        let latestLocation =
            workout.points.last?
                .location
        let elapsed =
            workout.elapsed(
                at: Date()
            )

        if ghostRace.reference != nil,
           !workout.walking {
            ghostRace
                .updatePhoneWorkout(
                    location:
                        latestLocation,
                    elapsedTime:
                        elapsed,
                    state:
                        workout.resumedAt == nil
                            ? .paused
                            : .running
                )

            phoneWorkout
                .applyGhostComparison(
                    ghostRace.comparison,
                    title:
                        ghostRace
                            .reference?
                            .title,
                    configuration:
                        settings
                            .ghostRaceAudioConfiguration
                )

            clearLiveGhostContext(
                sendToWatch: false
            )
        } else {
            syncPhoneLiveGhost(
                workout
            )
        }

        if let latestLocation {
            await publishPhoneLocation(
                workout,
                location:
                    latestLocation
            )
        }
    }

    @MainActor
    private func syncGhostComparisons() async {
        if mirroring.hasActiveMirroredWorkout {
            await syncWatchRuntime()
            return
        }

        if phoneWorkout.active != nil {
            await syncPhoneRuntime()
            return
        }

        if realtime
            .selectedLiveGhostSessionID == nil {
            clearLiveGhostContext(
                sendToWatch: false
            )
        }
    }

    @MainActor
    private func syncWatchLiveGhost(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) async {
        guard ghostRace.reference == nil,
              snapshot.kind == .running,
              let selected =
                realtime
                    .selectedLiveGhostSession
        else {
            if realtime
                .selectedLiveGhostSessionID == nil {
                clearLiveGhostContext(
                    sendToWatch: true
                )
            }
            return
        }

        guard let comparison =
                realtime
                    .liveGhostComparison(
                        ownDistanceMeters:
                            snapshot
                                .distanceMeters,
                        ownElapsedSeconds:
                            snapshot
                                .elapsedTime,
                        ownRouteKey:
                            snapshot
                                .routeComparisonID,
                        ownRouteProgressPercent:
                            snapshot
                                .routeProgressPercent,
                        ownRouteDeviationMeters:
                            snapshot
                                .routeDeviationMeters
                    )
        else {
            return
        }

        let context =
            makeLiveGhostContext(
                session: selected,
                comparison:
                    comparison
            )

        storeLiveGhostContext(
            context,
            sendToWatch: true
        )
    }

    @MainActor
    private func syncPhoneLiveGhost(
        _ workout: PhoneWorkout
    ) {
        guard !workout.walking,
              let selected =
                realtime
                    .selectedLiveGhostSession
        else {
            if realtime
                .selectedLiveGhostSessionID == nil {
                phoneWorkout
                    .applyGhostComparison(
                        nil,
                        title: nil,
                        configuration: nil
                    )
                clearLiveGhostContext(
                    sendToWatch: false
                )
            }
            return
        }

        guard let comparison =
                realtime
                    .liveGhostComparison(
                        ownDistanceMeters:
                            workout
                                .distanceMeters,
                        ownElapsedSeconds:
                            workout
                                .elapsed(
                                    at: Date()
                                ),
                        ownRouteKey:
                            workout
                                .plannedComparisonRouteID,
                        ownRouteProgressPercent:
                            workout
                                .routeProgressPercent,
                        ownRouteDeviationMeters:
                            workout
                                .routeDeviationMeters
                    )
        else {
            return
        }

        let context =
            makeLiveGhostContext(
                session: selected,
                comparison:
                    comparison
            )

        storeLiveGhostContext(
            context,
            sendToWatch: false
        )

        phoneWorkout
            .applyLiveGhostUpdate(
                title:
                    context.title,
                distanceDelta:
                    comparison
                        .signedDistanceMeters,
                timeDelta:
                    comparison
                        .estimatedTimeDeltaSeconds,
                configuration:
                    settings
                        .ghostRaceAudioConfiguration
            )
    }

    @MainActor
    private func publishWatchLocation(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) async {
        if realtime.currentSession == nil {
            guard social.privacy?
                    .shareLiveWorkoutLocation ==
                    true
            else {
                return
            }

            let activity: String
            switch snapshot.kind {
            case .walking:
                activity = "walking"
            case .cycling:
                activity = "cycling"
            case .running:
                activity = "running"
            default:
                return
            }

            let visibility =
                ATHLTHLiveWorkoutVisibility(
                    rawValue:
                        social.privacy?
                            .liveLocationVisibility ??
                        "followers"
                ) ?? .followers

            _ = await realtime
                .beginLiveWorkout(
                    title:
                        snapshot.routeTitle ??
                        snapshot.kind.title,
                    activity: activity,
                    visibility: visibility,
                    routeKey:
                        snapshot
                            .routeComparisonID,
                    routeDistanceMeters:
                        snapshot
                            .routeDistanceMeters,
                    routeTitle:
                        snapshot
                            .routeTitle
                )
        }

        await realtime
            .publishMirroredSnapshot(
                snapshot,
                includeHeartRate:
                    social.privacy?
                        .shareLiveWorkoutHeartRate ==
                    true
            )
    }

    @MainActor
    private func publishPhoneLocation(
        _ workout: PhoneWorkout,
        location: CLLocation
    ) async {
        if realtime.currentSession == nil {
            guard social.privacy?
                    .shareLiveWorkoutLocation ==
                    true
            else {
                return
            }

            let visibility =
                ATHLTHLiveWorkoutVisibility(
                    rawValue:
                        social.privacy?
                            .liveLocationVisibility ??
                        "followers"
                ) ?? .followers

            _ = await realtime
                .beginLiveWorkout(
                    title:
                        workout.title,
                    activity:
                        workout.walking
                            ? "walking"
                            : "running",
                    visibility:
                        visibility,
                    routeKey:
                        workout
                            .plannedComparisonRouteID,
                    routeDistanceMeters:
                        workout
                            .plannedRouteDistanceKilometers
                            .map {
                                max(
                                    $0 * 1_000,
                                    0
                                )
                            },
                    routeTitle:
                        workout
                            .plannedRouteTitle
                )
        }

        await realtime
            .publishLocation(
                location,
                distanceMeters:
                    workout
                        .distanceMeters,
                elapsedSeconds:
                    workout
                        .elapsed(
                            at: Date()
                        ),
                routeProgressPercent:
                    workout
                        .routeProgressPercent,
                routeDeviationMeters:
                    workout
                        .routeDeviationMeters,
                routeKey:
                    workout
                        .plannedComparisonRouteID,
                routeDistanceMeters:
                    workout
                        .plannedRouteDistanceKilometers
                        .map {
                            max(
                                $0 * 1_000,
                                0
                            )
                        },
                routeTitle:
                    workout
                        .plannedRouteTitle
            )
    }

    @MainActor
    private func finalizePhoneGhostIfNeeded() {
        guard let workout =
                phoneWorkout
                    .completionStartedWorkout,
              !workout.walking,
              ghostRace.reference != nil
        else {
            return
        }

        ghostRace
            .updatePhoneWorkout(
                location:
                    workout
                        .points
                        .last?
                        .location,
                elapsedTime:
                    max(
                        workout
                            .accumulatedSeconds,
                        workout.elapsed(
                            at:
                                workout.end ??
                                Date()
                        )
                    ),
                state: .completed
            )
    }

    private func makeLiveGhostContext(
        session:
            ATHLTHLiveWorkoutSession,
        comparison:
            ATHLTHLiveGhostComparison
    ) -> ATHLTHLiveGhostContext {
        ATHLTHLiveGhostContext(
            title:
                opponentName(
                    session
                ),
            distanceDeltaMeters:
                comparison
                    .signedDistanceMeters,
            estimatedTimeDeltaSeconds:
                comparison
                    .estimatedTimeDeltaSeconds,
            updatedAt:
                comparison.updatedAt,
            audio:
                liveGhostAudioContext
        )
    }

    private var liveGhostAudioContext:
        ATHLTHLiveGhostAudioContext {
        let audio =
            settings
                .ghostRaceAudioConfiguration

        return ATHLTHLiveGhostAudioContext(
            enabled: audio.enabled,
            distanceIntervalMeters:
                audio
                    .distanceIntervalMeters,
            timeIntervalSeconds:
                audio
                    .timeIntervalSeconds,
            announceLeadChanges:
                audio
                    .announceLeadChanges,
            leadChangeThresholdMeters:
                audio
                    .leadChangeThresholdMeters,
            periodicDeliveryRawValue:
                audio
                    .resolvedPeriodicDelivery
                    .rawValue,
            leadChangeDeliveryRawValue:
                audio
                    .resolvedLeadChangeDelivery
                    .rawValue,
            importantLeadChangeDeliveryRawValue:
                audio
                    .resolvedImportantLeadChangeDelivery
                    .rawValue,
            importantLeadChangeMeters:
                audio
                    .resolvedImportantLeadChangeMeters
        )
    }

    private func opponentName(
        _ session:
            ATHLTHLiveWorkoutSession
    ) -> String {
        social.visibleProfiles
            .first {
                $0.userID ==
                    session.ownerID
            }?
            .resolvedName ??
        social.following
            .first {
                $0.userID ==
                    session.ownerID
            }?
            .resolvedName ??
        session.title
    }

    @MainActor
    private func storeLiveGhostContext(
        _ liveGhost:
            ATHLTHLiveGhostContext,
        sendToWatch: Bool
    ) {
        var context =
            ATHLTHLiveWorkoutContextStore
                .load()

        context.liveGhost =
            liveGhost

        ATHLTHLiveWorkoutContextStore
            .save(context)

        if sendToWatch {
            watchConnection
                .sendLiveSurfaceContext(
                    context
                )
        }
    }

    @MainActor
    private func clearLiveGhostContext(
        sendToWatch: Bool
    ) {
        var context =
            ATHLTHLiveWorkoutContextStore
                .load()

        guard context.liveGhost != nil
        else {
            return
        }

        context.liveGhost = nil
        ATHLTHLiveWorkoutContextStore
            .save(context)

        if sendToWatch {
            watchConnection
                .sendLiveSurfaceContext(
                    context
                )
        }
    }
}
