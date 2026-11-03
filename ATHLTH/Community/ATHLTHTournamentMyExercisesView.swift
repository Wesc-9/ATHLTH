import SwiftUI

/// Exercise deadlines belong to the actual match, not a generic tournament
/// calendar. One missing completion causes a walkover after the server cutoff.
struct ATHLTHTournamentMyExercisesView: View {
    let tournament: ATHLTHTournamentRemote
    let matches: [ATHLTHTournamentRemoteMatch]
    let userID: UUID

    @State private var candidates: [ATHLTHTournamentExerciseCandidateRemote] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var slots: [ATHLTHTournamentMatchExerciseRemote] = []
    @State private var completions: [ATHLTHTournamentExerciseCompletionRemote] = []
    @State private var reportSlot: ATHLTHTournamentMatchExerciseRemote?
    @State private var errorMessage: String?
    @State private var loading = false

    private let cloud = ATHLTHTournamentLobbyCloudService()

    private var relevantMatches: [ATHLTHTournamentRemoteMatch] {
        matches.filter {
            !$0.isWarmup && !$0.isBye &&
            ($0.homeID == userID || $0.awayID == userID)
        }
        .sorted { a,b in
            let at = a.deadlineAt ?? .distantFuture
            let bt = b.deadlineAt ?? .distantFuture
            return at < bt
        }
    }

    var body: some View {
        VStack(alignment: .leading,spacing: 13) {
            HStack {
                Text("Mine øvelser")
                    .font(.system(size: 23,weight: .regular,design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
            }
            Text("Gjennomfør hver øvelse innen fristen. Hvis motstanderen har registrert gjennomføring og du ikke har det, blir det walkover når fristen går ut.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                .fixedSize(horizontal: false,vertical: true)

            if let errorMessage {
                Label(errorMessage,systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if loading { ProgressView("Henter øvelser…") }

            let currentMatches = relevantMatches.prefix(5)
            ForEach(Array(currentMatches)) { match in
                VStack(alignment: .leading,spacing: 10) {
                    HStack {
                        Text(match.phase == .group
                             ? "Gruppe \((match.groupIndex ?? 0)+1)"
                             : "Runde \(match.roundNumber)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(match.status == "confirmed" ? "Avgjort" : "Pågående")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    let exercises = slots.filter { $0.matchID == match.id }
                        .sorted { $0.position < $1.position }
                    if exercises.isEmpty {
                        Text("Øvelsesfrister vises når oppgjøret er planlagt.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    ForEach(exercises) { slot in
                        let candidate = candidates.first { $0.id == slot.candidateID }
                        let recorded = completions.contains {
                            $0.matchExerciseID == slot.id && $0.userID == userID
                        }
                        HStack(alignment: .center,spacing: 10) {
                            Image(systemName: recorded
                                  ? "checkmark.circle.fill"
                                  : slot.state == "walkover"
                                  ? "flag.fill" : "circle")
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                            VStack(alignment: .leading,spacing: 4) {
                                Text(candidate.flatMap {
                                    exerciseNames[$0.exerciseID]
                                } ?? "Øvelse \(slot.position)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                                Text("Frist " + slot.deadlineAt.formatted(
                                    date: .abbreviated,time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                                if slot.state == "walkover" {
                                    Text("Walkover registrert")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                } else if slot.state == "disputed" {
                                    Text("Må avklares av arrangør")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 4)
                            if recorded {
                                Text("Utført")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                            } else if match.status != "confirmed" &&
                                      slot.state == "pending" &&
                                      slot.deadlineAt > Date() &&
                                      (match.scheduledAt ?? .distantPast) <= Date() {
                                Button("Registrer") { reportSlot = slot }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                            }
                        }
                        .padding(.vertical,8)
                        Divider().opacity(0.45)
                    }
                }
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }
        }
        .task(id: matches.map(\.id)) { await reload() }
        .sheet(item: $reportSlot) { slot in
            ATHLTHTournamentExerciseEvidenceSheet(
                exerciseName: candidates.first(where: {
                    $0.id == slot.candidateID
                }).flatMap { exerciseNames[$0.exerciseID] } ?? "Øvelse",
                deadline: slot.deadlineAt
            ) { note in
                try await cloud.completeExercise(
                    slotID: slot.id,evidence: note
                )
                await reload()
            }
        }
    }

    @MainActor
    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading=false }
        do {
            async let selected = cloud.candidates(tournamentID: tournament.id)
            async let exercises = cloud.matchExercises(
                matchIDs: relevantMatches.map(\.id)
            )
            let newCandidates = try await selected
            let newSlots = try await exercises
            async let recorded = cloud.completions(slotIDs: newSlots.map(\.id))
            async let exerciseNamesTask = cloud.exerciseNames(
                ids: Set(newCandidates.map(\.exerciseID))
            )
            candidates = newCandidates
            slots = newSlots
            completions = try await recorded
            exerciseNames = try await exerciseNamesTask
            errorMessage = nil
        } catch {
            errorMessage = "Kunne ikke hente øvelsesfrister: " +
                error.localizedDescription
        }
    }
}

private struct ATHLTHTournamentExerciseEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exerciseName: String
    let deadline: Date
    let onSubmit: @MainActor (String) async throws -> Void

    @State private var evidence = ""
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading,spacing: 17) {
                Text(exerciseName)
                    .font(.system(size: 28,design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Label("Siste frist: " +
                      deadline.formatted(date: .abbreviated,time: .shortened),
                      systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                Text("Beskriv hva du gjennomførte. Registreringen er tidsstemplet og synlig i konkurransen. Korrekt treningsresultat må fortsatt godkjennes etter konkurransereglene.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                TextField("Beskriv gjennomføringen",text: $evidence,axis: .vertical)
                    .lineLimit(3...6)
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Button {
                    Task {
                        submitting=true
                        defer { submitting=false }
                        do {
                            try await onSubmit(evidence.trimmingCharacters(
                                in: .whitespacesAndNewlines))
                            dismiss()
                        } catch { errorMessage=error.localizedDescription }
                    }
                } label: {
                    HStack {
                        if submitting { ProgressView().tint(.white) }
                        Text("Registrer gjennomført")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity,minHeight: 52)
                    .background(ATHLTHArenaV3Style.ink,in: Capsule())
                }
                .disabled(submitting || evidence.trimmingCharacters(
                    in: .whitespacesAndNewlines).count<3 || evidence.count>500 ||
                    deadline<=Date())
                Spacer()
            }
            .padding(18)
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Gjennomføring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium,.large])
    }
}
