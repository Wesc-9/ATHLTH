import Foundation
import SwiftUI

/// Matches completed workouts to Arena round templates without inferring
/// intermediate 1 km / 5 km splits from a longer run.
enum ATHLTHArenaEvidenceMatcher {
    struct Match {
        let metricType: String
        let metricValue: Double

        var formatted: String {
            switch metricType {
            case "elapsed_seconds":
                let seconds = Int(metricValue.rounded())
                return String(format: "%d:%02d", seconds / 60, seconds % 60)
            case "distance_meters":
                return String(format: "%.2f km", metricValue / 1_000)
            default:
                return ATHLTHLocalization.choose(
                    english: "1 completed session", norwegian: "1 fullført økt"
                )
            }
        }
    }

    static func match(
        _ workout: SocialPublishableWorkout,
        template: ATHLTHArenaRoundTemplate,
        targetDistanceMeters: Double? = nil,
        startsAt: Date?,
        endsAt: Date?
    ) -> Match? {
        guard let startsAt, let endsAt,
              workout.startDate >= startsAt,
              workout.endDate <= endsAt,
              workout.endDate > workout.startDate,
              workout.endDate <= Date(),
              workout.duration.isFinite,
              workout.duration > 0,
              workout.duration <= 24 * 60 * 60
        else { return nil }

        switch template {
        case .fastest5K, .fastest1K:
            let target = template == .fastest5K ? 5_000.0 : 1_000.0
            guard workout.activity == .running,
                  workout.isIndoor != true,
                  let distance = workout.distanceMeters,
                  distance.isFinite,
                  abs(distance - target) <= target * 0.02,
                  workout.duration >= (target == 5_000 ? 600 : 100),
                  workout.duration <= (target == 5_000 ? 18_000 : 7_200)
            else { return nil }
            return Match(metricType: "elapsed_seconds", metricValue: workout.duration)

        case .fastestDistance:
            guard let target = targetDistanceMeters,
                  target.isFinite, (100...500_000).contains(target),
                  workout.activity == .running,
                  workout.isIndoor != true,
                  let distance = workout.distanceMeters,
                  distance.isFinite,
                  abs(distance - target) <= target * 0.02,
                  workout.duration >= max(10, target / 15),
                  workout.duration <= min(86_400, max(1_800, target * 3.6))
            else { return nil }
            return Match(metricType: "elapsed_seconds", metricValue: workout.duration)

        case .mostDistance:
            guard (workout.activity == .running || workout.activity == .walking),
                  let distance = workout.distanceMeters,
                  distance.isFinite,
                  (300...500_000).contains(distance),
                  workout.duration >= 300,
                  distance <= workout.endDate.timeIntervalSince(workout.startDate) * 15
            else { return nil }
            return Match(metricType: "distance_meters", metricValue: distance)

        case .mostWorkouts:
            guard [.running, .walking, .strength].contains(workout.activity),
                  workout.duration >= 600
            else { return nil }
            return Match(metricType: "completed_workout", metricValue: 1)

        // Repetition challenges require a known exercise and actual
        // set-level evidence; generic total reps are not sufficient.
        case .mostRepetitions, .fastestRoute, .custom:
            return nil
        }
    }
}


//// Local route eligibility is informational evidence, never server attestation.
/// The same constraints guard discovery AND the final share action.
enum ATHLTHArenaRouteEvidencePolicy {
    static func eligibleWorkout(
        _ workout: SocialPublishableWorkout,
        plannedDistanceMeters: Double,
        startsAt: Date?,
        endsAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let startsAt, let endsAt,
              startsAt < endsAt,
              plannedDistanceMeters.isFinite,
              (100...500_000).contains(plannedDistanceMeters),
              workout.activity == .running,
              workout.isIndoor != true,
              workout.startDate >= startsAt,
              workout.endDate > workout.startDate,
              workout.endDate <= endsAt,
              workout.endDate <= now,
              let distance = workout.distanceMeters,
              distance.isFinite,
              distance > 0,
              abs(distance - plannedDistanceMeters) <= plannedDistanceMeters * 0.05,
              workout.duration.isFinite,
              workout.duration > 0,
              workout.duration <= 86_400,
              distance <= workout.duration * 15
        else { return false }
        return true
    }

