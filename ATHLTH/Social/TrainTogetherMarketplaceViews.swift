import CoreLocation
import MapKit
import SwiftUI

struct TrainTogetherMarketplaceView:
    View
{
    // Allows Community's shared create hub to start the existing workout
    // planner directly, rather than maintaining a second creation form.
    let initialCreationMode: SocialWorkoutParticipationMode?

    init(initialCreationMode: SocialWorkoutParticipationMode? = nil) {
        self.initialCreationMode = initialCreationMode
    }

    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var social:
        SocialStore

    @StateObject private var marketplace =
        TrainTogetherMarketplaceStore()

    @State private var showingCreate =
        false
    @State private var didOpenInitialCreation = false
    @State private var searchText = ""
    @State private var selectedKind:
        WorkoutKind?
    @State private var timeFilter:
        TrainTogetherTimeFilter = .upcoming
    @State private var modeFilter:
        TrainTogetherModeFilter = .all
    @State private var showingMap = false
    @State private var joinRequestPost: TrainTogetherPost?

    private var plannedKinds: Set<WorkoutKind> {
        var planned = session.standalonePlannedSessions
        if let plan = session.activePlan {
            planned += plan.weeks.flatMap { $0.days }
                .flatMap { $0.sessions }
        }
        let now = Date()
        return Set(
            planned.filter {
                guard let start = $0.scheduledStart else { return false }
                return start >= now && start < now.addingTimeInterval(14 * 86400)
            }.map(\.kind)
        )
    }

    private func matchScore(_ post: TrainTogetherPost) -> Int {
        var score = 0
        if plannedKinds.contains(postKind(post)) { score += 3 }
        if social.isFollowing(post.creatorID) { score += 2 }
        if post.spotsLeft > 0 { score += 1 }
        return score
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                hero
                filterBar

                if !ownUpcomingPosts.isEmpty {
                    sectionHeader(
                        ATHLTHLocalization.choose(
                            english:
                                "Your workouts",
                            norwegian:
                                "Dine økter"
                        ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Manage requests and open spots.",
                                norwegian:
                                    "Administrer forespørsler og ledige plasser."
                            )
                    )

                    ForEach(
                        ownUpcomingPosts
                    ) { post in
                        NavigationLink {
                            TrainTogetherPostDetailView(
                                postID: post.id
                            )
                            .environmentObject(
                                marketplace
                            )
                        } label: {
                            postCard(post)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !pastJoinedPosts.isEmpty {
                    sectionHeader(
                        ATHLTHLocalization.choose(
                            english: "Previously planned together",
                            norwegian: "Tidligere fellesøkter"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Open the shared chat and add memories. Only workouts you hosted or joined.",
                            norwegian: "Åpne felles chat og del minner. Kun økter du arrangerte eller ble med på."
                        )
                    )

                    ForEach(pastJoinedPosts.prefix(5)) { post in
                        NavigationLink {
                            TrainTogetherPostDetailView(postID: post.id)
                                .environmentObject(marketplace)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: postKind(post).systemImage)
                                    .foregroundStyle(ATHLTHTheme.vitality)
                                    .frame(width: 35, height: 35)
                                    .background(
                                        ATHLTHTheme.vitalitySoft,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(post.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                    Text(
                                        post.scheduledStart.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(15)
                            .athlthTrainTogetherCard(radius: 18, subtle: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                sectionHeader(
                    ATHLTHLocalization.choose(
                        english:
                            "Find a workout",
                        norwegian:
                            "Finn en økt"
                    ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Ask to join when something fits you.",
                            norwegian:
                                "Spør om å bli med når du finner noe som passer."
                        )
                )

                if marketplace.isLoading && visiblePosts.isEmpty {
                    ProgressView(
                        ATHLTHLocalization.choose(
                            english: "Finding workouts…",
                            norwegian: "Finner økter…"
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else if marketplace.refreshErrorMessage != nil && visiblePosts.isEmpty {
                    refreshStatus(isFailure: true)
                } else if !marketplace.hasLoaded && visiblePosts.isEmpty {
                    // A view-scoped task may have been cancelled before
                    // the first successful load. Do not claim there are
                    // no workouts when nothing has been fetched yet.
                    refreshStatus(isFailure: false)
                } else if visiblePosts.isEmpty {
                    emptyState
                } else if showingMap && modeFilter != .sameWorkout {
                    TrainTogetherAreaMapView(
                        posts: visiblePosts.filter {
                            $0.resolvedParticipationMode == .physical
                        }
                    )
                    .environmentObject(marketplace)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visiblePosts) { post in
                            VStack(spacing: 6) {
                                NavigationLink {
                                    TrainTogetherPostDetailView(postID: post.id)
                                        .environmentObject(marketplace)
                                } label: {
                                    postCard(post)
                                }
                                .buttonStyle(.plain)

                                if post.spotsLeft > 0 {
                                    quickJoinAction(post)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 34)
        }
        .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
        .navigationTitle(
            "Train Together"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .toolbar {
            ToolbarItem(
                placement:
                    .topBarTrailing
            ) {
                Button {
                    showingCreate = true
                } label: {
                    Image(
                        systemName:
                            "plus"
                    )
                }
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english:
                            "Create workout",
                        norwegian:
                            "Opprett økt"
                    )
                )
            }
        }
        .searchable(
            text: $searchText,
            prompt:
                ATHLTHLocalization.choose(
                    english:
                        "Area, workout or athlete",
                    norwegian:
                        "Område, økt eller utøver"
                )
        )
        .sheet(item: $joinRequestPost) { post in
            TrainTogetherJoinRequestSheet(post: post)
                .environmentObject(marketplace)
        }
        .sheet(
            isPresented:
                $showingCreate
        ) {
            NavigationStack {
                TrainTogetherPostCreateView(
                    initialParticipationMode:
                        modeFilter == .sameWorkout
                            ? .remote
                            : .physical
                )
                .environmentObject(
                    marketplace
                )
            }
        }
        .task {
            if let initialCreationMode,
               !didOpenInitialCreation {
                didOpenInitialCreation = true
                modeFilter = initialCreationMode == .remote
                    ? .sameWorkout
                    : .physical
                showingCreate = true
            }
            async let market:
                Void = marketplace.refresh()
            async let socialRefresh:
                Void = social.refresh()
            _ = await (
                market,
                socialRefresh
            )
        }
        .refreshable {
            await marketplace.refresh()
            await social.refresh()
        }
        .alert(
            "Train Together",
            isPresented:
                Binding(
                    get: {
                        marketplace
                            .errorMessage != nil
                    },
                    set: { visible in
                        if !visible {
                            marketplace
                                .errorMessage = nil
                        }
                    }
                )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {}
        } message: {
            Text(
                marketplace
                    .errorMessage ??
                ""
            )
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TRAIN TOGETHER")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHTheme.vitality)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Find people to train with",
                        norwegian: "Finn noen å trene med"
                    )
                )
                .font(.system(size: 27, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHTrainTogetherDesign.ink)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Meet nearby or do the same workout remotely.",
                        norwegian: "Møt opp fysisk eller tren samme økt på avstand."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainTogetherCard(radius: 24)
    }

    /// Refresh problems are not creation/action errors: show an inline
    /// retry instead of a modal alert that blocks the entire marketplace.
    private func refreshStatus(isFailure: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: isFailure ? "wifi.exclamationmark" : "arrow.clockwise")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(ATHLTHTrainTogetherDesign.accent)

            Text(
                isFailure
                    ? ATHLTHLocalization.choose(
                        english: "Could not update workouts",
                        norwegian: "Kunne ikke oppdatere øktene"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Workouts have not loaded yet",
                        norwegian: "Øktene er ikke lastet inn ennå"
                    )
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTrainTogetherDesign.ink)

            Text(
                ATHLTHLocalization.choose(
                    english: "Check your connection and try again.",
                    norwegian: "Sjekk tilkoblingen og prøv igjen."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                Task { await marketplace.refresh() }
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Try again",
                        norwegian: "Prøv igjen"
                    ),
                    systemImage: "arrow.clockwise"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 42)
                .background(ATHLTHTrainTogetherDesign.accent,
                            in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(marketplace.isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .athlthTrainTogetherCard(radius: 22)
        .accessibilityElement(children: .contain)
    }

    private var filterBar: some View {
        VStack(spacing: 12) {
            // The primary tabs describe HOW people train together.
            // A short first tab keeps both longer Norwegian labels
            // readable on narrow iPhones without horizontal scrolling.
            HStack(spacing: 4) {
                ForEach(TrainTogetherModeFilter.allCases) { option in
                    Button {
                        modeFilter = option
                    } label: {
                        Text(option.title)
                            .font(
                                .system(
                                    size: 12,
                                    weight: modeFilter == option
                                        ? .semibold
                                        : .medium
                                )
                            )
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(
                                modeFilter == option
                                    ? Color.white
                                    : ATHLTHTheme.primaryText
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                modeFilter == option
                                    ? ATHLTHTrainTogetherDesign.accent
                                    : Color.clear,
                                in: RoundedRectangle(
                                    cornerRadius: 15,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(
                        width: option == .all ? 64 : nil
                    )
                    .accessibilityAddTraits(
                        modeFilter == option ? .isSelected : []
                    )
                }
            }
            .padding(4)
            .background(
                ATHLTHTrainTogetherDesign.accentSoft.opacity(0.64),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )

            // Keep sport filters independently usable in all three tabs.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        title: ATHLTHLocalization.choose(
                            english: "All sports",
                            norwegian: "Alle aktiviteter"
                        ),
                        icon: "sparkles",
                        selected: selectedKind == nil
                    ) {
                        selectedKind = nil
                    }

                    ForEach(
                        [
                            WorkoutKind.running,
                            .strength,
                            .walking,
                            .custom
                        ]
                    ) { kind in
                        filterChip(
                            title: kind.title,
                            icon: kind.systemImage,
                            selected: selectedKind == kind
                        ) {
                            selectedKind = kind
                        }
                    }
                }
            }

            if modeFilter != .sameWorkout {
                HStack {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "View",
                            norwegian: "Visning"
                        )
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: $showingMap) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "List", norwegian: "Liste"
                            ),
                            systemImage: "list.bullet"
                        ).tag(false)
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Map", norwegian: "Kart"
                            ),
                            systemImage: "map"
                        ).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }

            // Date filtering is retained as a menu rather than
            // competing with the new primary participation tabs.
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english: "When",
                        norwegian: "Når"
                    )
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "When",
                            norwegian: "Når"
                        ),
                        selection: $timeFilter
                    ) {
                        ForEach(TrainTogetherTimeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                } label: {
                    Label(
                        timeFilter.title,
                        systemImage: "calendar"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(
                        ATHLTHTrainTogetherDesign.surface,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            ATHLTHTrainTogetherDesign.outline, lineWidth: 0.8
                        )
                    }
                }
            }
        }
        .padding(14)
        .athlthTrainTogetherCard(radius: 22, subtle: true)
    }

    private func filterChip(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(
            action: action
        ) {
            Label(
                title,
                systemImage: icon
            )
            .font(
                .caption
                    .weight(.semibold)
            )
            .foregroundStyle(
                selected
                    ? Color.white
                    : ATHLTHTheme
                        .primaryText
            )
            .padding(
                .horizontal,
                12
            )
            .frame(height: 36)
            .background(
                selected
                    ? ATHLTHTrainTogetherDesign.accent
                    : ATHLTHTrainTogetherDesign.surface,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        ATHLTHTrainTogetherSectionTitle(title: title, subtitle: subtitle)
            .padding(.horizontal, 3)
    }

    private func postCard(
        _ post: TrainTogetherPost
    ) -> some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack(spacing: 12) {
                    SocialAvatar(
                        profile:
                            post.creatorCard,
                        size: 46
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            post.creatorDisplayName
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                        if let username =
                                post.creatorUsername,
                           !username.isEmpty {
                            Text(
                                "@\(username)"
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    Spacer()

                    Text(
                        post.spotsLeft == 0
                            ? ATHLTHLocalization.choose(
                                english: "FULL",
                                norwegian: "FULL"
                            )
                            : ATHLTHLocalization.format(
                                english:
                                    "%d open",
                                norwegian:
                                    "%d ledig",
                                post.spotsLeft
                            )
                    )
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        post.spotsLeft >
                            0
                            ? ATHLTHTheme
                                .vitality
                            : .secondary
                    )
                    .padding(
                        .horizontal,
                        9
                    )
                    .frame(height: 26)
                    .background(
                        (
                            post.spotsLeft >
                                0
                                ? ATHLTHTheme
                                    .vitalitySoft
                                : Color.primary
                                    .opacity(
                                        0.05
                                    )
                        ),
                        in: Capsule()
                    )
                }

                HStack(
                    alignment: .top,
                    spacing: 11
                ) {
                    Image(
                        systemName:
                            postKind(post)
                                .systemImage
                    )
                    .font(
                        .system(
                            size: 18,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .background(
                        ATHLTHTheme
                            .accentSoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 12,
                                style:
                                    .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(post.title)
                            .font(
                                .headline
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                        Text(
                            post.scheduledStart
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        .tertiary
                    )
                }

                if matchScore(post) >= 3 {
                    Label(
                        plannedKinds.contains(postKind(post))
                            ? ATHLTHLocalization.choose(
                                english: "Matches your planned sport",
                                norwegian: "Passer treningsplanen din"
                            )
                            : ATHLTHLocalization.choose(
                                english: "You follow the organizer",
                                norwegian: "Du følger arrangøren"
                            ),
                        systemImage: "sparkles"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)
                }

                HStack(spacing: 8) {
                    infoPill(
                        post.broadArea,
                        icon:
                            "mappin.and.ellipse"
                    )

                    infoPill(
                        levelTitle(
                            post.level
                        ),
                        icon:
                            "gauge.with.dots.needle.50percent"
                    )

                    if let duration =
                            post.durationMinutes {
                        infoPill(
                            "\(duration) min",
                            icon: "clock"
                        )
                    }
                }

                if let km = post.distanceKilometers,
                   km > 0 {
                    Label(
                        String(format: "%.1f km", km),
                        systemImage: "figure.run"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    infoPill(
                        post
                            .resolvedParticipationMode
                            .title,
                        icon:
                            post
                                .resolvedParticipationMode
                                .systemImage
                    )

                    infoPill(
                        post
                            .resolvedJoinPolicy
                            .title,
                        icon:
                            post
                                .resolvedJoinPolicy ==
                                .open
                                ? "door.left.hand.open"
                                : "hand.raised.fill"
                    )
                }

                if let request =
                        marketplace.request(
                            for: post.id,
                            userID:
                                session
                                    .profile
                                    .userID
                        ),
                   post.creatorID !=
                    session.profile.userID {
                    requestStatusPill(
                        request.state
                    )
                }
            }
        }
    }

    private func infoPill(
        _ title: String,
        icon: String
    ) -> some View {
        Label(
            title,
            systemImage: icon
        )
        .font(
            .system(
                size: 10,
                weight: .semibold
            )
        )
        .foregroundStyle(
            ATHLTHTheme
                .mutedText
        )
        .padding(
            .horizontal,
            9
        )
        .frame(height: 28)
        .background(
            ATHLTHTrainTogetherDesign.accentSoft.opacity(0.50),
            in: Capsule()
        )
        .lineLimit(1)
    }

    private func requestStatusPill(
        _ state:
            TrainTogetherRequestState
    ) -> some View {
        Label(
            requestStateTitle(state),
            systemImage:
                requestStateIcon(state)
        )
        .font(
            .caption2
                .weight(.semibold)
        )
        .foregroundStyle(
            state == .accepted
                ? ATHLTHTheme
                    .vitality
                : ATHLTHTheme
                    .mutedText
        )
    }

    private func quickJoinAction(_ post: TrainTogetherPost) -> some View {
        let request = marketplace.request(
            for: post.id,
            userID: session.profile.userID
        )
        return HStack(spacing: 9) {
            if let request, request.state == .pending || request.state == .accepted {
                Label(
                    request.state == .accepted
                        ? ATHLTHLocalization.choose(
                            english: "You're joining", norwegian: "Du er med"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Request sent", norwegian: "Forespørsel sendt"
                        ),
                    systemImage: request.state == .accepted
                        ? "checkmark.circle.fill" : "clock"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.vitality)
            } else {
                Button {
                    if post.resolvedJoinPolicy == .open {
                        Task {
                            guard await marketplace.joinOpen(postID: post.id) else { return }
                            await social.refresh()
                        }
                    } else {
                        joinRequestPost = post
                    }
                } label: {
                    Label(
                        post.resolvedJoinPolicy == .open
                            ? ATHLTHLocalization.choose(
                                english: "Join workout", norwegian: "Bli med"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Ask to join", norwegian: "Be om å bli med"
                            ),
                        systemImage: "person.badge.plus"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.vitality)
                .controlSize(.regular)
                .disabled(marketplace.isWorking)
            }
        }
        .padding(.horizontal, 4)
    }

    private var visiblePosts:
        [TrainTogetherPost] {
        marketplace.posts
            .filter { post in
                guard
                    post.creatorID !=
                        session
                            .profile
                            .userID,
                    post.status ==
                        .open ||
                    post.status ==
                        .full,
                    post.scheduledStart >
                        Date()
                else {
                    return false
                }

                if !modeFilter.includes(
                    post.resolvedParticipationMode
                ) {
                    return false
                }

                if let selectedKind,
                   postKind(post) !=
                    selectedKind {
                    return false
                }

                guard
                    timeFilter
                        .includes(
                            post.scheduledStart
                        )
                else {
                    return false
                }

                let query =
                    searchText
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .lowercased()

                guard !query.isEmpty
                else {
                    return true
                }

                return
                    post.title
                        .lowercased()
                        .contains(query) ||
                    post.broadArea
                        .lowercased()
                        .contains(query) ||
                    post.creatorDisplayName
                        .lowercased()
                        .contains(query)
            }
            .sorted { lhs, rhs in
                let a = matchScore(lhs)
                let b = matchScore(rhs)
                return a == b
                    ? lhs.scheduledStart < rhs.scheduledStart
                    : a > b
            }
    }

    private var ownUpcomingPosts:
        [TrainTogetherPost] {
        marketplace.posts
            .filter {
                $0.creatorID ==
                    session
                        .profile
                        .userID &&
                (
                    $0.status == .open ||
                    $0.status == .full
                ) &&
                $0.scheduledStart >
                    Date() &&
                modeFilter.includes(
                    $0.resolvedParticipationMode
                )
            }
            .sorted {
                $0.scheduledStart <
                    $1.scheduledStart
            }
    }

    private var pastJoinedPosts: [TrainTogetherPost] {
        marketplace.posts
            .filter { post in
                post.scheduledStart < Date() &&
                post.status != .cancelled &&
                (
                    post.creatorID == session.profile.userID ||
                    marketplace.request(
                        for: post.id,
                        userID: session.profile.userID
                    )?.state == .accepted
                )
            }
            .sorted { $0.scheduledStart > $1.scheduledStart }
    }

    private var emptyState:
        some View {
        ATHLTHTrainTogetherSurface {
            VStack(spacing: 12) {
                Image(
                    systemName:
                        "person.2.slash"
                )
                .font(
                    .system(
                        size: 30,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Nothing matches yet",
                        norwegian:
                            "Ingen økter passer akkurat nå"
                    )
                )
                .font(
                    .headline
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Create the first workout, or change the filters.",
                        norwegian:
                            "Opprett den første økten, eller endre filtrene."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .multilineTextAlignment(
                    .center
                )
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(
                .vertical,
                18
            )
        }
    }
}

/// Primary marketplace filter. A remote Train Together session
/// shares a workout start/progress, not a physical meeting place.
private enum TrainTogetherModeFilter: String, CaseIterable, Identifiable {
    case all
    case physical
    case sameWorkout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(
                english: "All",
                norwegian: "Alle"
            )
        case .physical:
            return ATHLTHLocalization.choose(
                english: "Train in person",
                norwegian: "Trene fysisk sammen"
            )
        case .sameWorkout:
            return ATHLTHLocalization.choose(
                english: "Train in the same workout",
                norwegian: "Trene i samme økt"
            )
        }
    }

    func includes(_ mode: SocialWorkoutParticipationMode) -> Bool {
        switch self {
        case .all:
            return true
        case .physical:
            return mode == .physical
        case .sameWorkout:
            return mode == .remote
        }
    }
}

private enum TrainTogetherTimeFilter:
    String,
    CaseIterable,
    Identifiable
{
    case upcoming
    case today
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming:
            return ATHLTHLocalization.choose(
                english: "Upcoming",
                norwegian: "Kommende"
            )
        case .today:
            return ATHLTHLocalization.choose(
                english: "Today",
                norwegian: "I dag"
            )
        case .week:
            return ATHLTHLocalization.choose(
                english: "7 days",
                norwegian: "7 dager"
            )
        }
    }

    func includes(
        _ date: Date
    ) -> Bool {
        switch self {
        case .upcoming:
            return date > Date()
        case .today:
            return Calendar.current
                .isDateInToday(date)
        case .week:
            guard let end =
                    Calendar.current
                        .date(
                            byAdding:
                                .day,
                            value: 7,
                            to: Date()
                        )
            else {
                return true
            }
            return
                date > Date() &&
                date <= end
        }
    }
}

struct TrainTogetherPostDetailView:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject private var marketplace:
        TrainTogetherMarketplaceStore
    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var social:
        SocialStore

    let postID: UUID

    @State private var showingRequest =
        false
    @State private var showingLaunch =
        false
    @State private var confirmingCancel =
        false
    @State private var showingReport =
        false
    @State private var confirmingBlock =
        false

    private var post:
        TrainTogetherPost? {
        marketplace.posts.first {
            $0.id == postID
        }
    }

    private var currentRequest:
        TrainTogetherRequest? {
        guard let post else {
            return nil
        }

        return marketplace.request(
            for: post.id,
            userID:
                session.profile.userID
        )
    }

    private var workoutInvite:
        SocialWorkoutInviteDisplay? {
        guard
            let sessionID =
                post?
                    .socialWorkoutSessionID
        else {
            return nil
        }

        return social
            .workoutInvites
            .first {
                $0.session.id ==
                    sessionID
            }
    }

    var body: some View {
        Group {
            if let post {
                ScrollView {
                    VStack(spacing: 16) {
                        ATHLTHCommunityContextRibbon(
                            kind: .trainTogether,
                            groupName: post.creatorDisplayName
                        )
                        detailHero(post)
                        workoutCard(post)

                        if post.creatorID ==
                            session.profile.userID {
                            creatorControls(post)
                        } else {
                            guestControls(post)
                        }

                        if shouldShowMeetup,
                           let meetup =
                            marketplace
                                .meetups[
                                    post.id
                                ] {
                            meetupCard(meetup)
                        }

                        if post.creatorID == session.profile.userID ||
                            currentRequest?.state == .accepted {
                            TrainTogetherCircleView(
                                post: post,
                                isHost: post.creatorID ==
                                    session.profile.userID
                            )
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english:
                            "Workout unavailable",
                        norwegian:
                            "Økten er ikke tilgjengelig"
                    ),
                    systemImage:
                        "calendar.badge.exclamationmark"
                )
            }
        }
        .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Train Together", norwegian: "Tren sammen"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .toolbar {
            if let post,
               post.creatorID !=
                session.profile.userID {
                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Menu {
                        Button {
                            showingReport = true
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Report",
                                    norwegian: "Rapporter"
                                ),
                                systemImage:
                                    "exclamationmark.bubble"
                            )
                        }

                        Button(
                            role: .destructive
                        ) {
                            confirmingBlock =
                                true
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Block athlete",
                                    norwegian: "Blokker utøver"
                                ),
                                systemImage:
                                    "hand.raised.fill"
                            )
                        }
                    } label: {
                        Image(
                            systemName:
                                "ellipsis.circle"
                        )
                    }
                }
            }
        }
        .task(id: postID) {
            await marketplace.refresh()

            if shouldShowMeetup {
                await marketplace
                    .loadMeetup(
                        postID: postID
                    )
            }

            await social.refresh()
        }
        .sheet(
            isPresented:
                $showingRequest
        ) {
            if let post {
                TrainTogetherJoinRequestSheet(
                    post: post
                )
                .environmentObject(
                    marketplace
                )
            }
        }
        .sheet(
            isPresented:
                $showingLaunch
        ) {
            if let workoutInvite {
                WorkoutInviteLaunchSheet(
                    invite:
                        workoutInvite
                )
            }
        }
        .sheet(
            isPresented:
                $showingReport
        ) {
            if let post {
                TrainTogetherReportSheet(
                    userID:
                        post.creatorID
                )
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english:
                    "Cancel this Train Together workout?",
                norwegian:
                    "Avlyse denne Train Together-økten?"
            ),
            isPresented:
                $confirmingCancel,
            titleVisibility:
                .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english:
                        "Cancel workout",
                    norwegian:
                        "Avlys økt"
                ),
                role: .destructive
            ) {
                Task {
                    _ = await marketplace
                        .cancel(
                            postID: postID
                        )
                    await social.refresh()
                }
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english:
                    "Block this athlete?",
                norwegian:
                    "Blokkere denne utøveren?"
            ),
            isPresented:
                $confirmingBlock,
            titleVisibility:
                .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Block",
                    norwegian: "Blokker"
                ),
                role: .destructive
            ) {
                if let post {
                    Task {
                        if await social
                            .block(
                                post.creatorID
                            ) {
                            await marketplace
                                .refresh()
                            dismiss()
                        }
                    }
                }
            }
        } message: {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Their open Train Together workouts will no longer appear for you.",
                    norwegian:
                        "Åpne Train Together-økter fra brukeren vil ikke lenger vises for deg."
                )
            )
        }
    }

    private func detailHero(
        _ post: TrainTogetherPost
    ) -> some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                HStack(spacing: 12) {
                    NavigationLink {
                        FriendProfileView(
                            userID:
                                post.creatorID
                        )
                    } label: {
                        SocialAvatar(
                            profile:
                                post.creatorCard,
                            size: 54
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            post.creatorDisplayName
                        )
                        .font(
                            .headline
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "is looking for someone to train with",
                                norwegian:
                                    "ønsker noen å trene med"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()
                }

                Text(post.title)
                    .font(
                        .title2
                            .weight(.bold)
                    )

                HStack(spacing: 8) {
                    detailChip(
                        post.scheduledStart
                            .formatted(
                                date:
                                    .abbreviated,
                                time:
                                    .shortened
                            ),
                        icon:
                            "calendar"
                    )

                    detailChip(
                        post.broadArea,
                        icon:
                            "mappin.and.ellipse"
                    )
                }

                HStack(spacing: 8) {
                    detailChip(
                        levelTitle(
                            post.level
                        ),
                        icon:
                            "gauge.with.dots.needle.50percent"
                    )

                    detailChip(
                        ATHLTHLocalization.format(
                            english:
                                "%d spot(s) left",
                            norwegian:
                                "%d plass(er) ledig",
                            post.spotsLeft
                        ),
                        icon:
                            "person.2"
                    )
                }

                HStack(spacing: 8) {
                    detailChip(
                        post
                            .resolvedParticipationMode
                            .title,
                        icon:
                            post
                                .resolvedParticipationMode
                                .systemImage
                    )

                    detailChip(
                        post
                            .resolvedJoinPolicy
                            .title,
                        icon:
                            post
                                .resolvedJoinPolicy ==
                                .open
                                ? "door.left.hand.open"
                                : "hand.raised.fill"
                    )
                }
            }
        }
    }

    private func workoutCard(
        _ post: TrainTogetherPost
    ) -> some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "The workout",
                        norwegian:
                            "Økten"
                    ),
                    systemImage:
                        postKind(post)
                            .systemImage
                )
                .font(
                    .headline
                )

                if let workout =
                        post.workoutPayload?
                            .workout {
                    Text(workout.title)
                        .font(
                            .title3
                                .weight(.bold)
                        )

                    HStack(spacing: 12) {
                        if let duration =
                                workout
                                    .durationMinutes {
                            Label(
                                "\(duration) min",
                                systemImage:
                                    "clock"
                            )
                        }

                        if let distance =
                                workout
                                    .targetDistanceKilometers {
                            Label(
                                String(
                                    format:
                                        "%.1f km",
                                    distance
                                ),
                                systemImage:
                                    "point.topleft.down.to.point.bottomright.curvepath"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                    if workout.kind ==
                        .strength,
                       !workout
                        .exercises
                        .isEmpty {
                        Text(
                            ATHLTHLocalization.format(
                                english:
                                    "%d exercises",
                                norwegian:
                                    "%d øvelser",
                                workout
                                    .exercises
                                    .count
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                } else {
                    Text(
                        postKind(post).title
                    )
                    .font(
                        .title3
                            .weight(.bold)
                    )
                }

                if let note =
                        post.note,
                   !note.isEmpty {
                    Divider()
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                }
            }
        }
    }

    private func creatorControls(
        _ post: TrainTogetherPost
    ) -> some View {
        VStack(spacing: 14) {
            ATHLTHTrainTogetherSurface {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    HStack {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Requests",
                                norwegian:
                                    "Forespørsler"
                            )
                        )
                        .font(
                            .headline
                        )

                        Spacer()

                        Text(
                            "\(pendingRequests.count)"
                        )
                        .font(
                            .caption
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            pendingRequests
                                .isEmpty
                                ? .secondary
                                : ATHLTHTheme
                                    .vitality
                        )
                    }

                    if pendingRequests.isEmpty {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "New join requests will appear here.",
                                norwegian:
                                    "Nye forespørsler om å bli med vises her."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    } else {
                        ForEach(
                            pendingRequests
                        ) { request in
                            requestRow(
                                request,
                                post: post
                            )
                        }
                    }
                }
            }

            if let sessionID =
                    post
                        .socialWorkoutSessionID {
                NavigationLink {
                    TrainTogetherCreatorLobbyView(
                        sessionID:
                            sessionID
                    )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Open workout lobby",
                            norwegian:
                                "Åpne øktlobby"
                        ),
                        systemImage:
                            "person.3.sequence.fill"
                    )
                    .font(.headline)
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .controlSize(.large)
                .tint(
                    ATHLTHTheme
                        .vitality
                )
            }

            Button(
                role: .destructive
            ) {
                confirmingCancel =
                    true
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Cancel listing",
                        norwegian:
                            "Avlys oppføring"
                    ),
                    systemImage:
                        "trash"
                )
                .frame(
                    maxWidth:
                        .infinity
                )
            }
            .buttonStyle(.bordered)
        }
    }

    private func guestControls(
        _ post: TrainTogetherPost
    ) -> some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                switch currentRequest?
                    .state {
                case .accepted:
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "You are joining this workout",
                            norwegian:
                                "Du skal være med på denne økten"
                        ),
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .font(
                        .headline
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "The exact meetup can now be shown. Your own workout copy, device choice and ready status stay personal.",
                            norwegian:
                                "Nøyaktig møtested kan nå vises. Din egen øktkopi, enhetsvalg og ready-status er fortsatt personlig."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                    if workoutInvite != nil {
                        Button {
                            showingLaunch =
                                true
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Open Train Together",
                                    norwegian:
                                        "Åpne Train Together"
                                ),
                                systemImage:
                                    "play.circle.fill"
                            )
                            .font(
                                .headline
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .tint(
                            ATHLTHTheme
                                .vitality
                        )
                    }

                case .pending:
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Request sent",
                            norwegian:
                                "Forespørsel sendt"
                        ),
                        systemImage:
                            "clock.fill"
                    )
                    .font(
                        .headline
                    )

                    Button(
                        ATHLTHLocalization.choose(
                            english:
                                "Withdraw request",
                            norwegian:
                                "Trekk forespørsel"
                        ),
                        role:
                            .destructive
                    ) {
                        if let request =
                                currentRequest {
                            Task {
                                _ = await marketplace
                                    .withdraw(
                                        requestID:
                                            request.id
                                    )
                            }
                        }
                    }

                case .declined,
                     .withdrawn:
                    Text(
                        post.resolvedJoinPolicy ==
                            .open
                            ? ATHLTHLocalization.choose(
                                english:
                                    "You can join again while the workout still has an open spot.",
                                norwegian:
                                    "Du kan bli med igjen så lenge økten fortsatt har en ledig plass."
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "You can send a new request if the workout is still open.",
                                norwegian:
                                    "Du kan sende en ny forespørsel hvis økten fortsatt er åpen."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                    joinControl(post)

                case .none:
                    joinControl(post)
                }
            }
        }
    }

    @ViewBuilder
    private func joinControl(
        _ post: TrainTogetherPost
    ) -> some View {
        if post.resolvedJoinPolicy ==
            .open {
            Button {
                Task {
                    _ = await marketplace
                        .joinOpen(
                            postID:
                                post.id
                        )
                    await social.refresh()
                }
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Join now",
                        norwegian:
                            "Bli med nå"
                    ),
                    systemImage:
                        "door.left.hand.open"
                )
                .font(.headline)
                .frame(
                    maxWidth:
                        .infinity
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .controlSize(.large)
            .tint(
                ATHLTHTheme
                    .vitality
            )
            .disabled(
                post.spotsLeft == 0 ||
                post.status != .open ||
                marketplace.isWorking
            )
        } else {
            askButton(post)
        }
    }

    private func askButton(
        _ post: TrainTogetherPost
    ) -> some View {
        Button {
            showingRequest = true
        } label: {
            Label(
                ATHLTHLocalization.choose(
                    english:
                        "Ask to join",
                    norwegian:
                        "Spør om å bli med"
                ),
                systemImage:
                    "hand.raised.fill"
            )
            .font(
                .headline
            )
            .frame(
                maxWidth:
                    .infinity
            )
        }
        .buttonStyle(
            .borderedProminent
        )
        .controlSize(.large)
        .tint(
            ATHLTHTheme
                .vitality
        )
        .disabled(
            post.spotsLeft == 0 ||
            post.status != .open
        )
    }

    private func requestRow(
        _ request:
            TrainTogetherRequest,
        post: TrainTogetherPost
    ) -> some View {
        HStack(spacing: 11) {
            NavigationLink {
                FriendProfileView(
                    userID:
                        request
                            .requesterID
                )
            } label: {
                SocialAvatar(
                    profile:
                        request
                            .requesterCard,
                    size: 44
                )
            }
            .buttonStyle(.plain)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    request
                        .requesterDisplayName
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                if let message =
                        request.message,
                   !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 7) {
                Button {
                    Task {
                        if await marketplace
                            .respond(
                                requestID:
                                    request.id,
                                accept:
                                    false
                            ) {
                            await social
                                .refresh()
                        }
                    }
                } label: {
                    Image(
                        systemName:
                            "xmark"
                    )
                    .frame(
                        width: 32,
                        height: 32
                    )
                }
                .buttonStyle(
                    .bordered
                )
                .tint(.secondary)

                Button {
                    Task {
                        if await marketplace
                            .respond(
                                requestID:
                                    request.id,
                                accept:
                                    true
                            ) {
                            await social
                                .refresh()
                            await marketplace
                                .loadMeetup(
                                    postID:
                                        post.id
                                )
                        }
                    }
                } label: {
                    Image(
                        systemName:
                            "checkmark"
                    )
                    .frame(
                        width: 32,
                        height: 32
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme
                        .vitality
                )
            }
        }
    }

    private func meetupCard(
        _ meetup:
            TrainTogetherMeetup
    ) -> some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Meetup",
                        norwegian:
                            "Møtested"
                    ),
                    systemImage:
                        "mappin.circle.fill"
                )
                .font(
                    .headline
                )

                if let name =
                        meetup.meetingName,
                   !name.isEmpty {
                    Text(name)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                }

                if let address =
                        meetup.meetingAddress,
                   !address.isEmpty {
                    Label(
                        address,
                        systemImage:
                            "map.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                if let details =
                        meetup.meetingDetails,
                   !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Only accepted participants can see this information.",
                        norwegian:
                            "Bare godkjente deltakere kan se denne informasjonen."
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }
        }
    }

    private func detailChip(
        _ text: String,
        icon: String
    ) -> some View {
        Label(
            text,
            systemImage: icon
        )
        .font(
            .caption
                .weight(.semibold)
        )
        .foregroundStyle(
            ATHLTHTheme
                .mutedText
        )
        .padding(
            .horizontal,
            10
        )
        .frame(height: 30)
        .background(
            Color.primary
                .opacity(0.04),
            in: Capsule()
        )
        .lineLimit(1)
    }

    private var pendingRequests:
        [TrainTogetherRequest] {
        marketplace
            .incomingRequests(
                for: postID
            )
            .filter {
                $0.state ==
                    .pending
            }
    }

    private var shouldShowMeetup:
        Bool {
        guard let post else {
            return false
        }

        return
            post.creatorID ==
                session.profile.userID ||
            currentRequest?
                .state ==
                .accepted
    }
}

