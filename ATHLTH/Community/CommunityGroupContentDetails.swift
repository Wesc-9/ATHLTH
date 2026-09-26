import MapKit
import SwiftUI

struct CommunityGroupEventDetailView: View {
    @EnvironmentObject private var groups:
        CommunityGroupStore
    @EnvironmentObject private var session:
        AppSessionStore

    @StateObject private var advanced =
        CommunityGroupAdvancedStore()

    let group: CommunityGroupRecord
    let event: CommunityGroupEventRecord

    @State private var showingEdit = false
    @State private var actionMessage: String?

    private var current:
        CommunityGroupEventRecord {
        advanced.latestEvent ?? event
    }

    private var canManageContent: Bool {
        groups.canManage(group) ||
        current.creatorID ==
            session.profile.userID ||
        advanced.hosts.contains {
            $0.userID ==
                session.profile.userID
        }
    }

    private var myRSVP: String? {
        advanced.eventRSVPs.first {
            $0.userID ==
                session.profile.userID
        }?.status
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent: Color.purple.opacity(0.22)
            )

            ScrollView {
                LazyVStack(spacing: 16) {
                    cover
                    titleBlock
                    organizerCard
                    scheduleCard
                    activityCard
                    participationCard
                    systemActionsCard
                    CommunityGroupDiscussionSection(
                        store: advanced,
                        group: group,
                        contentType: "event",
                        contentID: current.id
                    )
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManageContent {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Menu {
                        if current.status != "cancelled" {
                            Button {
                                showingEdit = true
                            } label: {
                                Label(
                                    "Edit Event",
                                    systemImage: "pencil"
                                )
                            }
                        }

                        Button {
                            Task {
                                let result =
                                    await advanced
                                        .duplicateEvent(
                                            event: current,
                                            hostIDs:
                                                advanced
                                                    .hosts
                                                    .map(
                                                        .userID
                                                    )
                                        )

                                if result != nil {
                                    actionMessage =
                                        "A draft copy was created."
                                }
                            }
                        } label: {
                            Label(
                                "Duplicate",
                                systemImage:
                                    "doc.on.doc"
                            )
                        }

                        if current.status !=
                            "cancelled" {
                            Button(
                                "Cancel Event",
                                role: .destructive
                            ) {
                                Task {
                                    if await advanced
                                        .cancelEvent(
                                            event: current
                                        ) {
                                        actionMessage =
                                            "Event cancelled."
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            CommunityGroupEventEditView(
                group: group,
                event: current,
                existingHostIDs:
                    Set(
                        advanced.hosts.map(\.userID)
                    )
            ) {
                Task {
                    await advanced.loadEvent(
                        groupID: group.id,
                        eventID: current.id
                    )
                    await groups.loadGroupContent(
                        group.id
                    )
                }
            }
        }
        .task {
            await advanced.loadEvent(
                groupID: group.id,
                eventID: event.id
            )
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: {
                    actionMessage != nil ||
                    advanced.errorMessage != nil
                },
                set: {
                    if !$0 {
                        actionMessage = nil
                        advanced.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                actionMessage ??
                advanced.errorMessage ??
                ""
            )
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let value = current.imageURL,
           let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    coverFallback(
                        icon: "calendar"
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
            )
        } else {
            coverFallback(icon: "calendar")
        }
    }

    private func coverFallback(
        icon: String
    ) -> some View {
        LinearGradient(
            colors: [
                Color.purple.opacity(0.18),
                ATHLTHTheme.cardWarm,
                ATHLTHTheme.canvasTop
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 42,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    Color.purple.opacity(0.70)
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
    }

    private var titleBlock: some View {
        ATHLTHCard {
            HStack(alignment: .top) {
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    Text(current.title)
                        .font(
                            .title2.weight(.bold)
                        )

                    if !current.summary.isEmpty {
                        Text(current.summary)
                            .font(.subheadline)
                            .foregroundStyle(
                                .secondary
                            )
                    }
                }

                Spacer()

                contentStatusBadge(
                    current.resolvedStatus
                )
            }
        }
    }

    private var organizerCard: some View {
        ATHLTHCard {
            Text("Hosted by")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                organizerAvatar

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(organizerName)
                        .font(
                            .headline
                        )

                    Text(
                        current.organizerKind ==
                            .group
                            ? "Group organizer"
                            : "Event organizer"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.top, 5)

            if !advanced.hosts.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                Text("Co-hosts")
                    .font(
                        .caption.weight(.semibold)
                    )
                    .foregroundStyle(.secondary)

                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 10) {
                        ForEach(
                            advanced.hosts
                        ) { host in
                            if let profile =
                                groups.profileCard(
                                    for: host.userID
                                ) {
                                NavigationLink {
                                    FriendProfileView(
                                        userID:
                                            host.userID
                                    )
                                } label: {
                                    VStack(spacing: 4) {
                                        CommunityContentAvatar(
                                            profile:
                                                profile,
                                            size: 38
                                        )
                                        Text(
                                            profile
                                                .usernameLabel
                                                .isEmpty
                                                ? profile
                                                    .resolvedName
                                                : profile
                                                    .usernameLabel
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .primaryText
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var organizerAvatar: some View {
        if current.organizerKind == .group {
            CommunityGroupIdentityAvatar(
                group: group,
                size: 48
            )
        } else if let userID =
                    current.organizerUserID ??
                    Optional(current.creatorID),
                  let profile =
                    groups.profileCard(
                        for: userID
                    ) {
            NavigationLink {
                FriendProfileView(
                    userID: userID
                )
            } label: {
                CommunityContentAvatar(
                    profile: profile,
                    size: 48
                )
            }
            .buttonStyle(.plain)
        } else {
            Image(
                systemName:
                    "person.crop.circle.fill"
            )
            .font(.system(size: 46))
            .foregroundStyle(.secondary)
        }
    }

    private var organizerName: String {
        if current.organizerKind == .group {
            return group.name
        }

        let id =
            current.organizerUserID ??
            current.creatorID

        return groups.profileCard(
            for: id
        )?.resolvedName ?? "Organizer"
    }

    private var scheduleCard: some View {
        ATHLTHCard {
            Text("When & where")
                .font(.headline)

            infoRow(
                icon: "calendar",
                title: "Starts",
                value:
                    current.startsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
            )

            if let endsAt = current.endsAt {
                infoRow(
                    icon: "clock",
                    title: "Ends",
                    value:
                        endsAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
            }

            if current.repeatRule ==
                "weekly" {
                infoRow(
                    icon: "repeat",
                    title: "Repeats",
                    value:
                        current.repeatUntil.map {
                            "Weekly until " +
                            $0.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        } ?? "Weekly"
                )
            }

            if !current.meetingName.isEmpty {
                infoRow(
                    icon: "mappin",
                    title: "Meeting point",
                    value:
                        current.meetingName
                )
            }

            if let lat =
                current.meetingLatitude,
               let lon =
                current.meetingLongitude {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center:
                                CLLocationCoordinate2D(
                                    latitude: lat,
                                    longitude: lon
                                ),
                            span:
                                MKCoordinateSpan(
                                    latitudeDelta:
                                        0.01,
                                    longitudeDelta:
                                        0.01
                                )
                        )
                    )
                ) {
                    Marker(
                        current.meetingName
                            .isEmpty
                            ? "Meeting point"
                            : current
                                .meetingName,
                        coordinate:
                            CLLocationCoordinate2D(
                                latitude: lat,
                                longitude: lon
                            )
                    )
                }
                .frame(height: 150)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16
                    )
                )
                .allowsHitTesting(false)
                .padding(.top, 8)
            }
        }
    }

    private var activityCard: some View {
        ATHLTHCard {
            Text("Activity")
                .font(.headline)

            if let configuration =
                current.activityConfiguration {
                Label(
                    configuration.compactSummary,
                    systemImage:
                        activityIcon(
                            configuration
                                .activityType
                        )
                )
                .font(
                    .subheadline.weight(.semibold)
                )
                .padding(.top, 6)

                activityDetails(
                    configuration
                )
            } else {
                Text(
                    current.activityType
                        .capitalized
                )
                .font(.subheadline)
            }
        }
    }

    private var participationCard: some View {
        ATHLTHCard {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("Attendance")
                        .font(.headline)

                    Text(
                        attendanceSummary
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if current.resolvedStatus !=
                .cancelled &&
                current.resolvedStatus !=
                .completed {
                HStack(spacing: 8) {
                    rsvpButton(
                        "Going",
                        status: "going"
                    )
                    rsvpButton(
                        "Maybe",
                        status: "maybe"
                    )
                    rsvpButton(
                        "Can't go",
                        status: "not_going"
                    )
                }
                .padding(.top, 10)
            }

            if myRSVP == "waitlist" {
                Label(
                    "You're on the waitlist",
                    systemImage: "clock.badge"
                )
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(.orange)
                .padding(.top, 8)
            }

            if let deadline =
                current.rsvpDeadline {
                Text(
                    "RSVP by " +
                    deadline.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }

            let going = advanced.eventRSVPs
                .filter { $0.status == "going" }

            if !going.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: -6) {
                        ForEach(
                            going.prefix(10),
                            id: \.userID
                        ) { rsvp in
                            if let profile =
                                groups.profileCard(
                                    for: rsvp.userID
                                ) {
                                NavigationLink {
                                    FriendProfileView(
                                        userID:
                                            rsvp.userID
                                    )
                                } label: {
                                    CommunityContentAvatar(
                                        profile:
                                            profile,
                                        size: 34
                                    )
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                Color.white,
                                                lineWidth: 2
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var attendanceSummary: String {
        let going = advanced.eventRSVPs
            .filter { $0.status == "going" }
            .count
        let waitlist = advanced.eventRSVPs
            .filter { $0.status == "waitlist" }
            .count

        if let capacity = current.capacity {
            let base =
                "\(going)/\(capacity) going"
            return waitlist > 0
                ? base +
                    " · \(waitlist) waitlisted"
                : base
        }

        return "\(going) going"
    }

    private var systemActionsCard: some View {
        ATHLTHCard {
            Text("Plan")
                .font(.headline)

            Button {
                Task {
                    do {
                        try await
                            CommunityGroupEventSystemActions
                                .addToCalendar(
                                    event: current,
                                    group: group
                                )
                        actionMessage =
                            "Added to Calendar."
                    } catch {
                        actionMessage =
                            error.localizedDescription
                    }
                }
            } label: {
                Label(
                    "Add to Calendar",
                    systemImage:
                        "calendar.badge.plus"
                )
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)

            Menu {
                reminderButton(
                    "1 day before",
                    minutes: 1_440
                )
                reminderButton(
                    "2 hours before",
                    minutes: 120
                )
                reminderButton(
                    "30 minutes before",
                    minutes: 30
                )
            } label: {
                Label(
                    "Set Reminder",
                    systemImage: "bell.badge"
                )
            }
            .buttonStyle(.bordered)
        }
    }

    private func reminderButton(
        _ title: String,
        minutes: Int
    ) -> some View {
        Button(title) {
            Task {
                do {
                    try await
                        CommunityGroupEventSystemActions
                            .scheduleReminder(
                                event: current,
                                minutesBefore:
                                    minutes
                            )
                    actionMessage =
                        "Reminder set."
                } catch {
                    actionMessage =
                        error.localizedDescription
                }
            }
        }
    }

    private func rsvpButton(
        _ title: String,
        status: String
    ) -> some View {
        let selected =
            myRSVP == status ||
            (
                status == "going" &&
                myRSVP == "waitlist"
            )

        return Button {
            Task {
                let resolved =
                    await advanced.setEventRSVP(
                        eventID: current.id,
                        status: status
                    )

                if resolved != nil {
                    await advanced.loadEvent(
                        groupID: group.id,
                        eventID: current.id
                    )
                    await groups.loadGroupContent(
                        group.id
                    )
                }
            }
        } label: {
            Text(title)
                .font(
                    .caption.weight(.semibold)
                )
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(
            selected
                ? ATHLTHTheme.accentDeep
                : .secondary
        )
    }

    @ViewBuilder
    private func activityDetails(
        _ configuration:
            CommunityGroupActivityConfiguration
    ) -> some View {
        if let route = configuration.route {
            infoRow(
                icon: "map.fill",
                title: "Route",
                value:
                    String(
                        format:
                            "%@ · %.1f km",
                        route.title,
                        route.distanceKilometers
                    )
            )
        }

        if let workout =
            configuration.runningWorkout {
            infoRow(
                icon: "figure.run.circle",
                title: "Workout",
                value: workout.title
            )
        }

        if let minutes =
            configuration.strengthDurationMinutes {
            infoRow(
                icon: "clock",
                title: "Duration",
                value: "\(minutes) min"
            )
        }

        if let exercises =
            configuration.strengthExercises,
           !exercises.isEmpty {
            infoRow(
                icon: "dumbbell.fill",
                title: "Exercises",
                value:
                    exercises
                        .map(\.name)
                        .joined(
                            separator: ", "
                        )
            )
        }
    }
}

struct CommunityGroupChallengeDetailView: View {
    @EnvironmentObject private var groups:
        CommunityGroupStore
    @EnvironmentObject private var session:
        AppSessionStore

    @StateObject private var advanced =
        CommunityGroupAdvancedStore()

    let group: CommunityGroupRecord
    let challenge: CommunityGroupChallengeRecord

    @State private var showingEdit = false
    @State private var actionMessage: String?

    private var current:
        CommunityGroupChallengeRecord {
        advanced.latestChallenge ?? challenge
    }

    private var canManageContent: Bool {
        groups.canManage(group) ||
        current.creatorID ==
            session.profile.userID ||
        advanced.hosts.contains {
            $0.userID ==
                session.profile.userID
        }
    }

    private var isJoined: Bool {
        advanced.participants.contains {
            $0.userID ==
                session.profile.userID &&
            $0.status == "joined"
        }
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent: Color.green.opacity(0.20)
            )

            ScrollView {
                LazyVStack(spacing: 16) {
                    cover
                    titleBlock
                    organizerCard
                    rulesCard
                    participationCard
                    progressCard
                    leaderboardCard
                    CommunityGroupDiscussionSection(
                        store: advanced,
                        group: group,
                        contentType: "challenge",
                        contentID: current.id
                    )
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManageContent {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Menu {
                        if current.status != "cancelled" {
                            Button {
                                showingEdit = true
                            } label: {
                                Label(
                                    "Edit Challenge",
                                    systemImage: "pencil"
                                )
                            }
                        }

                        Button {
                            Task {
                                let result =
                                    await advanced
                                        .duplicateChallenge(
                                            challenge:
                                                current,
                                            hostIDs:
                                                advanced
                                                    .hosts
                                                    .map(
                                                        .userID
                                                    )
                                        )

                                if result != nil {
                                    actionMessage =
                                        "A draft copy was created."
                                }
                            }
                        } label: {
                            Label(
                                "Duplicate",
                                systemImage:
                                    "doc.on.doc"
                            )
                        }

                        if current.status !=
                            "cancelled" {
                            Button(
                                "Cancel Challenge",
                                role: .destructive
                            ) {
                                Task {
                                    if await advanced
                                        .cancelChallenge(
                                            challenge:
                                                current
                                        ) {
                                        actionMessage =
                                            "Challenge cancelled."
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            CommunityGroupChallengeEditView(
                group: group,
                challenge: current,
                existingHostIDs:
                    Set(
                        advanced.hosts.map(\.userID)
                    )
            ) {
                Task {
                    await advanced.loadChallenge(
                        groupID: group.id,
                        challengeID:
                            current.id
                    )
                    await groups.loadGroupContent(
                        group.id
                    )
                }
            }
        }
        .task {
            await advanced.loadChallenge(
                groupID: group.id,
                challengeID: challenge.id
            )
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: {
                    actionMessage != nil ||
                    advanced.errorMessage != nil
                },
                set: {
                    if !$0 {
                        actionMessage = nil
                        advanced.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                actionMessage ??
                advanced.errorMessage ??
                ""
            )
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let value = current.imageURL,
           let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    challengeCoverFallback
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
            )
        } else {
            challengeCoverFallback
        }
    }

    private var challengeCoverFallback:
        some View {
        LinearGradient(
            colors: [
                Color.green.opacity(0.18),
                ATHLTHTheme.cardWarm,
                ATHLTHTheme.canvasTop
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "bolt.fill")
                .font(
                    .system(
                        size: 42,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    Color.green.opacity(0.70)
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
    }

    private var titleBlock: some View {
        ATHLTHCard {
            HStack(alignment: .top) {
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    Text(current.title)
                        .font(
                            .title2.weight(.bold)
                        )

                    if !current.summary.isEmpty {
                        Text(current.summary)
                            .font(.subheadline)
                            .foregroundStyle(
                                .secondary
                            )
                    }
                }

                Spacer()

                contentStatusBadge(
                    current.resolvedStatus
                )
            }
        }
    }

    private var organizerCard: some View {
        ATHLTHCard {
            Text("Hosted by")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if current.organizerKind == .group {
                    CommunityGroupIdentityAvatar(
                        group: group,
                        size: 48
                    )
                } else {
                    let userID =
                        current.organizerUserID ??
                        current.creatorID

                    if let profile =
                        groups.profileCard(
                            for: userID
                        ) {
                        NavigationLink {
                            FriendProfileView(
                                userID: userID
                            )
                        } label: {
                            CommunityContentAvatar(
                                profile:
                                    profile,
                                size: 48
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(challengeOrganizerName)
                        .font(.headline)
                    Text(
                        current.organizerKind ==
                            .group
                            ? "Group organizer"
                            : "Challenge organizer"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.top, 5)

            if !advanced.hosts.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                Text(
                    "\(advanced.hosts.count) co-host\(advanced.hosts.count == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var challengeOrganizerName: String {
        if current.organizerKind == .group {
            return group.name
        }

        return groups.profileCard(
            for:
                current.organizerUserID ??
                current.creatorID
        )?.resolvedName ?? "Organizer"
    }

    private var rulesCard: some View {
        ATHLTHCard {
            Text("Challenge Rules")
                .font(.headline)

            if let configuration =
                current.activityConfiguration {
                infoRow(
                    icon:
                        activityIcon(
                            configuration
                                .activityType
                        ),
                    title: "Activity",
                    value:
                        configuration
                            .compactSummary
                )
            }

            infoRow(
                icon: current.metric.icon,
                title: "Goal",
                value: goalDescription
            )

            infoRow(
                icon: "calendar",
                title: "Window",
                value:
                    current.startsAt.formatted(
                        date: .abbreviated,
                        time: .omitted
                    ) +
                    " – " +
                    current.endsAt.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
            )

            infoRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Attempts",
                value:
                    current.attemptLimit.map {
                        "\($0) maximum"
                    } ?? "Unlimited"
            )

            if current.routeVerificationEnabled {
                infoRow(
                    icon:
                        "checkmark.seal.fill",
                    title:
                        "Route verification",
                    value:
                        "90% match · \(current.routeToleranceMeters) m tolerance"
                )
            }

            if current.startsAt <= Date() {
                Label(
                    "Core competition rules are locked after start.",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
    }

    private var goalDescription: String {
        switch current.metric {
        case .distanceKM:
            return String(
                format:
                    "%.1f km · %@",
                current.targetValue,
                current.scoringMode.title
            )
        case .workouts:
            return String(
                format:
                    "%.0f workouts · %@",
                current.targetValue,
                current.scoringMode.title
            )
        case .activeMinutes:
            return String(
                format:
                    "%.0f min · %@",
                current.targetValue,
                current.scoringMode.title
            )
        case .fastestTime:
            return "Fastest qualifying time"
        }
    }

    private var participationCard: some View {
        ATHLTHCard {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("Participation")
                        .font(.headline)

                    Text(
                        current.joinRequired
                            ? "\(joinedCount) joined"
                            : "Open participation"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if current.joinRequired &&
                    current.resolvedStatus !=
                        .completed &&
                    current.resolvedStatus !=
                        .cancelled {
                    Button(
                        isJoined
                            ? "Leave"
                            : "Join Challenge"
                    ) {
                        Task {
                            if await advanced
                                .setChallengeParticipation(
                                    challengeID:
                                        current.id,
                                    join: !isJoined
                                ) != nil {
                                await advanced
                                    .loadChallenge(
                                        groupID:
                                            group.id,
                                        challengeID:
                                            current.id
                                    )
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(
                        ATHLTHTheme.accentDeep
                    )
                    .controlSize(.regular)
                    .fontWeight(
                        isJoined
                            ? .regular
                            : .semibold
                    )
                }
            }
        }
    }

    private var joinedCount: Int {
        advanced.participants
            .filter { $0.status == "joined" }
            .count
    }

    private var progressCard: some View {
        ATHLTHCard {
            Text("My Progress")
                .font(.headline)

            if let entry = myLeaderboardEntry {
                Text(
                    formatScore(
                        entry.score
                    )
                )
                .font(
                    .system(
                        size: 30,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .padding(.top, 5)

                Text(
                    "\(entry.attemptCount) attempt\(entry.attemptCount == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let limit =
                    current.attemptLimit {
                    ProgressView(
                        value:
                            min(
                                Double(
                                    entry.attemptCount
                                ),
                                Double(limit)
                            ),
                        total:
                            Double(limit)
                    )
                    .padding(.top, 8)
                }
            } else {
                Text(
                    isJoined ||
                    !current.joinRequired
                        ? "No qualifying attempts yet."
                        : "Join the challenge to start tracking progress."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
        }
    }

    private var leaderboardCard: some View {
        ATHLTHCard {
            HStack {
                Text(
                    current.resolvedStatus ==
                        .completed
                        ? "Results"
                        : "Leaderboard"
                )
                .font(.headline)

                Spacer()

                Text(
                    "\(leaderboard.count) participant\(leaderboard.count == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if leaderboard.isEmpty {
                Text(
                    "No qualifying results yet."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        leaderboard.prefix(20)
                    ) { entry in
                        HStack(spacing: 10) {
                            Text("#\(entry.rank)")
                                .font(
                                    .caption
                                        .weight(.bold)
                                )
                                .frame(width: 28)

                            if let profile =
                                groups.profileCard(
                                    for: entry.userID
                                ) {
                                NavigationLink {
                                    FriendProfileView(
                                        userID:
                                            entry
                                                .userID
                                    )
                                } label: {
                                    CommunityContentAvatar(
                                        profile:
                                            profile,
                                        size: 34
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    entry.displayName
                                )
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )

                                Text(
                                    "\(entry.attemptCount) attempt\(entry.attemptCount == 1 ? "" : "s")"
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                            }

                            Spacer()

                            Text(
                                formatScore(
                                    entry.score
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(.bold)
                            )
                        }
                        .padding(.vertical, 9)

                        if entry.id !=
                            leaderboard
                                .prefix(20)
                                .last?
                                .id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }

            let unverified = advanced.attempts
                .filter {
                    $0.verificationStatus ==
                        "unverified"
                }
                .count

            if unverified > 0 {
                Label(
                    "\(unverified) attempt\(unverified == 1 ? "" : "s") did not pass route verification and are excluded.",
                    systemImage:
                        "exclamationmark.shield"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
        }
    }

    private var myLeaderboardEntry:
        CommunityGroupLeaderboardEntry? {
        leaderboard.first {
            $0.userID ==
                session.profile.userID
        }
    }

    private var leaderboard:
        [CommunityGroupLeaderboardEntry] {
        let valid = advanced.attempts.filter {
            $0.verificationStatus !=
                "unverified"
        }

        var userIDs = Set(
            valid.map(\.userID)
        )

        if current.joinRequired {
            userIDs.formUnion(
                advanced.participants
                    .filter {
                        $0.status == "joined" ||
                        $0.status == "completed"
                    }
                    .map(\.userID)
            )
        }

        let scored = userIDs.compactMap {
            userID
            -> (
                UUID,
                Double,
                Int
            )? in

            let attempts = valid.filter {
                $0.userID == userID
            }

            guard !attempts.isEmpty else {
                return nil
            }

            let score: Double
            switch current.scoringMode {
            case .cumulative:
                score = attempts.reduce(0) {
                    $0 + $1.contribution
                }

            case .bestAttempt:
                if current
                    .prefersLowerLeaderboardScore {
                    score =
                        attempts
                            .map(\.contribution)
                            .min() ?? 0
                } else {
                    score =
                        attempts
                            .map(\.contribution)
                            .max() ?? 0
                }

            case .completeTarget:
                score = min(
                    attempts.reduce(0) {
                        $0 +
                        $1.contribution
                    },
                    current.targetValue
                )
            }

            return (
                userID,
                score,
                attempts.count
            )
        }

        let sorted = scored.sorted {
            if current
                .prefersLowerLeaderboardScore {
                return $0.1 < $1.1
            }

            return $0.1 > $1.1
        }

        return sorted.enumerated().map {
            index,
            item in

            let profile =
                groups.profileCard(
                    for: item.0
                )

            return CommunityGroupLeaderboardEntry(
                userID: item.0,
                displayName:
                    profile?.resolvedName ??
                    "Participant",
                username:
                    profile?.username,
                avatarURL:
                    profile?.avatarURL,
                score: item.1,
                attemptCount: item.2,
                rank: index + 1
            )
        }
    }

    private func formatScore(
        _ score: Double
    ) -> String {
        switch current.metric {
        case .distanceKM:
            return String(
                format: "%.1f km",
                score
            )
        case .workouts:
            return String(
                format: "%.0f",
                score
            )
        case .activeMinutes:
            return String(
                format: "%.0f min",
                score
            )
        case .fastestTime:
            let seconds =
                max(
                    Int(score.rounded()),
                    0
                )
            return String(
                format:
                    "%d:%02d",
                seconds / 60,
                seconds % 60
            )
        }
    }
}

struct CommunityGroupDiscussionSection: View {
    @ObservedObject var store:
        CommunityGroupAdvancedStore
    @EnvironmentObject private var groups:
        CommunityGroupStore
    @EnvironmentObject private var session:
        AppSessionStore

    let group: CommunityGroupRecord
    let contentType: String
    let contentID: UUID

    @State private var draft = ""

    var body: some View {
        ATHLTHCard {
            Text("Discussion")
                .font(.headline)

            if store.comments.isEmpty {
                Text(
                    "No comments yet. Ask a question or share an update about this \(contentType)."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(
                        store.comments
                    ) { comment in
                        commentRow(comment)
                    }
                }
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "Comment",
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    submit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Color(
                        .secondarySystemGroupedBackground
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 15
                    )
                )

                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(
                            .system(
                                size: 14,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            ATHLTHTheme.accentDeep,
                            in: Circle()
                        )
                }
                .disabled(
                    draft
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                )
            }
            .padding(.top, 10)
        }
    }

    private func commentRow(
        _ comment:
            CommunityGroupContentCommentRecord
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            if let profile =
                groups.profileCard(
                    for: comment.authorID
                ) {
                NavigationLink {
                    FriendProfileView(
                        userID:
                            comment.authorID
                    )
                } label: {
                    CommunityContentAvatar(
                        profile: profile,
                        size: 32
                    )
                }
                .buttonStyle(.plain)
            }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    groups.profileCard(
                        for:
                            comment.authorID
                    )?.usernameLabel
                        .nonEmpty ??
                    groups.profileCard(
                        for:
                            comment.authorID
                    )?.resolvedName ??
                    "Member"
                )
                .font(
                    .caption.weight(.semibold)
                )

                Text(comment.body)
                    .font(.subheadline)

                Text(
                    comment.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            if comment.authorID ==
                session.profile.userID ||
                groups.canManage(group) {
                Menu {
                    Button(
                        "Delete",
                        role: .destructive
                    ) {
                        Task {
                            _ = await store
                                .deleteComment(
                                    contentType:
                                        contentType,
                                    contentID:
                                        contentID,
                                    commentID:
                                        comment.id
                                )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func submit() {
        let body = draft
        draft = ""

        Task {
            let sent =
                await store.postComment(
                    groupID: group.id,
                    contentType: contentType,
                    contentID: contentID,
                    body: body
                )

            if !sent {
                draft = body
            }
        }
    }
}

struct CommunityContentAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let value = profile.avatarURL,
               let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Image(systemName: "person.fill")
            .font(
                .system(
                    size: size * 0.40,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: size,
                height: size
            )
            .background(
                ATHLTHTheme.accentSoft,
                in: Circle()
            )
    }
}

struct CommunityGroupIdentityAvatar: View {
    let group: CommunityGroupRecord
    let size: CGFloat

    var body: some View {
        Group {
            if let value = group.imageURL,
               let url = URL(string: value) {
                AsyncImage(url: url) {
                    phase in

                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius:
                    size * 0.28,
                style: .continuous
            )
        )
    }

    private var fallback: some View {
        Image(systemName: "person.3.fill")
            .font(
                .system(
                    size: size * 0.36,
                    weight: .semibold
                )
            )
            .foregroundStyle(.indigo)
            .frame(
                width: size,
                height: size
            )
            .background(
                Color.indigo.opacity(0.10),
                in: RoundedRectangle(
                    cornerRadius:
                        size * 0.28,
                    style: .continuous
                )
            )
    }
}

@ViewBuilder
private func contentStatusBadge(
    _ status: CommunityGroupContentStatus
) -> some View {
    Text(status.title)
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            statusTint(status)
                .opacity(0.12),
            in: Capsule()
        )
        .foregroundStyle(
            statusTint(status)
        )
}

private func statusTint(
    _ status: CommunityGroupContentStatus
) -> Color {
    switch status {
    case .draft:
        return .secondary
    case .upcoming:
        return .blue
    case .live:
        return .green
    case .completed:
        return .indigo
    case .cancelled:
        return .red
    }
}

private func infoRow(
    icon: String,
    title: String,
    value: String
) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(width: 24)

        VStack(
            alignment: .leading,
            spacing: 1
        ) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
        }

        Spacer()
    }
    .padding(.top, 8)
}

private func activityIcon(
    _ activity: String
) -> String {
    switch activity {
    case "running":
        return "figure.run"
    case "walking":
        return "figure.walk"
    case "cycling":
        return "figure.outdoor.cycle"
    case "strength":
        return "dumbbell.fill"
    default:
        return "figure.mixed.cardio"
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
