import SwiftUI

/// A bounded, deterministic action scan that checks invitation-stage and
/// active competitions fairly without querying all historical series.
enum ATHLTHArenaActionSelection {
    static let maxChecked = 12
    private static let guaranteedPerStatus = 6

    static func candidates(
        from all: [ATHLTHArenaRemoteSeries]
    ) -> [ATHLTHArenaRemoteSeries] {
        let eligible = all.filter { $0.status == "draft" || $0.status == "active" }
        func earlier(_ lhs: ATHLTHArenaRemoteSeries, _ rhs: ATHLTHArenaRemoteSeries) -> Bool {
            let l = lhs.endsAt ?? .distantFuture
            let r = rhs.endsAt ?? .distantFuture
            if l != r { return l < r }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let drafts = eligible.filter { $0.status == "draft" }.sorted(by: earlier)
        let active = eligible.filter { $0.status == "active" }.sorted(by: earlier)
        let guaranteed = Array(drafts.prefix(guaranteedPerStatus)) +
            Array(active.prefix(guaranteedPerStatus))
        let chosenIDs = Set(guaranteed.map(\.id))
        let overflow = eligible.filter { !chosenIDs.contains($0.id) }
            .sorted(by: earlier)
        return Array((guaranteed + overflow).prefix(maxChecked))
    }
}

/// A read-only inbox for Arena. The existing destination views remain the
/// authority for acceptance, rules, scores and every server-side mutation.
struct ATHLTHArenaNextStepsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var challenges: ChallengeStore

    @StateObject private var liveDuels = GhostFriendRaceStore()
    @State private var remoteSteps: [RemoteStep] = []
    @State private var loadedFor: UUID?
    @State private var isLoading = false
    @State private var refreshQueued = false
    @State private var loadError: String?
    @State private var loadGeneration = 0
    @State private var hasUncheckedSeries = false
    @State private var lastRefreshCompletedAt: Date?

    private let cloud = ATHLTHArenaCloudService()

    struct RemoteStep: Identifiable {
        let series: ATHLTHArenaRemoteSeries
        let action: ATHLTHArenaNextAction
        let priority: Int
        var id: UUID { series.id }
    }

    private struct LocalItem: Identifiable {
        enum Target {
            case challenge(UUID)
            case live
            case series(ATHLTHArenaRemoteSeries)
        }

        let id: String
        let priority: Int
        let title: String
        let detail: String
        let symbol: String
        let target: Target
    }