private struct TrainTogetherReportSheet:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject private var social:
        SocialStore

    let userID: UUID

    @State private var reason =
        "unsafe"
    @State private var details = ""
    @State private var sending =
        false

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    ATHLTHLocalization.choose(
                        english: "Reason",
                        norwegian: "Årsak"
                    )
                ) {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Reason",
                            norwegian: "Årsak"
                        ),
                        selection: $reason
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Unsafe behaviour",
                                norwegian:
                                    "Utrygg oppførsel"
                            )
                        )
                        .tag("unsafe")

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Harassment",
                                norwegian:
                                    "Trakassering"
                            )
                        )
                        .tag("harassment")

                        Text("Spam")
                            .tag("spam")

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Other",
                                norwegian: "Annet"
                            )
                        )
                        .tag("other")
                    }

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Details (optional)",
                            norwegian:
                                "Detaljer (valgfritt)"
                        ),
                        text: $details,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Report athlete",
                    norwegian:
                        "Rapporter utøver"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Send",
                            norwegian: "Send"
                        )
                    ) {
                        sending = true

                        Task {
                            if await social.report(
                                userID,
                                reason: reason,
                                details:
                                    details
                                        .trimmingCharacters(
                                            in:
                                                .whitespacesAndNewlines
                                        )
                                        .isEmpty
                                        ? nil
                                        : details
                            ) {
                                dismiss()
                            }

                            sending = false
                        }
                    }
                    .disabled(sending)
                }
            }
        }
    }
}

