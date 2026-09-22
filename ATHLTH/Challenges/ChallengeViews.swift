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
                        .foregroundStyle(.green)
                }

                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .frame(width: 32, height: 32)
                        .background(.green.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if highlighted.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 42, height: 42)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

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
                .foregroundStyle(.green)
                .frame(width: 40, height: 40)
                .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))

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
            Color.green.opacity(0.035),
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
    @State private var showingCreate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ATHLTH Challenges")
                            .font(.largeTitle.bold())
                        Text("Head-to-head, groups, routes and strength.")
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
                            .background(.green.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if challenges.visibleChallenges.isEmpty {
                    ContentUnavailableView(
                        "No challenges yet",
                        systemImage: "figure.run.circle",
                        description: Text("Create a running or strength challenge and invite one or more friends.")
                    )
                    .padding(.vertical, 50)
                } else {
                    let current = challenges.visibleChallenges.filter {
                        $0.status != .completed && $0.status != .cancelled
                    }
                    let finished = challenges.visibleChallenges.filter {
                        $0.status == .completed || $0.status == .cancelled
                    }

                    if !current.isEmpty {
                        sectionTitle("Current")
                        ForEach(current) { challenge in
                            NavigationLink {
                                ChallengeDetailView(challengeID: challenge.id)
                            } label: {
                                ChallengeHeroCard(challenge: challenge)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !finished.isEmpty {
                        sectionTitle("History")
                        ForEach(finished) { challenge in
                            NavigationLink {
                                ChallengeDetailView(challengeID: challenge.id)
                            } label: {
                                ChallengeCompactRow(challenge: challenge)
                                    .padding()
                                    .background(
                                        Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 20)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            challenges.refreshStatuses()
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
}

struct ChallengeHeroCard: View {
    let challenge: ATHLTHChallenge

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: challenge.sport == .running
                    ? [.green.opacity(0.92), .black.opacity(0.90)]
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

    init(preselectedFriends: [SocialProfileCard] = []) {
        self.preselectedFriends = preselectedFriends
    }

    @State private var step = 0
    @State private var sport: ATHLTHChallengeSport = .running
    @State private var scoring: ATHLTHChallengeScoring = .fastestDistance
    @State private var title = ""

    @State private var targetDistanceKm = 5.0
    @State private var targetDurationMinutes = 60.0
    @State private var timeBasis: ChallengeTimeBasis = .elapsed
    @State private var selectedRouteID: UUID?
    @State private var gpsRequired = true
    @State private var routeMatchPercent = 90.0

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
                    .tint(.green)
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
            .navigationTitle("Create Challenge")
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
                if newSport == .running {
                    scoring = .fastestDistance
                    verificationPolicy = .verifiedRequired
                } else {
                    scoring = .heaviestWeight
                    verificationPolicy = .verifiedPreferredManualAllowed
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
            Text("What are you competing in?")
                .font(.title2.bold())

            HStack(spacing: 12) {
                sportButton(.running)
                sportButton(.strength)
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

                        Image(systemName: scoring == option ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(scoring == option ? .green : .secondary)
                    }
                    .padding()
                    .challengeCard()
                }
                .buttonStyle(.plain)
            }

            TextField("Challenge title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set the rules")
                .font(.title2.bold())

            if sport == .running {
                runningRules
            } else {
                strengthRules
            }

            Toggle("Allow multiple attempts", isOn: $allowMultipleAttempts)

            VStack(alignment: .leading, spacing: 7) {
                Label("Rules lock when the challenge starts", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Once live, target, route, verification and scoring cannot be changed.")
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
                numberField(
                    title: "Distance",
                    suffix: "km",
                    value: $targetDistanceKm
                )
            }

            if scoring == .farthestInTime {
                numberField(
                    title: "Time",
                    suffix: "min",
                    value: $targetDurationMinutes
                )
            }

            if scoring == .fastestDistance || scoring == .fastestRoute {
                Picker("Timing", selection: $timeBasis) {
                    ForEach(ChallengeTimeBasis.allCases) { basis in
                        Text(basis.title).tag(basis)
                    }
                }
                .pickerStyle(.segmented)
            }

            Picker("Route", selection: $selectedRouteID) {
                Text("Any route").tag(nil as UUID?)
                ForEach(session.savedRoutes) { route in
                    Text("\(route.title) · \(route.distanceKilometers, specifier: "%.1f") km")
                        .tag(route.id as UUID?)
                }
            }

            if selectedRouteID != nil {
                Toggle("GPS required", isOn: $gpsRequired)
                    .disabled(true)

                HStack {
                    Text("Minimum route match")
                    Spacer()
                    Text("\(Int(routeMatchPercent))%")
                        .font(.subheadline.bold())
                }

                Slider(value: $routeMatchPercent, in: 80...98, step: 1)
            } else {
                Toggle("Require GPS verification", isOn: $gpsRequired)
            }

            Picker("Verification", selection: $verificationPolicy) {
                Text("Verified required")
                    .tag(ChallengeVerificationPolicy.verifiedRequired)
                Text("Manual allowed")
                    .tag(ChallengeVerificationPolicy.verifiedPreferredManualAllowed)
            }

            Text("For competitive running, ATHLTH recommends Verified required. Manual results are clearly marked if you choose to allow them.")
                .challengeHint()
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

            Picker("Result verification", selection: $verificationPolicy) {
                ForEach(ChallengeVerificationPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(
                    verificationPolicy.title,
                    systemImage: verificationPolicy == .verifiedRequired
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

            Text("Manual strength submissions are always labelled Manual in the leaderboard. ATHLTH-tracked sets are labelled ATHLTH Verified.")
                .challengeHint()
        }
    }

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who are you challenging?")
                .font(.title2.bold())

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
                            .fill(.green.opacity(0.10))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.green)
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
                    .tint(.green)
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
                                    ? .green
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
                scoring: scoring,
                verification: verificationPolicy
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
                allowMultipleAttempts ? "Multiple · best counts" : "One"
            )

            if let route = selectedRoute {
                reviewRow("Route", route.title)
                reviewRow("Route match", "≥ \(Int(routeMatchPercent))%")
            } else if sport == .running {
                reviewRow("Route", "Anywhere")
            }

            if sport == .strength {
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
                    .foregroundStyle(.green)
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
            .tint(.green)
            .frame(maxWidth: .infinity)
            .disabled(!canContinue)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var scoringOptions: [ATHLTHChallengeScoring] {
        switch sport {
        case .running:
            return [.fastestDistance, .farthestInTime, .mostDistance, .fastestRoute]
        case .strength:
            return [.heaviestWeight, .mostReps, .exerciseVolume, .workoutVolume]
        }
    }

    private var stepTitle: String {
        ["Type", "Rules", "People", "Schedule", "Review"][step]
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return true
        case 1:
            if sport == .running {
                if scoring == .fastestDistance && targetDistanceKm <= 0 { return false }
                if scoring == .farthestInTime && targetDurationMinutes <= 0 { return false }
                if scoring == .fastestRoute && selectedRouteID == nil { return false }
                return true
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

    private var resolvedTitle: String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }

        switch scoring {
        case .fastestDistance:
            return "Fastest \(targetDistanceKm.cleanChallengeNumber)K"
        case .farthestInTime:
            return "Farthest in \(targetDurationMinutes.cleanChallengeNumber) min"
        case .mostDistance:
            return "Most Distance"
        case .fastestRoute:
            return selectedRoute.map { "Fastest · \($0.title)" } ?? "Route Challenge"
        case .heaviestWeight:
            return "Heaviest \(exerciseName)"
        case .mostReps:
            return "Most Reps · \(exerciseName)"
        case .exerciseVolume:
            return "\(exerciseName) Volume"
        case .workoutVolume:
            return "Workout Volume"
        }
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
            scoring: scoring,
            verificationPolicy: verificationPolicy,
            targetDistanceMeters: scoring == .fastestDistance
                ? targetDistanceKm * 1_000
                : nil,
            targetDurationSeconds: scoring == .farthestInTime
                ? targetDurationMinutes * 60
                : nil,
            timeBasis: timeBasis,
            route: routeSnapshot,
            gpsRequired: selectedRouteID != nil ? true : gpsRequired,
            minimumRouteMatchPercent: selectedRouteID != nil
                ? routeMatchPercent
                : nil,
            exerciseName: sport == .strength && scoring != .workoutVolume
                ? exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            fixedWeightKilograms: sport == .strength &&
                scoring == .mostReps &&
                requiredWeightEnabled
                ? requiredWeightKg
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
                sport == option ? Color.green : Color(.secondarySystemGroupedBackground),
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
                .fill(.green.opacity(0.10))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.green)
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
            return "Choose a distance. Fastest qualifying time wins."
        case .farthestInTime:
            return "Choose a time window. Furthest verified distance wins."
        case .mostDistance:
            return "Every qualifying run adds to the total."
        case .fastestRoute:
            return "Everyone completes the same saved route."
        case .heaviestWeight:
            return "Highest qualifying completed set wins."
        case .mostReps:
            return "Most reps, optionally at a required weight."
        case .exerciseVolume:
            return "Highest reps × weight volume for one exercise."
        case .workoutVolume:
            return "Highest total volume in one strength workout."
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

struct MeetupLocationPicker: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var position: MapCameraPosition

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let coordinate {
                    Marker("Meet here", coordinate: coordinate)
                        .tint(.green)
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
                colors: sport == .running
                    ? [.green.opacity(0.90), .black]
                    : [.orange.opacity(0.80), .black],
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
                            .tint(.green)
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
                .tint(.green)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .challengeCard()
    }

    private func detailHero(_ challenge: ATHLTHChallenge) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: challenge.sport == .running
                    ? [.green.opacity(0.95), .black]
                    : [.orange.opacity(0.86), .black],
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
                        .foregroundStyle(entry.rank == 1 ? .green : .secondary)
                        .frame(width: 34)

                    Circle()
                        .fill(.green.opacity(0.10))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Text(entry.participant.displayName.prefix(1).uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(.green)
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
                                    : .green
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
            } else if challenge.sport == .running {
                ruleRow("Route", "Anywhere")
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
                .tint(.green)
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
                    .foregroundStyle(.green)
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
                    .tint(.green)
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
                                ? .green
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
                                ? (attempt.verification == .manual ? .orange : .green)
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
                                            : .green
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
                Color.green.opacity(0.06),
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
