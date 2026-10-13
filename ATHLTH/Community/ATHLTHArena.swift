import Foundation
import SwiftUI

// MARK: - Arena draft foundation
// This is deliberately separate from ATHLTHChallenge and Weekly Challenge.
// Drafts are local to their creator until a server-authorized multiplayer
// workflow (invites, approval, results) has been implemented.

enum ATHLTHArenaScope: String, CaseIterable, Codable, Identifiable {
    case duel
    case friends
    case club

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duel: return ATHLTHLocalization.choose(english: "1 vs 1", norwegian: "1 mot 1")
        case .friends: return ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner")
        case .club: return "Club"
        }
    }

    var symbol: String {
        switch self {
        case .duel: return "person.2.fill"
        case .friends: return "person.3.fill"
        case .club: return "shield.lefthalf.filled"
        }
    }
}

enum ATHLTHArenaScoring: String, CaseIterable, Codable, Identifiable {
    case winner = "winner"
    case podium = "podium"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winner:
            return ATHLTHLocalization.choose(
                english: "Winner gets 1 point",
                norwegian: "Vinneren får 1 poeng"
            )
        case .podium:
            return ATHLTHLocalization.choose(
                english: "Podium: 3 / 2 / 1 points",
                norwegian: "Pall: 3 / 2 / 1 poeng"
            )
        }
    }
}

/// The primary Arena action is a view-only interpretation of server state.
/// It never marks rounds complete or assigns points. The server remains
/// authoritative for invitations, approvals and score settlement.
enum ATHLTHArenaNextAction: Equatable {
    case respondToInvite
    case addRound
    case approveRule(UUID)
    case waitingForInvites
    case waitingForPlayers
    case waitingForRules
    case startSeries
    case runRoute
    case compete
    case reviewScores
    case finalStandings

    static func resolve(
        status: String,
        response: String?,
        isOrganizer: Bool,
        roundIDs: [UUID],
        personallyApproved: Set<UUID>,
        allRulesApproved: Bool,
        pendingInvites: Int,
        acceptedCount: Int,
        hasUnacceptedMembers: Bool = false,
        hasRoute: Bool,
        deadlinePassed: Bool
    ) -> ATHLTHArenaNextAction? {
        if response == "invited" { return .respondToInvite }
        guard response == "accepted" else { return nil }
        switch status {
        case "draft":
            if roundIDs.isEmpty {
                return isOrganizer ? .addRound : .waitingForRules
            }
            if let roundID = roundIDs.first(where: {
                !personallyApproved.contains($0)
            }) {
                return .approveRule(roundID)
            }
            if pendingInvites > 0 { return .waitingForInvites }
            // Declined/deleted slots must be dealt with before the start gate.
            // Do not advertise "Start" solely because remaining athletes approved.
            if hasUnacceptedMembers || acceptedCount < 2 {
                return .waitingForPlayers
            }
            if !allRulesApproved { return .waitingForRules }
            return isOrganizer ? .startSeries : .waitingForRules
        case "active":
            if deadlinePassed { return .reviewScores }
            return hasRoute ? .runRoute : .compete
        case "completed":
            return .finalStandings
        default:
            return nil
        }
    }
}

enum ATHLTHArenaRoundTemplate: String, CaseIterable, Codable, Identifiable {
    case fastest5K
    case fastest1K
    case fastestDistance
    case fastestRoute
    case mostDistance
    case mostWorkouts
    case mostRepetitions
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastest5K: return ATHLTHLocalization.choose(english: "Fastest 5 km", norwegian: "Raskeste 5 km")
        case .fastest1K: return ATHLTHLocalization.choose(english: "Fastest 1 km", norwegian: "Raskeste 1 km")
        case .fastestDistance: return ATHLTHLocalization.choose(english: "Custom distance", norwegian: "Valgfri distanse")
        case .fastestRoute: return ATHLTHLocalization.choose(english: "Route time trial", norwegian: "Ruteutfordring")
        case .mostDistance: return ATHLTHLocalization.choose(english: "Most distance", norwegian: "Flest kilometer")
        case .mostWorkouts: return ATHLTHLocalization.choose(english: "Most workouts", norwegian: "Flest treningsøkter")
        case .mostRepetitions: return ATHLTHLocalization.choose(english: "Most repetitions", norwegian: "Flest repetisjoner")
        case .custom: return ATHLTHLocalization.choose(english: "Custom round", norwegian: "Egen runde")
        }
    }

    var explanation: String {
        switch self {
        case .fastest5K, .fastest1K, .fastestDistance:
            return ATHLTHLocalization.choose(
                english: "The fastest qualifying time wins.",
                norwegian: "Raskeste gyldige tid vinner."
            )
        case .fastestRoute:
            return ATHLTHLocalization.choose(
                english: "Complete the agreed route. Route results need participant review; automatic GPS verification is not yet supported.",
                norwegian: "Fullfør avtalt rute. Ruteresultater godkjennes av deltakerne; automatisk GPS-kontroll støttes ikke ennå."
            )
        case .mostDistance:
            return ATHLTHLocalization.choose(
                english: "Most qualifying distance during the round wins.",
                norwegian: "Flest gyldige kilometer i runden vinner."
            )
        case .mostWorkouts:
            return ATHLTHLocalization.choose(
                english: "Most qualifying workouts wins. Minimum length must be set before starting.",
                norwegian: "Flest godkjente økter vinner. Minste øktlengde må bestemmes før start."
            )
        case .mostRepetitions:
            return ATHLTHLocalization.choose(
                english: "Exercise and repetition requirements must be agreed before starting.",
                norwegian: "Øvelse og krav til repetisjoner må avtales før start."
            )
        case .custom:
            return ATHLTHLocalization.choose(
                english: "Agree on a measurable result and verification before starting.",
                norwegian: "Avtal et målbart resultat og verifisering før start."
            )
        }
    }
}

struct ATHLTHArenaRoundDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var template: ATHLTHArenaRoundTemplate
    var title: String
    var rules: String
    /// Structured fields for distance and route rounds; older drafts decode nil.
    var targetDistanceMeters: Double? = nil
    var routeSnapshot: ChallengeRouteSnapshot? = nil
}

struct ATHLTHArenaCompetitionDraft: Codable, Identifiable {
    var id = UUID()
    var ownerID: UUID
    var title: String
    var scope: ATHLTHArenaScope
    var scoring: ATHLTHArenaScoring
    var durationDays: Int
    var participantIDs: [UUID]
    var clubID: UUID?
    var createdAt = Date()
    var rounds: [ATHLTHArenaRoundDraft] = []
}


// MARK: - Publication preflight

/// Mirrors the published Arena limits before a remote write. The backend
/// remains the authority for membership, invitations and competition starts.
enum ATHLTHArenaDraftIssue: Equatable {
    case missingTitle, titleTooLong, invalidDuration, invalidInvitees
    case duelNeedsOneOpponent, missingClub, missingRounds, tooManyRounds
    case invalidRound, invalidDistance, missingRoute

    var message: String {
        switch self {
        case .missingTitle:
            return ATHLTHLocalization.choose(
                english: "Give the competition a name before inviting.",
                norwegian: "Gi konkurransen et navn før du inviterer."
            )
        case .titleTooLong:
            return ATHLTHLocalization.choose(
                english: "The competition name can have up to 80 characters.",
                norwegian: "Konkurransenavnet kan ha maksimalt 80 tegn."
            )
        case .invalidDuration:
            return ATHLTHLocalization.choose(
                english: "Choose a duration from 1 to 90 days.",
                norwegian: "Velg en varighet mellom 1 og 90 dager."
            )
        case .invalidInvitees:
            return ATHLTHLocalization.choose(
                english: "Select 1–20 different participants, excluding yourself.",
                norwegian: "Velg 1–20 forskjellige deltakere, uten deg selv."
            )
        case .duelNeedsOneOpponent:
            return ATHLTHLocalization.choose(
                english: "A 1-on-1 duel requires exactly one opponent.",
                norwegian: "En 1-mot-1-duell krever nøyaktig én motstander."
            )
        case .missingClub:
            return ATHLTHLocalization.choose(
                english: "Choose a Club before sending invitations.",
                norwegian: "Velg en klubb før du sender invitasjoner."
            )
        case .missingRounds:
            return ATHLTHLocalization.choose(
                english: "Add at least one round before sending invitations.",
                norwegian: "Legg til minst én runde før du sender invitasjoner."
            )
        case .tooManyRounds:
            return ATHLTHLocalization.choose(
                english: "A competition can contain up to 16 rounds. Remove a round to continue.",
                norwegian: "En konkurranse kan ha maksimalt 16 runder. Fjern en runde for å fortsette."
            )
        case .invalidRound:
            return ATHLTHLocalization.choose(
                english: "One or more rounds need a valid name and rules.",
                norwegian: "Én eller flere runder mangler gyldig navn eller regler."
            )
        case .invalidDistance:
            return ATHLTHLocalization.choose(
                english: "Choose a valid round distance between 0.1 and 500 km.",
                norwegian: "Velg en gyldig rundedistanse mellom 0,1 og 500 km."
            )
        case .missingRoute:
            return ATHLTHLocalization.choose(
                english: "A route round needs a saved route with a valid preview.",
                norwegian: "En ruterunde må ha en lagret rute med gyldig forhåndsvisning."
            )
        }
    }
}