    static func eligibleProof(
        matchPercent: Double,
        startGapMeters: Double,
        endGapMeters: Double,
        measuredDistanceMeters: Double,
        plannedDistanceMeters: Double,
        elapsedSeconds: Double
    ) -> Bool {
        guard matchPercent.isFinite,
              (90...100).contains(matchPercent),
              startGapMeters.isFinite,
              (0...120).contains(startGapMeters),
              endGapMeters.isFinite,
              (0...120).contains(endGapMeters),
              plannedDistanceMeters.isFinite,
              (100...500_000).contains(plannedDistanceMeters),
              measuredDistanceMeters.isFinite,
              measuredDistanceMeters > 0,
              abs(measuredDistanceMeters - plannedDistanceMeters)
                  <= plannedDistanceMeters * 0.05,
              elapsedSeconds.isFinite,
              elapsedSeconds > 0,
              elapsedSeconds <= 86_400,
              measuredDistanceMeters <= elapsedSeconds * 15
        else { return false }
        return true
    }
}

struct ATHLTHArenaRouteProof {
    let matchPercent: Double
    let startGapMeters: Double
    let endGapMeters: Double
}

/// The route proof is evaluated locally from HealthKit GPS data.
/// Only summary metrics are shared after an explicit user action.
struct ATHLTHArenaEvidenceCandidate: Identifiable {
    let workout: SocialPublishableWorkout
    let match: ATHLTHArenaEvidenceMatcher.Match
    let sourceCheck: ATHLTHArenaLocalSourceCheck
    var routeProof: ATHLTHArenaRouteProof? = nil

    var id: UUID { workout.id }
}

