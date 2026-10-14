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
        case .past: return "Replay"
        case .target: return ATHLTHLocalization.choose(english: "Target", norwegian: "Mål")
        }
    }

    var headline: String {
        switch self {
        case .live:
            return ATHLTHLocalization.choose(
                english: "Run against someone now.",
                norwegian: "Løp mot noen nå."
            )
        case .past:
            return ATHLTHLocalization.choose(
                english: "Run a previous workout.",
                norwegian: "Løp en tidligere økt."
            )
        case .target:
            return ATHLTHLocalization.choose(
                english: "Set a goal. Chase it.",
                norwegian: "Sett et mål og jag det."
            )
        }
    }

    var introduction: String {
        switch self {
        case .live:
            return ATHLTHLocalization.choose(
                english: "Race live against visible runners or invite a friend.",
                norwegian: "Konkurrer live mot andre løpere eller inviter en venn."
            )
        case .past:
            return ATHLTHLocalization.choose(
                english: "Select a GPS run and challenge your previous performance.",
                norwegian: "Velg en GPS-økt og utfordre din tidligere tid."
            )
        case .target:
            return ATHLTHLocalization.choose(
                english: "Choose a route and set your finish time or pace per km.",
                norwegian: "Velg en rute og sett ønsket sluttid eller tempo per km."
            )
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

private enum GhostReplayDistanceFilter: String, CaseIterable, Identifiable {
    case all, five, ten, half

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
        case .five: return "5 km"
        case .ten: return "10 km"
        case .half: return "21 km"
        }
    }

    var distanceRange: ClosedRange<Double>? {
        switch self {
        case .all: return nil
        case .five: return 4.5...5.5
        case .ten: return 9.0...11.0
        case .half: return 19.0...23.0
        }
    }
}

private enum GhostReplaySort: String, CaseIterable, Identifiable {
    case newest, fastest, longest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return ATHLTHLocalization.choose(english: "Newest", norwegian: "Nyeste")
        case .fastest: return ATHLTHLocalization.choose(english: "Fastest", norwegian: "Raskest")
        case .longest: return ATHLTHLocalization.choose(english: "Longest", norwegian: "Lengst")
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

    // Replay lists only GPS runs that can actually prepare a Ghost.
    @State private var recentRuns: [WorkoutSummary] = []
    @State private var replayCandidates: [WorkoutSummary] = []
    @State private var replayCheckedCount = 0
    @State private var loading = false
    @State private var verifyingReplay = false
    @State private var startingWorkoutID: UUID?
    @State private var liveStartingSessionID: UUID?
    // Each race category keeps its own experience level.
    @AppStorage("athlth.ghostRace.live.advancedMode")
    private var liveAdvancedMode = false
    @AppStorage("athlth.ghostRace.replay.advancedMode")
    private var replayAdvancedMode = false
    @AppStorage("athlth.ghostRace.target.advancedMode")
    private var targetAdvancedMode = false
    @State private var selectedMode:
        GhostRaceHubMode = .past

    private var advancedMode: Bool {
        switch selectedMode {
        case .live: return liveAdvancedMode
        case .past: return replayAdvancedMode
        case .target: return targetAdvancedMode
        }
    }