    private var items: [LocalItem] {
        let currentUser = session.profile.userID

        let challengeItems = challenges.incomingInvitations(for: currentUser)
            .map { challenge in
                LocalItem(
                    id: "challenge-\(challenge.id.uuidString)",
                    priority: 0,
                    title: challenge.title,
                    detail: ATHLTHLocalization.choose(
                        english: "Challenge invitation · Your answer is needed",
                        norwegian: "Utfordringsinvitasjon · Venter på svar"
                    ),
                    symbol: "envelope.badge",
                    target: .challenge(challenge.id)
                )
            }

        let liveItems = liveDuels.incoming
            .filter { $0.status == .pending && $0.expiresAt > Date() }
            .prefix(3)
            .map { race in
                LocalItem(
                    id: "live-\(race.id.uuidString)",
                    priority: 0,
                    title: race.title,
                    detail: ATHLTHLocalization.choose(
                        english: "Live Ghost · Invitation to answer",
                        norwegian: "Live Ghost · Invitasjon til vurdering"
                    ),
                    symbol: "figure.run.circle",
                    target: .live
                )
            }

        let serverItems: [LocalItem] = loadedFor == currentUser
            ? remoteSteps.map { step in
                LocalItem(
                    id: "series-\(step.id.uuidString)",
                    priority: step.priority,
                    title: step.series.title,
                    detail: label(for: step.action),
                    symbol: symbol(for: step.action),
                    target: .series(step.series)
                )
            }
            : []

        return (challengeItems + liveItems + serverItems).sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ATHLTH · ARENA")
                        .font(ATHLTHArenaLightStyle.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    Text(ATHLTHLocalization.choose(
                        english: "Your next step",
                        norwegian: "Din neste handling"
                    ))
                    .font(ATHLTHArenaLightStyle.editorialTitle(25))
                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                }
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 38, height: 38)
                            .background(ATHLTHArenaLightStyle.soft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Refresh next steps",
                        norwegian: "Oppdater neste handling"
                    ))
                }
            }

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
            }

            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    Text(isLoading
                         ? ATHLTHLocalization.choose(
                             english: "Checking competitions…",
                             norwegian: "Sjekker konkurransene…"
                           )
                         : ATHLTHLocalization.choose(
                             english: "No immediate actions shown. Find all competitions below.",
                             norwegian: "Ingen handlinger vises akkurat nå. Se alle konkurranser nedenfor."
                           ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHArenaLightStyle.card(18))
            } else {
                ForEach(Array(items.prefix(4))) { item in
                    NavigationLink {
                        destination(for: item.target)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                                .frame(width: 42, height: 42)
                                .background(ATHLTHArenaLightStyle.soft,
                                            in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                                    .lineLimit(2)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                        }
                        .padding(13)
                        .background(ATHLTHArenaLightStyle.card(18))
                    }
                    .buttonStyle(.plain)
                }

                if items.count > 4 {
                    Text(ATHLTHLocalization.choose(
                        english: "More actions are available in your competitions below.",
                        norwegian: "Flere handlinger finnes i konkurransene nedenfor."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                }
            }
            if hasUncheckedSeries && loadedFor == session.profile.userID {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Showing priority actions from a selection of competitions. Check the full list below for the rest.",
                        norwegian: "Viser prioriterte handlinger fra et utvalg konkurranser. Se hele listen nedenfor for resten."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            // Refresh after returning from a detail screen where the user may
            // have accepted an invite or voted, without polling in background.
            if let last = lastRefreshCompletedAt,
               Date().timeIntervalSince(last) >= 25 {
                Task { await reload() }
            }
        }
        .task(id: session.profile.userID) {
            await reload()
            await liveDuels.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await reload()
                    await liveDuels.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for target: LocalItem.Target) -> some View {
        switch target {
        case .challenge(let id):
            ChallengeDetailView(challengeID: id)
        case .live:
            GhostFriendRaceHubView()
        case .series(let series):
            ATHLTHArenaOnlineDetailView(series: series)
        }
    }

    private func label(for action: ATHLTHArenaNextAction) -> String {
        switch action {
        case .respondToInvite:
            return ATHLTHLocalization.choose(
                english: "Invitation · Review and respond",
                norwegian: "Invitasjon · Se over og svar"
            )
        case .approveRule:
            return ATHLTHLocalization.choose(
                english: "Round rules · Your approval needed",
                norwegian: "Runderegler · Trenger din godkjenning"
            )
        case .reviewScores:
            return ATHLTHLocalization.choose(
                english: "Result · Your vote is needed",
                norwegian: "Resultat · Trenger din stemme"
            )
        case .addRound:
            return ATHLTHLocalization.choose(
                english: "Set up the first round",
                norwegian: "Legg til første runde"
            )
        case .startSeries:
            return ATHLTHLocalization.choose(
                english: "All agreed · Ready to start",
                norwegian: "Alle er enige · Klar til start"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Competition needs attention",
                norwegian: "Konkurransen trenger oppfølging"
            )
        }
    }

    private func symbol(for action: ATHLTHArenaNextAction) -> String {
        switch action {
        case .respondToInvite: return "envelope.open"
        case .approveRule: return "checkmark.shield"
        case .reviewScores: return "medal"
        case .addRound: return "plus.square.on.square"
        case .startSeries: return "flag.checkered"
        default: return "trophy"
        }
    }

    @MainActor
    private func reload() async {
        if isLoading {
            refreshQueued = true
            return
        }
        isLoading = true
        loadGeneration += 1
        let generation = loadGeneration
        let userID = session.profile.userID
        loadedFor = nil
        remoteSteps = []
        hasUncheckedSeries = false
        loadError = nil
        defer {
            isLoading = false
            if refreshQueued {
                refreshQueued = false
                Task { await reload() }
            }
        }

        do {
            let series = try await cloud.loadSeries()
            // Balance invitations (draft) and live rounds (active). This
            // remains a priority digest, not a complete replacement for the
            // authorized competition list below.
            let candidates = ATHLTHArenaActionSelection.candidates(from: series)
            let eligibleCount = series.filter {
                $0.status == "draft" || $0.status == "active"
            }.count
            var detailFailures = 0

            var found: [RemoteStep] = []
            for series in candidates {
                guard !Task.isCancelled, session.profile.userID == userID else { return }
                do {
                let members = try await cloud.loadMembers(seriesID: series.id)
                guard let own = members.first(where: { $0.userID == userID }),
                      own.response == "accepted" || own.response == "invited" else {
                    continue
                }
                if own.response == "invited" {
                    found.append(RemoteStep(
                        series: series, action: .respondToInvite, priority: 0
                    ))
                    continue
                }
                let rounds = try await cloud.loadProposals(seriesID: series.id)
                let approvals = rounds.isEmpty ? [] :
                    try await cloud.loadApprovals(roundIDs: rounds.map(\.id))
                let accepted = members.filter { $0.response == "accepted" }
                let eligible = Set(accepted.compactMap(\.userID))
                let ownApprovals = Set(approvals.filter {
                    $0.userID == userID
                }.map(\.roundID))
                let allApproved = ATHLTHArenaRuleAgreementPresentation.allAgreed(
                    roundIDs: rounds.map(\.id),
                    acceptedUserIDs: eligible,
                    pendingInvitations: members.filter { $0.response == "invited" }.count,
                    approvals: approvals
                )
                let isOrganizer: Bool = {
                    if let owner = series.ownerID { return owner == userID }
                    return accepted.sorted {
                        if $0.createdAt != $1.createdAt {
                            return $0.createdAt < $1.createdAt
                        }
                        return $0.slotID.uuidString < $1.slotID.uuidString
                    }.first?.userID == userID
                }()

                if series.status == "active" {
                    let results = try await cloud.loadRoundResults(seriesID: series.id)
                    let pending = results.filter { $0.status == "pending" }
                    if !pending.isEmpty {
                        let votes = try await cloud.loadResultVotes(
                            resultIDs: pending.map(\.id)
                        )
                        if pending.contains(where: {
                            ATHLTHArenaResultHistoryPresentation.needsYourVote(
                                result: $0,
                                viewerID: userID,
                                eligibleIDs: eligible,
                                votes: votes
                            )
                        }) {
                            found.append(RemoteStep(
                                series: series, action: .reviewScores, priority: 1
                            ))
                            continue
                        }
                    }
                }

                if let action = ATHLTHArenaNextAction.resolve(
                    status: series.status,
                    response: own.response,
                    isOrganizer: isOrganizer,
                    roundIDs: rounds.map(\.id),
                    personallyApproved: ownApprovals,
                    allRulesApproved: allApproved,
                    pendingInvites: members.filter { $0.response == "invited" }.count,
                    acceptedCount: eligible.count,
                    hasUnacceptedMembers: members.contains { $0.response != "accepted" },
                    hasRoute: rounds.contains {
                        $0.template == .fastestRoute && $0.routeSnapshot != nil
                    },
                    deadlinePassed: series.endsAt.map { $0 <= Date() } ?? false
                ) {
                    switch action {
                    case .approveRule:
                        found.append(RemoteStep(
                            series: series, action: action, priority: 2
                        ))
                    case .addRound, .startSeries:
                        found.append(RemoteStep(
                            series: series, action: action, priority: 3
                        ))
                    default: break
                    }
                }
                } catch {
                    // One inaccessible/temporarily failed series cannot hide
                    // other fully verified actions from the user.
                    detailFailures += 1
                    continue
                }
            }
            guard !Task.isCancelled,
                  session.profile.userID == userID,
                  generation == loadGeneration else { return }
            remoteSteps = found
            loadedFor = userID
            hasUncheckedSeries = eligibleCount > candidates.count
            lastRefreshCompletedAt = Date()
            if detailFailures > 0 {
                loadError = ATHLTHLocalization.choose(
                    english: "Some competitions could not be checked. View all competitions below for their current status.",
                    norwegian: "Noen konkurranser kunne ikke kontrolleres. Åpne alle konkurransene nedenfor for oppdatert status."
                )
            }
        } catch {
            guard session.profile.userID == userID,
                  generation == loadGeneration else { return }
            remoteSteps = []
            loadedFor = nil
            hasUncheckedSeries = false
            lastRefreshCompletedAt = Date()
            loadError = ATHLTHLocalization.choose(
                english: "Some Arena actions could not be checked. Open your competitions below for the latest status.",
                norwegian: "Enkelte Arena-handlinger kunne ikke kontrolleres. Åpne konkurransene nedenfor for oppdatert status."
            )
        }
    }
}