private struct TrainTogetherJoinRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var marketplace: TrainTogetherMarketplaceStore

    let post: TrainTogetherPost
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ATHLTHTrainTogetherSurface {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                                .frame(width: 49, height: 49)
                                .background(
                                    ATHLTHTrainTogetherDesign.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 15)
                                )
                            VStack(alignment: .leading, spacing: 6) {
                                Text(post.title)
                                    .font(.system(size: 25, weight: .semibold, design: .serif))
                                    .foregroundStyle(ATHLTHTrainTogetherDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(post.broadArea + " · " + post.scheduledStart.formatted(
                                    date: .abbreviated, time: .shortened
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    ATHLTHTrainTogetherSurface {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Message the organizer (optional)",
                                norwegian: "Melding til arrangøren (valgfritt)"
                            ),
                            systemImage: "bubble.left"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainTogetherDesign.ink)

                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Hi! Can I join?",
                                norwegian: "Hei! Kan jeg bli med?"
                            ),
                            text: $message,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .padding(13)
                        .background(
                            ATHLTHTrainTogetherDesign.accentSoft.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }

                    Label(
                        ATHLTHLocalization.choose(
                            english: "Exact meeting details and the shared lobby are available only after the organizer approves you.",
                            norwegian: "Nøyaktig møtested og felles lobby blir først tilgjengelig når arrangøren har godkjent deg."
                        ),
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 7)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Ask to join", norwegian: "Spør om å bli med"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        if await marketplace.requestToJoin(
                            postID: post.id, message: message
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Send request", norwegian: "Send forespørsel"
                        ),
                        systemImage: "paperplane.fill"
                    )
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTrainTogetherDesign.accent)
                .disabled(marketplace.isWorking)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }
}

