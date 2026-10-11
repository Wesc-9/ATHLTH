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

struct ATHLTHArenaEvidenceCandidate: Identifiable {
    let workout: SocialPublishableWorkout
    let match: ATHLTHArenaEvidenceMatcher.Match
    let sourceCheck: ATHLTHArenaLocalSourceCheck

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
                        Button {
                            selectedRound = round
                        } label: {
                            Text(ATHLTHLocalization.choose(
                                english: "Select", norwegian: "Velg"
                            ))
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(available == 0 || submitting)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
        workouts.compactMap { workout in
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
        submitting = true
        defer { submitting = false }
        do {
            try await cloud.shareWorkoutEvidence(
                roundID: round.id,
                workout: candidate.workout,
                metricType: candidate.match.metricType,
                metricValue: candidate.match.metricValue
            )
            notice = ATHLTHLocalization.choose(
                english: "Workout added for group review.",
                norwegian: "Økten er delt til vurdering i gruppen."
            )
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
                Text(ATHLTHLocalization.choose(
                    english: "Participants will see the workout timestamp, source and result, not your GPS track or heart rate.",
                    norwegian: "Deltakerne får se tidspunkt, øktkilde og resultat, ikke GPS-spor eller puls."
                ))
            }
        }
    }
}