enum ATHLTHArenaDraftValidation {
    static func issue(for draft: ATHLTHArenaCompetitionDraft) -> ATHLTHArenaDraftIssue? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return .missingTitle }
        if title.count > 80 { return .titleTooLong }
        if !(1...90).contains(draft.durationDays) { return .invalidDuration }
        if draft.scope == .club && draft.clubID == nil { return .missingClub }

        let invitees = draft.participantIDs
        if !(1...20).contains(invitees.count) ||
            invitees.contains(draft.ownerID) ||
            Set(invitees).count != invitees.count {
            return .invalidInvitees
        }
        if draft.scope == .duel && invitees.count != 1 {
            return .duelNeedsOneOpponent
        }
        if draft.rounds.isEmpty { return .missingRounds }
        if draft.rounds.count > 16 { return .tooManyRounds }
        if Set(draft.rounds.map(\.id)).count != draft.rounds.count {
            return .invalidRound
        }

        for round in draft.rounds {
            let name = round.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let rules = round.rules.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || name.count > 80 || rules.isEmpty || rules.count > 600 {
                return .invalidRound
            }
            if round.template == .fastestDistance || round.template == .fastestRoute {
                guard let distance = round.targetDistanceMeters,
                      distance.isFinite, (100...500_000).contains(distance) else {
                    return .invalidDistance
                }
            }
            if round.template == .fastestRoute {
                guard let route = round.routeSnapshot,
                      route.distanceKilometers.isFinite,
                      (0.1...500).contains(route.distanceKilometers),
                      (2...1_500).contains(route.coordinates.count),
                      route.coordinates.allSatisfy({
                          $0.latitude.isFinite && $0.longitude.isFinite &&
                          (-90...90).contains($0.latitude) &&
                          (-180...180).contains($0.longitude)
                      }) else {
                    return .missingRoute
                }
                if abs((round.targetDistanceMeters ?? 0) -
                       route.distanceKilometers * 1_000) > 1 {
                    return .invalidDistance
                }
            }
        }
        return nil
    }
}

enum ATHLTHArenaDraftStorage {
    private static func key(for userID: UUID) -> String {
        AccountLocalStorage.key("arenaDrafts", userID: userID)
    }

    static func load(for userID: UUID) -> [ATHLTHArenaCompetitionDraft] {
        guard let data = UserDefaults.standard.data(forKey: key(for: userID)),
              let decoded = try? JSONDecoder().decode(
                [ATHLTHArenaCompetitionDraft].self,
                from: data
              ) else {
            return []
        }
        return decoded.filter { $0.ownerID == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ drafts: [ATHLTHArenaCompetitionDraft], for userID: UUID) {
        guard let encoded = try? JSONEncoder().encode(
            drafts.filter { $0.ownerID == userID }
        ) else { return }
        UserDefaults.standard.set(encoded, forKey: key(for: userID))
    }

    static func removeForDeletedAccount(_ userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: userID))
    }
}

// MARK: - Community entry point

struct ATHLTHArenaEntryCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(ATHLTHArenaLightStyle.soft)
                    .frame(width: 58, height: 58)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ATHLTH Arena")
                    .font(ATHLTHArenaLightStyle.editorialTitle(21))
                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                Text(ATHLTHLocalization.choose(
                    english: "Multiple rounds. One overall champion.",
                    norwegian: "Flere runder. Én sammenlagtvinner."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 3)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
        }
        .padding(16)
        .background(ATHLTHArenaLightStyle.card(23))
    }
}

private enum ATHLTHArenaCreationMode: String, Identifiable {
    case challenge
    case route
    case distance
    case strength
    case series
    case teamRelay

    var id: String { rawValue }
}

/// A team competition needs at least two athletes on each side and an
/// even total roster, including the organizer. It is still only a draft
/// until the invited athletes consent and the organizer configures teams.
enum ATHLTHArenaTeamStartRules {
    static func validInviteeCount(_ count: Int) -> Bool {
        (3...19).contains(count) && count.isMultiple(of: 2) == false
    }
}

/// Shows existing Challenge activity in Arena without copying its rules or data.
private struct ATHLTHArenaChallengeOverviewSection: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore

    private var incoming: [ATHLTHChallenge] {
        challenges.incomingInvitations(for: session.profile.userID)
    }

    private var active: [ATHLTHChallenge] {
        challenges.trainingChallenges(for: session.profile.userID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.circle.fill")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Challenges right now",
                    norwegian: "Aktuelle utfordringer"
                ))
                .font(.headline)
                Spacer()
                NavigationLink {
                    ATHLTHArenaSingleChallengesView()
                } label: {
                    HStack(spacing: 4) {
                        Text(ATHLTHLocalization.choose(english: "View all", norwegian: "Se alle"))
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            if incoming.isEmpty && active.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sportscourt")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "Your new duels and invitations will appear here.",
                        norwegian: "Nye dueller og invitasjoner vises her."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHArenaLightStyle.card(17))
            }

            ForEach(Array(incoming.prefix(2))) { challenge in
                challengeRow(challenge, invitation: true)
            }

            ForEach(Array(active.prefix(3))) { challenge in
                challengeRow(challenge, invitation: false)
            }
        }
    }

    private func challengeRow(_ challenge: ATHLTHChallenge, invitation: Bool) -> some View {
        NavigationLink {
            ChallengeDetailView(challengeID: challenge.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: challenge.sport.systemImage)
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 40, height: 40)
                    .background(ATHLTHTheme.vitalitySoft.opacity(0.66), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)
                    Text(invitation
                        ? ATHLTHLocalization.choose(english: "Invitation to review", norwegian: "Invitasjon til vurdering")
                        : challenge.sport.title
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(13)
            .background(ATHLTHArenaLightStyle.card(17))
        }
        .buttonStyle(.plain)
    }
}