struct TrainTogetherPostCreateView:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var marketplace:
        TrainTogetherMarketplaceStore

    @State private var selectedSourceID:
        UUID?
    /// The same structured workout prepared by SessionEditorView.
    @State private var preparedWorkout: PlannedSession?
    @State private var workoutToEdit: PlannedSession?
    @State private var showingSharedWorkoutEditor = false
    @State private var showingPlannedWorkoutPicker = false
    @State private var title = ""
    @State private var kind:
        WorkoutKind = .running
    @State private var scheduledStart =
        Date()
            .addingTimeInterval(
                24 * 60 * 60
            )
    @State private var durationMinutes =
        60
    @State private var distanceText = ""
    @State private var level = "all"
    @State private var broadArea = ""
    @State private var note = ""
    @State private var participationMode:
        SocialWorkoutParticipationMode =
            .physical

    init(
        initialParticipationMode: SocialWorkoutParticipationMode = .physical,
        repeating post: TrainTogetherPost? = nil,
        initialWorkout: PlannedSession? = nil
    ) {
        _participationMode = State(
            initialValue: post?.resolvedParticipationMode ??
                initialParticipationMode
        )
        if let post {
            // Prefill public workout parameters, never copy a private
            // meeting location or another participant's personal data.
            _title = State(initialValue: post.title)
            _kind = State(
                initialValue: WorkoutKind(rawValue: post.workoutKind) ?? .running
            )
            _durationMinutes = State(initialValue: post.durationMinutes ?? 60)
            _distanceText = State(
                initialValue: post.distanceKilometers.map {
                    String(format: "%.1f", $0)
                } ?? ""
            )
            _level = State(initialValue: post.level)
            _maxGuests = State(initialValue: post.maxGuests)
            if post.resolvedParticipationMode == .physical {
                _broadArea = State(initialValue: post.broadArea)
            }
        } else if let initialWorkout {
            // Prefill the existing invitation composer from the unsaved
            // workout draft. Never publish it until the user taps Publish.
            _preparedWorkout = State(initialValue: initialWorkout)
            _title = State(initialValue: initialWorkout.title)
            _kind = State(initialValue: initialWorkout.kind)
            _durationMinutes = State(initialValue: initialWorkout.durationMinutes ?? 0)
            _distanceText = State(initialValue:
                initialWorkout.targetDistanceKilometers.map {
                    String(format: "%g", $0)
                } ?? ""
            )
            _plannedExercises = State(initialValue: initialWorkout.exercises)
            if let planned = initialWorkout.scheduledStart,
               planned > Date().addingTimeInterval(10 * 60) {
                _scheduledStart = State(initialValue: planned)
            }
        }
    }
    @State private var joinPolicy:
        TrainTogetherJoinPolicy =
            .request
    @State private var maxGuests = 1
    @State private var meetingName = ""
    @State private var meetingAddress = ""
    @State private var meetingLatitude:
        Double?
    @State private var meetingLongitude:
        Double?
    @State private var meetingDetails = ""
    @State private var plannedExercises:
        [PlannedExercise] = []
    @State private var showingExercisePicker =
        false
    @State private var editingExercise:
        PlannedExercise?
    @State private var showingMeetingSearch =
        false

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                introCard

                createSectionHeader(
                    ATHLTHLocalization.choose(
                        english:
                            "Use a real workout",
                        norwegian:
                            "Bruk en faktisk økt"
                    )
                )

                sourceCard

                if preparedWorkout != nil {
                    createSectionHeader(
                        ATHLTHLocalization.choose(
                            english: "Train Together options",
                            norwegian: "Train Together-valg"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Only meetup and participation differ from personal planning.",
                            norwegian: "Kun oppmøte og deltakelse kommer i tillegg til øktplanen."
                        )
                    )
                    socialWorkoutCard

                if participationMode ==
                    .physical {
                    createSectionHeader(
                        ATHLTHLocalization.choose(
                            english:
                                "Private meetup",
                            norwegian:
                                "Privat møtested"
                        ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Choose an address from Apple Maps. Exact meetup details are only shown to accepted participants.",
                                norwegian:
                                    "Velg en adresse fra Apple Maps. Nøyaktig møtested vises bare til godkjente deltakere."
                            )
                    )

                    meetupCard
                }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(
            .interactively
        )
        .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Create Train Together",
                norwegian:
                    "Opprett Train Together"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .toolbarBackground(
            .hidden,
            for: .navigationBar
        )
        .toolbar {
            ToolbarItem(
                placement:
                    .cancellationAction
            ) {
                Button(
                    ATHLTHLocalization.choose(
                        english:
                            "Cancel",
                        norwegian:
                            "Avbryt"
                    )
                ) {
                    dismiss()
                }
            }

            ToolbarItem(
                placement:
                    .confirmationAction
            ) {
                Button(
                    ATHLTHLocalization.choose(
                        english:
                            "Publish",
                        norwegian:
                            "Publiser"
                    )
                ) {
                    publish()
                }
                .fontWeight(.semibold)
                .disabled(
                    !canPublish ||
                    marketplace.isWorking
                )
            }
        }
        .sheet(isPresented: $showingSharedWorkoutEditor) {
            SessionEditorView(
                standaloneDate: scheduledStart,
                initialSourceWorkout: workoutToEdit,
                onPreparedWorkout: { workout in
                    applyPreparedWorkout(workout)
                }
            )
        }
        .sheet(isPresented: $showingPlannedWorkoutPicker) {
            ATHLTHPlannedWorkoutTypePickerView { workout, _ in
                selectedSourceID = workout.id
                workoutToEdit = workout
                showingPlannedWorkoutPicker = false
                showingSharedWorkoutEditor = true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented:
                $showingExercisePicker
        ) {
            NavigationStack {
                ExerciseLibraryView(
                    selectionTitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Add exercise",
                            norwegian:
                                "Legg til øvelse"
                        )
                ) { entry in
                    addExercise(
                        entry.exercise
                    )
                    showingExercisePicker =
                        false
                }
            }
        }
        .sheet(
            item:
                $editingExercise
        ) { exercise in
            PlannedExerciseEditorView(
                exercise: exercise,
                advancedMode: true
            ) { updated in
                updateExercise(
                    updated
                )
            }
        }
        .sheet(
            isPresented:
                $showingMeetingSearch
        ) {
            NavigationStack {
                TrainTogetherMapPlacePickerView {
                    place in
                    applyMeetingPlace(
                        place
                    )
                    showingMeetingSearch =
                        false
                }
            }
        }
    }

    private var introCard:
        some View {
        ATHLTHTrainTogetherSurface {
            HStack(
                alignment: .top,
                spacing: 14
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    Text(
                        "TRAIN TOGETHER"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .tracking(1.7)
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "One workout. Your people.",
                            norwegian:
                                "Én økt. Dine folk."
                        )
                    )
                    .font(
                        .title2
                            .weight(.bold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Set up the workout like Ghost: clear, structured and ready to share. Training details stay attached when someone joins.",
                            norwegian:
                                "Sett opp økten som i Ghost: ryddig, strukturert og klar til å dele. Treningsdetaljene følger med når noen blir med."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "person.2.wave.2.fill"
                )
                .font(
                    .system(
                        size: 25,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .vitality
                )
                .frame(
                    width: 54,
                    height: 54
                )
                .background(
                    ATHLTHTheme
                        .vitalitySoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 17,
                            style:
                                .continuous
                        )
                )
            }
        }
    }

    // Keep the source selector in a small independent view-builder.
    // A local if-let inside the original huge Train Together body triggers
    // a Swift 6/Xcode 27 type-checker assertion on the simulator.
    @ViewBuilder
    private var sourceCard: some View {
        if let workout = preparedWorkout {
            preparedWorkoutCard(workout)
        } else {
            ATHLTHTrainTogetherWorkoutSourceCard(
                context: ATHLTHLocalization.choose(
                    english: "Build your workout in the shared planner. Then choose how and where to train together.",
                    norwegian: "Bygg økten i den felles planleggeren. Velg deretter hvordan og hvor dere trener sammen."
                ),
                onCreateNew: {
                    selectedSourceID = nil
                    workoutToEdit = nil
                    showingSharedWorkoutEditor = true
                },
                onUsePlanned: {
                    showingPlannedWorkoutPicker = true
                }
            )
        }
    }

    private func preparedWorkoutCard(_ workout: PlannedSession) -> some View {
        ATHLTHTrainTogetherSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    Image(systemName: workout.kind.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 46, height: 46)
                        .background(ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "PLANNED WORKOUT",
                            norwegian: "PLANLAGT ØKT"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(workout.title)
                            .font(.headline)
                        Text(workout.kind.title)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer()
                }
                if let time = workout.scheduledStart {
                    Label(
                        time.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                }
                if let duration = workout.durationMinutes {
                    Label("\(duration) min", systemImage: "clock")
                        .font(.caption)
                }
                if !workout.exercises.isEmpty {
                    Text(ATHLTHLocalization.format(
                        english: "%d exercises",
                        norwegian: "%d øvelser",
                        workout.exercises.count
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Button {
                    workoutToEdit = workout
                    showingSharedWorkoutEditor = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Edit workout", norwegian: "Rediger økt"
                    ), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)

                Button {
                    preparedWorkout = nil
                    workoutToEdit = nil
                    selectedSourceID = nil
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose another workout",
                        norwegian: "Velg en annen økt"
                    ))
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var workoutCard:
        some View {
        ATHLTHTrainTogetherSurface {
            VStack(spacing: 0) {
                createTextFieldRow(
                    icon: "text.cursor",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Workout title",
                            norwegian:
                                "Navn på økten"
                        ),
                    text: $title
                )

                createDivider

                HStack(spacing: 12) {
                    createIcon(
                        kind.systemImage
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Activity",
                            norwegian:
                                "Aktivitet"
                        )
                    )

                    Spacer()

                    Picker(
                        "",
                        selection: $kind
                    ) {
                        Text(
                            WorkoutKind
                                .running
                                .title
                        )
                        .tag(
                            WorkoutKind
                                .running
                        )
                        Text(
                            WorkoutKind
                                .strength
                                .title
                        )
                        .tag(
                            WorkoutKind
                                .strength
                        )
                        Text(
                            WorkoutKind
                                .walking
                                .title
                        )
                        .tag(
                            WorkoutKind
                                .walking
                        )
                        Text(
                            WorkoutKind
                                .custom
                                .title
                        )
                        .tag(
                            WorkoutKind
                                .custom
                        )
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(
                        ATHLTHTheme
                            .primaryText
                    )
                }
                .padding(.vertical, 13)

                createDivider

                HStack(spacing: 12) {
                    createIcon(
                        "calendar"
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "When",
                            norwegian:
                                "Når"
                        )
                    )

                    Spacer()

                    DatePicker(
                        "",
                        selection:
                            $scheduledStart,
                        in:
                            Date()
                                .addingTimeInterval(
                                    15 * 60
                                )...,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                    .labelsHidden()
                }
                .padding(.vertical, 11)

                createDivider

                HStack(spacing: 12) {
                    createIcon(
                        "timer"
                    )

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "Duration: %d min",
                            norwegian:
                                "Varighet: %d min",
                            durationMinutes
                        )
                    )

                    Spacer()

                    Stepper(
                        "",
                        value:
                            $durationMinutes,
                        in: 10...360,
                        step: 5
                    )
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.vertical, 11)

                if kind == .running ||
                    kind == .walking {
                    createDivider

                    HStack(spacing: 12) {
                        createIcon(
                            "point.topleft.down.to.point.bottomright.curvepath"
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Distance",
                                    norwegian:
                                        "Distanse"
                                )
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Optional",
                                    norwegian:
                                        "Valgfritt"
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Spacer()

                        TextField(
                            "km",
                            text:
                                $distanceText
                        )
                        .keyboardType(
                            .decimalPad
                        )
                        .multilineTextAlignment(
                            .trailing
                        )
                        .frame(width: 88)

                        Text("km")
                            .foregroundStyle(
                                .secondary
                            )
                    }
                    .padding(.vertical, 11)
                }

                createDivider

                HStack(spacing: 12) {
                    createIcon(
                        "gauge.with.dots.needle.50percent"
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Level",
                            norwegian:
                                "Nivå"
                        )
                    )

                    Spacer()

                    Picker(
                        "",
                        selection: $level
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "All levels",
                                norwegian:
                                    "Alle nivåer"
                            )
                        )
                        .tag("all")
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Beginner",
                                norwegian:
                                    "Nybegynner"
                            )
                        )
                        .tag("beginner")
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Intermediate",
                                norwegian:
                                    "Middels"
                            )
                        )
                        .tag(
                            "intermediate"
                        )
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Advanced",
                                norwegian:
                                    "Avansert"
                            )
                        )
                        .tag("advanced")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(
                        ATHLTHTheme
                            .primaryText
                    )
                }
                .padding(.vertical, 13)

                createDivider

                VStack(
                    alignment: .leading,
                    spacing: 9
                ) {
                    HStack(spacing: 12) {
                        createIcon(
                            "text.alignleft"
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Description",
                                norwegian:
                                    "Beskrivelse"
                            )
                        )

                        Spacer()

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Optional",
                                norwegian:
                                    "Valgfritt"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "A short note about the workout",
                            norwegian:
                                "Kort om økten"
                        ),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .padding(12)
                    .background(
                        ATHLTHTheme
                            .surfaceSage,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14,
                                style:
                                    .continuous
                            )
                    )
                }
                .padding(.vertical, 13)

                createDivider

                HStack(spacing: 12) {
                    createIcon(
                        "person.2.fill"
                    )

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "Open spots: %d",
                            norwegian:
                                "Ledige plasser: %d",
                            maxGuests
                        )
                    )

                    Spacer()

                    Stepper(
                        "",
                        value:
                            $maxGuests,
                        in: 1...15
                    )
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.vertical, 11)
            }
        }
    }

    private var strengthExercisesCard:
        some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                if plannedExercises.isEmpty {
                    HStack(
                        alignment: .top,
                        spacing: 11
                    ) {
                        createIcon(
                            "dumbbell.fill"
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "No exercises added",
                                    norwegian:
                                        "Ingen øvelser lagt til"
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "That is fine for a free strength session. Add exercises only when the session should have a shared structure.",
                                    norwegian:
                                        "Det er helt fint for en fri styrkeøkt. Legg bare til øvelser når økten skal ha et felles oppsett."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                    }
                } else {
                    ForEach(
                        Array(
                            plannedExercises
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, exercise in
                        if index > 0 {
                            createDivider
                        }

                        HStack(spacing: 10) {
                            Button {
                                editingExercise =
                                    exercise
                            } label: {
                                HStack(
                                    spacing: 11
                                ) {
                                    createIcon(
                                        "dumbbell.fill"
                                    )

                                    VStack(
                                        alignment:
                                            .leading,
                                        spacing: 3
                                    ) {
                                        Text(
                                            exercise
                                                .embeddedExercise
                                                .displayName
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
                                        .lineLimit(2)

                                        Text(
                                            exerciseSummary(
                                                exercise
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                    }

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            Button(
                                role:
                                    .destructive
                            ) {
                                plannedExercises
                                    .removeAll {
                                        $0.id ==
                                            exercise.id
                                    }
                            } label: {
                                Image(
                                    systemName:
                                        "trash"
                                )
                                .font(
                                    .system(
                                        size: 14,
                                        weight:
                                            .semibold
                                    )
                                )
                                .frame(
                                    width: 34,
                                    height: 34
                                )
                                .background(
                                    Color.red
                                        .opacity(
                                            0.07
                                        ),
                                    in: Circle()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(
                            .vertical,
                            4
                        )
                    }
                }

                Button {
                    showingExercisePicker =
                        true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                plannedExercises
                                    .isEmpty
                                    ? "Add exercises"
                                    : "Add another exercise",
                            norwegian:
                                plannedExercises
                                    .isEmpty
                                    ? "Legg til øvelser"
                                    : "Legg til en øvelse"
                        ),
                        systemImage:
                            "plus.circle.fill"
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 46)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme
                        .accentDeep
                )
            }
        }
    }

    private var socialWorkoutCard:
        some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                WorkoutSocialModePicker(
                    mode:
                        $participationMode
                )

                createDivider

                HStack(spacing: 12) {
                    createIcon(
                        "person.badge.plus"
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Who can join?",
                                norwegian:
                                    "Hvem kan bli med?"
                            )
                        )

                        Text(
                            joinPolicy
                                .subtitle
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                    }

                    Spacer()

                    Picker(
                        "",
                        selection:
                            $joinPolicy
                    ) {
                        ForEach(
                            TrainTogetherJoinPolicy
                                .allCases
                        ) { policy in
                            Text(
                                policy.title
                            )
                            .tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(
                        ATHLTHTheme
                            .primaryText
                    )
                }
            }
        }
    }

    private var meetupCard:
        some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                Button {
                    showingMeetingSearch =
                        true
                } label: {
                    HStack(spacing: 12) {
                        createIcon(
                            "map.fill"
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                meetingName
                                    .isEmpty
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Choose meeting point",
                                        norwegian:
                                            "Velg møtepunkt"
                                    )
                                    : meetingName
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
                                meetingAddress
                                    .isEmpty
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Search addresses and places in Apple Maps",
                                        norwegian:
                                            "Søk etter adresse eller sted i Apple Maps"
                                    )
                                    : meetingAddress
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .lineLimit(2)
                        }

                        Spacer()

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
                .buttonStyle(.plain)

                if !meetingName.isEmpty ||
                    !meetingAddress.isEmpty {
                    Button(
                        role: .destructive
                    ) {
                        clearMeetingPlace()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Clear meeting point",
                                norwegian:
                                    "Fjern møtepunkt"
                            ),
                            systemImage:
                                "xmark.circle"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                createDivider

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Extra directions",
                            norwegian:
                                "Ekstra beskrivelse"
                        )
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Entrance, landmark or other useful detail",
                            norwegian:
                                "Inngang, landemerke eller annen nyttig info"
                        ),
                        text:
                            $meetingDetails,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .padding(12)
                    .background(
                        ATHLTHTheme
                            .surfaceSage,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14,
                                style:
                                    .continuous
                            )
                    )
                }
            }
        }
    }

    private func createSectionHeader(
        _ title: String, subtitle: String? = nil
    ) -> some View {
        ATHLTHTrainTogetherSectionTitle(title: title, subtitle: subtitle ?? "")
            .padding(.horizontal, 3)
    }

    private func createTextFieldRow(
        icon: String,
        title: String,
        text:
            Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            createIcon(icon)

            TextField(
                title,
                text: text
            )
        }
        .padding(.vertical, 13)
    }

    private func createIcon(
        _ systemImage: String
    ) -> some View {
        Image(
            systemName:
                systemImage
        )
        .font(
            .system(
                size: 14,
                weight: .semibold
            )
        )
        .foregroundStyle(
            ATHLTHTheme
                .accentDeep
        )
        .frame(
            width: 32,
            height: 32
        )
        .background(
            ATHLTHTheme
                .accentSoft,
            in:
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
        )
    }

    private var createDivider:
        some View {
        Rectangle()
            .fill(
                ATHLTHTheme
                    .divider
            )
            .frame(height: 1)
            .padding(
                .leading,
                44
            )
    }

    private var selectedWorkout:
        PlannedSession? {
        guard let selectedSourceID
        else {
            return nil
        }

        return availablePlannedSessions
            .first {
                $0.id ==
                    selectedSourceID
            }
    }

    private var availablePlannedSessions:
        [PlannedSession] {
        var workouts =
            session
                .standalonePlannedSessions

        if let plan =
                session.activePlan {
            workouts.append(
                contentsOf:
                    plan.weeks
                        .flatMap {
                            $0.days
                        }
                        .flatMap {
                            $0.sessions
                        }
            )
        }

        var seen:
            Set<UUID> = []

        return workouts
            .filter {
                seen.insert(
                    $0.id
                )
                .inserted
            }
            .sorted {
                (
                    $0.scheduledStart ??
                    .distantFuture
                ) <
                (
                    $1.scheduledStart ??
                    .distantFuture
                )
            }
    }

    private var distanceKilometers:
        Double? {
        let clean =
            distanceText
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .replacingOccurrences(
                    of: ",",
                    with: "."
                )

        guard !clean.isEmpty
        else {
            return nil
        }

        return Double(clean)
    }

    private var distanceIsValid:
        Bool {
        let clean =
            distanceText
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        return
            clean.isEmpty ||
            (
                distanceKilometers ??
                0
            ) > 0
    }

    private var canPublish:
        Bool {
        let cleanTitle =
            title
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
        let cleanArea =
            broadArea
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        return
            preparedWorkout != nil &&
            !cleanTitle.isEmpty &&
            (
                participationMode ==
                    .remote ||
                cleanArea.count >= 2
            ) &&
            scheduledStart >
                Date()
                    .addingTimeInterval(
                        10 * 60
                    ) &&
            (durationMinutes == 0 || durationMinutes >= 10) &&
            distanceIsValid
    }

    private func applyPreparedWorkout(_ workout: PlannedSession) {
        preparedWorkout = workout
        title = workout.title
        kind = normalizedKind(workout.kind)
        if let when = workout.scheduledStart {
            scheduledStart = when
        }
        durationMinutes = workout.durationMinutes ?? 0
        distanceText = workout.targetDistanceKilometers.map {
            String(format: "%g", $0)
        } ?? ""
        plannedExercises = workout.exercises
        note = workout.notes ?? ""
        if let point = workout.meetingPoint {
            meetingName = point.name
            meetingAddress = point.address
            meetingLatitude = point.latitude
            meetingLongitude = point.longitude
            broadArea = point.name
        }
    }

    private func startFromScratch() {
        selectedSourceID = nil
        title = ""
        kind = .running
        distanceText = ""
        plannedExercises = []
        note = ""
    }

    private func apply(
        _ workout:
            PlannedSession
    ) {
        selectedSourceID =
            workout.id
        title = workout.title
        kind = normalizedKind(
            workout.kind
        )

        if let scheduled =
                workout.scheduledStart,
           scheduled > Date() {
            scheduledStart =
                scheduled
        }

        durationMinutes =
            workout.durationMinutes ??
            durationMinutes

        if let distance =
                workout
                    .targetDistanceKilometers {
            distanceText =
                String(
                    format: "%g",
                    distance
                )
        } else {
            distanceText = ""
        }

        plannedExercises =
            workout.exercises
        note =
            workout.notes ??
            ""
    }

    private func addExercise(
        _ exercise: Exercise
    ) {
        let planned =
            PlannedExercise(
                id: UUID(),
                exerciseID:
                    exercise.id,
                embeddedExercise:
                    exercise.snapshot,
                sets: 3,
                reps: 8,
                targetWeightKilograms:
                    nil,
                targetRPE: nil,
                restSeconds: 90,
                notes: nil,
                targetRIR: nil,
                supersetGroupID:
                    nil,
                progression:
                    StrengthProgressionRule
                        .none
            )

        plannedExercises.append(
            planned
        )
    }

    private func updateExercise(
        _ updated:
            PlannedExercise
    ) {
        guard let index =
                plannedExercises
                    .firstIndex(
                        where: {
                            $0.id ==
                                updated.id
                        }
                    )
        else {
            return
        }

        plannedExercises[index] =
            updated
    }

    private func exerciseSummary(
        _ exercise:
            PlannedExercise
    ) -> String {
        [
            exercise
                .compactTargetSummary,
            exercise
                .compactLoadSummary
        ]
        .compactMap { $0 }
        .joined(
            separator: " · "
        )
    }

    private func applyMeetingPlace(
        _ place:
            TrainTogetherMapPlace
    ) {
        meetingName =
            place.name
        meetingAddress =
            place.address
        meetingLatitude =
            place.latitude
        meetingLongitude =
            place.longitude

        if !place.broadArea.isEmpty {
            broadArea =
                place.broadArea
        } else {
            broadArea =
                place.name
        }
    }

    private func clearMeetingPlace() {
        meetingName = ""
        meetingAddress = ""
        meetingLatitude = nil
        meetingLongitude = nil
        broadArea = ""
    }

    private func publish() {
        let postID = UUID()
        let cleanTitle =
            title.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
        let cleanArea =
            participationMode ==
                .remote
                ? ATHLTHLocalization.choose(
                    english: "Online",
                    norwegian: "På avstand"
                )
                : broadArea
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
        let resolvedDistance =
            kind == .running ||
            kind == .walking
                ? distanceKilometers
                : nil

        // Never reconstitute a simplified workout here; preserve the full
        // premium planner structure, pace, route, blocks and alerts.
        guard var workout = preparedWorkout else { return }

        workout.title = cleanTitle
        workout.kind = kind
        workout.scheduledStart =
            scheduledStart
        workout.durationMinutes =
            durationMinutes > 0 ? durationMinutes : nil
        workout.targetDistanceKilometers =
            resolvedDistance

        if kind == .strength {
            workout.exercises =
                plannedExercises
        }

        let route =
            workout.routeID.flatMap {
                routeID in
                session.savedRoutes
                    .first {
                        $0.id ==
                            routeID
                    }
            }

        let payload =
            SocialWorkoutInvitePayload(
                workout: workout,
                route: route,
                routeAlerts:
                    workout
                        .routeAlertConfiguration,
                participationMode:
                    participationMode,
                maxParticipants:
                    min(
                        max(
                            maxGuests + 1,
                            2
                        ),
                        16
                    )
            )

        let post =
            TrainTogetherPostWrite(
                id: postID,
                creatorID:
                    session
                        .profile
                        .userID,
                creatorDisplayName:
                    session
                        .profile
                        .displayName,
                creatorUsername:
                    session
                        .profile
                        .username
                        .isEmpty
                        ? nil
                        : session
                            .profile
                            .username,
                creatorAvatarURL:
                    session
                        .profile
                        .avatarURL?
                        .absoluteString,
                title: cleanTitle,
                workoutKind:
                    kind.rawValue,
                scheduledStart:
                    scheduledStart,
                durationMinutes:
                    durationMinutes > 0 ? durationMinutes : nil,
                distanceKilometers:
                    resolvedDistance,
                level: level,
                broadArea: cleanArea,
                note:
                    note
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                        ? nil
                        : String(
                            note.prefix(
                                1200
                            )
                        ),
                maxGuests:
                    maxGuests,
                acceptedGuests: 0,
                status: "open",
                participationMode:
                    participationMode
                        .rawValue,
                joinPolicy:
                    joinPolicy
                        .rawValue,
                workoutPayload:
                    payload,
                sourcePlannedSessionID:
                    selectedSourceID
            )

        let cleanMeeting =
            meetingName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
        let cleanAddress =
            meetingAddress
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
        let cleanDetails =
            meetingDetails
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        let meetup =
            participationMode ==
                .physical
                ? TrainTogetherMeetupWrite(
                    postID: postID,
                    creatorID:
                        session
                            .profile
                            .userID,
                    meetingName:
                        cleanMeeting.isEmpty
                            ? nil
                            : String(
                                cleanMeeting
                                    .prefix(160)
                            ),
                    meetingAddress:
                        cleanAddress.isEmpty
                            ? nil
                            : String(
                                cleanAddress
                                    .prefix(400)
                            ),
                    meetingLatitude:
                        meetingLatitude,
                    meetingLongitude:
                        meetingLongitude,
                    meetingDetails:
                        cleanDetails.isEmpty
                            ? nil
                            : String(
                                cleanDetails
                                    .prefix(600)
                            )
                )
                : nil

        Task {
            if await marketplace
                .publish(
                    post: post,
                    meetup: meetup
                ) {
                dismiss()
            }
        }
    }
}

