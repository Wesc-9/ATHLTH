import Foundation
import MapKit
import SwiftUI
import Supabase

/// Shared Arena series with live invitations, consensual scoring and
/// deadline-based completion. Club and Weekly Challenges remain separate.
struct ATHLTHArenaOnlineSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore

    @State private var series: [ATHLTHArenaRemoteSeries] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private let cloud = ATHLTHArenaCloudService()
    @State private var showsAllCompleted = false

    private var activeSeries: [ATHLTHArenaRemoteSeries] {
        series.filter { $0.status == "active" }
    }

    private var awaitingSeries: [ATHLTHArenaRemoteSeries] {
        series.filter { $0.status == "draft" }
    }

    private var finishedSeries: [ATHLTHArenaRemoteSeries] {
        series.filter { $0.status == "completed" }
    }

    private var otherSeries: [ATHLTHArenaRemoteSeries] {
        series.filter { !["active", "draft", "completed"].contains($0.status) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.circle.fill")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Shared series", norwegian: "Delte konkurranser"
                ))
                .font(.headline)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Refresh series", norwegian: "Oppdater konkurranser"
                    ))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if series.isEmpty && !loading {
                Text(ATHLTHLocalization.choose(
                    english: "Published series and received invitations will appear here.",
                    norwegian: "Publiserte serier og invitasjoner vises her."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHArenaLightStyle.card(17))
            }

            if !activeSeries.isEmpty {
                sectionHeading(
                    title: ATHLTHLocalization.choose(
                        english: "In progress", norwegian: "Pågår nå"
                    ),
                    count: activeSeries.count,
                    icon: "bolt.fill"
                )
                ForEach(activeSeries) { item in
                    seriesRow(item)
                }
            }

            if !awaitingSeries.isEmpty {
                sectionHeading(
                    title: ATHLTHLocalization.choose(
                        english: "Awaiting agreement", norwegian: "Avventer godkjenning"
                    ),
                    count: awaitingSeries.count,
                    icon: "checkmark.shield"
                )
                ForEach(awaitingSeries) { item in
                    seriesRow(item)
                }
            }

            if !finishedSeries.isEmpty {
                HStack {
                    sectionHeading(
                        title: ATHLTHLocalization.choose(
                            english: "Completed", norwegian: "Fullførte"
                        ),
                        count: finishedSeries.count,
                        icon: "trophy.fill"
                    )
                    Spacer(minLength: 8)
                    if finishedSeries.count > 2 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsAllCompleted.toggle()
                            }
                        } label: {
                            Text(showsAllCompleted
                                ? ATHLTHLocalization.choose(
                                    english: "Show less", norwegian: "Vis færre"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "View all", norwegian: "Se alle"
                                )
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                    }
                }
                ForEach(Array(finishedSeries.prefix(
                    showsAllCompleted ? finishedSeries.count : 2
                ))) { item in
                    seriesRow(item)
                }
            }

            if !otherSeries.isEmpty {
                sectionHeading(
                    title: ATHLTHLocalization.choose(
                        english: "Other competitions", norwegian: "Andre konkurranser"
                    ),
                    count: otherSeries.count,
                    icon: "list.bullet"
                )
                ForEach(otherSeries) { item in
                    seriesRow(item)
                }
            }
        }
        .task(id: session.profile.userID) {
            await refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .task(id: session.profile.userID) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                await refresh()
            }
        }
    }

    private func sectionHeading(
        title: String,
        count: Int,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Text("\(count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    ATHLTHTheme.vitalitySoft.opacity(0.7),
                    in: Capsule()
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 5)
    }

    private func seriesRow(
        _ item: ATHLTHArenaRemoteSeries
    ) -> some View {
        let isActive = item.status == "active"
        let isCompleted = item.status == "completed"
        let statusLabel: String = isActive
            ? ATHLTHLocalization.choose(english: "ACTIVE", norwegian: "AKTIV")
            : isCompleted
                ? ATHLTHLocalization.choose(english: "FINISHED", norwegian: "FERDIG")
                : item.status == "draft"
                    ? ATHLTHLocalization.choose(english: "AGREEMENT", norwegian: "ENIGHET")
                    : item.status.uppercased()
        let accent: Color = isActive
            ? ATHLTHTheme.accentDeep
            : isCompleted ? .secondary : .orange

        return NavigationLink {
            ATHLTHArenaOnlineDetailView(series: item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: item.scope.symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.10), in:
                        RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(item.scope.title)
                        if let date = isCompleted
                            ? (item.completedAt ?? item.endsAt)
                            : item.endsAt {
                            Image(systemName: "calendar")
                            Text(date.formatted(.dateTime.day().month(.abbreviated)))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.09), in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
            .padding(14)
            .background(ATHLTHArenaLightStyle.card(18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isActive ? ATHLTHTheme.accentDeep.opacity(0.18)
                                 : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            series = try await cloud.loadSeries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Results here are informational. Arena's normal result proposal and
/// unanimous participant voting remain the ONLY path to award round points.
/// The DB-authenticated round link prevents unrelated races showing here.
private struct ATHLTHArenaLinkedLiveDuelsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @State private var linkedChallenges: [GhostFriendRaceChallengeRecord] = []

    let series: ATHLTHArenaRemoteSeries
    let rounds: [ATHLTHArenaRemoteProposal]
    let members: [ATHLTHArenaRemoteMember]
    let isOrganizer: Bool
    let onReview: (UUID) -> Void
    let onPropose: (ATHLTHArenaLiveOutcomeDraft) -> Void

    @State private var rooms: [LiveGhostRaceRoomRecord] = []
    @State private var participants: [LiveGhostRaceParticipantRecord] = []
    @State private var roundResults: [ATHLTHArenaRoundResult] = []
    @State private var roundResultsLoaded = false
    @State private var showHistoricalDuels = false
    @State private var showAllDuels = false
    @State private var loading = false
    @State private var errorMessage: String?
    private let arenaCloud = ATHLTHArenaCloudService()

    private var linked: [GhostFriendRaceChallengeRecord] {
        let roundIDs = Set(rounds.map(\.id))
        return linkedChallenges.filter {
            guard let roundID = $0.arenaRoundID else { return false }
            return roundIDs.contains(roundID) &&
                $0.status == .accepted
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private var rivalry: ATHLTHArenaRivalrySummary {
        ATHLTHArenaRivalrySummary.calculate(
            challenges: linked,
            rooms: rooms,
            participants: participants,
            eligibleRoundIDs: Set(rounds.map(\.id)),
            currentUserID: session.profile.userID
        )
    }

    private var rivalryRecord: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "medal.fill")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Head-to-head record", norwegian: "Innbyrdes oppgjør"
                ))
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Reported races", norwegian: "Oppgitte dueller"
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            HStack(spacing: 0) {
                rivalryStat(
                    title: ATHLTHLocalization.choose(
                        english: "Wins", norwegian: "Seire"
                    ),
                    value: rivalry.wins
                )
                Divider().frame(height: 38)
                rivalryStat(
                    title: ATHLTHLocalization.choose(
                        english: "Losses", norwegian: "Tap"
                    ),
                    value: rivalry.losses
                )
                Divider().frame(height: 38)
                rivalryStat(
                    title: ATHLTHLocalization.choose(
                        english: "Draws", norwegian: "Uavgjort"
                    ),
                    value: rivalry.ties
                )
            }

            if rivalry.excluded > 0 {
                Label(
                    ATHLTHLocalization.format(
                        english: "%d finished races excluded due to missing or inconsistent times.",
                        norwegian: "%d fullførte dueller er utelatt på grunn av manglende eller motstridende tider.",
                        rivalry.excluded
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Text(ATHLTHLocalization.choose(
                english: "Only consistent, completed Live Ghost results linked to this series. This is not the official Arena score.",
                norwegian: "Kun fullførte Live Ghost-dueller med samsvarende resultater i denne serien. Dette er ikke den offisielle poengstillingen."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(14)
        .background(ATHLTHArenaLightStyle.card(17))
    }

    private func rivalryStat(title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(ATHLTHTheme.primaryText)
            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var shownDuels: [GhostFriendRaceChallengeRecord] {
        linked.filter { challenge in
            let status = rooms.first(where: { $0.challengeID == challenge.id })?.status
            return ATHLTHArenaLiveDuelBrowsing.isHistorical(
                roomStatus: status,
                expiresAt: challenge.expiresAt
            ) == showHistoricalDuels
        }
    }

    var body: some View {
        if series.scope == .duel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Linked Live Ghost duels",
                            norwegian: "Tilknyttede Live Ghost-dueller"
                        ),
                        systemImage: "bolt.horizontal.circle.fill"
                    )
                    .font(.headline)
                    Spacer()
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Refresh linked races",
                            norwegian: "Oppdater tilknyttede dueller"
                        ))
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if rivalry.finishedCount > 0 || rivalry.excluded > 0 {
                    rivalryRecord
                }

                Picker(
                    ATHLTHLocalization.choose(
                        english: "Duel status", norwegian: "Duellstatus"
                    ),
                    selection: $showHistoricalDuels
                ) {
                    Text(ATHLTHLocalization.choose(
                        english: "Active", norwegian: "Pågående"
                    )).tag(false)
                    Text(ATHLTHLocalization.choose(
                        english: "History", norwegian: "Historikk"
                    )).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: showHistoricalDuels) { _, _ in
                    showAllDuels = false
                }

                if shownDuels.isEmpty && !loading {
                    Text(showHistoricalDuels
                        ? ATHLTHLocalization.choose(
                            english: "Completed and expired duels will be kept here as competition history.",
                            norwegian: "Fullførte og utløpte dueller blir liggende her i konkurransehistorikken."
                        )
                        : ATHLTHLocalization.choose(
                            english: "No active linked duel. Invite the opponent from the 1v1 competition above.",
                            norwegian: "Ingen pågående tilknyttet duell. Inviter motstanderen fra 1-mot-1-konkurransen over."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(shownDuels.prefix(showAllDuels ? 150 : 5))) { challenge in
                    let room = rooms.first { $0.challengeID == challenge.id }
                    let senderTime = participants.first {
                        $0.challengeID == challenge.id &&
                        $0.userID == challenge.senderID
                    }?.elapsedSeconds
                    let recipientTime = participants.first {
                        $0.challengeID == challenge.id &&
                        $0.userID == challenge.recipientID
                    }?.elapsedSeconds
                    let existingResult = roundResults.first {
                        $0.roundID == challenge.arenaRoundID &&
                        $0.status != "rejected"
                    }
                    let review = ATHLTHArenaLiveDuelReview.candidate(
                        senderID: challenge.senderID,
                        recipientID: challenge.recipientID,
                        senderSeconds: senderTime,
                        recipientSeconds: recipientTime,
                        reportedWinnerID: room?.winnerID,
                        isFinished: room?.status == .finished
                    )
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(rounds.first { $0.id == challenge.arenaRoundID }?.title ??
                                ATHLTHLocalization.choose(
                                    english: "Arena round", norwegian: "Arena-runde"
                                ))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(liveStatus(for: room, expiresAt: challenge.expiresAt))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }

                        if room?.status == .finished {
                            ForEach([challenge.senderID, challenge.recipientID], id: \.self) { userID in
                                HStack {
                                    Text(userName(userID))
                                        .font(.caption)
                                    Spacer()
                                    let time = userID == challenge.senderID
                                        ? senderTime : recipientTime
                                    Text(time.map(GhostTargetTimeFormatter.string) ?? "—")
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }

                            if let review {
                                Label(
                                    review.winnerID.map { userName($0) } ??
                                        ATHLTHLocalization.choose(
                                            english: "Provisional tie", norwegian: "Foreløpig uavgjort"
                                        ),
                                    systemImage: review.winnerID == nil
                                        ? "equal.circle" : "trophy"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                if review.winnerID != nil {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english: "Reported time difference",
                                            norwegian: "Oppgitt tidsforskjell"
                                        ) + ": " +
                                        String(format: "%.1f s", review.marginSeconds)
                                    )
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                            } else {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Incomplete or inconsistent times – review required",
                                        norwegian: "Manglende eller motstridende tider – må kontrolleres"
                                    ),
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }

                            if let room,
                               let review,
                               let highlights = ATHLTHArenaLiveDuelReview.highlights(
                                   senderPeakLeadMeters: room.senderMaxLeadMeters,
                                   recipientPeakLeadMeters: room.recipientMaxLeadMeters,
                                   leadChangeCount: room.leadChangeCount
                               ) {
                                HStack(spacing: 8) {
                                    raceHighlight(
                                        title: ATHLTHLocalization.choose(
                                            english: "Time gap", norwegian: "Tidsforskjell"
                                        ),
                                        value: String(format: "%.1f s", review.marginSeconds)
                                    )
                                    raceHighlight(
                                        title: ATHLTHLocalization.choose(
                                            english: "Peak lead", norwegian: "Maks forsprang"
                                        ),
                                        value: String(format: "%.0f m", highlights.peakLeadMeters)
                                    )
                                    raceHighlight(
                                        title: ATHLTHLocalization.choose(
                                            english: "Lead changes", norwegian: "Lederskifter"
                                        ),
                                        value: String(highlights.leadChanges)
                                    )
                                }
                                .accessibilityElement(children: .contain)
                            }

                            Text(ATHLTHLocalization.choose(
                                english: "Live results are participant-reported and not independently route-verified. Series points require a separate result proposal and unanimous approval.",
                                norwegian: "Live-resultater er oppgitt av deltakerne og ikke uavhengig ruteverifisert. Seriepoeng krever et eget resultatforslag og enstemmig godkjenning."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                            if let existingResult {
                                Label(
                                    existingResult.status == "approved"
                                        ? ATHLTHLocalization.choose(
                                            english: "Round result approved",
                                            norwegian: "Runderesultatet er godkjent"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Round result already submitted",
                                            norwegian: "Resultatforslag er allerede sendt"
                                        ),
                                    systemImage: existingResult.status == "approved"
                                        ? "checkmark.seal.fill" : "clock"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            }

                            if isOrganizer, roundResultsLoaded,
                               existingResult == nil,
                               let review,
                               let liveDraft = proposalDraft(
                                   for: challenge, result: review
                               ) {
                                Button {
                                    onPropose(liveDraft)
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Prepare result proposal",
                                            norwegian: "Klargjør resultatforslag"
                                        ),
                                        systemImage: "square.and.pencil"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ATHLTHTheme.accentDeep)
                            } else {
                                Button {
                                    if let roundID = challenge.arenaRoundID {
                                        onReview(roundID)
                                    }
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Review this round's result",
                                            norwegian: "Kontroller resultatet i denne runden"
                                        ),
                                        systemImage: "checkmark.shield"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .tint(ATHLTHTheme.accentDeep)
                            }
                        } else if canRejoin(room: room, expiresAt: challenge.expiresAt) {
                            NavigationLink {
                                LiveGhostRaceLobbyView(challenge: challenge)
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Open synchronized race",
                                        norwegian: "Åpne synkronisert duell"
                                    ),
                                    systemImage: "arrow.up.right"
                                )
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(ATHLTHArenaLightStyle.card(17))
                }

                if shownDuels.count > 5 {
                    Button {
                        showAllDuels.toggle()
                    } label: {
                        HStack {
                            Text(showAllDuels
                                ? ATHLTHLocalization.choose(
                                    english: "Show fewer duels", norwegian: "Vis færre dueller"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Show all duels", norwegian: "Se alle dueller"
                                )
                            )
                            Spacer()
                            Image(systemName: showAllDuels
                                ? "chevron.up" : "chevron.down"
                            )
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .task(id: series.id) {
                await refresh()
                // Refresh only while the active duel screen is visible.
                // Avoid an always-on realtime connection for past results.
                while !Task.isCancelled && series.status == "active" {
                    do {
                        try await Task.sleep(for: .seconds(25))
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    if scenePhase == .active { await refresh() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
        }
    }

    /// Convert only a consistent, completed 1v1 report into an editable
    /// proposal. Missing/tied values must go through manual result review.
    private func proposalDraft(
        for challenge: GhostFriendRaceChallengeRecord,
        result: ATHLTHArenaLiveDuelCandidate
    ) -> ATHLTHArenaLiveOutcomeDraft? {
        guard series.status == "active",
              let roundID = challenge.arenaRoundID,
              rounds.contains(where: { $0.id == roundID }),
              let winnerID = result.winnerID,
              winnerID == challenge.senderID || winnerID == challenge.recipientID,
              let sender = members.first(where: {
                  $0.userID == challenge.senderID && $0.response == "accepted"
              }),
              let recipient = members.first(where: {
                  $0.userID == challenge.recipientID && $0.response == "accepted"
              }),
              sender.slotID != recipient.slotID else {
            return nil
        }

        guard let slots = ATHLTHArenaLiveDuelReview.proposedSlots(
            candidate: result,
            senderID: challenge.senderID,
            recipientID: challenge.recipientID,
            senderSlotID: sender.slotID,
            recipientSlotID: recipient.slotID,
            scoring: series.scoring
        ) else { return nil }
        let details = String(
            format: "Live Ghost %@. Rapporterte tider: %.1f s / %.1f s. Deltakerdata, ikke uavhengig GPS-verifisert; krever godkjenning.",
            challenge.id.uuidString,
            result.senderSeconds,
            result.recipientSeconds
        )
        return ATHLTHArenaLiveOutcomeDraft(
            roundID: roundID,
            rankedSlots: slots,
            evidenceNote: details
        )
    }

    private func raceHighlight(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(9)
        .background(
            ATHLTHTheme.vitalitySoft.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
    }

    private func liveStatus(
        for room: LiveGhostRaceRoomRecord?,
        expiresAt: Date
    ) -> String {
        switch room?.status {
        case .finished:
            return ATHLTHLocalization.choose(english: "Finished", norwegian: "Fullført")
        case .cancelled:
            return ATHLTHLocalization.choose(english: "Cancelled", norwegian: "Avlyst")
        case .racing:
            return ATHLTHLocalization.choose(english: "Live now", norwegian: "Pågår nå")
        case .countdown:
            return ATHLTHLocalization.choose(english: "Countdown", norwegian: "Nedtelling")
        case .lobby:
            return expiresAt <= Date()
                ? ATHLTHLocalization.choose(english: "Expired", norwegian: "Utløpt")
                : ATHLTHLocalization.choose(english: "Waiting in lobby", norwegian: "Venter i lobby")
        case nil:
            return expiresAt <= Date()
                ? ATHLTHLocalization.choose(english: "Expired", norwegian: "Utløpt")
                : ATHLTHLocalization.choose(english: "Awaiting start", norwegian: "Venter på start")
        }
    }

    private func canRejoin(
        room: LiveGhostRaceRoomRecord?,
        expiresAt: Date
    ) -> Bool {
        ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: room?.status,
            expiresAt: expiresAt
        )
    }

    private func userName(_ id: UUID) -> String {
        if id == session.profile.userID {
            return ATHLTHLocalization.choose(english: "You", norwegian: "Du")
        }
        return (social.visibleProfiles + social.mutualFollows)
            .first(where: { $0.userID == id })?.resolvedName ??
            ATHLTHLocalization.choose(english: "Opponent", norwegian: "Motstander")
    }

    @MainActor
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        let roundIDs = rounds.map(\.id)
        guard !roundIDs.isEmpty else {
            linkedChallenges = []
            rooms = []
            participants = []
            roundResults = []
            roundResultsLoaded = false
            errorMessage = nil
            return
        }

        do {
            // Filter server-side by the precise Arena rounds. The generic
            // Ghost inbox loads only the latest 100 global invitations and
            // can lose legitimate, older races from a longer competition.
            let fetched: [GhostFriendRaceChallengeRecord] =
                try await SupabaseEnvironment.client
                    .from("ghost_race_challenges")
                    .select()
                    .in("arena_round_id", values: roundIDs)
                    .order("created_at", ascending: false)
                    .limit(150)
                    .execute().value

            let eligible = fetched.filter {
                $0.status == .accepted &&
                $0.arenaRoundID.map { roundIDs.contains($0) } == true
            }
            let ids = eligible.map(\.id)
            guard !ids.isEmpty else {
                linkedChallenges = []
                rooms = []
                participants = []
                roundResults = []
                roundResultsLoaded = false
                errorMessage = nil
                return
            }

            async let roomsTask: [LiveGhostRaceRoomRecord] =
                SupabaseEnvironment.client
                    .from("live_ghost_race_rooms")
                    .select()
                    .in("challenge_id", values: ids)
                    .execute().value
            async let participantsTask: [LiveGhostRaceParticipantRecord] =
                SupabaseEnvironment.client
                    .from("live_ghost_race_participants")
                    .select()
                    .in("challenge_id", values: ids)
                    .execute().value
            async let resultsTask = arenaCloud.loadRoundResults(seriesID: series.id)

            let fetchedRooms = try await roomsTask
            let fetchedParticipants = try await participantsTask
            let fetchedResults = try await resultsTask
            guard !Task.isCancelled else { return }

            rooms = fetchedRooms
            participants = fetchedParticipants
            roundResults = fetchedResults
            linkedChallenges = eligible
            roundResultsLoaded = true
            errorMessage = nil
        } catch {
            // Fail closed: never expose a score proposal using old
            // result/permission data when a fresh query failed.
            roundResultsLoaded = false
            linkedChallenges = []
            rooms = []
            participants = []
            errorMessage = error.localizedDescription
        }
    }
}

struct ATHLTHArenaOnlineDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let series: ATHLTHArenaRemoteSeries

    @State private var members: [ATHLTHArenaRemoteMember] = []
    @State private var rounds: [ATHLTHArenaRemoteProposal] = []
    @State private var approvals: [ATHLTHArenaRemoteApproval] = []
    @State private var sharedWorkoutEvidence: [ATHLTHArenaWorkoutEvidence] = []
    @State private var loading = false
    @State private var writing = false
    @State private var message: String?
    @State private var showingRoundCreator = false
    @State private var latestSeries: ATHLTHArenaRemoteSeries?
    @State private var remoteRevision = UUID()
    @State private var pendingLiveOutcome: ATHLTHArenaLiveOutcomeDraft?
    @State private var invitationToReplace: ATHLTHArenaRemoteMember?
    @State private var invitationToRemove: ATHLTHArenaRemoteMember?
    @State private var replacementChoices: [ATHLTHArenaClubAthlete] = []
    private let clubDirectory = ATHLTHArenaClubDirectory()

    private var currentSeries: ATHLTHArenaRemoteSeries {
        latestSeries ?? series
    }

    private let cloud = ATHLTHArenaCloudService()

    private var ownMembership: ATHLTHArenaRemoteMember? {
        members.first { $0.userID == session.profile.userID }
    }

    private var canParticipate: Bool {
        ownMembership?.response == "accepted"
    }

    private var outstandingInvitations: Int {
        members.filter { $0.response == "invited" }.count
    }

    private var acceptedMembers: [ATHLTHArenaRemoteMember] {
        members.filter { $0.response == "accepted" && $0.userID != nil }
    }

    private var isOrganizer: Bool {
        if series.ownerID == session.profile.userID { return true }
        guard series.ownerID == nil else { return false }
        return acceptedMembers
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.slotID.uuidString < $1.slotID.uuidString
            }
            .first?.userID == session.profile.userID
    }

    private var isGroupSeries: Bool {
        members.count > 2
    }

    private var nextAction: ATHLTHArenaNextAction? {
        let activeIDs = Set(acceptedMembers.compactMap(\.userID))
        let ownApprovals = Set(approvals.filter {
            $0.userID == session.profile.userID
        }.map(\.roundID))
        let allApproved = !rounds.isEmpty && activeIDs.count >= 2 &&
            rounds.allSatisfy { round in
                let approved = Set(approvals.filter {
                    $0.roundID == round.id
                }.map(\.userID))
                return activeIDs.isSubset(of: approved)
            }
        return ATHLTHArenaNextAction.resolve(
            status: currentSeries.status,
            response: ownMembership?.response,
            isOrganizer: isOrganizer,
            roundIDs: rounds.map(\.id),
            personallyApproved: ownApprovals,
            allRulesApproved: allApproved,
            pendingInvites: outstandingInvitations,
            acceptedCount: activeIDs.count,
            hasRoute: rounds.contains(where: {
                $0.template == .fastestRoute && $0.routeSnapshot != nil
            }),
            deadlinePassed: currentSeries.endsAt.map { $0 <= Date() } ?? false
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                nextActionCard(scrollProxy)
                if ownMembership?.response == "invited" {
                    invitationActions
                        .id("arena-invitation")
                }
                detailNavigator(scrollProxy)

                if currentSeries.scope == .duel,
                   currentSeries.status == "active",
                   canParticipate,
                   let opponentID = acceptedMembers
                       .compactMap(\.userID)
                       .first(where: { $0 != session.profile.userID }),
                   social.mutualFollows.contains(where: { $0.userID == opponentID }) {
                    NavigationLink {
                        GhostFriendRaceHubView(
                            preferredFriendID: opponentID,
                            preferredRoute: rounds
                                .first(where: {
                                    $0.template == .fastestRoute &&
                                    $0.routeSnapshot != nil
                                })
                                .flatMap(\.routeSnapshot)
                                .flatMap { arenaTrainingRoute(from: $0) },
                            arenaRoundID: rounds.first(where: {
                                $0.template == .fastestRoute &&
                                $0.routeSnapshot != nil
                            })?.id
                        )
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "bolt.horizontal.circle.fill")
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.13), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Start a synchronized live duel",
                                    norwegian: "Start en synkronisert live-duell"
                                ))
                                .font(.subheadline.weight(.bold))
                                Text(ATHLTHLocalization.choose(
                                    english: "Opponent selected. Choose your earlier run or this competition route.",
                                    norwegian: "Motstanderen er valgt. Bruk en tidligere økt eller konkurranseruten."
                                ))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.84))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(
                            LinearGradient(
                                colors: [ATHLTHTheme.accentDeep, ATHLTHTheme.vitality],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    Text(ATHLTHLocalization.choose(
                        english: "Live Ghost uses a separate invite and synchronized race lobby. A live result does not automatically award Arena series points.",
                        norwegian: "Live Ghost bruker egen invitasjon og synkronisert race-lobby. Resultatet gir ikke automatisk poeng i Arena-serien."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Participants", norwegian: "Deltakere"
                        ))
                        .font(.headline)
                        Spacer()
                        Text("\(members.count)")
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    ForEach(members) { member in
                        HStack(spacing: 10) {
                            Image(systemName: member.isDeleted
                                  ? "person.crop.circle.badge.xmark"
                                  : member.userID == series.ownerID
                                      ? "crown.fill" : "person.crop.circle")
                                .foregroundStyle(
                                    member.isDeleted ? Color.gray : ATHLTHTheme.accentDeep
                                )
                            Text(displayName(for: member.userID))
                                .font(.subheadline)
                                .foregroundStyle(
                                    member.isDeleted ? Color.gray : ATHLTHTheme.primaryText
                                )
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(member.points.formatted()) p")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        member.isDeleted ? Color.gray : ATHLTHTheme.primaryText
                                    )
                                Text(responseTitle(member.response))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            if currentSeries.status == "draft" && isOrganizer &&
                               (member.response == "invited" || member.response == "declined"),
                               member.userID != nil {
                                Menu {
                                    Button {
                                        invitationToReplace = member
                                        Task { await loadReplacementChoices() }
                                    } label: {
                                        Label(ATHLTHLocalization.choose(
                                            english: "Replace invitation",
                                            norwegian: "Erstatt invitasjon"
                                        ), systemImage: "person.crop.circle.badge.plus")
                                    }
                                    Button(role: .destructive) {
                                        invitationToRemove = member
                                    } label: {
                                        Label(ATHLTHLocalization.choose(
                                            english: "Remove invitation",
                                            norwegian: "Fjern invitasjon"
                                        ), systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                        .frame(minWidth: 35, minHeight: 35)
                                }
                                .disabled(writing)
                            }
                        }
                        .padding(11)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .id("arena-participants")

                if let route = rounds.compactMap(\.routeSnapshot).first {
                    arenaRoutePreview(route)
                        .id("arena-map")
                }

                ATHLTHArenaScoringSection(
                    series: currentSeries,
                    members: members,
                    rounds: rounds,
                    isOrganizer: isOrganizer,
                    liveOutcomeDraft: $pendingLiveOutcome,
                    onChanged: { await refresh() },
                    approvedRules: Dictionary(grouping: approvals, by: \.roundID)
                )
                .id("arena-standings")

                if canParticipate && currentSeries.scope == .duel {
                    ATHLTHArenaLinkedLiveDuelsSection(
                        series: currentSeries,
                        rounds: rounds,
                        members: members,
                        isOrganizer: isOrganizer,
                        onReview: { roundID in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(
                                    "arena-review-\(roundID.uuidString)",
                                    anchor: .top
                                )
                            }
                        },
                        onPropose: { proposal in
                            pendingLiveOutcome = proposal
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(
                                    "arena-review-\(proposal.roundID.uuidString)",
                                    anchor: .top
                                )
                            }
                        }
                    )
                }

                if currentSeries.status == "active" && canParticipate {
                    ATHLTHArenaEvidenceSection(
                        series: currentSeries,
                        rounds: rounds
                    )
                    .id(remoteRevision)
                }

                ATHLTHArenaReplacementSection(
                    series: currentSeries,
                    members: members,
                    isOrganizer: isOrganizer,
                    onChanged: { await refresh() }
                )
                .id(remoteRevision)

                if isGroupSeries && canParticipate {
                    NavigationLink {
                        ATHLTHArenaGroupChatView(series: series)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Competition group chat",
                                    norwegian: "Konkurransens gruppechat"
                                ))
                                .font(.subheadline.weight(.semibold))
                                Text(ATHLTHLocalization.choose(
                                    english: "Discuss proposals with the group",
                                    norwegian: "Diskuter forslag med gruppen"
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .padding(16)
                        .background(ATHLTHArenaLightStyle.card(18))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Proposed rounds",
                            norwegian: "Foreslåtte runder"
                        ))
                        .font(.headline)
                        Spacer()
                        if canParticipate && currentSeries.status == "draft" {
                            Button {
                                showingRoundCreator = true
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Suggest", norwegian: "Foreslå"
                                ), systemImage: "plus")
                            }
                            .font(.caption.weight(.semibold))
                            .disabled(writing)
                        }
                    }

                    if rounds.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No rounds have been suggested yet.",
                            norwegian: "Ingen runder er foreslått ennå."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    ForEach(rounds) { round in
                        roundCard(round)
                            .id("arena-rule-\(round.id.uuidString)")
                    }
                }
                .id("arena-rounds")

                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        currentSeries.status == "draft"
                            ? ATHLTHLocalization.choose(
                                english: "Waiting for agreement",
                                norwegian: "Avventer godkjenning"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Group-verified scoring",
                                norwegian: "Poeng godkjennes av gruppen"
                            ),
                        systemImage: "lock.shield"
                    )
                        .font(.subheadline.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "Accepted athletes approve each result before it awards points. Automatic activity verification remains in development.",
                        norwegian: "Alle aktive deltakere godkjenner hvert resultat før poeng deles ut. Automatisk aktivitetsverifisering kommer senere."
                    ))
                    .font(.footnote)
                }
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(16)
                .background(ATHLTHTheme.accentDeep.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 17))

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaLightStyle.canvasBackground)
        .environment(\.colorScheme, .light)
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .task(id: series.id) {
            await refresh()
        }
        .refreshable { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Remove this invitation?",
                norwegian: "Fjerne denne invitasjonen?"
            ),
            isPresented: Binding(
                get: { invitationToRemove != nil },
                set: { if !$0 { invitationToRemove = nil } }
            )
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Remove invitation", norwegian: "Fjern invitasjon"
            ), role: .destructive) {
                if let member = invitationToRemove, let userID = member.userID {
                    Task { await changeInvitation(oldUserID: userID, replacement: nil) }
                }
                invitationToRemove = nil
            }
        }
        .sheet(item: $invitationToReplace) { member in
            NavigationStack {
                List {
                    if replacementChoices.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No eligible athletes found. Select a Club member or mutual follower.",
                            norwegian: "Ingen aktuelle utøvere funnet. Velg et klubbmedlem eller en gjensidig følger."
                        ))
                        .foregroundStyle(.secondary)
                    }
                    ForEach(replacementChoices) { athlete in
                        Button {
                            invitationToReplace = nil
                            if let oldUser = member.userID {
                                Task {
                                    await changeInvitation(
                                        oldUserID: oldUser,
                                        replacement: athlete.id
                                    )
                                }
                            }
                        } label: {
                            HStack {
                                Text(athlete.displayName)
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                        }
                    }
                }
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Choose replacement", norwegian: "Velg erstatter"
                ))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avbryt"
                        )) { invitationToReplace = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showingRoundCreator) {
            ATHLTHArenaAddRoundView { round in
                Task { await propose(round) }
            }
        }
        }
    }

    /// One small, premium context card instead of another long menu.
    /// The button only navigates to existing flows; it never approves
    /// rules, starts workouts or grants points without explicit action.
    @ViewBuilder
    private func nextActionCard(_ proxy: ScrollViewProxy) -> some View {
        if let action = nextAction {
            let info = nextActionCopy(action)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: info.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 41, height: 41)
                        .background(
                            ATHLTHTheme.vitalitySoft.opacity(0.75),
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "YOUR NEXT STEP",
                            norwegian: "DITT NESTE STEG"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(info.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(info.detail)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    switch action {
                    case .addRound:
                        showingRoundCreator = true
                    default:
                        let target: String
                        switch action {
                        case .respondToInvite: target = "arena-invitation"
                        case .approveRule(let roundID):
                            target = "arena-rule-\(roundID.uuidString)"
                        case .waitingForInvites, .waitingForPlayers:
                            target = "arena-participants"
                        case .waitingForRules, .runRoute, .compete:
                            target = "arena-rounds"
                        case .startSeries, .reviewScores, .finalStandings:
                            target = "arena-standings"
                        case .addRound: target = "arena-rounds"
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                } label: {
                    HStack {
                        Text(info.buttonTitle)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(
                        ATHLTHTheme.vitalitySoft.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(15)
            .background(ATHLTHArenaLightStyle.card(20))
            .accessibilityElement(children: .contain)
        }
    }

    private func nextActionCopy(
        _ action: ATHLTHArenaNextAction
    ) -> (title: String, detail: String, buttonTitle: String, symbol: String) {
        switch action {
        case .respondToInvite:
            return (
                ATHLTHLocalization.choose(
                    english: "An invitation is waiting", norwegian: "Du har en invitasjon"
                ),
                ATHLTHLocalization.choose(
                    english: "Review the competition before you decide.",
                    norwegian: "Se over konkurransen før du bestemmer deg."
                ),
                ATHLTHLocalization.choose(
                    english: "Review invitation", norwegian: "Se invitasjonen"
                ),
                "envelope.open"
            )
        case .addRound:
            return (
                ATHLTHLocalization.choose(
                    english: "Add the first round", norwegian: "Legg til første runde"
                ),
                ATHLTHLocalization.choose(
                    english: "Choose a route, distance, strength or workout goal.",
                    norwegian: "Velg rute, distanse, styrke eller øktmål."
                ),
                ATHLTHLocalization.choose(english: "Add round", norwegian: "Legg til runde"),
                "plus.circle.fill"
            )
        case .approveRule:
            return (
                ATHLTHLocalization.choose(
                    english: "A round needs your approval",
                    norwegian: "En runde trenger din godkjenning"
                ),
                ATHLTHLocalization.choose(
                    english: "Review the agreed route and rules before accepting.",
                    norwegian: "Kontroller rute og regler før du godkjenner."
                ),
                ATHLTHLocalization.choose(
                    english: "Review round", norwegian: "Se runden"
                ),
                "checkmark.shield"
            )
        case .waitingForInvites:
            return (
                ATHLTHLocalization.choose(
                    english: "Waiting for invited athletes",
                    norwegian: "Venter på inviterte deltakere"
                ),
                ATHLTHLocalization.choose(
                    english: "The competition starts after invitations and rules are approved.",
                    norwegian: "Konkurransen starter når invitasjoner og regler er godkjent."
                ),
                ATHLTHLocalization.choose(english: "View athletes", norwegian: "Se deltakere"),
                "person.2.badge.clock"
            )
        case .waitingForPlayers:
            return (
                ATHLTHLocalization.choose(
                    english: "More athletes are needed",
                    norwegian: "Trenger flere deltakere"
                ),
                ATHLTHLocalization.choose(
                    english: "At least two accepted athletes must participate.",
                    norwegian: "Minst to deltakere må ha takket ja."
                ),
                ATHLTHLocalization.choose(english: "View athletes", norwegian: "Se deltakere"),
                "person.2"
            )
        case .waitingForRules:
            return (
                ATHLTHLocalization.choose(
                    english: "Awaiting final rule approvals",
                    norwegian: "Avventer siste regelgodkjenninger"
                ),
                ATHLTHLocalization.choose(
                    english: "Everyone must agree before the competition can begin.",
                    norwegian: "Alle må godkjenne reglene før konkurransen starter."
                ),
                ATHLTHLocalization.choose(english: "View rounds", norwegian: "Se rundene"),
                "clock"
            )
        case .startSeries:
            return (
                ATHLTHLocalization.choose(
                    english: "The competition can start",
                    norwegian: "Konkurransen kan starte"
                ),
                ATHLTHLocalization.choose(
                    english: "All eligible athletes have agreed. Start when ready.",
                    norwegian: "Alle deltakere har godkjent. Start når dere er klare."
                ),
                ATHLTHLocalization.choose(
                    english: "Go to start", norwegian: "Gå til start"
                ),
                "flag.checkered"
            )
        case .runRoute:
            return (
                ATHLTHLocalization.choose(
                    english: "Your route is ready", norwegian: "Ruten din er klar"
                ),
                ATHLTHLocalization.choose(
                    english: "Open a route round to start Ghost or record a qualifying run.",
                    norwegian: "Åpne en ruterunde for Ghost eller registrer et gyldig løp."
                ),
                ATHLTHLocalization.choose(english: "Open rounds", norwegian: "Åpne runder"),
                "point.topleft.down.to.point.bottomright.curvepath"
            )
        case .compete:
            return (
                ATHLTHLocalization.choose(
                    english: "Your competition is active", norwegian: "Konkurransen pågår"
                ),
                ATHLTHLocalization.choose(
                    english: "Check the current round goals and shared results.",
                    norwegian: "Se rundemålene og resultatene som er delt."
                ),
                ATHLTHLocalization.choose(english: "See rounds", norwegian: "Se rundene"),
                "figure.run"
            )
        case .reviewScores:
            return (
                ATHLTHLocalization.choose(
                    english: "Time to review results",
                    norwegian: "Tid for resultatgodkjenning"
                ),
                ATHLTHLocalization.choose(
                    english: "The training period has ended. Only approved results award points.",
                    norwegian: "Treningsperioden er over. Kun godkjente resultater gir poeng."
                ),
                ATHLTHLocalization.choose(
                    english: "Review standings", norwegian: "Kontroller stillingen"
                ),
                "checkmark.seal"
            )
        case .finalStandings:
            return (
                ATHLTHLocalization.choose(
                    english: "The final table is ready", norwegian: "Sluttstillingen er klar"
                ),
                ATHLTHLocalization.choose(
                    english: "See the approved scores and competition history.",
                    norwegian: "Se godkjente poeng og konkurransehistorikk."
                ),
                ATHLTHLocalization.choose(
                    english: "Final standings", norwegian: "Sluttstilling"
                ),
                "trophy"
            )
        }
    }

    private func detailNavigator(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                navigationButton(
                    title: ATHLTHLocalization.choose(english: "Standings", norwegian: "Stilling"),
                    icon: "chart.bar.fill",
                    target: "arena-standings",
                    proxy: proxy
                )
                navigationButton(
                    title: ATHLTHLocalization.choose(english: "Rounds", norwegian: "Runder"),
                    icon: "flag.checkered",
                    target: "arena-rounds",
                    proxy: proxy
                )
                navigationButton(
                    title: ATHLTHLocalization.choose(english: "Athletes", norwegian: "Deltakere"),
                    icon: "person.2.fill",
                    target: "arena-participants",
                    proxy: proxy
                )
                if rounds.contains(where: { $0.routeSnapshot != nil }) {
                    navigationButton(
                        title: ATHLTHLocalization.choose(english: "Map", norwegian: "Kart"),
                        icon: "map.fill",
                        target: "arena-map",
                        proxy: proxy
                    )
                }
                if isGroupSeries && canParticipate {
                    NavigationLink {
                        ATHLTHArenaGroupChatView(series: currentSeries)
                    } label: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(ATHLTHArenaLightStyle.card(16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Competition navigation",
            norwegian: "Konkurransenavigasjon"
        ))
    }

    private func navigationButton(
        title: String,
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
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(ATHLTHArenaLightStyle.card(16))
        }
        .buttonStyle(.plain)
    }

    /// Reuses the existing route workout and Ghost engines, not a new
    /// independent workout recorder. A round only contains a shared course,
    /// never another athlete's private GPS workout.
    private func arenaTrainingRoute(
        from snapshot: ChallengeRouteSnapshot
    ) -> TrainingRoute? {
        guard snapshot.distanceKilometers.isFinite,
              (0.1...500).contains(snapshot.distanceKilometers),
              (2...1_500).contains(snapshot.coordinates.count),
              snapshot.coordinates.allSatisfy({
                  $0.latitude.isFinite && $0.longitude.isFinite &&
                  (-90...90).contains($0.latitude) &&
                  (-180...180).contains($0.longitude)
              }) else {
            return nil
        }
        return TrainingRoute(
            id: snapshot.routeID ?? UUID(),
            ownerID: session.profile.userID,
            title: snapshot.title,
            visibility: .privateOnly,
            coordinates: snapshot.coordinates,
            distanceKilometers: snapshot.distanceKilometers,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            startName: nil,
            endName: nil,
            expectedTravelTimeSeconds: nil,
            routeSource: "arena_competition"
        )
    }

    private func arenaRoutePreview(_ route: ChallengeRouteSnapshot) -> some View {
        let points = route.coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minLatitude = latitudes.min() ?? 0
        let maxLatitude = latitudes.max() ?? 0
        let minLongitude = longitudes.min() ?? 0
        let maxLongitude = longitudes.max() ?? 0
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.008, (maxLatitude - minLatitude) * 1.35),
                longitudeDelta: max(0.008, (maxLongitude - minLongitude) * 1.35)
            )
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Competition route", norwegian: "Konkurranserute"
                ))
                .font(.headline)
                Spacer()
                Text(String(format: "%.2f km", route.distanceKilometers))
                    .font(.subheadline.weight(.bold))
            }
            Text(route.title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)

            if points.count >= 2 {
                Map(initialPosition: .region(region)) {
                    MapPolyline(coordinates: points)
                        .stroke(ATHLTHTheme.accentDeep, lineWidth: 5)
                }
                .mapControlVisibility(.hidden)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Map of the agreed competition route",
                    norwegian: "Kart over den avtalte konkurranseruten"
                ))
            }
            Text(ATHLTHLocalization.choose(
                english: "Route results require participant approval; map preview is not GPS verification.",
                norwegian: "Ruteresultater godkjennes av deltakerne. Kartvisningen er ikke GPS-verifisering."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(16)
        .background(ATHLTHArenaLightStyle.card(20))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("ATHLTH ARENA", systemImage: "trophy.fill")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.88))
            Text(series.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(series.scope.title + " · " +
                 "\(series.durationDays) " +
                 ATHLTHLocalization.choose(english: "days", norwegian: "dager"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.74))
            Text(series.scoring.title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
            Text(currentSeries.status == "completed"
                ? ATHLTHLocalization.choose(english: "Completed", norwegian: "Fullført")
                : currentSeries.status == "active"
                    ? ATHLTHLocalization.choose(english: "Active", norwegian: "Aktiv")
                    : ATHLTHLocalization.choose(english: "Pending agreement", norwegian: "Avventer enighet"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.90))
            if currentSeries.status == "active",
               let endsAt = currentSeries.endsAt {
                if Date() >= endsAt {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Competition ended · 48-hour result review",
                            norwegian: "Treningsperioden er slutt · 48 timer resultatgodkjenning"
                        ),
                        systemImage: "clock.badge.checkmark"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    Text(endsAt.addingTimeInterval(48 * 3_600), style: .date)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.74))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(ATHLTHLocalization.choose(
                            english: "Competition ends", norwegian: "Konkurransen slutter"
                        ))
                        Text(endsAt, style: .date)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                }
            } else if currentSeries.status == "completed",
                      currentSeries.completionReason == "deadline_unresolved" {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Finished with unresolved rounds; no points for missing approvals.",
                        norwegian: "Avsluttet med uavklarte runder – ingen poeng for manglende godkjenning."
                    ),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
            }
            if outstandingInvitations > 0 {
                Label(
                    "\(outstandingInvitations) " +
                    ATHLTHLocalization.choose(
                        english: "invitations pending",
                        norwegian: "invitasjoner venter"
                    ),
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.90))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [ATHLTHTheme.accentDeep, ATHLTHTheme.vitality],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var invitationActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ATHLTHLocalization.choose(
                english: "You're invited to this series.",
                norwegian: "Du er invitert til denne konkurranseserien."
            ))
            .font(.subheadline.weight(.semibold))
            HStack {
                Button {
                    Task { await respond(accept: true) }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Accept", norwegian: "Godta"
                    ), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(writing)
                Button {
                    Task { await respond(accept: false) }
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Decline", norwegian: "Avslå"
                    ))
                }
                .buttonStyle(.bordered)
                .disabled(writing)
            }
        }
        .padding(15)
        .background(ATHLTHTheme.accentDeep.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    private func roundCard(_ round: ATHLTHArenaRemoteProposal) -> some View {
        let acceptedIDs = Set(acceptedMembers.compactMap(\.userID))
        let approvedIDs = Set(
            approvals.filter { $0.roundID == round.id }.map(\.userID)
        )
        let voteCount = approvedIDs.intersection(acceptedIDs).count
        let fullyApproved = outstandingInvitations == 0 &&
            !acceptedIDs.isEmpty &&
            acceptedIDs.isSubset(of: approvedIDs)
        let alreadyVoted = approvedIDs.contains(session.profile.userID)

        // The comparison uses a reported time for this exact round, not
        // a competitor's private GPS trace or a server-verified result.
        let rivalSeconds = ATHLTHArenaSuggestedRanking.fastestSharedRivalTime(
            roundID: round.id,
            currentUserID: session.profile.userID,
            evidence: sharedWorkoutEvidence
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(round.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer()
                if fullyApproved {
                    Label(ATHLTHLocalization.choose(
                        english: "Agreed", norwegian: "Godkjent"
                    ), systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                }
            }
            Text(round.rules)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

            if let snapshot = round.routeSnapshot {
                Label(
                    String(format: "%.2f km", snapshot.distanceKilometers),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)

                if currentSeries.status == "active", canParticipate,
                   let route = arenaTrainingRoute(from: snapshot) {
                    NavigationLink {
                        TargetGhostSetupView(
                            route: route,
                            challengeTitle: currentSeries.title,
                            suggestedDurationSeconds: rivalSeconds
                        )
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rivalSeconds == nil
                                    ? ATHLTHLocalization.choose(
                                        english: "Train with a target Ghost",
                                        norwegian: "Tren med mål-Ghost"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Chase a shared rival time",
                                        norwegian: "Jakt på en delt rivaltid"
                                    ))
                                .font(.subheadline.weight(.semibold))
                                if let rivalSeconds {
                                    Text(
                                        GhostTargetTimeFormatter.string(rivalSeconds) + " · " +
                                        ATHLTHLocalization.choose(
                                            english: "Reported time, awaiting group approval",
                                            norwegian: "Oppgitt tid, avventer gruppegodkjenning"
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                } else {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Choose a pace or finish time on this route.",
                                        norwegian: "Velg tempo eller sluttid på denne ruten."
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .padding(12)
                        .background(
                            ATHLTHTheme.vitalitySoft.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Configure target Ghost for this competition route",
                        norwegian: "Sett opp mål-Ghost for konkurranseruten"
                    ))
                }
            }
            Text("\(voteCount)/\(acceptedIDs.count) " +
                 ATHLTHLocalization.choose(
                    english: "accepted members approved",
                    norwegian: "aktive deltakere har godkjent"
                 ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)

            if currentSeries.status == "draft" && canParticipate && !alreadyVoted && !fullyApproved {
                Button {
                    Task { await approve(roundID: round.id) }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Approve round", norwegian: "Godkjenn runde"
                    ), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(writing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 17))
    }

    private func responseTitle(_ response: String) -> String {
        switch response {
        case "accepted":
            return ATHLTHLocalization.choose(english: "Accepted", norwegian: "Godtatt")
        case "declined":
            return ATHLTHLocalization.choose(english: "Declined", norwegian: "Avslått")
        case "deleted":
            return ATHLTHLocalization.choose(english: "Deleted", norwegian: "Slettet")
        default:
            return ATHLTHLocalization.choose(english: "Invited", norwegian: "Invitert")
        }
    }

    private func displayName(for userID: UUID?) -> String {
        guard let userID else {
            return ATHLTHLocalization.choose(
                english: "Deleted user", norwegian: "Slettet bruker"
            )
        }
        if userID == session.profile.userID {
            return ATHLTHLocalization.choose(english: "You", norwegian: "Du")
        }
        return (social.visibleProfiles + social.mutualFollows)
            .first { $0.userID == userID }?.resolvedName ??
            ATHLTHLocalization.choose(
                english: "Participant", norwegian: "Deltaker"
            )
    }

    @MainActor
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let loadedSeries = cloud.loadSeries()
            async let loadedMembers = cloud.loadMembers(seriesID: series.id)
            async let loadedRounds = cloud.loadProposals(seriesID: series.id)
            let memberRows = try await loadedMembers
            let roundRows = try await loadedRounds
            let approvalRows = try await cloud.loadApprovals(
                roundIDs: roundRows.map(\.id)
            )
            let seriesRows = try await loadedSeries
            latestSeries = seriesRows.first { $0.id == series.id }
            members = memberRows
            rounds = roundRows
            approvals = approvalRows
            if memberRows.contains(where: {
                $0.userID == session.profile.userID && $0.response == "accepted"
            }) {
                sharedWorkoutEvidence =
                    (try? await cloud.loadWorkoutEvidence(seriesID: series.id)) ?? []
            } else {
                sharedWorkoutEvidence = []
            }
            remoteRevision = UUID()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func loadReplacementChoices() async {
        do {
            let choices: [ATHLTHArenaClubAthlete]
            if let club = currentSeries.clubID {
                choices = try await clubDirectory.athletes(in: club)
            } else {
                choices = social.mutualFollows.map {
                    ATHLTHArenaClubAthlete(id: $0.userID, displayName: $0.resolvedName)
                }
            }
            let used = Set(members.compactMap(\.userID))
            replacementChoices = choices.filter { !used.contains($0.id) }
                .sorted {
                    $0.displayName.localizedStandardCompare($1.displayName)
                        == .orderedAscending
                }
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func changeInvitation(oldUserID: UUID, replacement: UUID?) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.changeInvitation(
                seriesID: currentSeries.id,
                oldUserID: oldUserID,
                replacementUserID: replacement
            )
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func respond(accept: Bool) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.respond(seriesID: series.id, accept: accept)
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func approve(roundID: UUID) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.approve(roundID: roundID)
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func propose(_ round: ATHLTHArenaRoundDraft) async {
        guard !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try await cloud.propose(
                seriesID: series.id,
                round: round,
                position: rounds.count
            )
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }
}