/// One Arena entry point for the already-authorized Live Ghost race flow.
/// Live duels are separate from multi-round scoring until an approved,
/// server-enforced round-to-race link exists. No GPS tracks are loaded here.
private struct ATHLTHArenaLiveDuelsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var races = GhostFriendRaceStore()

    private var activeRaces: [GhostFriendRaceChallengeRecord] {
        (races.incoming + races.outgoing)
            .filter { $0.status == .accepted && $0.expiresAt > Date() }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var incomingInvites: [GhostFriendRaceChallengeRecord] {
        races.incoming.filter {
            $0.status == .pending && $0.expiresAt > Date()
        }
    }

    private var outgoingInvites: [GhostFriendRaceChallengeRecord] {
        races.outgoing.filter {
            $0.status == .pending && $0.expiresAt > Date()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Live duels", norwegian: "Live-dueller"
                ))
                .font(.headline)
                Spacer()
                if races.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await races.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Refresh live duels", norwegian: "Oppdater live-dueller"
                    ))
                }
            }

            NavigationLink {
                GhostFriendRaceHubView()
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Challenge a friend live",
                            norwegian: "Utfordre en venn direkte"
                        ))
                        .font(.subheadline.weight(.bold))
                        Text(ATHLTHLocalization.choose(
                            english: "Invite, get ready and start together.",
                            norwegian: "Inviter, bli klare og start sammen."
                        ))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                    }
                    Spacer(minLength: 3)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [ATHLTHTheme.accentDeep, ATHLTHTheme.vitality],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            if let error = races.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !incomingInvites.isEmpty {
                NavigationLink {
                    GhostFriendRaceHubView()
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "envelope.badge")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(
                            "\(incomingInvites.count) " +
                            ATHLTHLocalization.choose(
                                english: "live duel invitations to answer",
                                norwegian: "invitasjoner til live-duell venter"
                            )
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(13)
                    .background(ATHLTHArenaLightStyle.card(17))
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(activeRaces.prefix(3))) { race in
                NavigationLink {
                    LiveGhostRaceLobbyView(challenge: race)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 38, height: 38)
                            .background(ATHLTHTheme.vitalitySoft.opacity(0.65), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(race.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)
                            Text(
                                String(format: "%.1f km", race.distanceMeters / 1_000) +
                                " · " +
                                ATHLTHLocalization.choose(
                                    english: "Ready for race lobby",
                                    norwegian: "Klar for race-lobby"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .padding(12)
                    .background(ATHLTHArenaLightStyle.card(17))
                }
                .buttonStyle(.plain)
            }

            if !outgoingInvites.isEmpty {
                Text(
                    "\(outgoingInvites.count) " +
                    ATHLTHLocalization.choose(
                        english: "sent invitations awaiting an answer",
                        norwegian: "sendte invitasjoner venter på svar"
                    )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Text(ATHLTHLocalization.choose(
                english: "Live Ghost uses your selected previous GPS run or planned route, with route privacy controls. Live duels do not award Arena series points automatically.",
                norwegian: "Live Ghost bruker en tidligere GPS-økt eller en valgt rute, med rutebeskyttelse. Live-dueller gir ikke automatisk poeng i Arena-serier."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .task { await races.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await races.refresh() } }
        }
    }
}

struct ATHLTHArenaHomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    @State private var drafts: [ATHLTHArenaCompetitionDraft] = []
    @State private var creationMode: ATHLTHArenaCreationMode?
    @State private var pendingDelete: UUID?
    @State private var remoteRevision = UUID()
    @State private var showingCreateOptions = false
    @AppStorage("athlth.arena.workspace.advancedMode")
    private var advanced = false

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introduction
                ATHLTHArenaNextStepsSection()
                    .id("arena-next-steps")

                if showingCreateOptions {
                    createOptions
                        .id("arena-create")
                } else if advanced {
                    arenaQuickNavigation(scrollProxy)
                    quickStart
                        .id("arena-create")
                } else {
                    simpleQuickStart
                        .id("arena-create")
                }

                Group {
                    ATHLTHArenaOnlineSection()
                        .id(remoteRevision)
                }
                .id("arena-online")

                ATHLTHArenaChallengeOverviewSection()
                    .id("arena-challenges")

                ATHLTHArenaLiveDuelsSection()
                    .id("arena-duels")

                if advanced {
                    ATHLTHArenaSeasonsSection()
                        .id("arena-seasons")

                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 10) {
                                arenaDestinations
                            }
                        } else {
                            HStack(spacing: 10) {
                                arenaDestinations
                            }
                        }
                    }
                }

                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Your competition series",
                        norwegian: "Dine konkurranseserier"
                    ))
                    .font(.headline)
                    Spacer()
                    Text("\(drafts.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .id("arena-drafts")

                if drafts.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No series yet",
                            norwegian: "Ingen konkurranseserier ennå"
                        ),
                        systemImage: "trophy",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Create a draft and suggest the first rounds.",
                            norwegian: "Opprett et utkast og foreslå de første rundene."
                        ))
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(drafts) { draft in
                        HStack(spacing: 10) {
                            NavigationLink {
                                ATHLTHArenaDraftDetailView(
                                    draft: draft,
                                    onSave: upsert,
                                    onPublished: { id in
                                        drafts.removeAll { $0.id == id }
                                        ATHLTHArenaDraftStorage.save(
                                            drafts,
                                            for: session.profile.userID
                                        )
                                        remoteRevision = UUID()
                                    }
                                )
                            } label: {
                                draftRow(draft)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                pendingDelete = draft.id
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .frame(width: 35, height: 44)
                            }
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Delete draft",
                                norwegian: "Slett utkast"
                            ))
                        }
                    }
                }

                Text(ATHLTHLocalization.choose(
                    english: "Drafts stay on this device until you publish. Publishing sends invitations and opens a shared lobby. Results are approved by the participants.",
                    norwegian: "Utkast lagres på denne enheten til du publiserer. Publisering sender invitasjoner og åpner en felles lobby. Resultatene godkjennes av deltakerne."
                ))
                .font(.footnote)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaLightStyle.canvasBackground)
        .environment(\.colorScheme, .light)
        .navigationTitle("Arena")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.profile.userID) {
            drafts = ATHLTHArenaDraftStorage.load(for: session.profile.userID)
        }
        .sheet(item: $creationMode) { mode in
            switch mode {
            case .challenge:
                ChallengeCreationView()
            case .route:
                ATHLTHArenaRouteStarter()
            case .distance:
                ATHLTHArenaDistanceStarter()
            case .strength:
                ChallengeCreationView(preselectedSport: .strength)
            case .series:
                ATHLTHArenaCreateView(
                    ownerID: session.profile.userID,
                    friends: social.mutualFollows,
                    onCreate: upsert
                )
            case .teamRelay:
                ATHLTHArenaCreateView(
                    ownerID: session.profile.userID,
                    friends: social.mutualFollows,
                    teamMode: true,
                    onCreate: upsert
                )
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Delete this draft?",
                norwegian: "Slette dette utkastet?"
            ),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button(
                ATHLTHLocalization.choose(english: "Delete", norwegian: "Slett"),
                role: .destructive
            ) {
                if let id = pendingDelete {
                    drafts.removeAll { $0.id == id }
                    ATHLTHArenaDraftStorage.save(drafts, for: session.profile.userID)
                }
                pendingDelete = nil
            }
            Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt"), role: .cancel) {
                pendingDelete = nil
            }
        }
        }
    }

    /// Quick jumps keep the premium Arena front page simple while allowing
    /// users to reach shared competitions, Live Ghost and results without
    /// scrolling through several independent modules.
    private func arenaQuickNavigation(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                arenaJump(
                    ATHLTHLocalization.choose(english: "Create", norwegian: "Opprett"),
                    icon: "plus.circle",
                    target: "arena-create",
                    proxy: proxy
                )
                arenaJump(
                    ATHLTHLocalization.choose(english: "Competitions", norwegian: "Konkurranser"),
                    icon: "trophy",
                    target: "arena-online",
                    proxy: proxy
                )
                arenaJump(
                    ATHLTHLocalization.choose(english: "Live duels", norwegian: "Live-dueller"),
                    icon: "bolt.fill",
                    target: "arena-duels",
                    proxy: proxy
                )
                arenaJump(
                    ATHLTHLocalization.choose(english: "Challenges", norwegian: "Utfordringer"),
                    icon: "flag.checkered",
                    target: "arena-challenges",
                    proxy: proxy
                )
                arenaJump(
                    ATHLTHLocalization.choose(english: "Seasons", norwegian: "Sesonger"),
                    icon: "trophy",
                    target: "arena-seasons",
                    proxy: proxy
                )
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Arena quick navigation",
            norwegian: "Hurtignavigering i Arena"
        ))
    }

    private func arenaJump(
        _ title: String,
        icon: String,
        target: String,
        proxy: ScrollViewProxy
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(target, anchor: .top)
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.horizontal, 13)
                .frame(minHeight: 42)
                .background(ATHLTHArenaLightStyle.card(14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var arenaDestinations: some View {
        NavigationLink {
            ATHLTHArenaSingleChallengesView()
        } label: {
            arenaDestination(
                title: ATHLTHLocalization.choose(
                    english: "Challenges", norwegian: "Enkeltutfordringer"
                ),
                detail: ATHLTHLocalization.choose(
                    english: "Invites, duels & results",
                    norwegian: "Dueller, invitasjoner og resultater"
                ),
                icon: "flag.checkered"
            )
        }
        .buttonStyle(.plain)

        NavigationLink {
            CommunityGroupsView()
        } label: {
            arenaDestination(
                title: "Clubs",
                detail: ATHLTHLocalization.choose(
                    english: "Club competitions", norwegian: "Klubbkonkurranser"
                ),
                icon: "person.3.fill"
            )
        }
        .buttonStyle(.plain)
    }

    private func heroCapability(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.89))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.11), in: Capsule())
    }

    private func arenaDestination(
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accentDeep.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(.horizontal, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 0.8)
        }
    }

    // The same editorial hierarchy as Training Plan: quiet eyebrow,
    // elegant title, warm paper, one principal action and a detail switch.
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ATHLTH · ARENA")
                        .font(ATHLTHArenaLightStyle.eyebrow)
                        .tracking(2.2)
                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    Text("Arena")
                        .font(ATHLTHArenaLightStyle.editorialTitle(36))
                        .foregroundStyle(ATHLTHArenaLightStyle.ink)
                }
                Spacer(minLength: 6)
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showingCreateOptions.toggle()
                    }
                } label: {
                    Image(systemName: showingCreateOptions ? "xmark" : "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 43, height: 43)
                        .background(ATHLTHArenaLightStyle.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Choose competition type",
                    norwegian: "Velg konkurranseform"
                ))
            }

            Text(ATHLTHLocalization.choose(
                english: "Make each session something worth striving for.",
                norwegian: "Gjør hver økt til noe å strekke seg etter."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHArenaLightStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Image(systemName: advanced
                    ? "slider.horizontal.3" : "checkmark.circle")
                    .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                Text(advanced
                    ? ATHLTHLocalization.choose(
                        english: "All competition tools",
                        norwegian: "Full konkurransekontroll"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Simple competition",
                        norwegian: "Enkel konkurranse"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Picker("", selection: $advanced) {
                    Text(ATHLTHLocalization.choose(
                        english: "Simple", norwegian: "Enkel"
                    )).tag(false)
                    Text(ATHLTHLocalization.choose(
                        english: "Advanced", norwegian: "Avansert"
                    )).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 174)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Arena detail level", norwegian: "Detaljnivå i Arena"
                ))
            }
        }
        .padding(.vertical, 3)
    }

    private var simpleQuickStart: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                Image("GoalRunning")
                    .resizable()
                    .scaledToFill()
                    .saturation(0.55)
                    .frame(width: geometry.size.width, height: 124)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .frame(height: 124)

            VStack(alignment: .leading, spacing: 13) {
                Text(ATHLTHLocalization.choose(
                    english: "YOUR NEXT CHALLENGE",
                    norwegian: "DIN NESTE UTFORDRING"
                ))
                .font(ATHLTHArenaLightStyle.eyebrow)
                .tracking(1.9)
                .foregroundStyle(ATHLTHArenaLightStyle.warmGold)

                Text(ATHLTHLocalization.choose(
                    english: "Who will you challenge?",
                    norwegian: "Hvem vil du utfordre?"
                ))
                .font(ATHLTHArenaLightStyle.editorialTitle(26))
                .foregroundStyle(ATHLTHArenaLightStyle.ink)

                Text(ATHLTHLocalization.choose(
                    english: "Choose a friend, a route or a distance. ATHLTH handles the rest.",
                    norwegian: "Velg en venn, en rute eller en distanse. ATHLTH hjelper deg videre."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showingCreateOptions = true
                    }
                } label: {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Create a challenge",
                            norwegian: "Lag en utfordring"
                        ))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 48)
                    .background(ATHLTHArenaLightStyle.ink,
                                in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)

                HStack(spacing: 9) {
                    simpleStartOption(
                        title: ATHLTHLocalization.choose(
                            english: "My route", norwegian: "Min rute"
                        ),
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    ) { creationMode = .route }

                    simpleStartOption(
                        title: ATHLTHLocalization.choose(
                            english: "Distance", norwegian: "Distanse"
                        ),
                        icon: "figure.run"
                    ) { creationMode = .distance }
                }
            }
            .padding(17)
        }
        .background(ATHLTHArenaLightStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(ATHLTHArenaLightStyle.line, lineWidth: 0.8)
        }
    }

    private func simpleStartOption(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                Text(title)
                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ATHLTHArenaLightStyle.soft,
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // One entry, six existing engines. Choosing a tile only opens its
    // established editor; publication and invitations require explicit steps.
    private var createOptions: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ATHLTH · ARENA")
                        .font(ATHLTHArenaLightStyle.eyebrow)
                        .tracking(2)
                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    Text(ATHLTHLocalization.choose(
                        english: "What will you create?",
                        norwegian: "Hva vil du opprette?"
                    ))
                    .font(ATHLTHArenaLightStyle.editorialTitle(27))
                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCreateOptions = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 37, height: 37)
                        .foregroundStyle(ATHLTHArenaLightStyle.ink)
                        .background(ATHLTHArenaLightStyle.soft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close creation choices",
                    norwegian: "Lukk opprettelsesvalgene"
                ))
            }
            Text(ATHLTHLocalization.choose(
                english: "Select a starting point. The underlying workout, route and scoring rules stay unchanged.",
                norwegian: "Velg et utgangspunkt. Treningsmotor, ruter og poengregler forblir som før."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHArenaLightStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)

            creationChoice(
                mode: .challenge,
                symbol: "flag.checkered",
                title: ATHLTHLocalization.choose(
                    english: "Challenge someone", norwegian: "Utfordre noen"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "One challenge, easy to set up",
                    norwegian: "Én utfordring – raskt å komme i gang"
                )
            )
            creationChoice(
                mode: .route,
                symbol: "map",
                title: ATHLTHLocalization.choose(
                    english: "Compete on a route", norwegian: "Konkurrer på en rute"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Choose a saved route and invite",
                    norwegian: "Velg en lagret rute og inviter"
                )
            )
            creationChoice(
                mode: .distance,
                symbol: "figure.run",
                title: ATHLTHLocalization.choose(
                    english: "Set a distance", norwegian: "Bestem en distanse"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Choose length and challenge",
                    norwegian: "Velg lengde og utfordre"
                )
            )
            if advanced {
                creationChoice(
                    mode: .strength,
                    symbol: "dumbbell.fill",
                    title: ATHLTHLocalization.choose(
                        english: "Strength competition", norwegian: "Styrkekonkurranse"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Repetitions, load and workout goals",
                        norwegian: "Repetisjoner, belastning og øktmål"
                    )
                )
                creationChoice(
                    mode: .series,
                    symbol: "trophy",
                    title: ATHLTHLocalization.choose(
                        english: "Competition series", norwegian: "Konkurranseserie"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Multiple rounds, participants and points",
                        norwegian: "Flere runder, deltakere og poeng"
                    )
                )
                creationChoice(
                    mode: .teamRelay,
                    symbol: "person.3.sequence.fill",
                    title: ATHLTHLocalization.choose(
                        english: "Teams & relay", norwegian: "Lag og stafett"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Team selection and relay legs",
                        norwegian: "Lagoppsett og stafettetapper"
                    )
                )
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        advanced = true
                    }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "See more competition types",
                        norwegian: "Se flere konkurranseformer"
                    ), systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .background(ATHLTHArenaLightStyle.card(21))
    }

    private func creationChoice(
        mode: ATHLTHArenaCreationMode,
        symbol: String,
        title: String,
        subtitle: String
    ) -> some View {
        Button {
            showingCreateOptions = false
            creationMode = mode
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHArenaLightStyle.soft,
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaLightStyle.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 1)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
            }
            .padding(11)
            .background(ATHLTHArenaLightStyle.soft.opacity(0.42),
                        in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Choose your competition",
                    norwegian: "Velg konkurranse"
                ))
                .font(ATHLTHArenaLightStyle.editorialTitle(23))
                .foregroundStyle(ATHLTHArenaLightStyle.ink)
                Spacer()
                Text(ATHLTHLocalization.choose(english: "Quick start", norwegian: "Hurtigstart"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { creationMode = .route } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Route", norwegian: "Rute"),
                        detail: ATHLTHLocalization.choose(english: "Choose or create a route", norwegian: "Velg eller lag en rute"),
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
                Button { creationMode = .distance } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                        detail: ATHLTHLocalization.choose(english: "Set your own length", norwegian: "Velg din egen lengde"),
                        icon: "timer"
                    )
                }
                Button { creationMode = .strength } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                        detail: ATHLTHLocalization.choose(english: "Weight, reps or volume", norwegian: "Vekt, reps eller volum"),
                        icon: "dumbbell.fill"
                    )
                }
                Button { creationMode = .series } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Competition series", norwegian: "Konkurranseserie"),
                        detail: ATHLTHLocalization.choose(english: "Multiple rounds and points", norwegian: "Flere runder og poeng"),
                        icon: "trophy.fill"
                    )
                }
            }
            .buttonStyle(.plain)

            Button { creationMode = .teamRelay } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 40, height: 40)
                        .background(
                            ATHLTHTheme.vitalitySoft.opacity(0.68),
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Team & relay competition",
                            norwegian: "Lag og stafett"
                        ))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(ATHLTHLocalization.choose(
                            english: "Invite teammates, plan relay legs, compete together",
                            norwegian: "Inviter lag, planlegg etapper og konkurrer sammen"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(14)
                .background(ATHLTHArenaLightStyle.card(19))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Create team or relay competition",
                norwegian: "Opprett lag- eller stafettkonkurranse"
            ))
        }
    }

    private func quickStartCard(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 37, height: 37)
                    .background(ATHLTHTheme.vitalitySoft.opacity(0.68), in: Circle())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Text(detail)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(13)
        .background(ATHLTHArenaLightStyle.card(19))
        .accessibilityElement(children: .combine)
    }

    private func draftRow(_ draft: ATHLTHArenaCompetitionDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: draft.scope.symbol)
                .font(.title3)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 42, height: 42)
                .background(ATHLTHTheme.accentDeep.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text("\(draft.scope.title) · \(draft.rounds.count) " +
                     ATHLTHLocalization.choose(english: "rounds", norwegian: "runder"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Spacer(minLength: 3)
            Text(ATHLTHLocalization.choose(english: "Draft", norwegian: "Utkast"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
        }
        .padding(12)
        .background(.regularMaterial, in:
            RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func upsert(_ draft: ATHLTHArenaCompetitionDraft) {
        guard draft.ownerID == session.profile.userID else { return }
        drafts.removeAll { $0.id == draft.id }
        drafts.insert(draft, at: 0)
        ATHLTHArenaDraftStorage.save(drafts, for: session.profile.userID)
    }
}

// MARK: - Creating a series

/// Reuses the established Challenge engine, including invitations and GPS rules.
private struct ATHLTHArenaRouteStarter: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRoute: TrainingRoute?
    @State private var showingChallenge = false

    var body: some View {
        NavigationStack {
            SavedRoutesView(
                selectionTitle: ATHLTHLocalization.choose(
                    english: "Choose a competition route",
                    norwegian: "Velg konkurranserute"
                ),
                onSelect: { route in
                    selectedRoute = route
                    showingChallenge = true
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingChallenge) {
            if let selectedRoute {
                ChallengeCreationView(preselectedRouteID: selectedRoute.id)
            }
        }
    }
}

/// Only configures the requested distance; Challenge owns scoring and validation.
private struct ATHLTHArenaDistanceStarter: View {
    @Environment(\.dismiss) private var dismiss
    @State private var distanceText = "5"
    @State private var showingChallenge = false

    private var distanceKilometers: Double? {
        guard let distance = Double(
            distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        ), distance.isFinite, (0.1...500).contains(distance) else {
            return nil
        }
        return distance
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("ATHLTH · ARENA")
                        .font(ATHLTHArenaLightStyle.eyebrow)
                        .tracking(2)
                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    Text(ATHLTHLocalization.choose(
                        english: "Choose your distance",
                        norwegian: "Velg din distanse"
                    ))
                    .font(ATHLTHArenaLightStyle.editorialTitle(30))
                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                }

                Text(ATHLTHLocalization.choose(
                    english: "Compete on any route over the chosen distance.",
                    norwegian: "Konkurrer hvor som helst på distansen du bestemmer."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHArenaLightStyle.secondary)

                HStack(spacing: 8) {
                    ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { km in
                        Button("\(Int(km)) km") {
                            distanceText = String(Int(km))
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)
                    }
                }

                HStack(spacing: 10) {
                    TextField(
                        ATHLTHLocalization.choose(english: "Kilometers", norwegian: "Kilometer"),
                        text: $distanceText
                    )
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .padding(13)
                    .background(ATHLTHArenaLightStyle.surface,
                                in: RoundedRectangle(cornerRadius: 14))
                    Text("km")
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                }
                if distanceKilometers == nil {
                    Text(ATHLTHLocalization.choose(
                        english: "Enter a distance between 0.1 and 500 km.",
                        norwegian: "Angi en distanse fra 0,1 til 500 km."
                    ))
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                Button {
                    showingChallenge = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Continue to challenge",
                            norwegian: "Fortsett til utfordring"
                        ),
                        systemImage: "arrow.right"
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(distanceKilometers == nil)
                Spacer()
            }
            .padding(20)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Distance challenge", norwegian: "Distanseutfordring"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingChallenge) {
            if let distanceKilometers {
                ChallengeCreationView(preselectedDistanceKm: distanceKilometers)
            }
        }
    }
}

private enum ATHLTHArenaSeriesPreset: String, CaseIterable, Identifiable {
    case custom
    case running
    case consistency

    var id: String { rawValue }

    var name: String {
        switch self {
        case .custom:
            return ATHLTHLocalization.choose(english: "From scratch", norwegian: "Fra bunnen")
        case .running:
            return ATHLTHLocalization.choose(english: "Running trio", norwegian: "Løpetrio")
        case .consistency:
            return ATHLTHLocalization.choose(english: "Consistency cup", norwegian: "Treningscup")
        }
    }

    var detail: String {
        switch self {
        case .custom:
            return ATHLTHLocalization.choose(english: "Choose your own rounds", norwegian: "Velg egne runder")
        case .running:
            return ATHLTHLocalization.choose(english: "1 km, 5 km and distance", norwegian: "1 km, 5 km og distanse")
        case .consistency:
            return ATHLTHLocalization.choose(english: "Workout count and distance", norwegian: "Antall økter og distanse")
        }
    }

    var rounds: [ATHLTHArenaRoundDraft] {
        let templates: [ATHLTHArenaRoundTemplate]
        switch self {
        case .custom: templates = []
        case .running: templates = [.fastest1K, .fastest5K, .mostDistance]
        case .consistency: templates = [.mostWorkouts, .mostDistance]
        }
        return templates.map {
            ATHLTHArenaRoundDraft(template: $0, title: $0.title, rules: $0.explanation)
        }
    }
}

struct ATHLTHArenaCreateView: View {
    @Environment(\.dismiss) private var dismiss

    let ownerID: UUID
    let friends: [SocialProfileCard]
    let onCreate: (ATHLTHArenaCompetitionDraft) -> Void
    private let teamMode: Bool

    @State private var title = ""
    @State private var scope: ATHLTHArenaScope = .duel
    @State private var scoring: ATHLTHArenaScoring = .winner
    @State private var durationDays = 14
    @State private var selectedPreset: ATHLTHArenaSeriesPreset = .custom
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var clubChoices: [ATHLTHArenaClubChoice] = []
    @State private var selectedClubID: UUID?
    @State private var clubAthletes: [ATHLTHArenaClubAthlete] = []
    @State private var clubError: String?
    private let clubDirectory = ATHLTHArenaClubDirectory()

    init(
        ownerID: UUID,
        friends: [SocialProfileCard],
        preselectedFriendID: UUID? = nil,
        teamMode: Bool = false,
        onCreate: @escaping (ATHLTHArenaCompetitionDraft) -> Void
    ) {
        self.ownerID = ownerID
        self.friends = friends
        self.onCreate = onCreate
        self.teamMode = teamMode
        _scope = State(initialValue: teamMode ? .friends : .duel)
        _title = State(initialValue: teamMode
            ? ATHLTHLocalization.choose(
                english: "Team Arena", norwegian: "Lagduellen"
            ) : "")
        _selectedFriendIDs = State(initialValue:
            preselectedFriendID.map { Set([$0]) } ?? []
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ATHLTH · ARENA")
                            .font(ATHLTHArenaLightStyle.eyebrow)
                            .tracking(2)
                            .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                        Text(teamMode
                            ? ATHLTHLocalization.choose(
                                english: "Build your team competition",
                                norwegian: "Bygg din lagkonkurranse"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Create a competition",
                                norwegian: "Opprett en konkurranse"
                            ))
                            .font(ATHLTHArenaLightStyle.editorialTitle(27))
                            .foregroundStyle(ATHLTHArenaLightStyle.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Start with a template or an empty series. Set the rounds and invite athletes before publishing.",
                            norwegian: "Velg en mal eller start uten runder. Du bestemmer rundene og inviterer deltakerne før publisering."
                        ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 9)
                }
                .listRowBackground(ATHLTHArenaLightStyle.soft)

                if teamMode {
                    Section {
                        Label(ATHLTHLocalization.choose(
                            english: "Set up a two-team Arena competition",
                            norwegian: "Opprett en Arena-konkurranse med to lag"
                        ), systemImage: "person.3.sequence.fill")
                        .font(.subheadline.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Choose at least three friends: you and the invited athletes must make an even number (4, 6, 8…). After invitations are accepted, configure balanced teams in the competition lobby. For a relay, add a Route round first, then assign relay legs.",
                            norwegian: "Velg minst tre venner: du og de inviterte må bli et partall (4, 6, 8 …). Etter at invitasjonene er godtatt, fordeler du deltakerne på to like store lag i konkurranselobbyen. For stafett legger du først til en ruterunde og fordeler deretter etappene."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                        Label(
                            ATHLTHArenaTeamStartRules.validInviteeCount(selectedFriendIDs.count)
                                ? ATHLTHLocalization.choose(
                                    english: "Roster size ready for teams",
                                    norwegian: "Riktig antall deltakere for lag"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Select an odd number of friends, at least three",
                                    norwegian: "Velg et oddetall venner, minst tre"
                                ),
                            systemImage: ATHLTHArenaTeamStartRules.validInviteeCount(selectedFriendIDs.count)
                                ? "checkmark.circle.fill" : "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaTeamStartRules.validInviteeCount(selectedFriendIDs.count)
                            ? ATHLTHTheme.accentDeep : ATHLTHTheme.mutedText)
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Team setup", norwegian: "Lagoppsett"
                        ))
                    }
                }

                Section {
                    ForEach(ATHLTHArenaSeriesPreset.allCases) { preset in
                        Button {
                            selectedPreset = preset
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: preset == selectedPreset
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHArenaLightStyle.ink)
                                    Text(preset.detail)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose a starting point",
                        norwegian: "Velg utgangspunkt"
                    ))
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "You can change or remove rounds in the draft before sending invitations.",
                        norwegian: "Du kan endre eller fjerne runder i utkastet før du inviterer."
                    ))
                }

                Section {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Competition name",
                            norwegian: "Navn på konkurransen"
                        ),
                        text: $title
                    )
                    .textInputAutocapitalization(.sentences)
                    if teamMode {
                        Label(ATHLTHLocalization.choose(
                            english: "Friends · two teams",
                            norwegian: "Venner · to lag"
                        ), systemImage: "person.3.fill")
                        .font(.subheadline)
                    } else {
                        Picker(ATHLTHLocalization.choose(
                            english: "Format", norwegian: "Konkurranseform"
                        ), selection: $scope) {
                            ForEach(ATHLTHArenaScope.allCases) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                    }
                    Picker(ATHLTHLocalization.choose(
                        english: "Scoring", norwegian: "Poengsystem"
                    ), selection: $scoring) {
                        ForEach(ATHLTHArenaScoring.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker(ATHLTHLocalization.choose(
                        english: "Duration", norwegian: "Varighet"
                    ), selection: $durationDays) {
                        ForEach([7, 14, 30], id: \.self) { days in
                            Text("\(days) " +
                                 ATHLTHLocalization.choose(english: "days", norwegian: "dager"))
                                .tag(days)
                        }
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Competition", norwegian: "Konkurranse"
                    ))
                }

                if scope == .club {
                    Section {
                        if clubChoices.isEmpty {
                            Text(ATHLTHLocalization.choose(
                                english: "Club admins can publish Club Arena series.",
                                norwegian: "Klubbadministratorer kan publisere Arena-serier for klubben."
                            ))
                            .foregroundStyle(.secondary)
                        }
                        ForEach(clubChoices) { choice in
                            Button {
                                selectedClubID = choice.id
                                selectedFriendIDs.removeAll()
                                Task { await loadClubAthletes(choice.id) }
                            } label: {
                                HStack {
                                    Text(choice.name).foregroundStyle(ATHLTHArenaLightStyle.ink)
                                    Spacer()
                                    Image(systemName: selectedClubID == choice.id
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                                }
                            }
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Choose Club", norwegian: "Velg klubb"
                        ))
                    }
                    Section {
                        if selectedClubID == nil {
                            Text(ATHLTHLocalization.choose(
                                english: "Select a Club to see members.",
                                norwegian: "Velg en klubb for å se medlemmer."
                            )).foregroundStyle(.secondary)
                        }
                        Text("\(selectedFriendIDs.count)/20 " +
                            ATHLTHLocalization.choose(
                                english: "selected", norwegian: "valgt"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(clubAthletes) { athlete in
                            Button {
                                if selectedFriendIDs.contains(athlete.id) {
                                    selectedFriendIDs.remove(athlete.id)
                                } else if selectedFriendIDs.count < 20 {
                                    selectedFriendIDs.insert(athlete.id)
                                }
                            } label: {
                                HStack {
                                    Text(athlete.displayName)
                                        .foregroundStyle(ATHLTHArenaLightStyle.ink)
                                    Spacer()
                                    Image(systemName: selectedFriendIDs.contains(athlete.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                                }
                            }
                        }
                        if let clubError {
                            Text(clubError).font(.caption).foregroundStyle(.red)
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Club athletes", norwegian: "Klubbmedlemmer"
                        ))
                    } footer: {
                        Text(ATHLTHLocalization.choose(
                            english: "Select up to 20 members; Inbox invitations are sent on publishing.",
                            norwegian: "Velg opptil 20 medlemmer. Invitasjoner sendes via innboksen ved publisering."
                        ))
                    }
                } else {
                    Section {
                        if friends.isEmpty {
                            Text(ATHLTHLocalization.choose(
                                english: "Mutual followers will appear here. You can still save a draft now.",
                                norwegian: "Gjensidige følgere vises her. Du kan likevel lagre et utkast nå."
                            ))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(friends, id: \.userID) { friend in
                                Button {
                                    if scope == .duel {
                                        selectedFriendIDs = [friend.userID]
                                    } else if selectedFriendIDs.contains(friend.userID) {
                                        selectedFriendIDs.remove(friend.userID)
                                    } else if selectedFriendIDs.count < 20 {
                                        selectedFriendIDs.insert(friend.userID)
                                    }
                                } label: {
                                    HStack {
                                        Text(friend.resolvedName)
                                            .foregroundStyle(ATHLTHArenaLightStyle.ink)
                                        Spacer()
                                        Image(systemName:
                                            selectedFriendIDs.contains(friend.userID)
                                            ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Invitees (draft only)",
                            norwegian: "Deltakere (kun utkast)"
                        ))
                    } footer: {
                        Text(scope == .club
                            ? ATHLTHLocalization.choose(
                                english: "Club membership and invitations will be connected in the next phase.",
                                norwegian: "Club-medlemskap og invitasjoner kobles på i neste fase."
                              )
                            : ATHLTHLocalization.choose(
                                english: "Selecting someone here does not send an invitation.",
                                norwegian: "Å velge noen her sender ikke en invitasjon."
                              ))
                    }
    
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "New series", norwegian: "Ny konkurranseserie"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Create draft", norwegian: "Opprett utkast")) {
                        let draft = ATHLTHArenaCompetitionDraft(
                            ownerID: ownerID,
                            title: String(title.trimmingCharacters(
                                in: .whitespacesAndNewlines).prefix(80)),
                            scope: scope,
                            scoring: scoring,
                            durationDays: durationDays,
                            participantIDs: Array(selectedFriendIDs).sorted {
                                $0.uuidString < $1.uuidString
                            },
                            clubID: scope == .club ? selectedClubID : nil,
                            rounds: selectedPreset.rounds
                        )
                        onCreate(draft)
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (scope == .club && selectedClubID == nil) ||
                        (teamMode && !ATHLTHArenaTeamStartRules.validInviteeCount(selectedFriendIDs.count))
                    )
                }
            }
            .task { await loadClubs() }
            .onChange(of: scope) { _, next in
                selectedFriendIDs.removeAll()
                if next != .club {
                    selectedClubID = nil
                    clubAthletes = []
                }
            }
        }
        .environment(\.colorScheme, .light)
        .tint(ATHLTHArenaLightStyle.action)
    }

    @MainActor
    private func loadClubs() async {
        do {
            clubChoices = try await clubDirectory.manageableClubs()
            clubError = nil
        } catch {
            clubError = error.localizedDescription
        }
    }

    @MainActor
    private func loadClubAthletes(_ club: UUID) async {
        do {
            let loaded = try await clubDirectory.athletes(in: club)
            guard selectedClubID == club else { return }
            clubAthletes = loaded
            clubError = nil
        } catch {
            clubError = error.localizedDescription
        }
    }
}

// MARK: - Editing a competition draft and its proposed rounds

struct ATHLTHArenaDraftDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ATHLTHArenaCompetitionDraft
    @State private var showingAddRound = false
    @State private var roundToEdit: ATHLTHArenaRoundDraft?

    let onSave: (ATHLTHArenaCompetitionDraft) -> Void
    let onPublished: (UUID) -> Void

    @State private var publishing = false
    @State private var publishError: String?

    private var validationIssue: ATHLTHArenaDraftIssue? {
        ATHLTHArenaDraftValidation.issue(for: draft)
    }

    init(
        draft: ATHLTHArenaCompetitionDraft,
        onSave: @escaping (ATHLTHArenaCompetitionDraft) -> Void,
        onPublished: @escaping (UUID) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onPublished = onPublished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ATHLTH · ARENA")
                        .font(ATHLTHArenaLightStyle.eyebrow)
                        .tracking(2)
                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)

                    Text(draft.title)
                        .font(ATHLTHArenaLightStyle.editorialTitle(29))
                        .foregroundStyle(ATHLTHArenaLightStyle.ink)
                    Text("\(draft.scope.title) · \(draft.durationDays) " +
                         ATHLTHLocalization.choose(english: "days", norwegian: "dager"))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                    Text(draft.scoring.title)
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(ATHLTHArenaLightStyle.card(21))

                HStack {
                    Text(ATHLTHLocalization.choose(english: "Rounds", norwegian: "Runder"))
                        .font(.headline)
                    Spacer()
                    Text("\(draft.rounds.count)")
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                }

                if draft.rounds.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "Add the first round. All rules can be revised before invitations are enabled.",
                        norwegian: "Legg til den første runden. Reglene kan endres før invitasjoner aktiveres."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                    .padding(16)
                }

                ForEach(draft.rounds) { round in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\((draft.rounds.firstIndex(where: { $0.id == round.id }) ?? 0) + 1)")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 27)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(round.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaLightStyle.ink)
                            Text(round.rules)
                                .font(.caption)
                                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                        }
                        Spacer(minLength: 3)
                        Button {
                            roundToEdit = round
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Edit round rules", norwegian: "Rediger rundereglene"
                        ))
                        Button(role: .destructive) {
                            draft.rounds.removeAll { $0.id == round.id }
                            onSave(draft)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Remove round", norwegian: "Fjern runde"
                        ))
                    }
                    .padding(14)
                    .background(ATHLTHArenaLightStyle.card(17))
                }

                Button {
                    showingAddRound = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Add round", norwegian: "Legg til runde"
                    ), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(draft.rounds.count >= 16)
                if draft.rounds.count >= 16 {
                    Text(ATHLTHArenaDraftIssue.tooManyRounds.message)
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                }

                VStack(alignment: .leading, spacing: 9) {
                    if draft.scope == .club && draft.clubID == nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Choose a Club when creating a new draft.",
                            norwegian: "Velg en klubb når du oppretter et nytt utkast."
                        ))
                        .font(.footnote)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                    } else {
                        Button {
                            Task { await publishDraft() }
                        } label: {
                            HStack {
                                if publishing {
                                    ProgressView().tint(.white)
                                }
                                Label(ATHLTHLocalization.choose(
                                    english: "Send invitations",
                                    norwegian: "Send invitasjoner"
                                ), systemImage: "paperplane.fill")
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(publishing || validationIssue != nil)
                    }

                    if let issue = validationIssue {
                        Label(issue.message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                    }
                    if let publishError {
                        Text(publishError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "A published series becomes a shared, pre-start lobby. It does not automatically begin a competition.",
                        norwegian: "En publisert serie blir et delt lobby-utkast. Konkurransen starter ikke automatisk."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label(ATHLTHLocalization.choose(
                        english: "Not started",
                        norwegian: "Ikke startet"
                    ), systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "These are private drafts. Publishing sends Inbox invitations and opens a shared Arena lobby. Points require participant approval.",
                        norwegian: "Dette er private utkast. Publisering sender invitasjoner via innboksen og åpner en felles Arena-lobby. Poeng krever deltakernes godkjenning."
                    ))
                    .font(.footnote)
                }
                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHTheme.accentDeep.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 17))
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaLightStyle.canvasBackground)
        .environment(\.colorScheme, .light)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Competition series", norwegian: "Konkurranseserie"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddRound) {
            ATHLTHArenaAddRoundView { round in
                guard draft.rounds.count < 16 else { return }
                draft.rounds.append(round)
                onSave(draft)
            }
        }
        .sheet(item: $roundToEdit) { original in
            ATHLTHArenaEditRoundView(round: original) { updated in
                guard let index = draft.rounds.firstIndex(where: { $0.id == original.id })
                else { return }
                draft.rounds[index] = updated
                onSave(draft)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                    onSave(draft)
                    dismiss()
                }
            }
        }
    }

    @MainActor
    private func publishDraft() async {
        guard !publishing, validationIssue == nil else { return }
        publishing = true
        publishError = nil
        defer { publishing = false }

        do {
            _ = try await ATHLTHArenaCloudService().publish(draft)
            onPublished(draft.id)
            dismiss()
        } catch {
            publishError = error.localizedDescription
        }
    }
}

