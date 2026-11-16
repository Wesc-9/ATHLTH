import SwiftUI

/// Separate iPad presentation over the same stores used by iPhone.
/// The sidebar is permanent in regular-width landscape windows; the system
/// collapses columns naturally when Stage Manager provides a narrow window.
/// Fixed-width iPad sidebar; only explicit user interaction changes visibility.
enum ATHLTHStudioSidebarLayoutPolicy {
    static let fixedWidth: CGFloat = 280
    static func toggled(_ value: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility {
        value == .detailOnly ? .all : .detailOnly
    }
}

private enum ATHLTHStudioDestination: String, CaseIterable, Identifiable {
    case overview, planner, insights, history, explore, community, coach, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return ATHLTHLocalization.choose(english: "Overview", norwegian: "Oversikt")
        case .planner: return ATHLTHLocalization.choose(english: "Plan Studio", norwegian: "Plan Studio")
        case .insights: return ATHLTHLocalization.choose(english: "Insights Lab", norwegian: "Innsiktslab")
        case .history: return ATHLTHLocalization.choose(english: "Workout history", norwegian: "Treningshistorikk")
        case .explore: return ATHLTHLocalization.choose(english: "Routes & Explore", norwegian: "Ruter og utforsk")
        case .community: return ATHLTHLocalization.choose(english: "Community", norwegian: "Fellesskap")
        case .coach: return "ATHLTH Coach"
        case .settings: return ATHLTHLocalization.choose(english: "Settings", norwegian: "Innstillinger")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .planner: "calendar"
        case .insights: "chart.xyaxis.line"
        case .history: "clock.arrow.circlepath"
        case .explore: "map"
        case .community: "person.3"
        case .coach: "sparkles"
        case .settings: "gearshape"
        }
    }
}

/// Intent thresholds for the iPad message-panel grip and header.
/// The conversation area never installs these gestures: it must retain
/// exactly the same horizontal scroll, attachments and interactions as iPhone.
enum ATHLTHStudioInboxPanelGesturePolicy {
    static func shouldOpen(translation: CGSize) -> Bool {
        translation.width <= -30 &&
            abs(translation.height) <= abs(translation.width) * 0.55
    }

    static func shouldClose(translation: CGSize) -> Bool {
        translation.width >= 85 &&
            abs(translation.height) <= abs(translation.width) * 0.55
    }
}

/// Owns the unread badge so incoming messages do not invalidate the
/// entire iPad Studio navigation tree.
private struct ATHLTHStudioInboxSidebarButton: View {
    @EnvironmentObject private var messaging: MessagingStore

    let selected: Bool
    let ink: Color
    let action: () -> Void

    private var unread: Int {
        max(0, messaging.unreadCount + messaging.messageRequestCount)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 17))
                    .frame(width: 24)

                Text(ATHLTHLocalization.choose(
                    english: "Inbox",
                    norwegian: "Innboks"
                ))
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)

                Spacer(minLength: 0)

                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 23)
                        .background(
                            ATHLTHTheme.premiumGoldSoft,
                            in: Capsule()
                        )
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? ink : ink.opacity(0.78))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(
            unread > 0
                ? ATHLTHLocalization.choose(
                    english: "\(unread) unread",
                    norwegian: "\(unread) uleste"
                )
                : ATHLTHLocalization.choose(
                    english: "No unread messages",
                    norwegian: "Ingen uleste meldinger"
                )
        )
        .accessibilityIdentifier("athlth-ipad-sidebar-inbox")
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

