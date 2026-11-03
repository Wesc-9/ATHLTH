import SwiftUI

/// Rules stay visible before and after the tournament begins. Under group
/// governance, all accepted athletes can offer alternatives and pick one
/// proposal. An absolute majority is required, not a plurality.
struct ATHLTHTournamentLobbyRulesView: View {
    @EnvironmentObject private var session: AppSessionStore

    let tournament: ATHLTHTournamentRemote
    let entries: [ATHLTHTournamentRemoteEntry]
    let names: [UUID: String]
    let onChange: @MainActor () async -> Void

    @State private var proposals: [ATHLTHTournamentRuleProposalRemote] = []
    @State private var votes: [ATHLTHTournamentRuleVoteRemote] = []
    @State private var showingProposal = false
    @State private var busy = false
    @State private var errorMessage: String?
    private let cloud = ATHLTHTournamentLobbyCloudService()

    private var isAccepted: Bool {
        entries.contains {
            $0.userID == session.profile.userID &&
            $0.response == "accepted" && $0.removedAt == nil
        }
    }
    private var acceptedCount: Int {
        entries.filter { $0.response == "accepted" && $0.removedAt == nil }.count
    }
    private var pendingCount: Int {
        entries.filter { $0.response == "invited" && $0.removedAt == nil }.count
    }
    private var votedFor: UUID? {
        votes.first { $0.voterID == session.profile.userID }?.proposalID
    }
    private var rulesLocked: Bool { tournament.rulesConfirmedAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Konkurranseregler")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Spacer()
                if rulesLocked {
                    Label("Godkjent", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                Label(tournament.rulesAuthority == .owner
                    ? "Arrangøren bestemmer" : "Gruppen bestemmer",
                    systemImage: tournament.rulesAuthority == .owner
                       ? "person.crop.circle" : "person.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)

                Text("Tillatte aktiviteter")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                FlowLayoutActivityBadges(activities: tournament.allowedActivities)

                Divider().opacity(0.5)
                HStack(spacing: 12) {
                    compactValue("Ny øvelse",
                        ATHLTHTournamentCadence.title(for: tournament.cadenceDays))
                    compactValue("Gjennomføringstid",
                        ATHLTHTournamentCadence.window(tournament.completionHours))
                }

                if tournament.completionHours > tournament.cadenceDays * 24 {
                    Text("Noen øvelser vil overlappe. Du kan se alle fristene i oppgjørsvisningen.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            .padding(16)
            .background(ATHLTHArenaV3Style.panel())

            if tournament.rulesAuthority == .group && !rulesLocked &&
               tournament.status == "inviting" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Velg konkurransereglene")
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text("Flertall kreves: minst \(acceptedCount / 2 + 1) av \(acceptedCount) godtatte deltakere. Hver deltaker kan stemme på ett alternativ.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    if pendingCount > 0 {
                        Label("Avventer svar fra \(pendingCount) inviterte før reglene kan låses.",
                              systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }

                    ForEach(proposals) { proposal in
                        proposalRow(proposal)
                    }

                    if isAccepted {
                        Button {
                            showingProposal = true
                        } label: {
                            Label("Foreslå et annet regelsett",
                                  systemImage: "plus.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                                .frame(maxWidth: .infinity, minHeight: 43)
                        }
                        .disabled(busy || proposals.count >= 16)
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: tournament.id) { await reload() }
        .sheet(isPresented: $showingProposal) {
            ATHLTHTournamentRuleProposalEditor(
                initialActivities: Set(tournament.allowedActivities),
                initialCadence: tournament.cadenceDays,
                initialCompletion: tournament.completionHours
            ) { activities, cadence, completion in
                try await cloud.proposeRules(
                    tournamentID: tournament.id,
                    activities: activities,
                    cadenceDays: cadence,
                    completionHours: completion
                )
                await reload()
                await onChange()
            }
        }
    }

    private func compactValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proposalRow(_ proposal: ATHLTHTournamentRuleProposalRemote)
        -> some View {
        let votesFor = votes.filter { $0.proposalID == proposal.id }.count
        let mine = votedFor == proposal.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(names[proposal.proposerID] ?? "Arrangørens forslag")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(votesFor) stemmer")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            Text(proposal.allowedActivities.map(\.title).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            HStack {
                Text(ATHLTHTournamentCadence.title(for: proposal.cadenceDays))
                Text("·")
                Text(ATHLTHTournamentCadence.window(proposal.completionHours))
                Spacer()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ATHLTHArenaV3Style.ink)
            if isAccepted {
                Button {
                    Task { await vote(proposal.id) }
                } label: {
                    Label(mine ? "Din stemme" : "Stem på dette",
                          systemImage: mine ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
                .buttonStyle(.plain)
                .disabled(busy || mine)
            }
        }
        .padding(14)
        .background(ATHLTHArenaV3Style.panel())
    }

    @MainActor private func vote(_ proposalID: UUID) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.voteRules(proposalID: proposalID)
            await reload()
            await onChange()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func reload() async {
        do {
            async let available = cloud.ruleProposals(tournamentID: tournament.id)
            async let tallies = cloud.ruleVotes(tournamentID: tournament.id)
            proposals = try await available
            votes = try await tallies
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct FlowLayoutActivityBadges: View {
    let activities: [ATHLTHTournamentActivity]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(activities) { activity in
                    Label(activity.title, systemImage: activity.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(ATHLTHArenaV3Style.cream, in: Capsule())
                }
            }
        }
    }
}

private struct ATHLTHTournamentRuleProposalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activities: Set<ATHLTHTournamentActivity>
    @State private var cadenceDays: Int
    @State private var completionHours: Int
    @State private var busy = false
    @State private var errorMessage: String?

    let onSubmit: @MainActor ([ATHLTHTournamentActivity], Int, Int) async throws -> Void

    init(
        initialActivities: Set<ATHLTHTournamentActivity>,
        initialCadence: Int,
        initialCompletion: Int,
        onSubmit: @escaping @MainActor ([ATHLTHTournamentActivity], Int, Int) async throws -> Void
    ) {
        _activities = State(initialValue: initialActivities)
        _cadenceDays = State(initialValue: initialCadence)
        _completionHours = State(initialValue: initialCompletion)
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Mitt forslag")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text("Velg aktivitetene, hvor ofte øvelsene skal komme, og hvor lenge de kan utføres.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 9) {
                        ForEach(ATHLTHTournamentActivity.allCases) { activity in
                            Button {
                                if activities.contains(activity) {
                                    activities.remove(activity)
                                } else { activities.insert(activity) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: activity.symbol)
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                    Text(activity.title)
                                        .font(.caption.weight(.medium))
                                    Spacer()
                                    Image(systemName: activities.contains(activity)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                }
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                                .padding(11)
                                .background(ATHLTHArenaV3Style.panel())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Ny øvelse")
                        Spacer()
                        Picker("Hyppighet", selection: $cadenceDays) {
                            ForEach(ATHLTHTournamentCadence.options,
                                    id: \.self) { day in
                                Text(ATHLTHTournamentCadence.title(for: day)).tag(day)
                            }
                        }
                    }
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())

                    HStack {
                        Text("Gjennomføringsfrist")
                        Spacer()
                        Picker("Frist", selection: $completionHours) {
                            ForEach(ATHLTHTournamentCadence.completionHours,
                                    id: \.self) { duration in
                                Text(ATHLTHTournamentCadence.window(duration))
                                    .tag(duration)
                            }
                        }
                    }
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                try await onSubmit(Array(activities).sorted {
                                    $0.rawValue < $1.rawValue
                                }, cadenceDays, completionHours)
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    } label: {
                        Text("Send regelsett til avstemning")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 53)
                            .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    }
                    .disabled(activities.isEmpty || busy)
                }
                .padding(18)
            }
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Regelforslag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