struct TrainTogetherMapPlace:
    Identifiable,
    Hashable
{
    let id: String
    let name: String
    let address: String
    let broadArea: String
    let latitude: Double
    let longitude: Double
}

struct TrainTogetherMapPlacePickerView:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    let onSelect:
        (TrainTogetherMapPlace) -> Void

    @State private var query = ""
    @State private var results:
        [TrainTogetherMapPlace] = []
    @State private var isSearching =
        false
    @State private var isResolvingMapTap =
        false
    @State private var searchError:
        String?
    @State private var selectedPlace:
        TrainTogetherMapPlace?
    @State private var cameraPosition:
        MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            mapSection

            if query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .count >= 2 {
                searchResultsSection
            } else {
                pickerHint
            }
        }
        .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Meeting point",
                norwegian:
                    "Møtepunkt"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .searchable(
            text: $query,
            placement:
                .navigationBarDrawer(
                    displayMode:
                        .always
                ),
            prompt:
                ATHLTHLocalization.choose(
                    english:
                        "Address or place",
                    norwegian:
                        "Adresse eller sted"
                )
        )
        .task(id: query) {
            await searchMaps()
        }
        .safeAreaInset(edge: .bottom) {
            confirmBar
        }
    }

    private var mapSection:
        some View {
        MapReader { proxy in
            Map(
                position:
                    $cameraPosition,
                interactionModes: [
                    .pan,
                    .zoom,
                    .rotate,
                    .pitch
                ]
            ) {
                if let selectedPlace {
                    Marker(
                        selectedPlace.name,
                        coordinate:
                            CLLocationCoordinate2D(
                                latitude:
                                    selectedPlace
                                        .latitude,
                                longitude:
                                    selectedPlace
                                        .longitude
                            )
                    )
                    .tint(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }
            .mapStyle(
                .standard(
                    elevation: .realistic
                )
            )
            .frame(minHeight: 300)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Image(
                        systemName:
                            "hand.tap.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Tap anywhere on the map, or search above",
                            norwegian:
                                "Trykk hvor som helst i kartet, eller søk over"
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(
                    .ultraThinMaterial,
                    in: Capsule()
                )
                .padding(12)
            }
            .overlay {
                if isResolvingMapTap {
                    ProgressView()
                        .padding(14)
                        .background(
                            .ultraThinMaterial,
                            in: Circle()
                        )
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate =
                            proxy.convert(
                                value.location,
                                from: .local
                            )
                        else {
                            return
                        }

                        Task {
                            await chooseCoordinate(
                                coordinate
                            )
                        }
                    }
            )
        }
    }

    @ViewBuilder
    private var searchResultsSection:
        some View {
        if isSearching &&
            results.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(height: 100)
        } else if let searchError,
                  results.isEmpty {
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english:
                        "Could not search Maps",
                    norwegian:
                        "Kunne ikke søke i Maps"
                ),
                systemImage:
                    "exclamationmark.triangle",
                description:
                    Text(searchError)
            )
            .frame(maxHeight: 180)
        } else if results.isEmpty {
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english:
                        "No places found",
                    norwegian:
                        "Ingen steder funnet"
                ),
                systemImage:
                    "magnifyingglass"
            )
            .frame(maxHeight: 160)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results) {
                        place in
                        Button {
                            chooseSearchResult(
                                place
                            )
                        } label: {
                            HStack(
                                spacing: 12
                            ) {
                                Image(
                                    systemName:
                                        selectedPlace?.id ==
                                        place.id
                                            ? "mappin.circle.fill"
                                            : "mappin.and.ellipse"
                                )
                                .font(
                                    .system(
                                        size: 17,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .vitality
                                )
                                .frame(
                                    width: 38,
                                    height: 38
                                )
                                .background(
                                    ATHLTHTheme
                                        .vitalitySoft,
                                    in:
                                        RoundedRectangle(
                                            cornerRadius:
                                                12,
                                            style:
                                                .continuous
                                        )
                                )

                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 3
                                ) {
                                    Text(
                                        place.name
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
                                        place.address
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                    .lineLimit(2)
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(.caption2.bold())
                                .foregroundStyle(
                                    .tertiary
                                )
                            }
                            .padding(14)
                            .athlthTrainTogetherCard(radius: 17, subtle: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 250)
        }
    }

    private var pickerHint:
        some View {
        VStack(spacing: 7) {
            Image(
                systemName:
                    "magnifyingglass.circle.fill"
            )
            .font(.system(size: 24))
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Search for an address, gym or place",
                    norwegian:
                        "Søk etter adresse, treningssenter eller sted"
                )
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "You can also zoom in and tap the exact point where you want to meet.",
                    norwegian:
                        "Du kan også zoome inn og trykke på det nøyaktige punktet der dere skal møtes."
                )
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .frame(height: 118)
    }

    private var confirmBar:
        some View {
        VStack(spacing: 8) {
            if let selectedPlace {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "mappin.circle.fill"
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 1
                    ) {
                        Text(
                            selectedPlace.name
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                        Text(
                            selectedPlace.address
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(1)
                    }

                    Spacer()
                }
            }

            Button {
                guard let selectedPlace
                else {
                    return
                }

                onSelect(selectedPlace)
                dismiss()
            } label: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Use this meeting point",
                        norwegian:
                            "Bruk dette møtepunktet"
                    )
                )
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    ATHLTHTheme
                        .accentDeep,
                    in:
                        RoundedRectangle(
                            cornerRadius: 15,
                            style:
                                .continuous
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedPlace == nil)
            .opacity(
                selectedPlace == nil
                    ? 0.40
                    : 1
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .background(
            .ultraThinMaterial
        )
    }

    private func chooseSearchResult(
        _ place:
            TrainTogetherMapPlace
    ) {
        selectedPlace = place
        cameraPosition =
            .region(
                MKCoordinateRegion(
                    center:
                        CLLocationCoordinate2D(
                            latitude:
                                place.latitude,
                            longitude:
                                place.longitude
                        ),
                    span:
                        MKCoordinateSpan(
                            latitudeDelta:
                                0.008,
                            longitudeDelta:
                                0.008
                        )
                )
            )
    }

    @MainActor
    private func chooseCoordinate(
        _ coordinate:
            CLLocationCoordinate2D
    ) async {
        isResolvingMapTap = true
        searchError = nil

        let location =
            CLLocation(
                latitude:
                    coordinate.latitude,
                longitude:
                    coordinate.longitude
            )

        do {
            let placemarks =
                try await CLGeocoder()
                    .reverseGeocodeLocation(
                        location
                    )
            let placemark =
                placemarks.first
            let place =
                mapPlace(
                    coordinate:
                        coordinate,
                    placemark:
                        placemark
                )

            selectedPlace = place
            cameraPosition =
                .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span:
                            MKCoordinateSpan(
                                latitudeDelta:
                                    0.006,
                                longitudeDelta:
                                    0.006
                            )
                    )
                )
        } catch {
            selectedPlace =
                TrainTogetherMapPlace(
                    id:
                        "\(coordinate.latitude)|\(coordinate.longitude)",
                    name:
                        ATHLTHLocalization.choose(
                            english:
                                "Selected meeting point",
                            norwegian:
                                "Valgt møtepunkt"
                        ),
                    address:
                        String(
                            format:
                                "%.5f, %.5f",
                            coordinate.latitude,
                            coordinate.longitude
                        ),
                    broadArea: "",
                    latitude:
                        coordinate.latitude,
                    longitude:
                        coordinate.longitude
                )
        }

        isResolvingMapTap = false
    }

    @MainActor
    private func searchMaps() async {
        let clean =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard clean.count >= 2
        else {
            results = []
            isSearching = false
            searchError = nil
            return
        }

        do {
            try await Task.sleep(
                for:
                    .milliseconds(280)
            )
        } catch {
            return
        }

        guard !Task.isCancelled
        else {
            return
        }

        isSearching = true
        searchError = nil

        let request =
            MKLocalSearch.Request()
        request.naturalLanguageQuery =
            clean
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]

        do {
            let response =
                try await MKLocalSearch(
                    request: request
                )
                .start()

            guard !Task.isCancelled
            else {
                return
            }

            results =
                response.mapItems
                    .prefix(20)
                    .map(
                        mapPlace
                    )
            isSearching = false
        } catch {
            guard !Task.isCancelled
            else {
                return
            }

            results = []
            isSearching = false
            searchError =
                error.localizedDescription
        }
    }

    private func mapPlace(
        _ item: MKMapItem
    ) -> TrainTogetherMapPlace {
        let placemark =
            item.placemark

        return mapPlace(
            coordinate:
                placemark.coordinate,
            placemark:
                placemark,
            fallbackName:
                item.name
        )
    }

    private func mapPlace(
        coordinate:
            CLLocationCoordinate2D,
        placemark:
            CLPlacemark?,
        fallbackName:
            String? = nil
    ) -> TrainTogetherMapPlace {
        let street =
            [
                placemark?
                    .subThoroughfare,
                placemark?
                    .thoroughfare
            ]
            .compactMap { $0 }
            .filter {
                !$0.isEmpty
            }
            .joined(separator: " ")
        let city =
            [
                placemark?.postalCode,
                placemark?.locality
            ]
            .compactMap { $0 }
            .filter {
                !$0.isEmpty
            }
            .joined(separator: " ")
        let address =
            [
                street,
                city,
                placemark?
                    .administrativeArea,
                placemark?.country
            ]
            .compactMap { $0 }
            .filter {
                !$0.isEmpty
            }
            .joined(separator: ", ")
        let fallbackAddress =
            String(
                format:
                    "%.5f, %.5f",
                coordinate.latitude,
                coordinate.longitude
            )
        let resolvedAddress =
            address.isEmpty
                ? fallbackAddress
                : address
        let name =
            fallbackName ??
            placemark?.name ??
            (
                street.isEmpty
                    ? ATHLTHLocalization.choose(
                        english:
                            "Selected meeting point",
                        norwegian:
                            "Valgt møtepunkt"
                    )
                    : street
            )
        let broadArea =
            placemark?.locality ??
            placemark?.subAdministrativeArea ??
            placemark?.administrativeArea ??
            ""

        return TrainTogetherMapPlace(
            id:
                "\(coordinate.latitude)|\(coordinate.longitude)|\(name)",
            name: name,
            address:
                resolvedAddress,
            broadArea:
                broadArea,
            latitude:
                coordinate.latitude,
            longitude:
                coordinate.longitude
        )
    }
}