/// Editing the descriptive rules never changes a structured distance or
/// route snapshot; the creator can remove/recreate a round to change its course.
private struct ATHLTHArenaEditRoundView: View {
    @Environment(\.dismiss) private var dismiss
    let round: ATHLTHArenaRoundDraft
    let onSave: (ATHLTHArenaRoundDraft) -> Void

    @State private var title: String
    @State private var rules: String

    init(
        round: ATHLTHArenaRoundDraft,
        onSave: @escaping (ATHLTHArenaRoundDraft) -> Void
    ) {
        self.round = round
        self.onSave = onSave
        _title = State(initialValue: round.title)
        _rules = State(initialValue: round.rules)
    }

    private var isValid: Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(name.count) &&
            (1...600).contains(detail.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(round.template.title)
                        .font(.subheadline.weight(.semibold))
                    if let distance = round.targetDistanceMeters {
                        Text(String(format: "%.2f km", distance / 1_000))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    if let route = round.routeSnapshot {
                        Text(route.title)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Round type", norwegian: "Type runde"
                    ))
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "To change the distance or route, remove this round and add a new one.",
                        norwegian: "For å endre distanse eller rute må du fjerne runden og legge til en ny."
                    ))
                }

                Section {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Round name", norwegian: "Navn på runden"
                        ),
                        text: $title
                    )
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Rules and verification", norwegian: "Regler og verifisering"
                        ),
                        text: $rules, axis: .vertical
                    )
                    .lineLimit(3...8)
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Details", norwegian: "Detaljer"
                    ))
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "Maximum 80 characters in the name and 600 in the rules. Participants approve these rules before the competition starts.",
                        norwegian: "Maksimalt 80 tegn i navnet og 600 i reglene. Deltakerne må godkjenne reglene før konkurransen starter."
                    ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Edit round", norwegian: "Rediger runde"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Save", norwegian: "Lagre"
                    )) {
                        guard isValid else { return }
                        var updated = round
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.rules = rules.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .environment(\.colorScheme, .light)
        .tint(ATHLTHArenaLightStyle.action)
    }
}