    private func setExperience(advanced: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch selectedMode {
            case .live: liveAdvancedMode = advanced
            case .past: replayAdvancedMode = advanced
            case .target: targetAdvancedMode = advanced
            }
            if !advanced {
                // Hidden advanced choices must never affect a basic start.
                captureDevice = .iPhone
                if selectedMode == .past {
                    replaySearch = ""
                    replayFavoritesOnly = false
                    replaySort = .newest
                }
            }
        }
    }
    @State private var replaySearch = ""
    @State private var replaySort: GhostReplaySort = .newest
    @State private var replayDistanceFilter: GhostReplayDistanceFilter = .all
    @State private var replayFavoritesOnly = false
    @State private var replayFavoriteIDs: Set<UUID> = []
    @State private var pendingReplayRun: WorkoutSummary?
    @State private var pendingLiveRace: ATHLTHLiveWorkoutSession?
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
            LazyVStack(spacing: 14) {
                hero
                modeOverview
                ghostExperiencePicker
                modeContent
                if selectedMode != .target && advancedMode {
                    workoutDeviceCard
                }
                if advancedMode {
                    audioCoachCard
                }
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
            loadReplayFavorites()
            async let runs: Void =
                loadRuns()
            async let live: Void =
                realtime
                    .refreshVisibleLiveSessions()
            _ = await (runs, live)
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Start Live Ghost?",
                norwegian: "Starte Live Ghost?"
            ),
            isPresented: Binding(
                get: { pendingLiveRace != nil },
                set: { if !$0 { pendingLiveRace = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let session = pendingLiveRace {
                Button(ATHLTHLocalization.choose(
                    english: "Start race",
                    norwegian: "Start konkurransen"
                )) {
                    pendingLiveRace = nil
                    Task { await startLiveGhost(session) }
                }
            }
        } message: {
            let device = captureDevice == .iPhone ? "iPhone" : "Apple Watch"
            Text("\(pendingLiveRace?.routeTitle ?? "Live Ghost") · \(device)")
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Race this previous run?",
                norwegian: "Konkurrere mot denne økten?"
            ),
            isPresented: Binding(
                get: { pendingReplayRun != nil },
                set: { if !$0 { pendingReplayRun = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let run = pendingReplayRun {
                Button(ATHLTHLocalization.choose(
                    english: "Start Replay",
                    norwegian: "Start Replay"
                )) {
                    pendingReplayRun = nil
                    Task { await start(run) }
                }
            }
        } message: {
            let duration = pendingReplayRun.map { clock($0.duration) } ?? "—"
            let distance = pendingReplayRun?.distanceKilometers ?? 0
            let device = captureDevice == .iPhone ? "iPhone" : "Apple Watch"
            Text(String(format: "%.1f km · %@ · %@", distance, duration, device))
        }
        .onChange(
            of: selectedMode
        ) { _, mode in
            if mode != .live {
                realtime.selectLiveGhost(nil)
            }
            if !advancedMode {
                captureDevice = .iPhone
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
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
            Image(selectedMode == .live ? "TrainHero" : "GoalMountain")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: 194)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.24)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

            VStack(alignment: .leading, spacing: 9) {
                Text("GHOST RACE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                Text(selectedMode.headline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                    .frame(maxWidth: 255, alignment: .leading)

                Text(selectedMode.introduction)
                    .font(.system(size: 12))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 268, alignment: .leading)

                if selectedMode == .live {
                    let count = realtime.visibleLiveSessions.filter {
                        $0.activity == "running" &&
                        $0.ownerID != realtime.currentUserID
                    }.count
                    Label(
                        ATHLTHLocalization.format(
                            english: "%d runners visible now",
                            norwegian: "%d løpere synlige nå",
                            count
                        ),
                        systemImage: "circle.fill"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color.white.opacity(0.94), in: Capsule()
                    )
                }
            }
            .padding(19)
            }
            .frame(width: geometry.size.width, height: 194)
            .clipped()
        }
        .frame(height: 194)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 23))
        .clipShape(RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .stroke(Color.white.opacity(0.86), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
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

    // An unobtrusive level choice belongs to the active category, never
    // to the Ghost Race title bar. One level can differ from another.
    private var ghostExperiencePicker: some View {
        HStack(spacing: 8) {
            Text(ATHLTHLocalization.choose(
                english: "Display",
                norwegian: "Visning"
            ))
            .font(.caption.weight(.medium))
            .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                experienceButton(
                    title: ATHLTHLocalization.choose(
                        english: "Basic", norwegian: "Enkel"
                    ),
                    isAdvanced: false
                )
                experienceButton(
                    title: ATHLTHLocalization.choose(
                        english: "Advanced", norwegian: "Avansert"
                    ),
                    isAdvanced: true
                )
            }
            .padding(3)
            .background(ATHLTHTheme.surfaceStone, in: Capsule())
        }
        .padding(.horizontal, 3)
    }

    private func experienceButton(
        title: String,
        isAdvanced: Bool
    ) -> some View {
        Button {
            setExperience(advanced: isAdvanced)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    advancedMode == isAdvanced
                        ? ATHLTHTheme.primaryText
                        : ATHLTHTheme.mutedText
                )
                .padding(.horizontal, 13)
                .frame(minHeight: 38)
                .background(
                    advancedMode == isAdvanced ? Color.white : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(advancedMode == isAdvanced ? .isSelected : [])
    }

    private var modeOverview: some View {
        HStack(spacing: 4) {
            ForEach(GhostRaceHubMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        selectedMode = mode
                    }
                } label: {
                    modeTile(mode, selected: selectedMode == mode)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            ATHLTHTheme.surfaceStone,
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }

    @ViewBuilder
    private var modeContent: some View {
        switch selectedMode {
        case .live:
            liveModeIntro
            if let selectedLiveSession {
                selectedLiveGhostCard(selectedLiveSession)
            }
            liveNowSection

        case .past:
            if advancedMode {
                pastSelfSection
            } else {
                basicReplaySection
            }
            if hasMoreReplayCandidates || verifyingReplay {
                replayMoreCard
            }
            if advancedMode {
                DisclosureGroup(
                    ATHLTHLocalization.choose(
                        english: "Race on a saved route",
                        norwegian: "Konkurrer på en lagret rute"
                    )
                ) {
                    routeSection
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            }

        case .target:
            targetGhostSection
        }
    }

    private var liveModeIntro: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Race with others",
                            norwegian: "Konkurrer mot andre"
                        ))
                        .font(.headline)
                        Text(ATHLTHLocalization.choose(
                            english: "Follow a public runner or invite a friend to a real duel.",
                            norwegian: "Følg en synlig løper, eller inviter en venn til en ekte duell."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(ATHLTHLocalization.choose(
                            english: "Live now", norwegian: "Live nå"
                        ), systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(ATHLTHLocalization.choose(
                            english: "See shared runs", norwegian: "Se delte økter"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .frame(minHeight: 80)
                    .background(ATHLTHTheme.accentSoft.opacity(0.75),
                                in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(ATHLTHTheme.accentDeep.opacity(0.55),
                                    lineWidth: 1)
                    }

                    NavigationLink {
                        GhostFriendRaceHubView(openInvitationOnAppear: true)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(ATHLTHLocalization.choose(
                                english: "Friends", norwegian: "Venner"
                            ), systemImage: "person.2.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                            HStack(spacing: 5) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Send invitation",
                                    norwegian: "Send invitasjon"
                                ))
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .frame(minHeight: 80)
                        .background(ATHLTHTheme.surfaceStone,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(ATHLTHTheme.border, lineWidth: 0.7)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
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
                    pendingLiveRace = liveSession
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

    // A visible shared run is a live reference, not proof that its owner
    // agreed to a synchronized duel. Friend invites handle mutual consent.
    private var sharedLiveRunningSessions: [ATHLTHLiveWorkoutSession] {
        realtime.visibleLiveSessions.filter {
            $0.activity == "running" &&
            $0.ownerID != realtime.currentUserID
        }
    }

    private var liveNowSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Live now", norwegian: "Live nå"
                        ))
                        .font(.headline)

                        Text(ATHLTHLocalization.choose(
                            english: "Shared runs · not synchronized duels",
                            norwegian: "Delte løp · ikke synkroniserte dueller"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()

                    Button {
                        Task { await realtime.refreshVisibleLiveSessions(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 44, height: 44)
                            .background(ATHLTHTheme.surfaceStone, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Refresh live runners",
                        norwegian: "Oppdater synlige løpere"
                    ))
                }

                if sharedLiveRunningSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.run.circle")
                            .font(.system(size: 38, weight: .ultraLight))
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(ATHLTHLocalization.choose(
                            english: "No shared runners right now",
                            norwegian: "Ingen synlige løpere akkurat nå"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)

                        Text(ATHLTHLocalization.choose(
                            english: "Only runners who enable live sharing are visible. You can still invite a friend.",
                            norwegian: "Bare løpere som har aktivert deling vises. Du kan fortsatt invitere en venn."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .multilineTextAlignment(.center)

                        NavigationLink {
                            GhostFriendRaceHubView(openInvitationOnAppear: true)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Invite a friend",
                                norwegian: "Inviter en venn"
                            ), systemImage: "person.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(ATHLTHTheme.surfaceStone.opacity(0.65),
                                in: RoundedRectangle(cornerRadius: 18))
                } else {
                    ForEach(Array(sharedLiveRunningSessions.prefix(8))) { liveSession in
                        let isSelected =
                            realtime.selectedLiveGhostSessionID == liveSession.id

                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(session: liveSession)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                        .frame(width: 44, height: 44)
                                        .background(ATHLTHTheme.accentSoft,
                                                    in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(liveRunnerName(liveSession))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ATHLTHTheme.primaryText)
                                        Text(liveSession.routeTitle ??
                                             liveSession.title)
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 4)

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                realtime.selectLiveGhost(
                                    isSelected ? nil : liveSession
                                )
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: isSelected
                                            ? "Live Ghost selected"
                                            : "Use as Live Ghost",
                                        norwegian: isSelected
                                            ? "Valgt som Live Ghost"
                                            : "Bruk som Live Ghost"
                                    ),
                                    systemImage: isSelected
                                        ? "checkmark.circle.fill" : "figure.run.circle"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    isSelected
                                        ? ATHLTHTheme.accentSoft
                                        : Color.white.opacity(0.8),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(13)
                        .background(ATHLTHTheme.surfaceStone.opacity(0.8),
                                    in: RoundedRectangle(cornerRadius: 17))
                    }
                }
            }
        }
    }

    private func liveRunnerName(
        _ liveSession: ATHLTHLiveWorkoutSession
    ) -> String {
        social.visibleProfiles.first {
            $0.userID == liveSession.ownerID
        }?.resolvedName ??
        social.following.first {
            $0.userID == liveSession.ownerID
        }?.resolvedName ??
        ATHLTHLocalization.choose(
            english: "ATHLTH runner", norwegian: "ATHLTH-løper"
        )
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

    private var availableTargetGhostRoutes: [TrainingRoute] {
        session.savedRoutes
            .filter { GhostTargetRouteEligibility.isUsable($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var targetGhostSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "Choose a course",
                            norwegian: "Velg en løype"
                        ))
                        .font(.headline)

                        Text(ATHLTHLocalization.choose(
                            english: advancedMode
                                ? "Choose a GPS course, then fine-tune time, pace and Ghost strategy."
                                : "Select a course. A finish-time suggestion is ready for you.",
                            norwegian: advancedMode
                                ? "Velg GPS-løype og finjuster tid, tempo og Ghost-strategi."
                                : "Velg en løype. Du får et ferdig forslag til sluttid."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                if availableTargetGhostRoutes.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No ready GPS courses",
                            norwegian: "Ingen klare GPS-løyper"
                        ),
                        systemImage: "map",
                        description: Text(ATHLTHLocalization.choose(
                            english: "A target Ghost needs a saved route with GPS geometry. Find or save a route to get started.",
                            norwegian: "Mål-Ghost trenger en lagret løype med GPS-punkter. Finn eller lagre en løype for å komme i gang."
                        ))
                    )

                    NavigationLink {
                        RouteLibraryListView(source: .database)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Find courses",
                            norwegian: "Finn løyper"
                        ), systemImage: "map.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                } else {
                    ForEach(Array(availableTargetGhostRoutes.prefix(
                        advancedMode ? 5 : 3
                    ))) { route in
                        NavigationLink {
                            TargetGhostSetupView(route: route)
                        } label: {
                            HStack(spacing: 12) {
                                RouteMapSnapshotThumbnail(
                                    route: route, height: 76
                                )
                                .frame(width: 98, height: 76)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(route.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                        .lineLimit(2)

                                    Label(
                                        String(format: "%.1f km", route.distanceKilometers),
                                        systemImage: "figure.run"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)

                                    Text(ATHLTHLocalization.choose(
                                        english: advancedMode
                                            ? "Configure Ghost" : "Choose finish time",
                                        norwegian: advancedMode
                                            ? "Tilpass Ghost" : "Velg sluttid"
                                    ))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                            }
                            .padding(9)
                            .background(
                                ATHLTHTheme.surfaceStone,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        TargetGhostRoutePickerView()
                    } label: {
                        HStack(spacing: 7) {
                            Text(ATHLTHLocalization.choose(
                                english: "See all saved courses",
                                norwegian: "Se alle lagrede løyper"
                            ))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var visibleReplayRuns: [WorkoutSummary] {
        let query = replaySearch.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let filtered = recentRuns.filter { workout in
            if replayFavoritesOnly && !replayFavoriteIDs.contains(workout.id) {
                return false
            }
            if let distanceRange = replayDistanceFilter.distanceRange,
               !(workout.distanceKilometers.map(distanceRange.contains) ?? false) {
                return false
            }
            guard !query.isEmpty else { return true }
            let searchable = [
                workout.startDate.formatted(date: .abbreviated, time: .omitted),
                workout.distanceKilometers.map {
                    String(format: "%.1f", $0)
                } ?? ""
            ].joined(separator: " ").lowercased()
            return searchable.localizedStandardContains(query)
        }

        switch replaySort {
        case .newest:
            return filtered.sorted { $0.startDate > $1.startDate }
        case .fastest:
            // Only meaningful for an explicit comparable distance range.
            guard replayDistanceFilter != .all else {
                return filtered.sorted { $0.startDate > $1.startDate }
            }
            return filtered.sorted {
                ($0.paceMinutesPerKilometer ?? .infinity) <
                ($1.paceMinutesPerKilometer ?? .infinity)
            }
        case .longest:
            return filtered.sorted {
                ($0.distanceMeters ?? 0) > ($1.distanceMeters ?? 0)
            }
        }
    }

    private var recommendedReplay: WorkoutSummary? {
        recentRuns.first
    }

    private func bestReplay(
        in distance: GhostReplayDistanceFilter
    ) -> WorkoutSummary? {
        guard let range = distance.distanceRange else { return nil }
        return recentRuns
            .filter {
                ($0.distanceKilometers.map(range.contains) ?? false) &&
                ($0.paceMinutesPerKilometer.map {
                    $0.isFinite && $0 > 0
                } ?? false)
            }
            .min {
                ($0.paceMinutesPerKilometer ?? .infinity) <
                ($1.paceMinutesPerKilometer ?? .infinity)
            }
    }

    private var similarReplayRuns: [WorkoutSummary] {
        guard let latest = recommendedReplay,
              let latestDistance = latest.distanceKilometers,
              latestDistance > 0 else {
            return []
        }
        // Similar distance is not the same thing as a route match.
        return Array(recentRuns.filter { workout in
            guard workout.id != latest.id,
                  let distance = workout.distanceKilometers else {
                return false
            }
            return abs(distance - latestDistance) <=
                max(latestDistance * 0.10, 0.25)
        }.prefix(3))
    }

    private var replayFavoritesKey: String {
        "athlth.ghost.replay.favorites.\(session.profile.userID.uuidString)"
    }

    private func loadReplayFavorites() {
        replayFavoriteIDs = Set(
            (UserDefaults.standard.stringArray(forKey: replayFavoritesKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    private func toggleReplayFavorite(_ id: UUID) {
        if replayFavoriteIDs.contains(id) {
            replayFavoriteIDs.remove(id)
        } else {
            replayFavoriteIDs.insert(id)
        }
        UserDefaults.standard.set(
            replayFavoriteIDs.map(\.uuidString).sorted(),
            forKey: replayFavoritesKey
        )
    }

    // Basic: one featured action, then up to two recent alternatives.
    // No search, sorting, favorites, or hidden advanced settings.
    private var basicReplaySection: some View {
        VStack(spacing: 14) {
            replayRecommendationCard

            if recentRuns.count > 1 {
                ATHLTHCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ATHLTHLocalization.choose(
                            english: "Other recent runs",
                            norwegian: "Andre nylige løp"
                        ))
                        .font(.headline)

                        ForEach(Array(recentRuns.dropFirst().prefix(2))) { workout in
                            replayRunCard(workout)
                        }
                    }
                }
            }
        }
    }

    private var replayRecommendationCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "Suggested Replay",
                        norwegian: "Anbefalt Replay"
                    ))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    Spacer()
                }

                if let recommendedReplay {
                    Text(ATHLTHLocalization.choose(
                        english: "Challenge your latest run",
                        norwegian: "Utfordre ditt siste løp"
                    ))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(ATHLTHLocalization.choose(
                        english: "Use your actual GPS track and finishing time as a Ghost.",
                        norwegian: "Løp mot din faktiske GPS-rute og sluttid."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    replayRunCard(recommendedReplay, featured: true)
                } else if loading || verifyingReplay {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(ATHLTHLocalization.choose(
                            english: "Checking previous GPS runs...",
                            norwegian: "Kontrollerer GPS fra tidligere løp ..."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74)
                } else {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No ready Ghost runs",
                            norwegian: "Ingen klare Ghost-økter"
                        ),
                        systemImage: "figure.run",
                        description: Text(ATHLTHLocalization.choose(
                            english: "A previous outdoor run needs a reliable GPS track. You can check more history below.",
                            norwegian: "Et tidligere utendørsløp må ha en brukbar GPS-rute. Du kan kontrollere flere økter nedenfor."
                        ))
                    )
                    .frame(minHeight: 130)
                }
            }
        }
    }

    private var pastSelfSection: some View {
        VStack(spacing: 14) {
            replayRecommendationCard

            if !similarReplayRuns.isEmpty {
                ATHLTHCard {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(ATHLTHLocalization.choose(
                            english: "Similar distance",
                            norwegian: "Lignende distanse"
                        ))
                        .font(.headline)
                        Text(ATHLTHLocalization.choose(
                            english: "Comparable length, not necessarily the same route.",
                            norwegian: "Omtrent like lange løp, men ikke nødvendigvis samme rute."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        ForEach(similarReplayRuns) { workout in
                            replayRunCard(workout)
                        }
                    }
                }
            }

            if bestReplay(in: .five) != nil ||
                bestReplay(in: .ten) != nil {
                ATHLTHCard {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 8) {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            Text(ATHLTHLocalization.choose(
                                english: "Your fastest comparable runs",
                                norwegian: "Dine raskeste sammenlignbare løp"
                            ))
                            .font(.headline)
                        }

                        if let best5 = bestReplay(in: .five) {
                            replayRunCard(best5, category: "5 km")
                        }
                        if let best10 = bestReplay(in: .ten) {
                            replayRunCard(best10, category: "10 km")
                        }
                    }
                }
            }

            ATHLTHCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Previous runs",
                                norwegian: "Tidligere løp"
                            ))
                            .font(.headline)

                            Text(ATHLTHLocalization.choose(
                                english: "GPS-verified workouts",
                                norwegian: "Økter med kontrollert GPS"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer(minLength: 6)
                        if loading || verifyingReplay {
                            ProgressView().controlSize(.small)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Search by date or distance",
                                norwegian: "Søk etter dato eller distanse"
                            ),
                            text: $replaySearch
                        )
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                    }
                    .padding(12)
                    .background(ATHLTHTheme.surfaceStone,
                                in: RoundedRectangle(cornerRadius: 13))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(GhostReplayDistanceFilter.allCases) { group in
                                Button {
                                    replayDistanceFilter = group
                                    if group == .all && replaySort == .fastest {
                                        replaySort = .newest
                                    }
                                } label: {
                                    Text(group.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(
                                            replayDistanceFilter == group
                                                ? Color.white
                                                : ATHLTHTheme.primaryText
                                        )
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 38)
                                        .background(
                                            replayDistanceFilter == group
                                                ? ATHLTHTheme.accentDeep
                                                : ATHLTHTheme.surfaceStone,
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(
                                    replayDistanceFilter == group
                                        ? .isSelected : []
                                )
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            replayFavoritesOnly.toggle()
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Favorites",
                                norwegian: "Favoritter"
                            ), systemImage: replayFavoritesOnly
                                ? "star.fill" : "star")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .padding(.horizontal, 11)
                            .frame(minHeight: 40)
                            .background(
                                replayFavoritesOnly
                                    ? ATHLTHTheme.accentSoft
                                    : ATHLTHTheme.surfaceStone,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Menu {
                            ForEach(GhostReplaySort.allCases) { option in
                                Button {
                                    replaySort = option
                                } label: {
                                    Label(option.title,
                                          systemImage: replaySort == option
                                            ? "checkmark" : "arrow.up.arrow.down")
                                }
                                .disabled(
                                    option == .fastest &&
                                    replayDistanceFilter == .all
                                )
                            }
                        } label: {
                            Label(replaySort.title,
                                  systemImage: "line.3.horizontal.decrease")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(minHeight: 40)
                        }
                    }

                    if replayDistanceFilter == .all {
                        Text(ATHLTHLocalization.choose(
                            english: "Select 5, 10 or 21 km to sort by fastest pace fairly.",
                            norwegian: "Velg 5, 10 eller 21 km for å sortere etter raskeste tempo."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    if visibleReplayRuns.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No verified runs match these filters.",
                            norwegian: "Ingen GPS-godkjente løp passer med filtrene."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 65)
                    } else {
                        LazyVStack(spacing: 9) {
                            ForEach(Array(visibleReplayRuns.prefix(30))) { workout in
                                replayRunCard(workout, showFavorite: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var replayMoreCard: some View {
        ATHLTHCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "More running history",
                        norwegian: "Mer løpehistorikk"
                    ))
                    .font(.subheadline.weight(.semibold))

                    Text(ATHLTHLocalization.format(
                        english: "%d of %d runs checked for GPS",
                        norwegian: "%d av %d løp kontrollert for GPS",
                        replayCheckedCount,
                        replayCandidates.count
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 8)

                if verifyingReplay || loading {
                    ProgressView()
                } else {
                    Button {
                        Task { await verifyNextReplayBatch() }
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Show more",
                            norwegian: "Vis flere"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accentDeep)
                }
            }
        }
    }

    private func replayRunCard(
        _ workout: WorkoutSummary,
        featured: Bool = false,
        category: String? = nil,
        showFavorite: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                pendingReplayRun = workout
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: featured
                        ? "flag.checkered" : "figure.run")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            if let category {
                                Text(category)
                                    .font(.caption.weight(.bold))
                            } else {
                                Text(workout.startDate.formatted(
                                    date: .abbreviated, time: .omitted
                                ))
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        HStack(spacing: 7) {
                            if let distance = workout.distanceKilometers {
                                Text(String(format: "%.2f km", distance))
                            }
                            Text(clock(workout.duration))
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                        if let pace = workout.paceMinutesPerKilometer {
                            Label(paceText(pace), systemImage: "speedometer")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                    }

                    Spacer(minLength: 3)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .frame(maxWidth: .infinity, minHeight: featured ? 86 : 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canStartRace || startingWorkoutID != nil)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Choose this verified run as your Ghost",
                norwegian: "Velg dette GPS-godkjente løpet som Ghost"
            ))

            if showFavorite {
                Button {
                    toggleReplayFavorite(workout.id)
                } label: {
                    Image(systemName: replayFavoriteIDs.contains(workout.id)
                        ? "star.fill" : "star")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    replayFavoriteIDs.contains(workout.id)
                        ? ATHLTHLocalization.choose(
                            english: "Remove favorite",
                            norwegian: "Fjern favoritt"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Add favorite",
                            norwegian: "Legg til favoritt"
                        )
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            featured ? ATHLTHTheme.accentSoft.opacity(0.65)
                     : ATHLTHTheme.surfaceStone,
            in: RoundedRectangle(cornerRadius: 16)
        )
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

    private var hasMoreReplayCandidates: Bool {
        replayCheckedCount < replayCandidates.count
    }

    // HealthKit run history alone does not guarantee a usable GPS track.
    // Validate progressively, without pulling heart-rate and other detail
    // data, and reuse HealthKitManager's route cache.
    private func loadRuns() async {
        // A pull-to-refresh must not reset an in-flight route scan.
        guard !verifyingReplay else { return }
        loading = true
        defer { loading = false }

        guard health.hasRequestedAuthorization else {
            recentRuns = []
            replayCandidates = []
            replayCheckedCount = 0
            return
        }

        let history = (try? await health.workoutHistory()) ?? health.workouts
        replayCandidates = history
            .filter {
                $0.activity == .running &&
                ($0.distanceMeters ?? 0) >= 250 &&
                $0.duration > 0
            }
            .sorted { $0.startDate > $1.startDate }

        recentRuns = []
        replayCheckedCount = 0
        await verifyNextReplayBatch()
    }

    private func verifyNextReplayBatch() async {
        guard !verifyingReplay, hasMoreReplayCandidates else { return }
        verifyingReplay = true
        defer { verifyingReplay = false }

        let batchEnd = min(replayCheckedCount + 12, replayCandidates.count)
        while replayCheckedCount < batchEnd {
            let workout = replayCandidates[replayCheckedCount]
            let route = await health.workoutRoute(for: workout.id)
            replayCheckedCount += 1

            // Match the actual GhostRaceStore.prepare() requirements.
            let valid = route
                .filter {
                    $0.coordinate.latitude.isFinite &&
                    $0.coordinate.longitude.isFinite &&
                    $0.horizontalAccuracy >= 0 &&
                    $0.horizontalAccuracy <= 65
                }
                .sorted { $0.timestamp < $1.timestamp }

            guard valid.count >= 2 else { continue }
            var distance = 0.0
            for index in 1..<valid.count {
                distance += valid[index].distance(from: valid[index - 1])
            }
            if distance >= 250 {
                recentRuns.append(workout)
            }
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
        HStack(spacing: 7) {
            Image(systemName: mode.icon)
                .font(.system(size: 14, weight: .semibold))
            Text(mode.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : ATHLTHTheme.primaryText)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            selected ? ATHLTHTheme.accentDeep : Color.clear,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: 13) {
                Label(
                    resultTitle(result),
                    systemImage: result.beatGhost == true
                        ? "trophy.fill" : "flag.checkered"
                )
                .font(.title3.weight(.bold))
                .foregroundStyle(
                    result.beatGhost == true
                        ? ATHLTHTheme.accentDeep
                        : ATHLTHTheme.primaryText
                )

                Text(resultSubtitle(result))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    resultStat(
                        label: ATHLTHLocalization.choose(
                            english: "Your time", norwegian: "Din tid"
                        ),
                        value: clock(result.elapsedTime),
                        icon: "stopwatch"
                    )
                    resultStat(
                        label: ATHLTHLocalization.choose(
                            english: "Ghost time", norwegian: "Ghost-tid"
                        ),
                        value: clock(result.referenceDuration),
                        icon: "figure.run"
                    )
                }

                if result.completedRoute,
                   let delta = result.signedTimeSeconds {
                    HStack(spacing: 8) {
                        Image(systemName: delta >= 0
                            ? "arrow.up.right.circle.fill"
                            : "arrow.down.right.circle.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Finish difference",
                                norwegian: "Forskjell ved målgang"
                            ))
                            .font(.caption)
                            Text(signedTimeText(delta))
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(12)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }

                if result.maximumLeadMeters > 0 ||
                    result.maximumDeficitMeters > 0 ||
                    result.leadChangeCount > 0 {
                    Divider()
                    HStack(spacing: 10) {
                        resultMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Best lead", norwegian: "Største ledelse"
                            ),
                            value: "\(Int(result.maximumLeadMeters.rounded())) m"
                        )
                        resultMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Largest gap", norwegian: "Største etterslep"
                            ),
                            value: "\(Int(result.maximumDeficitMeters.rounded())) m"
                        )
                        resultMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Lead changes", norwegian: "Lederskifter"
                            ),
                            value: "\(result.leadChangeCount)"
                        )
                    }
                }
            }
        }
    }

    private func resultStat(
        label: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(ATHLTHTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            ATHLTHTheme.surfaceStone,
            in: RoundedRectangle(cornerRadius: 14)
        )
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

    private func resultTitle(_ result: GhostRaceResult) -> String {
        guard result.completedRoute,
              let beat = result.beatGhost else {
            return ATHLTHLocalization.choose(
                english: "Ghost Race finished",
                norwegian: "Ghost Race fullført"
            )
        }
        return beat
            ? ATHLTHLocalization.choose(
                english: "You beat your ghost!",
                norwegian: "Du slo Ghosten!"
            )
            : ATHLTHLocalization.choose(
                english: "Ghost wins this time",
                norwegian: "Ghosten vant denne gangen"
            )
    }

    private func resultSubtitle(_ result: GhostRaceResult) -> String {
        guard result.completedRoute,
              let delta = result.signedTimeSeconds else {
            return ATHLTHLocalization.choose(
                english: "The route could not be matched precisely enough for a reliable finish comparison.",
                norwegian: "Ruten kunne ikke sammenlignes nøyaktig nok til å fastslå tidsforskjellen."
            )
        }
        if abs(delta) < 1 {
            return ATHLTHLocalization.choose(
                english: "You matched the Ghost's time.",
                norwegian: "Du løp på samme tid som Ghosten."
            )
        }
        return delta > 0
            ? ATHLTHLocalization.choose(
                english: "You reached the finish ahead of the Ghost.",
                norwegian: "Du kom i mål før Ghosten."
            )
            : ATHLTHLocalization.choose(
                english: "The Ghost reached the finish before you.",
                norwegian: "Ghosten kom i mål før deg."
            )
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
            .onChange(of: phoneWorkout.active?.resumedAt) { _, _ in
                // Pausing may change workout state without creating a GPS
                // point. Hide the old lead immediately on pause/resume.
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
            .onChange(of: realtime.liveGhostConnectionState) { _, _ in
                // A loss of GPS may change only the connection state.
                // Propagate that state to Watch even without a new point.
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
                guard activeID == nil,
                      !mirroring.hasActiveMirroredWorkout,
                      !watchConnection.hasActiveWatchWorkout
                else {
                    // The Watch may still own the synchronized workout.
                    // A phone recorder finishing must never tear it down.
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
            guard ATHLTHLiveGhostWorkoutBinding.accepts(
                ghostChallengeID: realtime.currentSession?.ghostChallengeID,
                comparisonRouteID: snapshot.routeComparisonID
            ) else {
                // A delayed finish from a different Watch workout cannot
                // end the current Live Ghost race or clear its comparisons.
                return
            }

            guard phoneWorkout.active == nil else {
                // Keep iPhone-owned sessions when the Watch merely
                // completed a separate mirrored workout.
                return
            }
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

        if snapshot.state == .running {
            await publishWatchLocation(
                snapshot
            )
        }
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
                            : .running,
                    routeProgressPercent:
                        workout.routeProgressPercent
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

        if let latestLocation,
           workout.resumedAt != nil {
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
        guard ATHLTHLiveGhostWorkoutBinding.accepts(
            ghostChallengeID: realtime.currentSession?.ghostChallengeID,
            comparisonRouteID: snapshot.routeComparisonID
        ) else { return }
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

        guard ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: selected.ghostChallengeID,
            selectedRouteKey: selected.routeKey,
            localComparisonRouteID: snapshot.routeComparisonID
        ) else {
            clearLiveGhostContext(sendToWatch: true)
            return
        }

        syncLiveGhostConnectionContext(
            session: selected,
            sendToWatch: true
        )

        // A resumed/stale mirrored Watch snapshot is not an updated
        // position. Keep HealthKit running and wait for a fresh sample.
        guard snapshot.state == .running,
              ATHLTHWatchLiveTelemetryFreshness.isFresh(
                  capturedAt: snapshot.capturedAt
              ) else {
            if snapshot.state == .paused {
                invalidateLiveGhostGap(sendToWatch: true)
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
            invalidateLiveGhostGap(sendToWatch: true)
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
        guard ATHLTHLiveGhostWorkoutBinding.accepts(
            ghostChallengeID: realtime.currentSession?.ghostChallengeID,
            comparisonRouteID: workout.plannedComparisonRouteID
        ) else { return }
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

        guard ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: selected.ghostChallengeID,
            selectedRouteKey: selected.routeKey,
            localComparisonRouteID: workout.plannedComparisonRouteID
        ) else {
            phoneWorkout.applyGhostComparison(
                nil, title: nil, configuration: nil
            )
            clearLiveGhostContext(sendToWatch: false)
            return
        }

        syncLiveGhostConnectionContext(
            session: selected,
            sendToWatch: false
        )

        // A paused phone workout must not fire Ghost overtakes from
        // stale distance while the rival continues running.
        guard workout.resumedAt != nil else {
            phoneWorkout.clearLiveGhostGap()
            invalidateLiveGhostGap(sendToWatch: false)
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
            phoneWorkout.clearLiveGhostGap()
            invalidateLiveGhostGap(sendToWatch: false)
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
                state: .completed,
                routeProgressPercent:
                    workout.routeProgressPercent
            )
    }

    private func makeLiveGhostContext(
        session:
            ATHLTHLiveWorkoutSession,
        comparison:
            ATHLTHLiveGhostComparison
    ) -> ATHLTHLiveGhostContext {
        let name =
            opponentName(
                session
            )

        return ATHLTHLiveGhostContext(
            title: name,
            distanceDeltaMeters:
                comparison
                    .signedDistanceMeters,
            estimatedTimeDeltaSeconds:
                comparison
                    .estimatedTimeDeltaSeconds,
            updatedAt:
                comparison.updatedAt,
            opponentName: name,
            opponentDistanceMeters:
                comparison
                    .opponentDistanceMeters,
            ownProgressPercent:
                comparison
                    .ownRouteProgressPercent,
            opponentProgressPercent:
                comparison
                    .opponentRouteProgressPercent,
            connectionText:
                liveGhostConnectionText,
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
                    .resolvedImportantLeadChangeMeters,
            statusDetailModeRawValue:
                audio
                    .resolvedStatusDetailMode
                    .rawValue,
            announceOvertakes:
                audio
                    .shouldAnnounceOvertakes,
            finalPhaseEnabled:
                audio
                    .shouldAnnounceFinalPhase,
            finalPhaseStartMeters:
                audio
                    .resolvedFinalPhaseStartMeters,
            liveConnectionAlerts:
                audio
                    .shouldAnnounceLiveConnectionChanges
        )
    }

    private var liveGhostConnectionText:
        String {
        switch realtime
            .liveGhostConnectionState {
        case .live:
            return "LIVE"
        case .delayed:
            return "DELAYED"
        case .reconnecting:
            return "RECONNECTING"
        case .waiting:
            return "WAITING"
        }
    }

    private func opponentName(
        _ session:
            ATHLTHLiveWorkoutSession
    ) -> String {
        guard let opponentID = ATHLTHLiveGhostRacingTelemetry.opponentID(
            ownerID: session.ownerID,
            otherID: session.opponentUserID,
            viewerID: realtime.currentUserID
        ) else { return session.title }
        return social.visibleProfiles
            .first { $0.userID == opponentID }?
            .resolvedName ??
        social.following
            .first { $0.userID == opponentID }?
            .resolvedName ??
        social.mutualFollows
            .first { $0.userID == opponentID }?
            .resolvedName ??
        session.title
    }

    @MainActor
    private func syncLiveGhostConnectionContext(
        session:
            ATHLTHLiveWorkoutSession,
        sendToWatch: Bool
    ) {
        let name =
            opponentName(
                session
            )
        let connection =
            liveGhostConnectionText
        let audio =
            settings
                .ghostRaceAudioConfiguration

        if !sendToWatch {
            phoneWorkout
                .applyLiveGhostConnectionState(
                    opponentName: name,
                    state: connection,
                    configuration: audio
                )
        }

        var context =
            ATHLTHLiveWorkoutContextStore
                .load()

        guard var liveGhost =
                context.liveGhost
        else {
            return
        }

        let liveAudio =
            liveGhostAudioContext
        let changed =
            liveGhost.connectionText !=
                connection ||
            liveGhost.opponentName !=
                name ||
            liveGhost.audio !=
                liveAudio

        guard changed else {
            return
        }

        liveGhost.connectionText =
            connection
        liveGhost.opponentName =
            name
        liveGhost.title =
            name
        liveGhost.audio =
            liveAudio
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

    /// An unavailable or untrusted GPS match is not a lead. Keep the
    /// live opponent and connection-state card while removing obsolete
    /// distances/time deltas, including cached Watch surface context.
    @MainActor
    private func invalidateLiveGhostGap(sendToWatch: Bool) {
        var context = ATHLTHLiveWorkoutContextStore.load()
        guard let liveGhost = context.liveGhost,
              liveGhost.distanceDeltaMeters != nil ||
                liveGhost.estimatedTimeDeltaSeconds != nil
        else { return }

        context.liveGhost = liveGhost.withoutUnverifiedGap()
        ATHLTHLiveWorkoutContextStore.save(context)
        if sendToWatch {
            watchConnection.sendLiveSurfaceContext(context)
        }
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
