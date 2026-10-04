import SwiftUI

struct TrainTogetherMarketplaceView:
    View
{
    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var social:
        SocialStore

    @StateObject private var marketplace =
        TrainTogetherMarketplaceStore()

    @State private var showingCreate =
        false
    @State private var searchText = ""
    @State private var selectedKind:
        WorkoutKind?
    @State private var timeFilter:
        TrainTogetherTimeFilter = .upcoming

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

                if marketplace.isLoading &&
                    visiblePosts.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Finding workouts…",
                                norwegian:
                                    "Finner økter…"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .frame(
                        maxWidth: .infinity
                    )
                    .padding(
                        .vertical,
                        36
                    )
                } else if visiblePosts.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(
                            visiblePosts
                        ) { post in
                            NavigationLink {
                                TrainTogetherPostDetailView(
                                    postID:
                                        post.id
                                )
                                .environmentObject(
                                    marketplace
                                )
                            } label: {
                                postCard(post)
                            }
                            .buttonStyle(
                                .plain
                            )
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 34)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.16)
            )
        )
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
        .sheet(
            isPresented:
                $showingCreate
        ) {
            NavigationStack {
                TrainTogetherPostCreateView()
                    .environmentObject(
                        marketplace
                    )
            }
        }
        .task {
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

    private var hero:
        some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        Text(
                            "TRAIN TOGETHER"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .tracking(2.5)
                        .foregroundStyle(
                            ATHLTHTheme
                                .vitality
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Post a workout. Find your people.",
                                norwegian:
                                    "Legg ut en økt. Finn noen å trene med."
                            )
                        )
                        .font(
                            .title2
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                    }

                    Spacer()

                    Image(
                        systemName:
                            "person.2.wave.2.fill"
                    )
                    .font(
                        .system(
                            size: 26,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )
                    .frame(
                        width: 58,
                        height: 58
                    )
                    .background(
                        ATHLTHTheme
                            .vitalitySoft,
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style:
                                .continuous
                        )
                    )
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Create a real workout you want company for. Everyone can browse the list and ask to join. You decide who is accepted.",
                        norwegian:
                            "Opprett en konkret treningsøkt du ønsker selskap på. Alle kan se listen og spørre om å bli med. Du bestemmer hvem som godkjennes."
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

                Button {
                    showingCreate = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Create workout",
                            norwegian:
                                "Opprett økt"
                        ),
                        systemImage:
                            "plus.circle.fill"
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
                .controlSize(.large)
            }
        }
    }

    private var filterBar:
        some View {
        VStack(spacing: 10) {
            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 8) {
                    filterChip(
                        title:
                            ATHLTHLocalization.choose(
                                english: "All",
                                norwegian: "Alle"
                            ),
                        icon:
                            "sparkles",
                        selected:
                            selectedKind ==
                                nil
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
                            title:
                                kind.title,
                            icon:
                                kind
                                    .systemImage,
                            selected:
                                selectedKind ==
                                    kind
                        ) {
                            selectedKind =
                                kind
                        }
                    }
                }
            }

            Picker(
                "",
                selection: $timeFilter
            ) {
                ForEach(
                    TrainTogetherTimeFilter
                        .allCases
                ) { filter in
                    Text(filter.title)
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
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
                    ? ATHLTHTheme
                        .vitality
                    : Color.white
                        .opacity(0.82),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(
        _ title: String,
        subtitle: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(title)
                .font(
                    .title3
                        .weight(.bold)
                )

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
        }
    }

    private func postCard(
        _ post: TrainTogetherPost
    ) -> some View {
        ATHLTHCard {
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
                                "@(username)"
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
                            "(duration) min",
                            icon: "clock"
                        )
                    }
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
            Color.primary
                .opacity(0.035),
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
                    Date()
            }
            .sorted {
                $0.scheduledStart <
                    $1.scheduledStart
            }
    }

    private var emptyState:
        some View {
        ATHLTHCard {
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
                    }
                    .padding(16)
                    .padding(.bottom, 28)
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
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.13)
            )
        )
        .navigationTitle(
            "Train Together"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
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
    }

    private func detailHero(
        _ post: TrainTogetherPost
    ) -> some View {
        ATHLTHCard {
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
            }
        }
    }

    private func workoutCard(
        _ post: TrainTogetherPost
    ) -> some View {
        ATHLTHCard {
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
                                "(duration) min",
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
            ATHLTHCard {
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
                            "(pendingRequests.count)"
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
        ATHLTHCard {
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
                        ATHLTHLocalization.choose(
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

                    askButton(post)

                case .none:
                    askButton(post)
                }
            }
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
        ATHLTHCard {
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

private struct TrainTogetherJoinRequestSheet:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject private var marketplace:
        TrainTogetherMarketplaceStore

    let post: TrainTogetherPost

    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text(post.title)
                            .font(
                                .headline
                            )
                        Text(
                            "(post.broadArea) · " +
                            post.scheduledStart
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english:
                            "Optional message",
                        norwegian:
                            "Valgfri melding"
                    )
                ) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Hi! Can I join?",
                            norwegian:
                                "Hei! Kan jeg bli med?"
                        ),
                        text: $message,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "The creator must approve you before exact meetup information or the shared workout lobby becomes available.",
                            norwegian:
                                "Oppretteren må godkjenne deg før nøyaktig møtested og den delte øktlobbyen blir tilgjengelig."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Ask to join",
                    norwegian:
                        "Spør om å bli med"
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
                                "Send",
                            norwegian:
                                "Send"
                        )
                    ) {
                        Task {
                            if await marketplace
                                .requestToJoin(
                                    postID:
                                        post.id,
                                    message:
                                        message
                                ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        marketplace
                            .isWorking
                    )
                }
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
    @State private var distanceKilometers =
        5.0
    @State private var level = "all"
    @State private var broadArea = ""
    @State private var note = ""
    @State private var maxGuests = 1
    @State private var meetingName = ""
    @State private var meetingDetails = ""

    var body: some View {
        Form {
            Section {
                Menu {
                    Button {
                        selectedSourceID = nil
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Create from scratch",
                                norwegian:
                                    "Lag fra bunnen"
                            ),
                            systemImage:
                                "plus"
                        )
                    }

                    ForEach(
                        availablePlannedSessions
                    ) { workout in
                        Button {
                            apply(workout)
                        } label: {
                            Label(
                                workout.title,
                                systemImage:
                                    workout
                                        .kind
                                        .systemImage
                            )
                        }
                    }
                } label: {
                    LabeledContent(
                        ATHLTHLocalization.choose(
                            english:
                                "Workout source",
                            norwegian:
                                "Grunnlag"
                        ),
                        value:
                            selectedWorkout?
                                .title ??
                            ATHLTHLocalization.choose(
                                english:
                                    "New workout",
                                norwegian:
                                    "Ny økt"
                            )
                    )
                }
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Use a real workout",
                        norwegian:
                            "Bruk en faktisk økt"
                    )
                )
            } footer: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Choose a planned workout to publish its structure, or create a simple workout from scratch.",
                        norwegian:
                            "Velg en planlagt økt for å publisere oppsettet, eller lag en enkel økt fra bunnen."
                    )
                )
            }

            Section(
                ATHLTHLocalization.choose(
                    english:
                        "Workout",
                    norwegian:
                        "Treningsøkt"
                )
            ) {
                TextField(
                    ATHLTHLocalization.choose(
                        english:
                            "Workout title",
                        norwegian:
                            "Navn på økten"
                    ),
                    text: $title
                )

                Picker(
                    ATHLTHLocalization.choose(
                        english:
                            "Activity",
                        norwegian:
                            "Aktivitet"
                    ),
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

                DatePicker(
                    ATHLTHLocalization.choose(
                        english: "When",
                        norwegian: "Når"
                    ),
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

                Stepper(
                    ATHLTHLocalization.format(
                        english:
                            "Duration: %d min",
                        norwegian:
                            "Varighet: %d min",
                        durationMinutes
                    ),
                    value:
                        $durationMinutes,
                    in: 10...360,
                    step: 5
                )

                if kind == .running ||
                    kind == .walking {
                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Distance (km)",
                            norwegian:
                                "Distanse (km)"
                        ),
                        value:
                            $distanceKilometers,
                        format: .number
                    )
                    .keyboardType(
                        .decimalPad
                    )
                }

                Picker(
                    ATHLTHLocalization.choose(
                        english:
                            "Level",
                        norwegian:
                            "Nivå"
                    ),
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
                    Text("Beginner")
                        .tag("beginner")
                    Text("Intermediate")
                        .tag("intermediate")
                    Text("Advanced")
                        .tag("advanced")
                }

                TextField(
                    ATHLTHLocalization.choose(
                        english:
                            "City / broad area",
                        norwegian:
                            "By / område"
                    ),
                    text: $broadArea
                )

                TextField(
                    ATHLTHLocalization.choose(
                        english:
                            "Short description (optional)",
                        norwegian:
                            "Kort beskrivelse (valgfritt)"
                    ),
                    text: $note,
                    axis: .vertical
                )
                .lineLimit(2...5)

                Stepper(
                    ATHLTHLocalization.format(
                        english:
                            "Open spots: %d",
                        norwegian:
                            "Ledige plasser: %d",
                        maxGuests
                    ),
                    value:
                        $maxGuests,
                    in: 1...10
                )
            }

            Section {
                TextField(
                    ATHLTHLocalization.choose(
                        english:
                            "Meeting place",
                        norwegian:
                            "Møtested"
                    ),
                    text: $meetingName
                )

                TextField(
                    ATHLTHLocalization.choose(
                        english:
                            "Extra directions",
                        norwegian:
                            "Ekstra beskrivelse"
                    ),
                    text:
                        $meetingDetails,
                    axis: .vertical
                )
                .lineLimit(2...4)
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Private meetup",
                        norwegian:
                            "Privat møtested"
                    )
                )
            } footer: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Only the broad area is visible in the marketplace. Exact meetup details are revealed after you accept someone.",
                        norwegian:
                            "Kun området vises i listen. Nøyaktig møtested vises først etter at du har godkjent noen."
                    )
                )
            }
        }
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
                .disabled(
                    !canPublish ||
                    marketplace.isWorking
                )
            }
        }
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
            !cleanTitle.isEmpty &&
            cleanArea.count >= 2 &&
            scheduledStart >
                Date()
                    .addingTimeInterval(
                        10 * 60
                    ) &&
            durationMinutes >= 10 &&
            distanceKilometers >
                0
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
        distanceKilometers =
            workout
                .targetDistanceKilometers ??
            distanceKilometers
        note =
            workout.notes ??
            note
    }

    private func publish() {
        let postID = UUID()
        let cleanTitle =
            title.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
        let cleanArea =
            broadArea.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        var workout =
            selectedWorkout ??
            PlannedSession(
                id: UUID(),
                title: cleanTitle,
                kind: kind,
                scheduledStart:
                    scheduledStart,
                durationMinutes:
                    durationMinutes,
                targetDistanceKilometers:
                    kind == .running ||
                    kind == .walking
                        ? distanceKilometers
                        : nil,
                targetPaceSecondsPerKilometer:
                    nil,
                routeID: nil,
                exercises: [],
                notes:
                    note.isEmpty
                        ? nil
                        : note
            )

        workout.title = cleanTitle
        workout.kind = kind
        workout.scheduledStart =
            scheduledStart
        workout.durationMinutes =
            durationMinutes

        if kind == .running ||
            kind == .walking {
            workout
                .targetDistanceKilometers =
                distanceKilometers
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
                        .routeAlertConfiguration
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
                    durationMinutes,
                distanceKilometers:
                    kind == .running ||
                    kind == .walking
                        ? distanceKilometers
                        : nil,
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
        let cleanDetails =
            meetingDetails
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        let meetup =
            TrainTogetherMeetupWrite(
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
                meetingDetails:
                    cleanDetails.isEmpty
                        ? nil
                        : String(
                            cleanDetails
                                .prefix(600)
                        )
            )

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
