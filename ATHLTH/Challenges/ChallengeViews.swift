import CoreLocation
import MapKit
import SwiftUI

struct ProfileChallengesSection: View {
    @EnvironmentObject private var challenges: ChallengeStore

    @State private var showingCreate = false

    private var highlighted: [ATHLTHChallenge] {
        Array(
            challenges.visibleChallenges
                .filter {
                    $0.status == .active ||
                    $0.status == .upcoming ||
                    $0.status == .invited
                }
                .prefix(2)
        )
    }

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Challenges")
                        .font(.title3.weight(.bold))
                    Text("Compete, train together and settle it with data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Text("View All")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .frame(width: 32, height: 32)
                        .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if highlighted.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(ATHLTHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Challenge your friends")
                            .font(.subheadline.weight(.semibold))
                        Text("Running, routes, strength and meet-up sessions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(highlighted) { challenge in
                        NavigationLink {
                            ChallengeDetailView(challengeID: challenge.id)
                        } label: {
                            ChallengeCompactRow(challenge: challenge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingCreate) {
            ChallengeCreationView()
        }
    }
}

struct ChallengeCompactRow: View {
    let challenge: ATHLTHChallenge

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: challenge.sport.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 40, height: 40)
                .background(ATHLTHTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(challenge.rules.scoring.title)
                    Text("·")
                    Text(statusText(challenge.status))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(challenge.participants.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("people")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(
            ATHLTHTheme.accent.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func statusText(_ status: ATHLTHChallengeStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .invited: return "Invited"
        case .upcoming: return "Upcoming"
        case .active: return "Live"
        case .completed: return "Finished"
        case .cancelled: return "Cancelled"
        }
    }
}

struct ChallengeHubView: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var officialChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var social: SocialStore

    @State private var showingCreate = false

    private var invitations: [ATHLTHChallenge] {
        challenges.visibleChallenges.filter {
            $0.status == .invited
        }
    }

    private var currentPersonal: [ATHLTHChallenge] {
        challenges.visibleChallenges.filter {
            $0.status != .completed &&
            $0.status != .cancelled &&
            $0.status != .invited
        }
    }

    private var finishedPersonal: [ATHLTHChallenge] {
        challenges.visibleChallenges.filter {
            $0.status == .completed ||
            $0.status == .cancelled
        }
    }

    private var officialHistory: [OfficialWeeklyChallenge] {
        officialChallenges.challenges
            .filter { $0.endsAt <= Date() }
            .sorted { $0.endsAt > $1.endsAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ATHLTH Challenges")
                            .font(.largeTitle.bold())

                        Text(
                            "Weekly community goals, friend challenges and routes."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(
                                ATHLTHTheme.accent.opacity(0.12),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create challenge")
                }

                if let weekly = officialChallenges.activeChallenge {
                    sectionTitle("ATHLTH Weekly")

                    OfficialWeeklyChallengeCard(
                        challenge: weekly,
                        profiles:
                            social.visibleProfiles +
                            social.friends
                    )
                }

                if !officialChallenges.upcomingChallenges.isEmpty {
                    sectionTitle("Coming Up")

                    VStack(spacing: 10) {
                        ForEach(
                            officialChallenges.upcomingChallenges.prefix(4)
                        ) { challenge in
                            NavigationLink {
                                OfficialWeeklyChallengeDetailView(
                                    challengeID: challenge.id
                                )
                            } label: {
                                officialRow(
                                    challenge,
                                    status: "Upcoming"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !invitations.isEmpty {
                    sectionTitle("Invitations")

                    ForEach(invitations) { challenge in
                        NavigationLink {
                            ChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            ChallengeHeroCard(
                                challenge: challenge
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !currentPersonal.isEmpty {
                    sectionTitle("Your Challenges")

                    ForEach(currentPersonal) { challenge in
                        NavigationLink {
                            ChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            ChallengeHeroCard(
                                challenge: challenge
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !officialHistory.isEmpty ||
                    !finishedPersonal.isEmpty {
                    sectionTitle("History")

                    VStack(spacing: 10) {
                        ForEach(officialHistory.prefix(8)) {
                            challenge in
                            NavigationLink {
                                OfficialWeeklyChallengeDetailView(
                                    challengeID: challenge.id
                                )
                            } label: {
                                officialRow(
                                    challenge,
                                    status:
                                        officialChallenges.isCompleted(
                                            challenge.id
                                        )
                                        ? "Completed"
                                        : "Finished"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(finishedPersonal) { challenge in
                            NavigationLink {
                                ChallengeDetailView(
                                    challengeID: challenge.id
                                )
                            } label: {
                                ChallengeCompactRow(
                                    challenge: challenge
                                )
                                .padding()
                                .background(
                                    Color(
                                        .secondarySystemGroupedBackground
                                    ),
                                    in: RoundedRectangle(
                                        cornerRadius: 20
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if officialChallenges.challenges.isEmpty &&
                    challenges.visibleChallenges.isEmpty {
                    ContentUnavailableView(
                        "No challenges yet",
                        systemImage: "figure.run.circle",
                        description: Text(
                            "The next ATHLTH Weekly challenge will appear here. You can also create a challenge with friends."
                        )
                    )
                    .padding(.vertical, 50)
                }
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            challenges.refreshStatuses()
            await officialChallenges.refresh()
            await officialChallenges.syncCompletionState(
                workouts: health.workouts
            )
        }
        .task(id: health.workouts.map(\.id)) {
            await officialChallenges.syncCompletionState(
                workouts: health.workouts
            )
        }
        .sheet(isPresented: $showingCreate) {
            ChallengeCreationView()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.bold())
            .tracking(1.3)
            .foregroundStyle(.secondary)
    }

    private func officialRow(
        _ challenge: OfficialWeeklyChallenge,
        status: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: challenge.kind.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 42, height: 42)
                .background(
                    Color.orange.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    challenge.kind.targetText(
                        challenge.targetValue
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        status == "Completed"
                            ? Color.green
                            : Color.orange
                    )

                Text(
                    challenge.startsAt.formatted(
                        .dateTime.month(.abbreviated).day()
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }
}

struct ChallengeHeroCard: View {
    let challenge: ATHLTHChallenge

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: challenge.sport == .running
                    ? [ATHLTHTheme.accent.opacity(0.92), .black.opacity(0.90)]
                    : [.orange.opacity(0.82), .black.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 130)
                .rotationEffect(.degrees(-12))
                .offset(x: 185, y: -35)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        challenge.status == .active ? "LIVE" : challenge.status.rawValue.uppercased(),
                        systemImage: challenge.status == .active ? "dot.radiowaves.left.and.right" : "calendar"
                    )
                    .font(.caption2.bold())
                    .tracking(1)

                    Spacer()

                    if challenge.rulesAreLocked {
                        Label("RULES LOCKED", systemImage: "lock.fill")
                            .font(.caption2.bold())
                    }
                }

                Spacer()

                Text(challenge.title)
                    .font(.title2.bold())
                    .lineLimit(2)

                HStack {
                    Label(challenge.rules.scoring.title, systemImage: challenge.sport.systemImage)
                    Spacer()
                    Label("\(challenge.participants.count)", systemImage: "person.2.fill")
                }
                .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct ChallengeCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let preselectedFriends: [SocialProfileCard]
    let preselectedRouteID: UUID?

    init(
        preselectedFriends: [SocialProfileCard] = [],
        preselectedRouteID: UUID? = nil
    ) {
        self.preselectedFriends = preselectedFriends
        self.preselectedRouteID = preselectedRouteID

        _selectedRouteID = State(initialValue: preselectedRouteID)

        if preselectedRouteID != nil {
            _step = State(initialValue: 0)
            _sport = State(initialValue: .running)
            _scoring = State(initialValue: .fastestDistance)
            _usesSpecificRoute = State(initialValue: true)
            _gpsRequired = State(initialValue: true)
            _verificationPolicy = State(
                initialValue: .verifiedRequired
            )
        }
    }

    @State private var step = 0
    @State private var sport: ATHLTHChallengeSport = .running
    @State private var scoring: ATHLTHChallengeScoring = .fastestDistance
    @State private var title = ""

    @State private var targetDistanceKm = 5.0
    @State private var targetDurationMinutes = 60.0
    @State private var timeBasis: ChallengeTimeBasis = .elapsed
    @State private var selectedRouteID: UUID?
    @State private var usesSpecificRoute = false
    @State private var gpsRequired = true
    @State private var routeMatchPercent = 90.0
    @State private var distanceTolerancePercent = 2.0
    @State private var startFinishToleranceMeters = 100.0
    @State private var routeDirection:
        ChallengeRouteDirection = .sameDirection
    @State private var attemptPolicy:
        ChallengeAttemptPolicy = .best
    @State private var attemptLimit = 0
    @State private var allowTreadmill = false
    @State private var advancedRules = false

    @State private var heartRateZone = 5
    @State private var heartRateAggregation:
        ChallengeHeartRateAggregation = .totalChallenge

    @State private var exerciseName = "Bench Press"
    @State private var requiredWeightEnabled = false
    @State private var requiredWeightKg = 80.0
    @State private var verificationPolicy: ChallengeVerificationPolicy = .verifiedPreferredManualAllowed

    @State private var startsAt = Date()
    @State private var hasEnd = true
    @State private var endsAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var allowMultipleAttempts = true

    @State private var invitees: [ChallengeParticipant] = []

    @State private var meetupEnabled = false
    @State private var meetupPlaceName = ""
    @State private var meetupAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var meetupCoordinate: CLLocationCoordinate2D?
    @State private var mapPosition: MapCameraPosition = .automatic

    @State private var visibility: ProfileVisibility = .friends

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 5)
                    .tint(ATHLTHTheme.accent)
                    .padding(.horizontal)

                Text(stepTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                ScrollView {
                    Group {
                        switch step {
                        case 0: typeStep
                        case 1: rulesStep
                        case 2: peopleStep
                        case 3: scheduleStep
                        default: reviewStep
                        }
                    }
                    .padding()
                }

                footer
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(
                preselectedRouteID == nil
                    ? "Create Challenge"
                    : "Challenge Route"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if social.friends.isEmpty {
                    await social.refresh()
                }

                if invitees.isEmpty && !preselectedFriends.isEmpty {
                    invitees = preselectedFriends.map(challengeParticipant)
                }
            }
            .onChange(of: sport) { _, newSport in
                switch newSport {
                case .running:
                    scoring = .fastestDistance
                    verificationPolicy = .verifiedRequired

                case .strength:
                    scoring = .heaviestWeight
                    usesSpecificRoute = false
                    selectedRouteID = nil
                    verificationPolicy =
                        .verifiedPreferredManualAllowed

                case .heartRate:
                    scoring = .heartRateZoneTime
                    usesSpecificRoute = false
                    selectedRouteID = nil
                    gpsRequired = false
                    verificationPolicy = .verifiedRequired
                    allowMultipleAttempts = true
                }
            }
            .onChange(of: scoring) { _, newScoring in
                guard sport == .running else {
                    return
                }

                verificationPolicy = .verifiedRequired

                if newScoring != .fastestDistance {
                    usesSpecificRoute = false
                    selectedRouteID = nil
                }
            }
            .onChange(of: usesSpecificRoute) { _, enabled in
                if enabled {
                    gpsRequired = true
                    allowTreadmill = false
                } else {
                    selectedRouteID = nil
                }
            }
            .onChange(of: gpsRequired) { _, required in
                if required {
                    allowTreadmill = false
                }
            }
            .onChange(of: heartRateAggregation) { _, aggregation in
                if aggregation == .totalChallenge {
                    allowMultipleAttempts = true
                }
            }
            .onChange(of: selectedRouteID) { _, routeID in
                guard let routeID,
                      let route = session.savedRoutes.first(where: { $0.id == routeID }),
                      let first = route.coordinates.first
                else {
                    return
                }

                meetupCoordinate = CLLocationCoordinate2D(
                    latitude: first.latitude,
                    longitude: first.longitude
                )
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: meetupCoordinate!,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.02,
                            longitudeDelta: 0.02
                        )
                    )
                )
            }
        }
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Challenge name")
                    .font(.headline)

                TextField(
                    "Give your challenge a name",
                    text: $title
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)

                Text("Required · this is what participants will see.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("What are you competing in?")
                .font(.title2.bold())
                .padding(.top, 4)

            HStack(spacing: 8) {
                sportButton(.running)
                sportButton(.strength)
                sportButton(.heartRate)
            }

            Text("Scoring")
                .font(.headline)
                .padding(.top, 4)

            ForEach(scoringOptions) { option in
                Button {
                    scoring = option
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.headline)
                            Text(scoringSubtitle(option))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(
                            systemName:
                                scoring == option
                                    ? "checkmark.circle.fill"
                                    : "circle"
                        )
                        .foregroundStyle(
                            scoring == option
                                ? ATHLTHTheme.accent
                                : .secondary
                        )
                    }
                    .padding()
                    .challengeCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Set the rules")
                    .font(.title2.bold())

                Spacer()

                Text(advancedRules ? "ADVANCED" : "BASIC")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            Picker(
                "Rule detail",
                selection: $advancedRules
            ) {
                Text("Basic").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)

            switch sport {
            case .running:
                runningRules
            case .strength:
                strengthRules
            case .heartRate:
                heartRateRules
            }

            if advancedRules &&
                sport != .running &&
                !(sport == .heartRate &&
                  heartRateAggregation == .totalChallenge) {
                Toggle(
                    "Allow multiple attempts",
                    isOn: $allowMultipleAttempts
                )
                .padding()
                .challengeCard()
            }

            VStack(alignment: .leading, spacing: 7) {
                Label(
                    "Rules lock when the challenge starts",
                    systemImage: "lock.fill"
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    "Once live, target, route, verification and scoring cannot be changed."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .challengeCard()
        }
    }

    private var runningRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            if scoring == .fastestDistance {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Course")
                        .font(.headline)

                    HStack(spacing: 12) {
                        routeRequirementButton(
                            title: "Run Anywhere",
                            subtitle: "Choose a distance",
                            icon: "figure.run",
                            selected: !usesSpecificRoute,
                            disabled: false
                        ) {
                            usesSpecificRoute = false
                        }

                        routeRequirementButton(
                            title: "Specific Route",
                            subtitle: "Same course",
                            icon:
                                "point.topleft.down.to.point.bottomright.curvepath",
                            selected: usesSpecificRoute,
                            disabled: false
                        ) {
                            usesSpecificRoute = true
                        }
                    }

                    Text(
                        usesSpecificRoute
                            ? "Everyone competes on the same saved route."
                            : "Everyone runs the same distance, but may choose their own course."
                    )
                    .challengeHint()
                }

                if usesSpecificRoute {
                    routeSelectionCard
                } else {
                    numberField(
                        title: "Distance",
                        suffix: "km",
                        value: $targetDistanceKm
                    )
                }
            }

            if scoring == .farthestInTime {
                numberField(
                    title: "Time",
                    suffix: "min",
                    value: $targetDurationMinutes
                )
            }

            if scoring == .fastestDistance &&
                usesSpecificRoute {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("GPS verification required")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Specific-route challenges must include GPS data."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .padding()
                .challengeCard()
            } else {
                Toggle(
                    "Require GPS verification",
                    isOn: $gpsRequired
                )
                .padding()
                .challengeCard()
            }

            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(ATHLTHTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified running only")
                        .font(.subheadline.weight(.semibold))

                    Text(
                        "Running results must come from ATHLTH or a qualifying Apple Health workout. Manual entries are not accepted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .challengeCard()

            if advancedRules {
                if scoring == .fastestDistance {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timing")
                            .font(.headline)

                        Picker(
                            "Timing",
                            selection: $timeBasis
                        ) {
                            ForEach(
                                ChallengeTimeBasis.allCases
                            ) { basis in
                                Text(basis.title)
                                    .tag(basis)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(
                            timeBasis == .elapsed
                                ? "Elapsed time includes pauses."
                                : "Moving time excludes detected stops."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .challengeCard()
                }

                if scoring == .fastestDistance &&
                    !usesSpecificRoute {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Distance tolerance")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(
                                "±\(distanceTolerancePercent.formatted(.number.precision(.fractionLength(0...1))))%"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        }

                        Slider(
                            value: $distanceTolerancePercent,
                            in: 0.5...5,
                            step: 0.5
                        )

                        Text(
                            distanceToleranceDescription
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .challengeCard()
                }

                if scoring == .fastestDistance &&
                    usesSpecificRoute {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Allowed route deviation")
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Text(
                                "\(Int(allowedRouteDeviationPercent))%"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        }

                        Slider(
                            value: allowedRouteDeviationBinding,
                            in: 2...20,
                            step: 1
                        )

                        Text(
                            "Participants must match at least \(Int(routeMatchPercent))% of the selected route."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()

                        HStack {
                            Text("Start & finish tolerance")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(
                                "\(Int(startFinishToleranceMeters)) m"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        }

                        Slider(
                            value: $startFinishToleranceMeters,
                            in: 25...500,
                            step: 25
                        )

                        Text(
                            "The attempt must start and finish within this distance of the saved route endpoints."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()

                        Text("Route direction")
                            .font(.subheadline.weight(.semibold))

                        Picker(
                            "Route direction",
                            selection: $routeDirection
                        ) {
                            ForEach(
                                ChallengeRouteDirection.allCases
                            ) { direction in
                                Text(direction.title)
                                    .tag(direction)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .challengeCard()
                }

                if !usesSpecificRoute {
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle(
                            "Allow treadmill",
                            isOn: $allowTreadmill
                        )
                        .disabled(gpsRequired)

                        Text(
                            gpsRequired
                                ? "Turn off GPS verification to allow indoor treadmill runs."
                                : "When enabled, verified indoor runs may qualify without a GPS route."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .challengeCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Allow multiple attempts",
                        isOn: $allowMultipleAttempts
                    )

                    if allowMultipleAttempts {
                        Divider()

                        Text("Attempt policy")
                            .font(.subheadline.weight(.semibold))

                        Picker(
                            "Attempt policy",
                            selection: $attemptPolicy
                        ) {
                            ForEach(
                                ChallengeAttemptPolicy.allCases
                            ) { policy in
                                Text(policy.title)
                                    .tag(policy)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker(
                            "Maximum attempts",
                            selection: $attemptLimit
                        ) {
                            Text("Unlimited").tag(0)
                            Text("3").tag(3)
                            Text("5").tag(5)
                        }
                    } else {
                        Text(
                            "Only the first qualifying attempt is recorded."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .challengeCard()

                Button {
                    resetRunningAdvancedRules()
                } label: {
                    Label(
                        "Reset to Recommended",
                        systemImage: "arrow.counterclockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var routeSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let route = selectedRoute {
                if route.coordinates.count >= 2 {
                    Map(
                        initialPosition: .region(
                            challengeRegion(for: route)
                        )
                    ) {
                        MapPolyline(
                            coordinates:
                                route.coordinates.map(\.coordinate)
                        )
                        .stroke(
                            ATHLTHTheme.accent,
                            style: StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                        if let first = route.coordinates.first {
                            Marker(
                                route.startName ?? "Start",
                                coordinate: first.coordinate
                            )
                            .tint(ATHLTHTheme.accent)
                        }

                        if let last = route.coordinates.last {
                            Marker(
                                route.endName ?? "Finish",
                                coordinate: last.coordinate
                            )
                            .tint(.red)
                        }
                    }
                    .allowsHitTesting(false)
                    .frame(height: 170)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(route.title)
                        .font(.headline)

                    if let start = route.startName,
                       let end = route.endName {
                        Text("\(start) → \(end)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 12) {
                        Label(
                            String(
                                format: "%.1f km",
                                route.distanceKilometers
                            ),
                            systemImage: "figure.run"
                        )

                        if let elevation = route.elevationGainMeters {
                            Label(
                                "\(Int(elevation.rounded())) m",
                                systemImage: "mountain.2.fill"
                            )
                        }

                        Label(
                            "\(route.coordinates.count) points",
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    NavigationLink {
                        ChallengeRouteSelectionView(
                            selectedRouteID: $selectedRouteID
                        )
                    } label: {
                        Label(
                            "Change Route",
                            systemImage: "map"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        RunRouteBuilderView()
                    } label: {
                        Label(
                            "New Route",
                            systemImage: "plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose a route")
                            .font(.headline)

                        Text(
                            session.savedRoutes.isEmpty
                                ? "You do not have any saved routes yet."
                                : "Select one of your saved routes or create a new one."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    if !session.savedRoutes.isEmpty {
                        NavigationLink {
                            ChallengeRouteSelectionView(
                                selectedRouteID: $selectedRouteID
                            )
                        } label: {
                            Label(
                                "My Routes",
                                systemImage: "map"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }

                    if session.savedRoutes.isEmpty {
                        NavigationLink {
                            RunRouteBuilderView()
                        } label: {
                            Label(
                                "Create New",
                                systemImage: "plus"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    } else {
                        NavigationLink {
                            RunRouteBuilderView()
                        } label: {
                            Label(
                                "Create New",
                                systemImage: "plus"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accent)
                    }
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private var heartRateRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Heart-rate zone")
                    .font(.headline)

                HStack(spacing: 7) {
                    ForEach(1...5, id: \.self) { zone in
                        Button {
                            heartRateZone = zone
                        } label: {
                            VStack(spacing: 4) {
                                Text("Z\(zone)")
                                    .font(.subheadline.weight(.bold))
                                Text(heartRateZonePercentText(zone))
                                    .font(.system(size: 9, weight: .medium))
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(
                                heartRateZone == zone
                                    ? .white
                                    : ATHLTHTheme.primaryText
                            )
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(
                                heartRateZone == zone
                                    ? ATHLTHTheme.accent
                                    : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let maximumHeartRateBPM {
                    HStack(spacing: 11) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                "Zone \(heartRateZone) · \(heartRateZoneBPMText(zone: heartRateZone, maxHR: maximumHeartRateBPM))"
                            )
                            .font(.subheadline.weight(.semibold))

                            Text(
                                "Calculated from your private max HR of \(maximumHeartRateBPM) bpm."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .challengeCard()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Maximum heart rate required",
                            systemImage: "heart.slash"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)

                        Text(
                            "ATHLTH compares time in a personal heart-rate zone. Add your maximum heart rate before creating this challenge."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        NavigationLink {
                            PersonalHealthProfileView()
                        } label: {
                            Label(
                                "Set Maximum Heart Rate",
                                systemImage: "heart.text.square"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }
                    .padding()
                    .challengeCard()
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Leaderboard")
                    .font(.headline)

                Picker(
                    "Leaderboard",
                    selection: $heartRateAggregation
                ) {
                    ForEach(
                        ChallengeHeartRateAggregation.allCases
                    ) { aggregation in
                        Text(aggregation.title)
                            .tag(aggregation)
                    }
                }
                .pickerStyle(.segmented)

                Text(heartRateAggregation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .challengeCard()

            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(ATHLTHTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified heart-rate data only")
                        .font(.subheadline.weight(.semibold))

                    Text(
                        "Any qualifying workout can count when it contains Apple Health heart-rate samples. Manual heart-rate results are never accepted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .challengeCard()

            if advancedRules {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "Personal zones",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        "Every participant is scored against their own private maximum heart rate. ATHLTH never exposes that value to the challenge or leaderboard."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .challengeCard()
            }
        }
    }

    private var strengthRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            if scoring != .workoutVolume {
                TextField("Exercise", text: $exerciseName)
                    .textFieldStyle(.roundedBorder)
            }

            if scoring == .mostReps {
                Toggle("Require a specific weight", isOn: $requiredWeightEnabled)

                if requiredWeightEnabled {
                    numberField(
                        title: "Required weight",
                        suffix: "kg",
                        value: $requiredWeightKg
                    )
                }
            }

            if advancedRules {
                Picker(
                    "Result verification",
                    selection: $verificationPolicy
                ) {
                    ForEach(
                        ChallengeVerificationPolicy.allCases
                    ) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        verificationPolicy.title,
                        systemImage:
                            verificationPolicy ==
                                .verifiedRequired
                                ? "checkmark.seal.fill"
                                : "hand.tap.fill"
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(verificationPolicy.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .challengeCard()
            }

            Text(
                "Manual strength submissions stay clearly labelled Manual. ATHLTH-tracked sets are labelled ATHLTH Verified."
            )
            .challengeHint()
        }
    }

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who are you challenging?")
                .font(.title2.bold())

            if let route = selectedRoute {
                HStack(spacing: 10) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route Challenge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(route.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(
                        String(
                            format: "%.1f km",
                            route.distanceKilometers
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding()
                .challengeCard()
            }

            participantRow(
                name: session.profile.displayName,
                username: session.profile.username,
                state: "You · Creator"
            )

            if !invitees.isEmpty {
                Text("SELECTED")
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                ForEach(invitees) { participant in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(ATHLTHTheme.accent.opacity(0.10))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(ATHLTHTheme.accent)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(participant.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let username = participant.username, !username.isEmpty {
                                Text("@\(username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            invitees.removeAll { $0.userID == participant.userID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .challengeCard()
                }
            }

            Text("FRIENDS")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(.secondary)

            if social.friends.isEmpty {
                VStack(spacing: 10) {
                    Text("Add friends before sending a challenge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        SocialHubView(initialTab: .discover)
                    } label: {
                        Label("Find Friends", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .challengeCard()
            } else {
                ForEach(social.friends) { friend in
                    Button {
                        toggleFriend(friend)
                    } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(profile: friend, size: 42)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.resolvedName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(friend.usernameLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(
                                systemName: invitees.contains(where: { $0.userID == friend.userID })
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                invitees.contains(where: { $0.userID == friend.userID })
                                    ? ATHLTHTheme.accent
                                    : .secondary
                            )
                        }
                        .padding()
                        .challengeCard()
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Visibility", selection: $visibility) {
                Text("Friends").tag(ProfileVisibility.friends)
                Text("Private").tag(ProfileVisibility.privateOnly)
                Text("Public").tag(ProfileVisibility.publicProfile)
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When does it count?")
                .font(.title2.bold())

            DatePicker(
                "Starts",
                selection: $startsAt,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )

            Toggle("Set an end time", isOn: $hasEnd)

            if hasEnd {
                DatePicker(
                    "Ends",
                    selection: $endsAt,
                    in: startsAt...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Toggle("Meet and train together", isOn: $meetupEnabled)

            if meetupEnabled {
                TextField("Meetup name", text: $meetupPlaceName)
                    .textFieldStyle(.roundedBorder)

                DatePicker(
                    "Meet at",
                    selection: $meetupAt,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Text("Tap the map to set the meetup point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MeetupLocationPicker(
                    coordinate: $meetupCoordinate,
                    position: $mapPosition
                )

                if selectedRouteID != nil {
                    Button("Use route start") {
                        guard let routeID = selectedRouteID,
                              let route = session.savedRoutes.first(where: { $0.id == routeID }),
                              let first = route.coordinates.first
                        else {
                            return
                        }

                        let coordinate = CLLocationCoordinate2D(
                            latitude: first.latitude,
                            longitude: first.longitude
                        )
                        meetupCoordinate = coordinate
                        mapPosition = .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(
                                    latitudeDelta: 0.015,
                                    longitudeDelta: 0.015
                                )
                            )
                        )
                    }
                    .font(.caption.weight(.semibold))
                }

                Text("Check-in is explicit. ATHLTH does not continuously share participants’ live location.")
                    .challengeHint()
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to challenge")
                .font(.title2.bold())

            ChallengeReviewCard(
                title: resolvedTitle,
                sport: sport,
                scoring: effectiveScoring,
                verification:
                    sport == .running
                        ? .verifiedRequired
                        : verificationPolicy
            )

            reviewRow("Starts", startsAt.formatted(date: .abbreviated, time: .shortened))

            if hasEnd {
                reviewRow("Ends", endsAt.formatted(date: .abbreviated, time: .shortened))
            }

            reviewRow(
                "Participants",
                "\(invitees.count + 1)"
            )

            reviewRow(
                "Attempts",
                runningAttemptSummary
            )

            if sport == .running &&
                scoring == .fastestDistance {
                if let route = selectedRoute,
                   usesSpecificRoute {
                    reviewRow("Course", "Specific Route")
                    reviewRow("Route", route.title)

                    if advancedRules {
                        reviewRow(
                            "Route deviation",
                            "\(Int(allowedRouteDeviationPercent))%"
                        )
                        reviewRow(
                            "Start/finish",
                            "Within \(Int(startFinishToleranceMeters)) m"
                        )
                        reviewRow(
                            "Direction",
                            routeDirection.title
                        )
                    }
                } else {
                    reviewRow("Course", "Run Anywhere")
                    reviewRow(
                        "Distance",
                        String(
                            format:
                                "%.1f km",
                            targetDistanceKm
                        )
                    )

                    if advancedRules {
                        reviewRow(
                            "Distance tolerance",
                            "±\(distanceTolerancePercent.formatted(.number.precision(.fractionLength(0...1))))%"
                        )
                        reviewRow(
                            "Treadmill",
                            allowTreadmill
                                ? "Allowed"
                                : "Not allowed"
                        )
                    }
                }

                if advancedRules {
                    reviewRow("Timing", timeBasis.title)
                    reviewRow(
                        "GPS",
                        usesSpecificRoute || gpsRequired
                            ? "Required"
                            : "Optional"
                    )
                }
            }

            if sport == .heartRate {
                reviewRow(
                    "Zone",
                    "Zone \(heartRateZone) · \(heartRateZonePercentText(heartRateZone))"
                )
                reviewRow(
                    "Leaderboard",
                    heartRateAggregation.title
                )
                reviewRow(
                    "Verification",
                    "Verified HR samples only"
                )
            } else if sport == .running {
                reviewRow(
                    "Verification",
                    "Verified only · no manual results"
                )
            } else if sport == .strength {
                reviewRow("Verification", verificationPolicy.title)
            }

            if meetupEnabled {
                reviewRow(
                    "Meetup",
                    meetupPlaceName.isEmpty ? "Pinned location" : meetupPlaceName
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Fair-play rules", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.accent)
                Text("Only attempts inside the challenge window count. Rules lock at start. Verified and Manual strength results stay visibly different.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .challengeCard()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") {
                    withAnimation { step -= 1 }
                }
                .buttonStyle(.bordered)
            }

            Button(step == 4 ? "Create Challenge" : "Continue") {
                if step == 4 {
                    createChallenge()
                } else {
                    withAnimation { step += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
            .frame(maxWidth: .infinity)
            .disabled(!canContinue)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var scoringOptions: [ATHLTHChallengeScoring] {
        switch sport {
        case .running:
            return [.fastestDistance, .farthestInTime, .mostDistance]
        case .strength:
            return [.heaviestWeight, .mostReps, .exerciseVolume, .workoutVolume]
        case .heartRate:
            return [.heartRateZoneTime]
        }
    }

    private var stepTitle: String {
        ["Challenge", "Rules", "People", "Schedule", "Review"][step]
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return !title
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        case 1:
            if sport == .running {
                if scoring == .fastestDistance {
                    if usesSpecificRoute {
                        return selectedRouteID != nil
                    }

                    return targetDistanceKm > 0
                }

                if scoring == .farthestInTime &&
                    targetDurationMinutes <= 0 {
                    return false
                }

                return true
            }

            if sport == .heartRate {
                return maximumHeartRateBPM != nil &&
                    (1...5).contains(heartRateZone)
            }

            if scoring != .workoutVolume &&
                exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }

            return true

        case 2:
            return !invitees.isEmpty

        case 3:
            if hasEnd && endsAt <= startsAt { return false }
            if meetupEnabled && meetupCoordinate == nil { return false }
            return true

        default:
            return true
        }
    }

    private var selectedRoute: TrainingRoute? {
        guard let selectedRouteID else { return nil }
        return session.savedRoutes.first { $0.id == selectedRouteID }
    }

    private var effectiveScoring: ATHLTHChallengeScoring {
        if sport == .running &&
            scoring == .fastestDistance &&
            usesSpecificRoute {
            return .fastestRoute
        }

        return scoring
    }

    private var resolvedTitle: String {
        title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func challengeParticipant(_ friend: SocialProfileCard) -> ChallengeParticipant {
        ChallengeParticipant(
            userID: friend.userID,
            username: friend.username,
            displayName: friend.resolvedName,
            state: .invited
        )
    }

    private func toggleFriend(_ friend: SocialProfileCard) {
        if invitees.contains(where: { $0.userID == friend.userID }) {
            invitees.removeAll { $0.userID == friend.userID }
        } else {
            invitees.append(challengeParticipant(friend))
        }
    }

    private func createChallenge() {
        let creator = ChallengeParticipant(
            userID: session.profile.userID,
            username: session.profile.username,
            displayName: session.profile.displayName,
            state: .creator
        )

        let routeSnapshot = selectedRoute.map {
            ChallengeRouteSnapshot(
                routeID: $0.id,
                title: $0.title,
                distanceKilometers: $0.distanceKilometers,
                coordinates: $0.coordinates
            )
        }

        let meetup: ChallengeMeetup?
        if meetupEnabled, let meetupCoordinate {
            meetup = ChallengeMeetup(
                placeName: meetupPlaceName.isEmpty
                    ? "Meetup point"
                    : meetupPlaceName,
                latitude: meetupCoordinate.latitude,
                longitude: meetupCoordinate.longitude,
                scheduledAt: meetupAt,
                checkInRadiusMeters: 150
            )
        } else {
            meetup = nil
        }

        let rules = ATHLTHChallengeRules(
            scoring: effectiveScoring,
            verificationPolicy:
                sport == .strength
                    ? verificationPolicy
                    : .verifiedRequired,
            targetDistanceMeters:
                scoring == .fastestDistance &&
                !usesSpecificRoute
                    ? targetDistanceKm * 1_000
                    : nil,
            targetDurationSeconds: scoring == .farthestInTime
                ? targetDurationMinutes * 60
                : nil,
            timeBasis: timeBasis,
            route: routeSnapshot,
            gpsRequired:
                usesSpecificRoute ? true : gpsRequired,
            minimumRouteMatchPercent:
                usesSpecificRoute
                    ? routeMatchPercent
                    : nil,
            distanceTolerancePercent:
                sport == .running &&
                scoring == .fastestDistance &&
                !usesSpecificRoute
                    ? distanceTolerancePercent
                    : nil,
            startFinishToleranceMeters:
                sport == .running &&
                usesSpecificRoute
                    ? startFinishToleranceMeters
                    : nil,
            routeDirection:
                sport == .running &&
                usesSpecificRoute
                    ? routeDirection
                    : nil,
            attemptPolicy:
                sport == .running
                    ? (allowMultipleAttempts
                        ? attemptPolicy
                        : .first)
                    : nil,
            maximumAttempts:
                sport == .running
                    ? (allowMultipleAttempts
                        ? (attemptLimit == 0
                            ? nil
                            : attemptLimit)
                        : 1)
                    : nil,
            allowTreadmill:
                sport == .running &&
                !usesSpecificRoute
                    ? allowTreadmill
                    : nil,
            exerciseName: sport == .strength && scoring != .workoutVolume
                ? exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            fixedWeightKilograms: sport == .strength &&
                scoring == .mostReps &&
                requiredWeightEnabled
                ? requiredWeightKg
                : nil,
            heartRateZone:
                sport == .heartRate
                    ? heartRateZone
                    : nil,
            heartRateAggregation:
                sport == .heartRate
                    ? heartRateAggregation
                    : nil,
            startsAt: startsAt,
            endsAt: hasEnd ? endsAt : nil,
            allowMultipleAttempts: allowMultipleAttempts,
            lockRulesAtStart: true,
            meetup: meetup
        )

        challenges.add(
            ATHLTHChallenge(
                creatorID: session.profile.userID,
                title: resolvedTitle,
                sport: sport,
                participants: [creator] + invitees,
                rules: rules,
                visibility: visibility
            )
        )

        dismiss()
    }

    private var runningAttemptSummary: String {
        guard sport == .running else {
            return allowMultipleAttempts
                ? "Multiple · best counts"
                : "One"
        }

        guard allowMultipleAttempts else {
            return "One · first counts"
        }

        let limitText =
            attemptLimit == 0
                ? "Unlimited"
                : "Max \(attemptLimit)"

        return "\(limitText) · \(attemptPolicy.shortTitle)"
    }

    private var distanceToleranceDescription: String {
        let target = targetDistanceKm
        let tolerance =
            target * distanceTolerancePercent / 100
        let lower = max(target - tolerance, 0)
        let upper = target + tolerance

        return String(
            format:
                "A %.1f km challenge accepts approximately %.2f–%.2f km.",
            target,
            lower,
            upper
        )
    }

    private func resetRunningAdvancedRules() {
        timeBasis = .elapsed
        distanceTolerancePercent = 2
        routeMatchPercent = 90
        startFinishToleranceMeters = 100
        routeDirection = .sameDirection
        allowMultipleAttempts = true
        attemptPolicy = .best
        attemptLimit = 0
        allowTreadmill = false

        if usesSpecificRoute {
            gpsRequired = true
        } else {
            gpsRequired = true
        }
    }

    private var maximumHeartRateBPM: Int? {
        session.onboardingProfile?.maximumHeartRateBPM
    }

    private func heartRateZonePercentText(
        _ zone: Int
    ) -> String {
        switch zone {
        case 1: return "50–60%"
        case 2: return "60–70%"
        case 3: return "70–80%"
        case 4: return "80–90%"
        default: return "90%+"
        }
    }

    private func heartRateZoneBPMText(
        zone: Int,
        maxHR: Int
    ) -> String {
        let lowerFactor: Double
        let upperFactor: Double

        switch zone {
        case 1:
            lowerFactor = 0.50
            upperFactor = 0.60
        case 2:
            lowerFactor = 0.60
            upperFactor = 0.70
        case 3:
            lowerFactor = 0.70
            upperFactor = 0.80
        case 4:
            lowerFactor = 0.80
            upperFactor = 0.90
        default:
            lowerFactor = 0.90
            upperFactor = 1.00
        }

        let lower = Int(
            ceil(Double(maxHR) * lowerFactor)
        )
        let upper = Int(
            floor(Double(maxHR) * upperFactor)
        )

        return "\(lower)–\(upper) bpm"
    }

    private var allowedRouteDeviationPercent: Double {
        max(0, 100 - routeMatchPercent)
    }

    private var allowedRouteDeviationBinding:
        Binding<Double> {
        Binding(
            get: {
                allowedRouteDeviationPercent
            },
            set: { newValue in
                routeMatchPercent =
                    max(80, min(98, 100 - newValue))
            }
        )
    }

    private func routeRequirementButton(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title3)

                Text(title)
                    .font(.subheadline.weight(.bold))

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(
                        selected
                            ? Color.white.opacity(0.80)
                            : .secondary
                    )
            }
            .foregroundStyle(
                selected ? .white : .primary
            )
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                selected
                    ? ATHLTHTheme.accent
                    : Color(
                        .secondarySystemGroupedBackground
                    ),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .opacity(disabled ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func challengeRegion(
        for route: TrainingRoute
    ) -> MKCoordinateRegion {
        let coordinates =
            route.coordinates.map(\.coordinate)

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 59.91,
                    longitude: 10.75
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.08,
                    longitudeDelta: 0.08
                )
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        let minLatitude =
            latitudes.min() ?? first.latitude
        let maxLatitude =
            latitudes.max() ?? first.latitude
        let minLongitude =
            longitudes.min() ?? first.longitude
        let maxLongitude =
            longitudes.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude:
                    (minLatitude + maxLatitude) / 2,
                longitude:
                    (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    (maxLatitude - minLatitude) * 1.35,
                    0.01
                ),
                longitudeDelta: max(
                    (maxLongitude - minLongitude) * 1.35,
                    0.01
                )
            )
        )
    }

    private func sportButton(_ option: ATHLTHChallengeSport) -> some View {
        Button {
            sport = option
        } label: {
            VStack(spacing: 9) {
                Image(systemName: option.systemImage)
                    .font(.title2)
                Text(option.title)
                    .font(.headline)
            }
            .foregroundStyle(sport == option ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                sport == option ? ATHLTHTheme.accent : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
    }

    private func numberField(
        title: String,
        suffix: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                "0",
                value: value,
                format: .number.precision(.fractionLength(0...3))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)

            Text(suffix)
                .foregroundStyle(.secondary)
        }
        .padding()
        .challengeCard()
    }

    private func participantRow(
        name: String,
        username: String,
        state: String
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ATHLTHTheme.accent.opacity(0.10))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(ATHLTHTheme.accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                if !username.isEmpty && name != "@\(username)" {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(state)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .challengeCard()
    }

    private func scoringSubtitle(_ scoring: ATHLTHChallengeScoring) -> String {
        switch scoring {
        case .fastestDistance:
            return "Fastest qualifying time wins. Choose your course setup in the next step."
        case .farthestInTime:
            return "Choose a time window. Furthest verified distance wins."
        case .mostDistance:
            return "Every qualifying run adds to the total."
        case .fastestRoute:
            return "Fastest qualifying time on a specific route."
        case .heaviestWeight:
            return "Highest qualifying completed set wins."
        case .mostReps:
            return "Most reps, optionally at a required weight."
        case .exerciseVolume:
            return "Highest reps × weight volume for one exercise."
        case .workoutVolume:
            return "Highest total volume in one strength workout."
        case .heartRateZoneTime:
            return "Compete on verified time spent in a personal heart-rate zone."
        }
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct ChallengeRouteSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    @Binding var selectedRouteID: UUID?

    var body: some View {
        List {
            if session.savedRoutes.isEmpty {
                ContentUnavailableView(
                    "No saved routes",
                    systemImage: "map",
                    description: Text(
                        "Create a route first, then return here to use it in the challenge."
                    )
                )
            } else {
                Section("My Routes") {
                    ForEach(session.savedRoutes) { route in
                        Button {
                            selectedRouteID = route.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill")
                                    .foregroundStyle(
                                        ATHLTHTheme.accent
                                    )
                                    .frame(width: 34)

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(route.title)
                                        .font(
                                            .subheadline
                                                .weight(.semibold)
                                        )
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 8) {
                                        Text(
                                            String(
                                                format:
                                                    "%.1f km",
                                                route
                                                    .distanceKilometers
                                            )
                                        )

                                        if let elevation =
                                            route
                                                .elevationGainMeters {
                                            Text(
                                                "· \(Int(elevation.rounded())) m ↑"
                                            )
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        selectedRouteID ==
                                            route.id
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                                .foregroundStyle(
                                    selectedRouteID ==
                                        route.id
                                        ? ATHLTHTheme.accent
                                        : .secondary
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label(
                        "Create New Route",
                        systemImage: "plus.circle.fill"
                    )
                }
            }
        }
        .navigationTitle("Choose Route")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MeetupLocationPicker: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var position: MapCameraPosition

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let coordinate {
                    Marker("Meet here", coordinate: coordinate)
                        .tint(ATHLTHTheme.accent)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture { point in
                if let location = proxy.convert(point, from: .local) {
                    coordinate = location
                }
            }
        }
    }
}

private struct ChallengeReviewCard: View {
    let title: String
    let sport: ATHLTHChallengeSport
    let scoring: ATHLTHChallengeScoring
    let verification: ChallengeVerificationPolicy

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: {
                    switch sport {
                    case .running:
                        return [
                            ATHLTHTheme.accent.opacity(0.90),
                            .black
                        ]
                    case .strength:
                        return [
                            .orange.opacity(0.80),
                            .black
                        ]
                    case .heartRate:
                        return [
                            .pink.opacity(0.88),
                            .red.opacity(0.72),
                            .black
                        ]
                    }
                }(),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(.white.opacity(0.10))
                .frame(width: 160, height: 115)
                .offset(x: 190, y: -30)

            VStack(alignment: .leading, spacing: 6) {
                Label("ATHLTH CHALLENGE", systemImage: sport.systemImage)
                    .font(.caption2.bold())
                    .tracking(1.2)

                Text(title)
                    .font(.title2.bold())

                Text("\(scoring.title) · \(verification.title)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
            }
            .foregroundStyle(.white)
            .padding()
        }
        .frame(height: 175)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct ChallengeDetailView: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @StateObject private var locationStore = ChallengeLocationStore()

    let challengeID: UUID

    @State private var showingManualStrengthAttempt = false
    @State private var showingCancel = false

    private var challenge: ATHLTHChallenge? {
        challenges.challenge(id: challengeID)
    }

    private var currentParticipant: ChallengeParticipant? {
        challenge?.participants.first {
            $0.userID == session.profile.userID
        }
    }

    var body: some View {
        Group {
            if let challenge {
                ScrollView {
                    VStack(spacing: 18) {
                        detailHero(challenge)

                        if currentParticipant?.state == .invited {
                            invitationResponseCard(challenge)
                        }

                        if challenge.sport == .heartRate &&
                            session.onboardingProfile?.maximumHeartRateBPM == nil {
                            heartRateProfileRequiredCard
                        }

                        leaderboardCard(challenge)
                        rulesCard(challenge)

                        if let meetup = challenge.rules.meetup {
                            meetupCard(challenge, meetup: meetup)
                        }

                        participantsCard(challenge)
                        attemptsCard(challenge)

                        if challenge.sport == .strength,
                           challenge.rules.verificationPolicy.allowsManual,
                           challenge.status == .active {
                            Button {
                                showingManualStrengthAttempt = true
                            } label: {
                                Label("Submit Manual Strength Result", systemImage: "hand.tap.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accent)
                        }

                        if challenge.creatorID == session.profile.userID &&
                           challenge.status != .completed &&
                           challenge.status != .cancelled {
                            Button("Cancel Challenge", role: .destructive) {
                                showingCancel = true
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Challenge")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    challenges.refreshStatuses()

                    if challenge.sport == .heartRate,
                       let maxHR =
                        session.onboardingProfile?.maximumHeartRateBPM {
                        await challenges.syncHeartRateHealthWorkouts(
                            health: health,
                            userID: session.profile.userID,
                            displayName: session.profile.displayName,
                            maximumHeartRateBPM: maxHR
                        )
                    }
                }
                .onChange(
                    of: session.onboardingProfile?.maximumHeartRateBPM
                ) { _, maxHR in
                    guard challenge.sport == .heartRate,
                          let maxHR
                    else {
                        return
                    }

                    Task {
                        await challenges.syncHeartRateHealthWorkouts(
                            health: health,
                            userID: session.profile.userID,
                            displayName: session.profile.displayName,
                            maximumHeartRateBPM: maxHR
                        )
                    }
                }
                .sheet(isPresented: $showingManualStrengthAttempt) {
                    if let currentParticipant {
                        ManualStrengthAttemptView(
                            challengeID: challenge.id,
                            participant: currentParticipant
                        )
                    }
                }
                .confirmationDialog(
                    "Cancel this challenge?",
                    isPresented: $showingCancel,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Challenge", role: .destructive) {
                        challenges.cancel(challenge.id)
                    }
                    Button("Keep Challenge", role: .cancel) {}
                }
            } else {
                ContentUnavailableView(
                    "Challenge unavailable",
                    systemImage: "person.2.slash"
                )
            }
        }
    }

    private var heartRateProfileRequiredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Set your maximum heart rate",
                systemImage: "heart.text.square"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text(
                "This challenge uses personal heart-rate zones. Your max HR stays private and is used only to calculate your own zone boundaries."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            NavigationLink {
                PersonalHealthProfileView()
            } label: {
                Text("Open Health Profile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
        }
        .padding()
        .challengeCard()
    }

    private func invitationResponseCard(_ challenge: ATHLTHChallenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You’ve been challenged")
                .font(.headline)

            Text("Accept to join the leaderboard. Declining removes you from active competition.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Decline") {
                    guard let currentParticipant else { return }
                    challenges.setParticipantState(
                        challengeID: challenge.id,
                        participantID: currentParticipant.id,
                        state: .declined
                    )
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Accept Challenge") {
                    guard let currentParticipant else { return }
                    challenges.setParticipantState(
                        challengeID: challenge.id,
                        participantID: currentParticipant.id,
                        state: .accepted
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .challengeCard()
    }

    private func detailHero(_ challenge: ATHLTHChallenge) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: {
                    switch challenge.sport {
                    case .running:
                        return [
                            ATHLTHTheme.accent.opacity(0.95),
                            .black
                        ]
                    case .strength:
                        return [
                            .orange.opacity(0.86),
                            .black
                        ]
                    case .heartRate:
                        return [
                            .pink.opacity(0.92),
                            .red.opacity(0.70),
                            .black
                        ]
                    }
                }(),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(.white.opacity(0.09))
                .frame(width: 220, height: 160)
                .rotationEffect(.degrees(-12))
                .offset(x: 160, y: -55)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ATHLTH CHALLENGE")
                        .font(.caption2.bold())
                        .tracking(1.5)

                    Spacer()

                    if challenge.rulesAreLocked {
                        Label("LOCKED", systemImage: "lock.fill")
                            .font(.caption2.bold())
                    }
                }

                Spacer()

                Text(challenge.title)
                    .font(.system(size: 31, weight: .bold))
                    .lineLimit(2)

                HStack {
                    Label(challenge.rules.scoring.title, systemImage: challenge.sport.systemImage)
                    Spacer()
                    Text(timeText(challenge))
                }
                .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 235)
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func leaderboardCard(_ challenge: ATHLTHChallenge) -> some View {
        let board = challenges.leaderboard(for: challenge.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Leaderboard")
                    .font(.title3.bold())
                Spacer()
                Text("\(board.count) competitors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(board) { entry in
                HStack(spacing: 12) {
                    Text(entry.rank.map { "#\($0)" } ?? "—")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(entry.rank == 1 ? ATHLTHTheme.accent : .secondary)
                        .frame(width: 34)

                    Circle()
                        .fill(ATHLTHTheme.accent.opacity(0.10))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Text(entry.participant.displayName.prefix(1).uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(ATHLTHTheme.accent)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.participant.displayName)
                            .font(.subheadline.weight(.semibold))

                        if let attempt = entry.bestAttempt {
                            HStack(spacing: 5) {
                                Label(
                                    attempt.verification.title,
                                    systemImage: attempt.verification.systemImage
                                )
                                if entry.attemptCount > 1 {
                                    Text("· \(entry.attemptCount) attempts")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(
                                attempt.verification == .manual
                                    ? .orange
                                    : ATHLTHTheme.accent
                            )
                        } else {
                            Text("No result yet")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(leaderboardValue(entry, challenge: challenge))
                        .font(.headline.monospacedDigit())
                }
                .padding(.vertical, 4)

                if entry.id != board.last?.id {
                    Divider().opacity(0.45)
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private func rulesCard(_ challenge: ATHLTHChallenge) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Rules")
                    .font(.headline)
                Spacer()
                Label(
                    challenge.rulesAreLocked ? "Locked" : "Locks at start",
                    systemImage: challenge.rulesAreLocked ? "lock.fill" : "lock.open.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            ruleRow("Scoring", challenge.rules.scoring.title)
            ruleRow("Verification", challenge.rules.verificationPolicy.title)

            if let target = challenge.rules.targetDistanceMeters {
                ruleRow("Distance", String(format: "%.2f km", target / 1_000))
            }

            if let duration = challenge.rules.targetDurationSeconds {
                ruleRow("Time", challengeDuration(duration))
            }

            if let route = challenge.rules.route {
                ruleRow("Route", route.title)
                ruleRow(
                    "Match required",
                    "\(Int(challenge.rules.minimumRouteMatchPercent ?? 90))%"
                )

                if let tolerance =
                    challenge.rules.startFinishToleranceMeters {
                    ruleRow(
                        "Start/finish",
                        "Within \(Int(tolerance)) m"
                    )
                }

                if let direction =
                    challenge.rules.routeDirection {
                    ruleRow(
                        "Direction",
                        direction.title
                    )
                }
            } else if challenge.sport == .running {
                ruleRow("Course", "Run Anywhere")

                if let tolerance =
                    challenge.rules.distanceTolerancePercent,
                   challenge.rules.scoring == .fastestDistance {
                    ruleRow(
                        "Distance tolerance",
                        "±\(tolerance.formatted(.number.precision(.fractionLength(0...1))))%"
                    )
                }

                if let allowTreadmill =
                    challenge.rules.allowTreadmill {
                    ruleRow(
                        "Treadmill",
                        allowTreadmill
                            ? "Allowed"
                            : "Not allowed"
                    )
                }
            }

            if challenge.sport == .running {
                ruleRow(
                    "Timing",
                    challenge.rules.timeBasis.title
                )
                ruleRow(
                    "GPS",
                    challenge.rules.gpsRequired
                        ? "Required"
                        : "Optional"
                )

                let attemptPolicy =
                    challenge.rules.attemptPolicy ??
                    .best
                let maxAttempts =
                    challenge.rules.maximumAttempts

                if challenge.rules.allowMultipleAttempts {
                    ruleRow(
                        "Attempt policy",
                        attemptPolicy.title
                    )
                    ruleRow(
                        "Attempt limit",
                        maxAttempts.map(String.init)
                            ?? "Unlimited"
                    )
                } else {
                    ruleRow("Attempts", "One")
                }
            }

            if challenge.sport == .heartRate {
                let zone = min(
                    max(challenge.rules.heartRateZone ?? 5, 1),
                    5
                )
                ruleRow("Zone", "Zone \(zone)")
                ruleRow(
                    "Zone range",
                    challengeHeartRateZonePercentText(zone)
                )
                ruleRow(
                    "Leaderboard",
                    (
                        challenge.rules.heartRateAggregation ??
                        .totalChallenge
                    ).title
                )
                ruleRow(
                    "Heart-rate source",
                    "Verified Apple Health"
                )
            }

            if let exercise = challenge.rules.exerciseName {
                ruleRow("Exercise", exercise)
            }

            if let required = challenge.rules.fixedWeightKilograms {
                ruleRow("Required weight", String(format: "%.1f kg", required))
            }

            ruleRow("Starts", challenge.rules.startsAt.formatted(date: .abbreviated, time: .shortened))

            if let endsAt = challenge.rules.endsAt {
                ruleRow("Ends", endsAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding()
        .challengeCard()
    }

    private func meetupCard(
        _ challenge: ATHLTHChallenge,
        meetup: ChallengeMeetup
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Meet & Train", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                Text(meetup.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(meetup.placeName)
                .font(.title3.weight(.semibold))

            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: meetup.latitude,
                            longitude: meetup.longitude
                        ),
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.012,
                            longitudeDelta: 0.012
                        )
                    )
                )
            ) {
                Marker(
                    meetup.placeName,
                    coordinate: CLLocationCoordinate2D(
                        latitude: meetup.latitude,
                        longitude: meetup.longitude
                    )
                )
                .tint(ATHLTHTheme.accent)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let participant = currentParticipant {
                let checkIn = challenge.checkIns.first {
                    $0.participantID == participant.id
                }

                if let checkIn {
                    Label(
                        checkIn.verifiedNearMeetup
                            ? "Checked in · location verified"
                            : "Checked in",
                        systemImage: checkIn.verifiedNearMeetup
                            ? "checkmark.seal.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                } else {
                    Button {
                        Task {
                            let location = await locationStore.requestCurrentLocation()
                            challenges.checkIn(
                                challengeID: challenge.id,
                                participantID: participant.id,
                                currentLocation: location
                            )
                        }
                    } label: {
                        HStack {
                            if locationStore.isLocating {
                                ProgressView()
                                    .tint(.white)
                            }
                            Label(
                                locationStore.isLocating ? "Checking location…" : "I'm here",
                                systemImage: "mappin.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .disabled(locationStore.isLocating)
                }
            }

            if let error = locationStore.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text("Check-in is explicit. ATHLTH requests a one-time location only when you press “I'm here”; it does not continuously expose your live location to other participants.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .challengeCard()
    }

    private func participantsCard(_ challenge: ATHLTHChallenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Participants")
                .font(.headline)

            ForEach(challenge.participants) { participant in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(participant.displayName)
                            .font(.subheadline.weight(.semibold))
                        if let username = participant.username {
                            Text("@\(username)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(participantState(participant.state))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            participant.state == .accepted ||
                            participant.state == .creator
                                ? ATHLTHTheme.accent
                                : .secondary
                        )
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private func attemptsCard(_ challenge: ATHLTHChallenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attempts")
                .font(.headline)

            if challenge.attempts.isEmpty {
                Text("No attempts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(challenge.attempts.sorted { $0.submittedAt > $1.submittedAt }.prefix(10)) { attempt in
                    HStack(alignment: .top, spacing: 10) {
                        Image(
                            systemName: attempt.isEligible
                                ? attempt.verification.systemImage
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            attempt.isEligible
                                ? (attempt.verification == .manual ? .orange : ATHLTHTheme.accent)
                                : .orange
                        )
                        .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(attempt.participantName)
                                    .font(.subheadline.weight(.semibold))
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(attempt.verification.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(
                                        attempt.verification == .manual
                                            ? .orange
                                            : ATHLTHTheme.accent
                                    )
                            }

                            Text(attempt.detail)
                                .font(.caption)

                            if let reason = attempt.ineligibilityReason {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            if let match = attempt.routeMatchPercent {
                                Text("Route match \(match, specifier: "%.0f")%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(attempt.submittedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider().opacity(0.45)
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private func leaderboardValue(
        _ entry: ChallengeLeaderboardEntry,
        challenge: ATHLTHChallenge
    ) -> String {
        guard let score = entry.score else { return "—" }

        switch challenge.rules.scoring {
        case .fastestDistance, .fastestRoute:
            return challengeDuration(score)
        case .farthestInTime, .mostDistance:
            return String(format: "%.2f km", score / 1_000)
        case .heaviestWeight:
            return String(format: "%.1f kg", score)
        case .mostReps:
            return "\(Int(score.rounded())) reps"
        case .exerciseVolume, .workoutVolume:
            return String(format: "%.0f kg", score)
        case .heartRateZoneTime:
            return challengeDuration(score)
        }
    }

    private func challengeHeartRateZonePercentText(
        _ zone: Int
    ) -> String {
        switch zone {
        case 1: return "50–60% of personal max HR"
        case 2: return "60–70% of personal max HR"
        case 3: return "70–80% of personal max HR"
        case 4: return "80–90% of personal max HR"
        default: return "90%+ of personal max HR"
        }
    }

    private func ruleRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func timeText(_ challenge: ATHLTHChallenge) -> String {
        if challenge.status == .active, let end = challenge.rules.endsAt {
            return end.formatted(.relative(presentation: .named))
        }

        if challenge.status == .upcoming || challenge.status == .invited {
            return "Starts " + challenge.rules.startsAt.formatted(date: .abbreviated, time: .shortened)
        }

        return challenge.status.rawValue.capitalized
    }

    private func participantState(_ state: ChallengeParticipantState) -> String {
        switch state {
        case .creator: return "Creator"
        case .invited: return "Invited"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        }
    }
}

struct ManualStrengthAttemptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var challenges: ChallengeStore

    let challengeID: UUID
    let participant: ChallengeParticipant

    @State private var weightKg = 0.0
    @State private var reps = 0
    @State private var volumeKg = 0.0
    @State private var note = ""
    @State private var error: String?

    private var challenge: ATHLTHChallenge? {
        challenges.challenge(id: challengeID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let challenge {
                    Section("Result") {
                        switch challenge.rules.scoring {
                        case .heaviestWeight:
                            numericField(
                                title: "Weight",
                                suffix: "kg",
                                value: $weightKg
                            )
                            Stepper(
                                "Reps: \(reps)",
                                value: $reps,
                                in: 0...200
                            )

                        case .mostReps:
                            if let fixed = challenge.rules.fixedWeightKilograms {
                                LabeledContent("Required weight") {
                                    Text("\(fixed, specifier: "%.1f") kg")
                                }
                            } else {
                                numericField(
                                    title: "Weight",
                                    suffix: "kg",
                                    value: $weightKg
                                )
                            }

                            Stepper(
                                "Reps: \(reps)",
                                value: $reps,
                                in: 0...500
                            )

                        case .exerciseVolume, .workoutVolume:
                            numericField(
                                title: "Total volume",
                                suffix: "kg",
                                value: $volumeKg
                            )

                        default:
                            EmptyView()
                        }
                    }

                    Section("Manual verification") {
                        Label("Manual result", systemImage: "hand.tap.fill")
                            .foregroundStyle(.orange)

                        Text("This attempt will be visible in the leaderboard with a Manual label.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Note or context (optional)", text: $note, axis: .vertical)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Submit Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submit()
                    }
                }
            }
        }
    }

    private func numericField(
        title: String,
        suffix: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                "0",
                value: value,
                format: .number.precision(.fractionLength(0...2))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }

    private var effectiveWeight: Double? {
        guard let challenge else {
            return weightKg > 0 ? weightKg : nil
        }

        if challenge.rules.scoring == .mostReps,
           let fixed = challenge.rules.fixedWeightKilograms {
            return fixed
        }

        return weightKg > 0 ? weightKg : nil
    }

    private func submit() {
        do {
            try challenges.submitManualStrengthAttempt(
                challengeID: challengeID,
                participantID: participant.id,
                participantName: participant.displayName,
                weightKilograms: effectiveWeight,
                reps: reps > 0 ? reps : nil,
                volumeKilograms: volumeKg > 0 ? volumeKg : nil,
                note: note
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private func challengeDuration(_ value: TimeInterval) -> String {
    let seconds = max(Int(value.rounded()), 0)
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remaining = seconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remaining)
    }

    return String(format: "%d:%02d", minutes, remaining)
}

private extension View {
    func challengeCard() -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }

    func challengeHint() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTheme.accent.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 14)
            )
    }
}

private extension Double {
    var cleanChallengeNumber: String {
        if abs(self - rounded()) < 0.001 {
            return String(Int(rounded()))
        }
        return String(format: "%.1f", self)
    }
}