private func postKind(
    _ post: TrainTogetherPost
) -> WorkoutKind {
    switch post.workoutKind {
    case WorkoutKind.running.rawValue:
        return .running
    case WorkoutKind.walking.rawValue:
        return .walking
    case WorkoutKind.strength.rawValue:
        return .strength
    default:
        return .custom
    }
}

private func normalizedKind(
    _ kind: WorkoutKind
) -> WorkoutKind {
    switch kind {
    case .running:
        return .running
    case .walking:
        return .walking
    case .strength:
        return .strength
    case .mobility,
         .recovery,
         .custom:
        return .custom
    }
}

private func levelTitle(
    _ raw: String
) -> String {
    switch raw {
    case "beginner":
        return ATHLTHLocalization.choose(
            english: "Beginner",
            norwegian: "Nybegynner"
        )
    case "intermediate":
        return ATHLTHLocalization.choose(
            english: "Intermediate",
            norwegian: "Middels"
        )
    case "advanced":
        return ATHLTHLocalization.choose(
            english: "Advanced",
            norwegian: "Avansert"
        )
    default:
        return ATHLTHLocalization.choose(
            english: "All levels",
            norwegian: "Alle nivåer"
        )
    }
}

private func requestStateTitle(
    _ state:
        TrainTogetherRequestState
) -> String {
    switch state {
    case .pending:
        return ATHLTHLocalization.choose(
            english: "Request sent",
            norwegian: "Forespørsel sendt"
        )
    case .accepted:
        return ATHLTHLocalization.choose(
            english: "Accepted",
            norwegian: "Godkjent"
        )
    case .declined:
        return ATHLTHLocalization.choose(
            english: "Declined",
            norwegian: "Avslått"
        )
    case .withdrawn:
        return ATHLTHLocalization.choose(
            english: "Withdrawn",
            norwegian: "Trukket"
        )
    }
}

private func requestStateIcon(
    _ state:
        TrainTogetherRequestState
) -> String {
    switch state {
    case .pending:
        return "clock"
    case .accepted:
        return "checkmark.circle.fill"
    case .declined:
        return "xmark.circle"
    case .withdrawn:
        return "arrow.uturn.backward.circle"
    }
}