struct ATHLTHiPadStudioRootView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMessagePanelMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var studioPlanSync: ATHLTHStudioPlanSyncStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var goalAccountSync: ATHLTHGoalAccountSyncStore
    @SceneStorage("athlth.studio.selectedDestination")
    private var savedDestination = ATHLTHStudioDestination.overview.rawValue
    @SceneStorage("athlth.studio.selectedLibraryPage")
    private var savedLibraryPage = ""
    @SceneStorage("athlth.studio.selectedSidebarPage")
    private var savedSidebarPage = ""
    @SceneStorage("athlth.studio.selectedCommunityTab")
    private var savedCommunityTab = ATHLTHCommunityMainTab.overview.rawValue
    @SceneStorage("athlth.studio.selectedHomeDayEpoch")
    private var savedHomeDayEpoch: Double = 0
    @State private var selection: ATHLTHStudioDestination = .overview
    // A repeated Home tap scrolls to the top; it must NOT destroy the
    // dashboard and restart its HealthKit, community and live child tasks.
    @State private var homeScrollRequest = 0
    @State private var communityTab: ATHLTHCommunityMainTab = .overview
    @State private var selectedWorkout: WorkoutSummary?
    @State private var inspectedWeekDate: Date?
    @State private var showingWorkoutDetail = false
    @State private var pendingWeekTrainLaunch = false
    @State private var pendingWeekStandaloneWorkout: PlannedSession?
    @State private var selectedHomeWeekDate: Date = .now
    /// Side-menu libraries live in the Studio detail column.
    @State private var libraryPage: ATHLTHStudioLibraryPage?
    /// Reset pushed detail cards when switching sidebar destinations.
    @State private var detailNavigationPath = NavigationPath()
    // Some destination-based links do not round-trip through NavigationPath.
    // Recreating the detail stack when a sidebar item is tapped guarantees
    // that a deep Settings/Widgets page cannot remain above the new destination.
    @State private var detailNavigationIdentity = UUID()
    /// The right inspector is for Messages only; Activity remains in Notifications.
    @State private var showingInspector = false
    /// Secondary Studio tools also replace the detail column, not modal sheets.
    @State private var sidebarPage: ATHLTHSideMenuDestination?
    @SceneStorage("athlth.studio.libraryExpanded") private var libraryExpanded = false
    // A user-controlled, per-window preference independent of the active page.
    @SceneStorage("athlth.studio.sidebarUserVisible") private var sidebarUserVisible = true
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var focusedPlanningDate: Date?
    @State private var trainRequest: ATHLTHTrainNavigationRequest?
    @State private var showingTrain = false
    @State private var selectedStandaloneWorkout: PlannedSession?
    @State private var showingPlanSync = false
    @State private var showingPresentation = false

    private let canvas = Color(red: 0.985, green: 0.979, blue: 0.965)
    private let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    private let gold = Color(red: 0.69, green: 0.54, blue: 0.32)

    private var messagePanelAnimation: Animation? {
        reduceMessagePanelMotion ? nil : .easeInOut(duration: 0.20)
    }

    init() {
        // Reuse the smoke-test tab argument to inspect actual Studio pages.
        let argument = ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--athlth-compatibility-tab=")
        }
        let index = argument.flatMap {
            Int($0.dropFirst("--athlth-compatibility-tab=".count))
        } ?? 0
        let destinations: [ATHLTHStudioDestination] = [
            .overview, .planner, .insights, .explore, .community
        ]
        let initial = destinations[min(max(0, index), 4)]
        let libraryArgument = ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--athlth-compatibility-library=")
        }
        let libraryPreview = libraryArgument.flatMap {
            ATHLTHStudioLibraryPage(
                rawValue: String(
                    $0.dropFirst("--athlth-compatibility-library=".count)
                )
            )
        }
        // Exercise the real Profile destination in iPad crash regression smoke.
        let sidebarArgument = ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--athlth-compatibility-sidebar=")
        }
        let sidebarPreview = sidebarArgument.flatMap {
            ATHLTHSideMenuDestination(rawValue: String(
                $0.dropFirst("--athlth-compatibility-sidebar=".count)
            ))
        }
        _selection = State(initialValue: initial)
        _libraryPage = State(initialValue: libraryPreview)
        _sidebarPage = State(initialValue: sidebarPreview)
        // Plan Studio and every other destination start with the same menu.
        _sidebarVisibility = State(initialValue: .all)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                // Suppress the system button in the left sidebar. The
                // existing single hamburger in the detail toolbar remains.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: ATHLTHStudioSidebarLayoutPolicy.fixedWidth,
                    ideal: ATHLTHStudioSidebarLayoutPolicy.fixedWidth,
                    max: ATHLTHStudioSidebarLayoutPolicy.fixedWidth
                )
        } detail: {
            NavigationStack(path: $detailNavigationPath) {
                studioDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvas.ignoresSafeArea())
                    .overlay(alignment: .topTrailing) {
                        // Keep the same panel-edge handle available whenever
                        // the inbox is collapsed, on every Studio destination.
                        if !showingInspector {
                            Button {
                                openMessageHub()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(gold)
                                    .frame(width: 26, height: 44)
                                    .background(canvas, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(gold.opacity(0.3)))
                                    // Preserve the slim visual grip with a
                                    // comfortable 44pt touch target.
                                    .frame(width: 44, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                ATHLTHLocalization.choose(
                                    english: "Open Inbox",
                                    norwegian: "Åpne innboks"
                                )
                            )
                            .accessibilityIdentifier("athlth-ipad-message-edge")
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Tap or swipe left on this handle to open Inbox",
                                norwegian: "Trykk eller sveip mot venstre på håndtaket for å åpne Innboks"
                            ))
                            .padding(.top, 14)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 15)
                                    .onEnded { value in
                                        if ATHLTHStudioInboxPanelGesturePolicy.shouldOpen(
                                            translation: value.translation
                                        ) {
                                            openMessageHub()
                                        }
                                    }
                            )
                        }
                    }
                    // Overview owns its compact title/metrics inside the
                    // content. Avoid the duplicate large "Overview" title
                    // that previously consumed substantial iPad space.
                    .navigationTitle(
                        libraryPage?.title ??
                            (sidebarPage != nil ? "" :
                                (selection == .overview ? "" : selection.label))
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    // Keep the Overview scroll edge clean: a visible bar
                    // previously rendered as an empty translucent title tile.
                    .toolbarBackground(canvas, for: .navigationBar)
                    .toolbarBackground(
                        (selection == .overview && libraryPage == nil
                            && sidebarPage == nil) || sidebarPage == .profile
                            ? .hidden : .visible,
                        for: .navigationBar
                    )
                    .toolbar(removing: .sidebarToggle)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                let next = ATHLTHStudioSidebarLayoutPolicy.toggled(sidebarVisibility)
                                sidebarUserVisible = next != .detailOnly
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    sidebarVisibility = next
                                }
                            } label: { Image(systemName: "line.3.horizontal") }
                            .accessibilityLabel(ATHLTHLocalization.choose(english: "Side menu", norwegian: "Sidemeny"))
                            .accessibilityIdentifier("athlth-ipad-sidebar-toggle")
                        }
                        // Inbox is available from the persistent edge handle
                        // and the iPad sidebar, not a duplicate toolbar icon.
                    }
            }
            .id(detailNavigationIdentity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        // A single root-level, read-only full-screen spectator handles both
        // running and strength. Do not display a second legacy floating card.
        // iPhone/iPad share the workout engine; only Studio navigation and
        // adaptive side-by-side presentation differ on iPad.
        .environment(\.athlthStudioFullscreenEditing, true)
        .tint(gold)
        .fullScreenCover(isPresented: $showingTrain) {
            ATHLTHStudioTrainWorkspaceView(navigationRequest: $trainRequest)
        }
        .sheet(isPresented: $showingPlanSync) {
            ATHLTHStudioPlanSyncPanel(sync: studioPlanSync)
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showingPresentation) {
            ATHLTHStudioPresentationView()
        }
        .sheet(item: $selectedStandaloneWorkout) { workout in
            ATHLTHStudioStandaloneWorkoutDetailView(workoutID: workout.id)
        }
        // Keep goal sync live while Studio is foregrounded, as on iPhone.
        .task(id: "\(session.profile.userID.uuidString)|\(session.signedIn)|\(String(describing: scenePhase))") {
            guard session.signedIn, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) }
                catch { return }
                guard !Task.isCancelled, session.signedIn, scenePhase == .active else { return }
                await goalAccountSync.sync(session: session, goals: goalStore)
            }
        }
        .onAppear {
            // Only restore the menu preference explicitly set in this window.
            sidebarVisibility = sidebarUserVisible ? .all : .detailOnly
            // Scene-local, not shared across windows: Stage Manager windows
            // can keep different destinations without fighting each other.
            let compatibilityLaunch = ProcessInfo.processInfo.arguments
                .contains {
                    $0.hasPrefix("--athlth-compatibility-tab=") ||
                        $0.hasPrefix("--athlth-compatibility-library=") ||
                        $0.hasPrefix("--athlth-compatibility-sidebar=")
                }
            if !compatibilityLaunch {
                if let restored = ATHLTHStudioDestination(rawValue: savedDestination) {
                    selection = restored
                }
                libraryPage = ATHLTHStudioLibraryPage(rawValue: savedLibraryPage)
                sidebarPage = ATHLTHSideMenuDestination(rawValue: savedSidebarPage)
                communityTab = ATHLTHCommunityMainTab(rawValue: savedCommunityTab)
                    ?? .overview
                // Restore a user-selected week, but discard nonsensical
                // timestamps (e.g. a corrupted or legacy scene value).
                let restoredDate = Date(timeIntervalSince1970: savedHomeDayEpoch)
                if savedHomeDayEpoch > 0,
                   abs(restoredDate.timeIntervalSinceNow) < 366 * 86_400 {
                    selectedHomeWeekDate = restoredDate
                }
            }
            studioPlanSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
            if studioPlanSync.enabled {
                Task { await studioPlanSync.sync(session: session) }
            }
        }
        .onChange(of: session.profile.userID) { _, _ in
            showingInspector = false
            studioPlanSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
            if session.signedIn {
                studioPlanSync.scheduleSync(session: session)
            }
        }
        .onChange(of: session.signedIn) { _, signedIn in
            if !signedIn { showingInspector = false }
            studioPlanSync.switchAccount(signedIn ? session.profile.userID : nil)
            goalAccountSync.switchAccount(signedIn ? session.profile.userID : nil)
            if signedIn {
                goalAccountSync.scheduleSync(session: session, goals: goalStore)
                studioPlanSync.scheduleSync(session: session)
            }
        }
        .onChange(of: goalStore.goals) { _, _ in
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.goalDocumentDidChange")
        )) { notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  session.signedIn, accountID == session.profile.userID else { return }
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.privateMeasurementsDidChange")
        )) { notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  session.signedIn, accountID == session.profile.userID else { return }
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onChange(of: session.trainingPlans) { _, _ in
            // Saving the local plan remains immediate and independent of
            // network; account sync preserves legacy opt-outs and conflict checks.
            studioPlanSync.scheduleSync(session: session)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                goalAccountSync.scheduleSync(session: session, goals: goalStore)
                if studioPlanSync.enabled {
                    Task { await studioPlanSync.sync(session: session) }
                }
            }
        }
        .onChange(of: selection) { _, destination in
            // openStudio(_:) already resets navigation and side destinations.
            // Resetting NavigationStack a second time in this observer can
            // race SwiftUI's detail-column transition and leave Home blank.
            // This observer only persists state, including the scene restore
            // path that sets selection directly.
            savedDestination = destination.rawValue
            if destination != .overview { focusedPlanningDate = nil }
        }
        .onChange(of: libraryPage) { _, page in
            savedLibraryPage = page?.rawValue ?? ""
            if page != nil { savedSidebarPage = "" }
        }
        .onChange(of: sidebarPage) { _, page in
            savedSidebarPage = page?.rawValue ?? ""
            if page != nil { savedLibraryPage = "" }
        }
        .onChange(of: communityTab) { _, tab in
            savedCommunityTab = tab.rawValue
        }
        .onChange(of: selectedHomeWeekDate) { _, date in
            savedHomeDayEpoch = date.timeIntervalSince1970
            // Keep the selected day accurate if the week changes while
            // its dedicated detail sheet is displayed.
            if inspectedWeekDate != nil && showingWorkoutDetail &&
                selectedWorkout == nil {
                inspectedWeekDate = Calendar.current.startOfDay(for: date)
            }
        }
        .onChange(of: focusedPlanningDate) { _, newDate in
            if newDate != nil {
                clearWeekInspectorIfNeeded()
                showingInspector = false
            }
            // Opening a planning day changes only the detail/inspector.
        }
        .inspector(isPresented: $showingInspector) {
            // The message view now owns its back, search and compose controls.
            // Removing the separate "Inbox panel" bar gives the messages
            // their full height and prevents duplicate navigation chrome.
            NavigationStack {
                MessageInboxDestinationView(
                    onBack: {
                        withAnimation(messagePanelAnimation) {
                            showingInspector = false
                        }
                    },
                    isInspectorPanel: true
                )
            }
            // Ensure a previous account's open thread cannot be reused.
            .id(session.profile.userID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(canvas)
            .inspectorColumnWidth(min: 340, ideal: 420, max: 510)
        }
        .sheet(isPresented: $showingWorkoutDetail, onDismiss: {
            inspectedWeekDate = nil
            selectedWorkout = nil
            // Launch a selected workout only after the detail sheet has
            // fully dismissed, avoiding competing modal presentations.
            if pendingWeekTrainLaunch {
                pendingWeekTrainLaunch = false
                showingTrain = true
            } else if let standalone = pendingWeekStandaloneWorkout {
                pendingWeekStandaloneWorkout = nil
                selectedStandaloneWorkout = standalone
            }
        }) {
            // Week days and recorded workouts remain accessible without
            // occupying the Inbox-only right panel.
            NavigationStack {
                VStack(spacing: 0) {
                    HStack {
                        if selectedWorkout != nil && inspectedWeekDate != nil {
                            Button {
                                selectedWorkout = nil
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Back to selected day",
                                        norwegian: "Tilbake til valgt dag"
                                    ),
                                    systemImage: "chevron.left"
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ink)
                        }
                        Spacer(minLength: 0)
                        Button {
                            showingWorkoutDetail = false
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Close", norwegian: "Lukk"
                                ),
                                systemImage: "xmark"
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ink)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    Divider().opacity(0.35)

                    if let selectedWorkout {
                        ATHLTHStudioWorkoutInspectionView(workout: selectedWorkout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let inspectedWeekDate {
                        ATHLTHStudioWeekDayInspectorView(
                            date: inspectedWeekDate,
                            onOpenWorkout: { openWeekWorkout($0, start: false) },
                            onStartWorkout: { openWeekWorkout($0, start: true) },
                            onSendToWatch: sendWeekWorkoutToWatch,
                            onInspectRecorded: inspectRecordedFromWeek,
                            onPlanWorkout: planFromWeekDay
                        )
                        .id(Calendar.current.startOfDay(for: inspectedWeekDate))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(canvas.ignoresSafeArea())
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func openMessageHub() {
        withAnimation(messagePanelAnimation) {
            showingInspector = true
        }
    }

    @ViewBuilder
    private var studioDetail: some View {
        if let libraryPage {
            ATHLTHiPadLibraryWorkspaceView(
                page: libraryPage,
                onSelect: openLibrary,
                onBack: { returnFromSidebarPage() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let sidebarPage {
            ATHLTHiPadSidebarPageView(
                destination: sidebarPage,
                onBack: { returnFromSidebarPage() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Plan Studio is a detail destination. The sidebar stays at
            // the exact width and visibility chosen by the user.
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The iPad sidebar follows the same information architecture as the
    /// iPhone Home menu, but opens the real iPad destinations and inspectors.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ATHLTH")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(ink)
                Text("STUDIO")
                    .font(.caption.weight(.medium))
                    .tracking(2)
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 17)

            // Keep the top area dedicated to ATHLTH navigation.
            // The signed-in athlete profile is pinned below Settings,
            // matching the iPhone side menu.
            Divider().padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Home", norwegian: "Hjem"),
                        symbol: "house",
                        selected: selection == .overview && libraryPage == nil &&
                            sidebarPage == nil
                    ) { openStudio(.overview) }
                    .accessibilityIdentifier("athlth-ipad-sidebar-home")

                    ATHLTHStudioInboxSidebarButton(
                        selected: showingInspector,
                        ink: ink,
                        action: openMessageHub
                    )

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Notifications", norwegian: "Varsler"),
                        symbol: "bell",
                        selected: sidebarPage == .notifications
                    ) { openSidebarPage(.notifications) }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Search", norwegian: "Søk"),
                        symbol: "magnifyingglass",
                        selected: sidebarPage == .search
                    ) { openSidebarPage(.search) }

                    Divider().padding(.vertical, 7).padding(.horizontal, 10)

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Plan Studio", norwegian: "Plan Studio"),
                        symbol: "calendar",
                        selected: selection == .planner && libraryPage == nil &&
                            sidebarPage == nil
                    ) { openStudio(.planner) }

                    trainingLibraryShortcut

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Train Together", norwegian: "Tren sammen"),
                        symbol: "person.2",
                        selected: sidebarPage == .trainTogether
                    ) { openSidebarPage(.trainTogether) }

                    sidebarAction(
                        "Ghost Race", symbol: "flag.checkered",
                        selected: sidebarPage == .ghostRace
                    ) {
                        openSidebarPage(.ghostRace)
                    }

                    sidebarAction(
                        "Arena", symbol: "trophy",
                        selected: sidebarPage == .arena
                    ) {
                        openSidebarPage(.arena)
                    }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber"),
                        symbol: "person.3",
                        selected: sidebarPage == .clubs
                    ) { openSidebarPage(.clubs) }
                    .contextMenu {
                        Button {
                            openStudio(.community)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Community", norwegian: "Fellesskap"
                            ), systemImage: "person.3")
                        }
                    }

                    Divider().padding(.vertical, 7).padding(.horizontal, 10)

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Progress", norwegian: "Fremgang"),
                        symbol: "chart.xyaxis.line",
                        selected: selection == .insights && libraryPage == nil &&
                            sidebarPage == nil
                    ) { openStudio(.insights) }
                    .contextMenu {
                        Button {
                            openStudio(.history)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Workout history", norwegian: "Treningshistorikk"
                            ), systemImage: "clock.arrow.circlepath")
                        }
                    }

                    sidebarAction("ATHLTH Coach", symbol: "sparkles",
                                  selected: selection == .coach &&
                                       libraryPage == nil && sidebarPage == nil) {
                        openStudio(.coach)
                    }

                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)

            Divider().padding(.horizontal, 18)

            sidebarAction(
                ATHLTHLocalization.choose(english: "Settings", norwegian: "Innstillinger"),
                symbol: "gearshape",
                selected: selection == .settings && libraryPage == nil &&
                    sidebarPage == nil
            ) { openStudio(.settings) }
                .contextMenu {
                    Button {
                        showingPlanSync = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Account sync", norwegian: "Kontosynkronisering"
                            ), systemImage: "icloud"
                        )
                    }
                    Button {
                        showingPresentation = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Presentation mode", norwegian: "Presentasjonsmodus"
                            ), systemImage: "rectangle.on.rectangle"
                        )
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Profile stays pinned to the bottom without a surrounding
            // card border or a divider that visually boxes it in.
            sidebarProfileRow
                .padding(.horizontal, 11)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .background(canvas)
    }

    private func sidebarAction(
        _ title: String,
        symbol: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? ink : ink.opacity(0.78))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sidebarProfileRow: some View {
        Button {
            openSidebarPage(.profile)
        } label: {
            HStack(spacing: 11) {
                Group {
                    if let avatarURL = session.profile.avatarURL {
                        ATHLTHStorageImage(url: avatarURL, maxPixelSize: 140) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                profileFallback
                            }
                        }
                    } else {
                        profileFallback
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.profile.displayName.isEmpty
                         ? "ATHLTH" : session.profile.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    Text(session.profile.username.isEmpty
                         ? ATHLTHLocalization.choose(english: "My profile", norwegian: "Min profil")
                         : "@\(session.profile.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gold)
                    .frame(width: 28, height: 28)
                    .background(ATHLTHStudioStyle.paper, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 74)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Use the same uninterrupted canvas as the sidebar. The full
            // footer row remains one accessible, tappable button.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Open my ATHLTH profile",
            norwegian: "Åpne ATHLTH-profilen min"
        ))
        .accessibilityAddTraits(sidebarPage == .profile ? .isSelected : [])
        .accessibilityIdentifier("athlth-ipad-profile-footer")
    }

    private var profileFallback: some View {
        Circle()
            .fill(ATHLTHStudioStyle.paper)
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(gold)
            }
    }

    private var trainingLibraryShortcut: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                Button {
                    openLibrary(.overview)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Training library", norwegian: "Treningsbibliotek"
                    ), systemImage: "books.vertical")
                        .font(.subheadline)
                        .foregroundStyle(libraryPage == .overview ? gold : ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-ipad-training-library-open")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        libraryExpanded.toggle()
                    }
                } label: {
                    Image(systemName: libraryExpanded ? "chevron.up" : "chevron.down")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Expand personal library",
                    norwegian: "Vis snarveier til mitt bibliotek"
                ))
                .accessibilityIdentifier("athlth-ipad-library-expand")
            }
            if libraryExpanded {
                libraryLink(.exercises, "Exercises", "Øvelser", symbol: "dumbbell")
                libraryLink(.routes, "Routes", "Ruter", symbol: "map")
                libraryLink(.trainingPlans, "Training plans", "Treningsplaner", symbol: "calendar")
                libraryLink(.workouts, "Workouts", "Treningsøkter", symbol: "bookmark")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 5)
        .contextMenu {
            Button {
                openStudio(.explore)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Routes & Explore", norwegian: "Ruter og utforsk"
                ), systemImage: "map")
            }
        }
    }

    private func libraryLink(
        _ section: ATHLTHPersonalLibrarySection,
        _ english: String,
        _ norwegian: String,
        symbol: String
    ) -> some View {
        Button {
            openPersonalLibrary(section)
        } label: {
            Label(ATHLTHLocalization.choose(english: english, norwegian: norwegian),
                  systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(
                    libraryPage == section.studioLibraryPage
                        ? gold : ink.opacity(0.77)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .background {
                    if libraryPage == section.studioLibraryPage {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.white.opacity(0.92))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            libraryPage == section.studioLibraryPage ? .isSelected : []
        )
        .accessibilityIdentifier(
            "athlth-ipad-sidebar-library-\(section.rawValue)"
        )
    }

    private func resetDetailNavigation(force: Bool = false) {
        // An implicit NavigationLink(destination:) can push without changing
        // the NavigationPath. Pop those routes when crossing destinations,
        // but never remount Home merely because Home is tapped twice.
        guard force || !detailNavigationPath.isEmpty else { return }
        detailNavigationPath = NavigationPath()
        detailNavigationIdentity = UUID()
    }

    private func openLibrary(_ page: ATHLTHStudioLibraryPage) {
        clearWeekInspectorIfNeeded()
        libraryExpanded = true
        focusedPlanningDate = nil
        resetDetailNavigation(force: libraryPage != page)
        sidebarPage = nil
        libraryPage = page
        // Replace the detail page only; do not force the sidebar open.
    }

    private func openPersonalLibrary(_ section: ATHLTHPersonalLibrarySection) {
        openLibrary(section.studioLibraryPage)
    }

    private func openSidebarPage(_ destination: ATHLTHSideMenuDestination) {
        clearWeekInspectorIfNeeded()
        focusedPlanningDate = nil
        resetDetailNavigation(force: sidebarPage != destination)
        libraryPage = nil
        sidebarPage = destination
        // The user controls the sidebar independently of opened pages.
    }

    private func returnFromSidebarPage() {
        resetDetailNavigation(force: true)
        libraryPage = nil
        sidebarPage = nil
        // Back navigation leaves the sidebar unchanged.
    }

    private func openStudio(_ destination: ATHLTHStudioDestination) {
        clearWeekInspectorIfNeeded()
        let changingDestination = selection != destination ||
            libraryPage != nil || sidebarPage != nil
        resetDetailNavigation(force: changingDestination)
        libraryPage = nil
        sidebarPage = nil
        if destination == .overview {
            // A tap on the already-selected Home item is still a real
            // navigation request. Reset any inline planner focus and force
            // the dashboard to become the visible detail root again.
            focusedPlanningDate = nil
            showingInspector = false
            homeScrollRequest &+= 1
        }
        selection = destination
        savedDestination = destination.rawValue
        // The sidebar width/visibility remains completely user-controlled.
    }

    private func openCommunity(_ tab: ATHLTHCommunityMainTab) {
        communityTab = tab
        openStudio(.community)
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .overview:
            ATHLTHStudioEditorialDashboardView(
                onInspect: inspect,
                onOpenPlanner: { openStudio(.planner) },
                onOpenPlanSync: { showingPlanSync = true },
                onOpenInsights: { openStudio(.insights) },
                onOpenSettings: { openStudio(.settings) },
                onOpenCommunity: { tab in
                    openCommunity(tab)
                },
                onOpenTrainTogether: {
                    openSidebarPage(.trainTogether)
                },
                onOpenNotifications: {
                    openSidebarPage(.notifications)
                },
                onOpenWorkout: { entry in
                    if let planID = entry.planID {
                        trainRequest = .workout(
                            planID: planID,
                            workoutID: entry.workout.id
                        )
                        showingTrain = true
                    } else {
                        // Open this precise standalone entry, not the
                        // generic Train landing page.
                        selectedStandaloneWorkout = entry.workout
                    }
                },
                onStartWorkout: { entry in
                    if let planID = entry.planID {
                        trainRequest = .startPlannedWorkout(
                            planID: planID, workoutID: entry.workout.id
                        )
                        showingTrain = true
                    } else {
                        selectedStandaloneWorkout = entry.workout
                    }
                },
                onSendToWatch: { entry in
                    guard let planID = entry.planID else { return }
                    trainRequest = .sendPlannedWorkoutToWatch(
                        planID: planID, workoutID: entry.workout.id
                    )
                    showingTrain = true
                },
                onStartAfter: { entry, seconds in
                    guard let planID = entry.planID else { return }
                    trainRequest = .startPlannedWorkoutAfter(
                        planID: planID, workoutID: entry.workout.id,
                        seconds: seconds
                    )
                    showingTrain = true
                },
                focusedPlanningDate: $focusedPlanningDate,
                selectedDate: $selectedHomeWeekDate,
                scrollToTopRequest: homeScrollRequest
            )
        case .planner:
            ATHLTHStudioPlannerView(
                onStartWorkout: { planID, workoutID in
                    trainRequest = .startPlannedWorkout(
                        planID: planID, workoutID: workoutID
                    )
                    showingTrain = true
                },
                onSendToWatch: { planID, workoutID in
                    trainRequest = .sendPlannedWorkoutToWatch(
                        planID: planID, workoutID: workoutID
                    )
                    showingTrain = true
                },
                onStartAfter: { planID, workoutID, seconds in
                    trainRequest = .startPlannedWorkoutAfter(
                        planID: planID, workoutID: workoutID, seconds: seconds
                    )
                    showingTrain = true
                },
                onOpenCoach: { openStudio(.coach) }
            )
        case .insights:
            ATHLTHStudioInsightsView()
        case .history:
            ATHLTHStudioHistoryView(onInspect: inspect)
        case .explore:
            ATHLTHStudioRouteWorkspaceView()
        case .community:
            ATHLTHCommunityV5View(initialTab: communityTab)
                .id(communityTab)
        case .coach:
            RecoveryCoachInboxDestinationView()
        case .settings:
            ATHLTHSettingsView()
        }
    }

    private func clearWeekInspectorIfNeeded() {
        guard inspectedWeekDate != nil || showingWorkoutDetail else { return }
        showingWorkoutDetail = false
        inspectedWeekDate = nil
        selectedWorkout = nil
    }

    private func inspectRecordedFromWeek(_ workout: WorkoutSummary) {
        // The detail sheet remains open; back returns to the selected day.
        selectedWorkout = workout
    }

    private func openWeekWorkout(
        _ item: ATHLTHStudioSchedule.Occurrence,
        start: Bool
    ) {
        if let planID = item.planID {
            trainRequest = start
                ? .startPlannedWorkout(
                    planID: planID, workoutID: item.workout.id
                )
                : .workout(
                    planID: planID, workoutID: item.workout.id
                )
            pendingWeekTrainLaunch = true
            showingWorkoutDetail = false
        } else {
            pendingWeekStandaloneWorkout = item.workout
            showingWorkoutDetail = false
        }
    }

    private func sendWeekWorkoutToWatch(
        _ item: ATHLTHStudioSchedule.Occurrence
    ) {
        guard let planID = item.planID else { return }
        trainRequest = .sendPlannedWorkoutToWatch(
            planID: planID, workoutID: item.workout.id
        )
        pendingWeekTrainLaunch = true
        showingWorkoutDetail = false
    }

    private func planFromWeekDay(_ date: Date) {
        showingWorkoutDetail = false
        focusedPlanningDate = Calendar.current.startOfDay(for: date)
    }

    private func inspect(_ workout: WorkoutSummary) {
        inspectedWeekDate = nil
        selectedWorkout = workout
        showingWorkoutDetail = true
    }
}