struct ATHLTHArenaEvidenceSection: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var phone: IPhoneWorkoutStore
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let series: ATHLTHArenaRemoteSeries
    let rounds: [ATHLTHArenaRemoteProposal]

    @State private var entries: [ATHLTHArenaWorkoutEvidence] = []
    @State private var selectedRound: ATHLTHArenaRemoteProposal?
    @State private var routeCandidates: [UUID: [ATHLTHArenaEvidenceCandidate]] = [:]
    @State private var routeSearchingID: UUID?
    @State private var pendingWithdrawal: ATHLTHArenaWorkoutEvidence?
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var notice: String?

    private let cloud = ATHLTHArenaCloudService()

    private var workouts: [SocialPublishableWorkout] {
        let finishedStrength = strength.workoutHistory
            .filter(\.isFinished)
            .map(SocialPublishableWorkout.init(strengthWorkout:))
        let finishedPhone = phone.history
            .filter { $0.end != nil }
            .map(SocialPublishableWorkout.init(phoneWorkout:))
        let fromHealth = health.workouts.map(SocialPublishableWorkout.init(summary:))

        // Mirrored workouts can be saved with *different* IDs. Collapse
        // only near-identical activity, time span and distance snapshots.
        return ATHLTHArenaWorkoutIdentity.distinct(
            (finishedStrength + finishedPhone + fromHealth)
                .sorted { $0.endDate > $1.endDate }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Workouts linked to Arena",
                    norwegian: "Treningsøkter knyttet til Arena"
                ),
                systemImage: "link.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "ATHLTH checks that each suggested workout is present in your local Apple Health or ATHLTH history. Review the result before choosing to share it.",
                norwegian: "ATHLTH kontrollerer at foreslåtte økter finnes i Apple Health eller ATHLTH-historikken på enheten. Se over resultatet før du velger å dele."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)

            if series.status == "active" {
                ForEach(rounds) { round in
                    let available = candidates(for: round).count
                    let needsRouteSearch = round.template == .fastestRoute &&
                        routeCandidates[round.id] == nil
                    HStack(spacing: 9) {
                        Image(systemName: "figure.run.circle")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(round.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(available) " + ATHLTHLocalization.choose(
                                english: "matching workouts", norwegian: "aktuelle økter"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        if routeSearchingID == round.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                if round.template == .fastestRoute &&
                                   (needsRouteSearch || available == 0) {
                                    Task { await searchRouteCandidates(for: round) }
                                } else {
                                    selectedRound = round
                                }
                            } label: {
                                Text(needsRouteSearch || (round.template == .fastestRoute && available == 0)
                                    ? ATHLTHLocalization.choose(
                                        english: "Check GPS", norwegian: "Sjekk GPS"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Select", norwegian: "Velg"
                                    ))
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHTheme.accentDeep)
                            .disabled((available == 0 && round.template != .fastestRoute)
                                      || submitting || routeSearchingID != nil)
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                if rounds.contains(where: { $0.template == .fastestRoute }) {
                    Text(ATHLTHLocalization.choose(
                        english: "Route comparisons happen on your device using HealthKit GPS data. Only matching time, distance and percentage are shared if you choose a workout.",
                        norwegian: "Rutesammenligning skjer på enheten med GPS-data fra Apple Health. Bare tid, distanse og treffprosent deles dersom du selv velger en økt."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }

            if !entries.isEmpty {
                Text("\(entries.count) " + ATHLTHLocalization.choose(
                    english: "workout links shared in this competition",
                    norwegian: "øktkoblinger delt i denne konkurransen"
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

                ForEach(entries.filter { $0.userID == session.profile.userID }) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rounds.first { $0.id == entry.roundID }?.title ??
                                 ATHLTHLocalization.choose(
                                    english: "Arena round", norwegian: "Arena-runde"
                                 ))
                                .font(.caption.weight(.semibold))
                            Text(entry.startedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            if let match = entry.reportedRouteMatchPercent {
                                Text(String(format: "%.0f %%", match) + " · " +
                                     ATHLTHLocalization.choose(
                                        english: "Device-reported route match",
                                        norwegian: "Rutematch rapportert av enheten"
                                     ))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingWithdrawal = entry
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Remove", norwegian: "Fjern"
                            ), systemImage: "trash")
                        }
                        .font(.caption)
                        .disabled(submitting)
                    }
                    .padding(11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
                }
            }

            Text(ATHLTHLocalization.choose(
                english: "A local workout-history match is not server verification. Only the workout ID, source, timing and relevant metric are shared after consent. GPS tracks and heart rate stay private; group review is still required.",
                norwegian: "En lokal øktkobling er ikke serververifisering. Kun økt-ID, kilde, tidspunkt og relevant resultat deles etter samtykke. GPS-spor og puls forblir private; gruppen må fortsatt godkjenne."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: series.id) { await refresh() }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Remove this shared workout?",
                norwegian: "Fjerne denne delte økten?"
            ),
            isPresented: Binding(
                get: { pendingWithdrawal != nil },
                set: { if !$0 { pendingWithdrawal = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Remove shared metrics", norwegian: "Fjern delte øktdata"
            ), role: .destructive) {
                if let evidence = pendingWithdrawal {
                    Task { await withdraw(evidence) }
                }
                pendingWithdrawal = nil
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) { pendingWithdrawal = nil }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "The shared workout metadata will be removed. Previously approved aggregate competition points remain.",
                norwegian: "De delte øktdataene fjernes. Allerede godkjente sammenlagtpoeng beholdes."
            ))
        }
        .sheet(item: $selectedRound) { round in
            ATHLTHArenaEvidencePicker(
                round: round,
                candidates: candidates(for: round)
            ) { candidate in
                Task { await share(candidate, in: round) }
            }
        }
    }

    private func candidates(
        for round: ATHLTHArenaRemoteProposal
    ) -> [ATHLTHArenaEvidenceCandidate] {
        if round.template == .fastestRoute {
            return routeCandidates[round.id] ?? []
        }
        return workouts.compactMap { workout in
            guard !ATHLTHArenaWorkoutIdentity.alreadyShared(
                    workout,
                    entries: entries,
                    userID: session.profile.userID
                  ),
                  let match = ATHLTHArenaEvidenceMatcher.match(
                    workout,
                    template: round.template,
                    targetDistanceMeters: round.targetDistanceMeters,
                    startsAt: series.startsAt,
                    endsAt: series.endsAt
                  ) else {
                return nil
            }
            let localCheck = ATHLTHArenaLocalEvidenceCheck.verify(
                workout,
                health: health.workouts,
                phone: phone.history,
                strength: strength.workoutHistory
            )
            guard localCheck.isUsable else { return nil }
            return ATHLTHArenaEvidenceCandidate(
                workout: workout,
                match: match,
                sourceCheck: localCheck
            )
        }
        .prefix(30)
        .map { $0 }
    }

    /// Explicit on-demand comparison; never polls GPS history in the background.
    @MainActor
    private func searchRouteCandidates(for round: ATHLTHArenaRemoteProposal) async {
        guard routeSearchingID == nil,
              let snapshot = round.routeSnapshot,
              let route = ATHLTHArenaCompetitionCourse.route(
                from: snapshot, ownerID: session.profile.userID
              ),
              let startsAt = series.startsAt,
              let endsAt = series.endsAt else {
            errorMessage = ATHLTHLocalization.choose(
                english: "This competition route or time window is unavailable.",
                norwegian: "Konkurranseruten eller tidsvinduet er ikke gyldig."
            )
            return
        }

        routeSearchingID = round.id
        defer { routeSearchingID = nil }
        errorMessage = nil

        let targetMeters = snapshot.distanceKilometers * 1_000
        var matches: [ATHLTHArenaEvidenceCandidate] = []
        for summary in health.workouts
            .filter({
                ATHLTHArenaRouteEvidencePolicy.eligibleWorkout(
                    SocialPublishableWorkout(summary: $0),
                    plannedDistanceMeters: targetMeters,
                    startsAt: startsAt,
                    endsAt: endsAt
                )
            })
            .sorted { $0.endDate > $1.endDate }
            .prefix(25) {
            if Task.isCancelled { return }

            let workout = SocialPublishableWorkout(summary: summary)
            guard !ATHLTHArenaWorkoutIdentity.alreadyShared(
                workout, entries: entries, userID: session.profile.userID
            ) else { continue }

            guard let analysis = await health.routePerformance(for: summary, against: route),
                  ATHLTHArenaRouteEvidencePolicy.eligibleProof(
                    matchPercent: analysis.routeMatchPercent,
                    startGapMeters: analysis.startDistanceMeters,
                    endGapMeters: analysis.endDistanceMeters,
                    measuredDistanceMeters: analysis.distanceMeters,
                    plannedDistanceMeters: targetMeters,
                    elapsedSeconds: analysis.durationSeconds
                  ) else { continue }

            let localCheck = ATHLTHArenaLocalEvidenceCheck.verify(
                workout,
                health: health.workouts,
                phone: phone.history,
                strength: strength.workoutHistory
            )
            guard localCheck.isUsable else { continue }

            matches.append(ATHLTHArenaEvidenceCandidate(
                workout: workout,
                // Use the same HealthKit workout duration that the server
                // receives when the athlete explicitly shares this proof.
                // GPS analysis time is used for quality checks only.
                match: ATHLTHArenaEvidenceMatcher.Match(
                    metricType: "elapsed_seconds",
                    metricValue: workout.duration
                ),
                sourceCheck: localCheck,
                routeProof: ATHLTHArenaRouteProof(
                    matchPercent: analysis.routeMatchPercent,
                    startGapMeters: analysis.startDistanceMeters,
                    endGapMeters: analysis.endDistanceMeters
                )
            ))
        }
        guard !Task.isCancelled else { return }
        routeCandidates[round.id] = matches
        if matches.isEmpty {
            notice = ATHLTHLocalization.choose(
                english: "No matching GPS workouts found in Apple Health for this route and competition window. You can retry after importing a workout.",
                norwegian: "Fant ingen GPS-økter i Apple Health som matcher ruten og konkurranseperioden. Du kan prøve igjen etter import."
            )
        } else {
            notice = nil
            selectedRound = round
        }
    }

    @MainActor
    private func refresh() async {
        do {
            entries = try await cloud.loadWorkoutEvidence(seriesID: series.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func withdraw(_ evidence: ATHLTHArenaWorkoutEvidence) async {
        guard !submitting else { return }
        submitting = true
        defer { submitting = false }
        do {
            try await cloud.withdrawWorkoutEvidence(id: evidence.id)
            notice = ATHLTHLocalization.choose(
                english: "Shared workout metadata removed.",
                norwegian: "Delte øktdata er fjernet."
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func share(
        _ candidate: ATHLTHArenaEvidenceCandidate,
        in round: ATHLTHArenaRemoteProposal
    ) async {
        guard !submitting else { return }
        let localCheck = ATHLTHArenaLocalEvidenceCheck.verify(
            candidate.workout,
            health: health.workouts,
            phone: phone.history,
            strength: strength.workoutHistory
        )
        guard localCheck.isUsable else {
            errorMessage = localCheck.description
            return
        }
        if round.template == .fastestRoute {
            guard let snapshot = round.routeSnapshot,
                  let proof = candidate.routeProof,
                  ATHLTHArenaRouteEvidencePolicy.eligibleWorkout(
                    candidate.workout,
                    plannedDistanceMeters: snapshot.distanceKilometers * 1_000,
                    startsAt: series.startsAt,
                    endsAt: series.endsAt
                  ),
                  ATHLTHArenaRouteEvidencePolicy.eligibleProof(
                    matchPercent: proof.matchPercent,
                    startGapMeters: proof.startGapMeters,
                    endGapMeters: proof.endGapMeters,
                    measuredDistanceMeters: candidate.workout.distanceMeters ?? 0,
                    plannedDistanceMeters: snapshot.distanceKilometers * 1_000,
                    elapsedSeconds: candidate.match.metricValue
                  ) else {
                errorMessage = ATHLTHLocalization.choose(
                    english: "This GPS result no longer meets the route requirements. Check GPS again.",
                    norwegian: "GPS-resultatet oppfyller ikke lenger rutekravene. Sjekk GPS på nytt."
                )
                routeCandidates[round.id] = nil
                return
            }
        } else if candidate.routeProof != nil {
            errorMessage = ATHLTHLocalization.choose(
                english: "The selected workout does not belong to this round.",
                norwegian: "Den valgte økten tilhører ikke denne runden."
            )
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            if let proof = candidate.routeProof {
                try await cloud.shareRouteWorkoutEvidence(
                    roundID: round.id,
                    workout: candidate.workout,
                    matchPercent: proof.matchPercent,
                    startGapMeters: proof.startGapMeters,
                    endGapMeters: proof.endGapMeters
                )
            } else {
                try await cloud.shareWorkoutEvidence(
                    roundID: round.id,
                    workout: candidate.workout,
                    metricType: candidate.match.metricType,
                    metricValue: candidate.match.metricValue
                )
            }
            notice = ATHLTHLocalization.choose(
                english: "Workout added for group review.",
                norwegian: "Økten er delt til vurdering i gruppen."
            )
            routeCandidates[round.id] = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ATHLTHArenaEvidencePicker: View {
    @Environment(\.dismiss) private var dismiss
    let round: ATHLTHArenaRemoteProposal
    let candidates: [ATHLTHArenaEvidenceCandidate]
    let onShare: (ATHLTHArenaEvidenceCandidate) -> Void

    @State private var candidateToConfirm: ATHLTHArenaEvidenceCandidate?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose the workout you want to share. This does not award points automatically.",
                        norwegian: "Velg hvilken økt du vil dele. Dette gir ikke poeng automatisk."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                ForEach(candidates) { candidate in
                    Button {
                        candidateToConfirm = candidate
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: candidate.workout.activity == .strength
                                ? "dumbbell.fill" : "figure.run")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.workout.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(candidate.workout.startDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(candidate.sourceCheck.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let proof = candidate.routeProof {
                                    Text(String(format: "GPS-rutematch %.0f %%", proof.matchPercent))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                            }
                            Spacer()
                            Text(candidate.match.formatted)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(round.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) { dismiss() }
                }
            }
            .confirmationDialog(
                ATHLTHLocalization.choose(
                    english: "Share workout with participants?",
                    norwegian: "Dele økten med deltakerne?"
                ),
                isPresented: Binding(
                    get: { candidateToConfirm != nil },
                    set: { if !$0 { candidateToConfirm = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(ATHLTHLocalization.choose(
                    english: "Share workout evidence",
                    norwegian: "Del øktresultatet"
                )) {
                    if let candidateToConfirm {
                        onShare(candidateToConfirm)
                        dismiss()
                    }
                    candidateToConfirm = nil
                }
                Button(ATHLTHLocalization.choose(
                    english: "Cancel", norwegian: "Avbryt"
                ), role: .cancel) { candidateToConfirm = nil }
            } message: {
                Text(candidateToConfirm?.routeProof != nil
                    ? ATHLTHLocalization.choose(
                        english: "Participants will see the workout time, distance and device-reported route match. Your GPS track is never uploaded. These measurements still require group approval.",
                        norwegian: "Deltakerne ser tid, distanse og rutematch rapportert av enheten. GPS-sporet lastes ikke opp. Resultatet må fortsatt godkjennes av gruppen."
                    )
                    : ATHLTHLocalization.choose(
                        english: "Participants will see the workout timestamp, source and result, not your GPS track or heart rate.",
                        norwegian: "Deltakerne får se tidspunkt, øktkilde og resultat, ikke GPS-spor eller puls."
                    )
                )
            }
        }
    }
}
