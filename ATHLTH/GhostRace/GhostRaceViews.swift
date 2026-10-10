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

    @State private var recentRuns: [WorkoutSummary] = []
    @State private var loading = false
    @State private var startingWorkoutID: UUID?
    @State private var liveStartingSessionID: UUID?
    @State private var selectedMode:
        GhostRaceHubMode = .live
    @State private var replaySearch = ""
    @State private var replaySort: GhostReplaySort = .newest
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
                modeOverview
                hero
                modeContent
                if selectedMode != .target {
                    workoutDeviceCard
                }
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
        ZStack(alignment: .leading) {
            Image(selectedMode == .live ? "TrainHero" : "GoalMountain")
                .resizable()
                .scaledToFill()
                .frame(height: 194)
                .frame(maxWidth: .infinity)
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

    private var modeOverview: some View {
        HStack(spacing: 5) {
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
                selectedLiveGhostCard(selectedLiveSession)
            }
            liveNowSection

        case .past:
            pastSelfSection
            DisclosureGroup(
                ATHLTHLocalization.choose(
                    english: "Other ways to compete",
                    norwegian: "Flere konkurransemuligheter"
                )
            ) {
                routeSection
                friendSection
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))

        case .target:
            targetGhostSection
        }
    }

    private var liveModeIntro: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose your opponent",
                        norwegian: "Velg motstander"
                    ))
                    .font(.headline)
                    Spacer()
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }

                HStack(spacing: 8) {
                    liveOption(
                        title: ATHLTHLocalization.choose(
                            english: "Live runners", norwegian: "Live nå"
                        ),
                        detail: ATHLTHLocalization.choose(
                            english: "Available below", norwegian: "Se løpere under"
                        ),
                        icon: "dot.radiowaves.left.and.right",
                        selected: true
                    )
                    NavigationLink {
                        GhostFriendRaceHubView()
                    } label: {
                        liveOption(
                            title: ATHLTHLocalization.choose(
                                english: "Friends", norwegian: "Venner"
                            ),
                            detail: ATHLTHLocalization.choose(
                                english: "Send invitation", norwegian: "Inviter en venn"
                            ),
                            icon: "person.2",
                            selected: false
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation { selectedMode = .past }
                    } label: {
                        liveOption(
                            title: ATHLTHLocalization.choose(
                                english: "Your Ghost", norwegian: "Eget løp"
                            ),
                            detail: ATHLTHLocalization.choose(
                                english: "Previous run", norwegian: "Tidligere økt"
                            ),
                            icon: "clock.arrow.circlepath",
                            selected: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                Text(ATHLTHLocalization.choose(
                    english: "Only runners who share their activity appear in the list.",
                    norwegian: "Bare løpere som deler aktiviteten sin, vises i listen."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func liveOption(
        title: String,
        detail: String,
        icon: String,
        selected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(10)
        .background(
            selected ? ATHLTHTheme.accentSoft : ATHLTHTheme.surfaceStone,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? ATHLTHTheme.accentDeep : ATHLTHTheme.border,
                        lineWidth: selected ? 1.1 : 0.7)
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
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose your course", norwegian: "Velg løype"
                    ))
                    .font(.headline)
                    Spacer()
                    NavigationLink {
                        TargetGhostRoutePickerView()
                    } label: {
                        HStack(spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "See all", norwegian: "Se alle"
                            ))
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }

                if session.savedRoutes.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No saved courses",
                            norwegian: "Ingen lagrede løyper"
                        ),
                        systemImage: "map",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Save a route to create a target Ghost.",
                            norwegian: "Lagre en rute for å opprette en mål-Ghost."
                        ))
                    )
                    NavigationLink {
                        RouteLibraryListView(source: .database)
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Browse routes",
                                norwegian: "Finn løyper"
                            ),
                            systemImage: "map.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                } else {
                    ForEach(
                        Array(session.savedRoutes.sorted {
                            $0.createdAt > $1.createdAt
                        }.prefix(3))
                    ) { route in
                        NavigationLink {
                            TargetGhostSetupView(route: route)
                        } label: {
                            HStack(spacing: 12) {
                                RouteMapSnapshotThumbnail(route: route, height: 80)
                                    .frame(width: 103, height: 80)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(route.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                        .lineLimit(1)
                                    Text(
                                        String(format: "%.1f km", route.distanceKilometers)
                                    )
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    Text(ATHLTHLocalization.choose(
                                        english: "Choose finish time or pace",
                                        norwegian: "Velg sluttid eller tempo"
                                    ))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(
                                ATHLTHTheme.surfaceStone,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var visibleReplayRuns: [WorkoutSummary] {
        let query = replaySearch.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let filtered = recentRuns.filter { workout in
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

    private var pastSelfSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Previous runs",
                        norwegian: "Tidligere løp"
                    ))
                    .font(.headline)
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                    Menu {
                        ForEach(GhostReplaySort.allCases) { option in
                            Button {
                                replaySort = option
                            } label: {
                                Label(
                                    option.title,
                                    systemImage: replaySort == option
                                        ? "checkmark" : "arrow.up.arrow.down"
                                )
                            }
                        }
                    } label: {
                        Label(replaySort.title, systemImage: "line.3.horizontal.decrease")
                            .font(.caption.weight(.semibold))
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Find runs by date or distance",
                            norwegian: "Søk på dato eller distanse"
                        ),
                        text: $replaySearch
                    )
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                }
                .padding(11)
                .background(
                    ATHLTHTheme.surfaceStone,
                    in: RoundedRectangle(cornerRadius: 13)
                )

                if recentRuns.isEmpty && !loading {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No running history",
                            norwegian: "Ingen tidligere løp"
                        ),
                        systemImage: "figure.run",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Runs from Apple Health can be used once a GPS route is available.",
                            norwegian: "Løp fra Apple Helse kan brukes når GPS-rute er tilgjengelig."
                        ))
                    )
                    .frame(minHeight: 140)
                } else if visibleReplayRuns.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "No runs match your search.",
                        norwegian: "Ingen løp samsvarer med søket."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleReplayRuns.prefix(30)) { workout in
                            runRow(workout)
                            if workout.id != visibleReplayRuns.prefix(30).last?.id {
                                Divider().opacity(0.65)
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
                pendingReplayRun = workout
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
        HStack(spacing: 7) {
            Image(systemName: mode.icon)
                .font(.system(size: 14, weight: .semibold))
            Text(mode.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : ATHLTHTheme.primaryText)
        .frame(maxWidth: .infinity)
        .frame(height: 43)
        .background(
            selected ? ATHLTHTheme.accentDeep : Color.white.opacity(0.85),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? Color.clear : ATHLTHTheme.border, lineWidth: 0.7)
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

        syncLiveGhostConnectionContext(
            session: selected,
            sendToWatch: true
        )

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

        syncLiveGhostConnectionContext(
            session: selected,
            sendToWatch: false
        )

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