struct ATHLTHArenaAddRoundView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    let onAdd: (ATHLTHArenaRoundDraft) -> Void

    @State private var template: ATHLTHArenaRoundTemplate = .fastest5K
    @State private var title = ATHLTHArenaRoundTemplate.fastest5K.title
    @State private var rules = ATHLTHArenaRoundTemplate.fastest5K.explanation
    @State private var exerciseName = ""
    @State private var distanceText = "5"
    @State private var selectedRoute: TrainingRoute?
    @State private var showingSavedRoutes = false

    private var distanceKM: Double? {
        guard let value = Double(
            distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        ), value.isFinite, (0.1...500).contains(value) else { return nil }
        return value
    }

    private var routeSnapshot: ChallengeRouteSnapshot? {
        guard template == .fastestRoute,
              let route = selectedRoute,
              route.distanceKilometers.isFinite,
              (0.1...500).contains(route.distanceKilometers),
              route.coordinates.count >= 2,
              route.coordinates.allSatisfy({
                  $0.latitude.isFinite && $0.longitude.isFinite &&
                  (-90...90).contains($0.latitude) &&
                  (-180...180).contains($0.longitude)
              }) else { return nil }
        // Share a bounded route preview only with competition participants.
        // Full GPS verification is intentionally NOT inferred from this shape.
        let stride = max(1, Int(ceil(Double(route.coordinates.count) / 1_400)))
        let reduced = route.coordinates.enumerated().compactMap { index, value in
            (index % stride == 0 || index == route.coordinates.count - 1) ? value : nil
        }
        guard (2...1_500).contains(reduced.count) else { return nil }
        return ChallengeRouteSnapshot(
            routeID: route.id,
            title: route.title,
            distanceKilometers: route.distanceKilometers,
            coordinates: reduced
        )
    }

    private var isValid: Bool {
        let hasText = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch template {
        case .fastestDistance: return hasText && distanceKM != nil
        case .fastestRoute: return hasText && routeSnapshot != nil
        case .mostRepetitions:
            return hasText && !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return hasText
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(ATHLTHLocalization.choose(
                        english: "Round type", norwegian: "Type utfordring"
                    ), selection: $template) {
                        ForEach(ATHLTHArenaRoundTemplate.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    TextField(ATHLTHLocalization.choose(
                        english: "Round name", norwegian: "Navn på runden"
                    ), text: $title)
                }

                if template == .fastestDistance {
                    Section {
                        HStack {
                            TextField(ATHLTHLocalization.choose(
                                english: "Distance in km", norwegian: "Distanse i km"
                            ), text: $distanceText)
                            .keyboardType(.decimalPad)
                            Text("km").foregroundStyle(.secondary)
                        }
                        if distanceKM == nil {
                            Text(ATHLTHLocalization.choose(
                                english: "Choose between 0.1 and 500 km.",
                                norwegian: "Velg mellom 0,1 og 500 km."
                            ))
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Competition distance", norwegian: "Konkurransedistanse"
                        ))
                    }
                }

                if template == .fastestRoute {
                    Section {
                        Button {
                            showingSavedRoutes = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(selectedRoute?.title ?? ATHLTHLocalization.choose(
                                        english: "Choose or build a route",
                                        norwegian: "Velg eller lag en rute"
                                    ))
                                    if let route = selectedRoute {
                                        Text(String(format: "%.2f km", route.distanceKilometers))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                        .buttonStyle(.plain)
                        Text(ATHLTHLocalization.choose(
                            english: "The route preview is shared with invited participants. Route results require manual approval; GPS matching is not yet automatic.",
                            norwegian: "Ruten deles med inviterte deltakere. Ruteresultater krever manuell godkjenning; GPS-matching er ikke automatisk ennå."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Competition route", norwegian: "Konkurranserute"
                        ))
                    }
                }

                Section {
                    if template == .mostRepetitions {
                        TextField(ATHLTHLocalization.choose(
                            english: "Exercise to compete in (required)",
                            norwegian: "Øvelsen dere konkurrerer i (påkrevd)"
                        ), text: $exerciseName)
                    }
                    TextField(ATHLTHLocalization.choose(
                        english: "Rules and verification",
                        norwegian: "Regler og verifisering"
                    ), text: $rules, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "Participants approve the rules before the competition starts.",
                        norwegian: "Deltakerne må godkjenne reglene før konkurransen starter."
                    ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "New round", norwegian: "Ny runde"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: template) { _, value in
                title = value.title
                rules = value.explanation
            }
            .sheet(isPresented: $showingSavedRoutes) {
                NavigationStack {
                    SavedRoutesView(
                        selectionTitle: ATHLTHLocalization.choose(
                            english: "Competition route",
                            norwegian: "Konkurranserute"
                        ),
                        onSelect: { route in
                            selectedRoute = route
                            showingSavedRoutes = false
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) { showingSavedRoutes = false }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Add", norwegian: "Legg til")) {
                        let prefix = template == .mostRepetitions
                            ? "Øvelse: " + exerciseName.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
                            : ""
                        let detail = template == .fastestDistance && distanceKM != nil
                            ? "Distanse: " + String(format: "%.2f km. ", distanceKM!) : ""
                        onAdd(ATHLTHArenaRoundDraft(
                            template: template,
                            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                            rules: String((prefix + detail +
                                rules.trimmingCharacters(in: .whitespacesAndNewlines)).prefix(600)),
                            targetDistanceMeters: template == .fastestDistance
                                ? distanceKM.map { $0 * 1_000 } :
                                (template == .fastestRoute
                                    ? routeSnapshot.map { $0.distanceKilometers * 1_000 }
                                    : nil),
                            routeSnapshot: routeSnapshot
                        ))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .environment(\.colorScheme, .light)
            .tint(ATHLTHArenaLightStyle.action)
        }
    }
}


// MARK: - Existing competitive Challenges in Arena
// Official Weekly Challenge keeps its independent editorial/admin workflows.
struct ATHLTHArenaSingleChallengesView: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @State private var showingCreate = false

    private var invitations: [ATHLTHChallenge] {
        challenges.incomingInvitations(for: session.profile.userID)
    }

    private var activeChallenges: [ATHLTHChallenge] {
        challenges.trainingChallenges(for: session.profile.userID)
    }

    private var history: [ATHLTHChallenge] {
        challenges.visibleChallenges
            .filter { $0.status == .completed || $0.status == .cancelled }
            .filter {
                $0.creatorID == session.profile.userID ||
                $0.participants.contains { $0.userID == session.profile.userID }
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "Single challenges",
                        norwegian: "Enkeltutfordringer"
                    ))
                    .font(.title2.weight(.bold))
                    Text(ATHLTHLocalization.choose(
                        english: "One-off duels, routes and activity goals. Series are managed separately in Arena.",
                        norwegian: "Enkeltdueller, ruter og aktivitetsmål. Konkurranseserier administreres separat i Arena."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Button {
                        showingCreate = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "New challenge", norwegian: "Ny utfordring"
                        ), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
                .padding(17)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 22))

                challengeSection(
                    ATHLTHLocalization.choose(english: "Invitations", norwegian: "Invitasjoner"),
                    items: invitations
                )
                challengeSection(
                    ATHLTHLocalization.choose(english: "Active challenges", norwegian: "Aktive utfordringer"),
                    items: activeChallenges
                )
                challengeSection(
                    ATHLTHLocalization.choose(english: "History", norwegian: "Historikk"),
                    items: history
                )
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaLightStyle.canvasBackground)
        .environment(\.colorScheme, .light)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Challenges", norwegian: "Utfordringer"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreate) {
            ChallengeCreationView()
        }
    }

    private func challengeSection(
        _ heading: String,
        items: [ATHLTHChallenge]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(heading)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)
            if items.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Nothing here yet.",
                    norwegian: "Ingenting her ennå."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 17))
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        ChallengeDetailView(challengeID: item.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.sport.systemImage)
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(item.sport.title)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .padding(14)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
