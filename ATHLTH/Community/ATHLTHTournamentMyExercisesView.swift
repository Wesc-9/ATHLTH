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
    @State private var autoReporting = false

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
            Text(tournament.releaseMode == "all_at_start"
                ? "Alle øvelser i oppgjøret er tilgjengelige fra samme starttidspunkt. Gjennomfør i valgfri rekkefølge."
                : tournament.releaseMode == "everyone_finished"
                ? "Neste øvelse åpnes når alle har godkjent forrige resultat, eller når den forrige fristen er behandlet. Uteblitt øvelse gir 0 poeng."
                : "Hver øvelse har en egen gjennomføringsfrist. Uteblitt øvelse gir 0 poeng; oppgjøret avgjøres først når alle øvelser er vurdert.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                .fixedSize(horizontal: false,vertical: true)

            if ATHLTHCompetitionAutoReporting.supports(tournament) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Send gjennomføring automatisk", isOn: Binding(
                        get: { autoReporting },
                        set: { value in
                            ATHLTHCompetitionAutoReporting.setEnabled(value, tournamentID: tournament.id, userID: userID)
                            autoReporting = value
                        }))
                        .tint(ATHLTHArenaV3Style.gold)
                    Text("Entydige målinger fra nye økter på denne enheten sendes som gjennomføringsbevis til motstanderen. Kampresultatet følger konkurransens vanlige godkjenning. Kun én konkurranse om gangen.")
                        .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                }.padding(15).background(ATHLTHArenaV3Style.panel())
            }
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
                        exerciseSlotRow(slot, match: match)
                    }
                }
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }
        }
        .task(id: matches.map(\.id)) {
            autoReporting = ATHLTHCompetitionAutoReporting.enabled(tournamentID: tournament.id, userID: userID)
            await reload()
        }
        .sheet(item: $reportSlot) { slot in
            ATHLTHTournamentExerciseEvidenceSheet(
                requiresVerifiedWorkout: tournament.raceRules.discipline == .sprint,
                userID: userID,
                earliestStart: slot.scheduledAt.addingTimeInterval(
                    tournament.raceRules.discipline == .sprint ? TimeInterval(tournament.raceRules.countdownSeconds) : 0),
                exerciseName: candidates.first(where: {
                    $0.id == slot.candidateID
                }).flatMap { exerciseNames[$0.lookupID] } ?? "Øvelse",
                deadline: slot.deadlineAt
            ) { note, sourceWorkoutID in
                try await cloud.completeExercise(
                    slotID: slot.id,evidence: note,
                    sourceWorkoutID: sourceWorkoutID
                )
                await reload()
            }
        }
    }

    @ViewBuilder
    private func exerciseSlotRow(
        _ slot: ATHLTHTournamentMatchExerciseRemote,
        match: ATHLTHTournamentRemoteMatch
    ) -> some View {
        let candidate = candidates.first { $0.id == slot.candidateID }
        let ownCompletion = completions.first {
            $0.matchExerciseID == slot.id && $0.userID == userID
        }
        let recorded = ownCompletion != nil
        let opponentID = match.homeID == userID
            ? match.awayID : match.homeID
        let unreviewedOpponent = completions.first {
            $0.matchExerciseID == slot.id &&
            $0.userID == opponentID &&
            $0.reviewStatus == "submitted"
        }

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center,spacing: 10) {
                Image(systemName: recorded
                      ? "checkmark.circle.fill"
                      : slot.state == "walkover"
                      ? "flag.fill" : "circle")
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                VStack(alignment: .leading,spacing: 4) {
                    Text(candidate.flatMap {
                        exerciseNames[$0.lookupID]
                    } ?? "Øvelse \(slot.position)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    if tournament.raceRules.discipline == .sprint {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let start = slot.scheduledAt.addingTimeInterval(
                                TimeInterval(tournament.raceRules.countdownSeconds))
                            let seconds = max(0, Int(ceil(start.timeIntervalSince(
                                context.date))))
                            Label(seconds == 0 ? "Startsignal gitt" :
                                  "Startsperre · \(seconds) sek",
                                  systemImage: "timer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                        }
                    }
                    if slot.scheduledAt > Date() {
                        Text("Åpner " + slot.scheduledAt.formatted(
                            date: .abbreviated,time: .shortened))
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    Text("Frist " + slot.deadlineAt.formatted(
                        date: .abbreviated,time: .shortened))
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    if tournament.releaseMode == "everyone_finished" &&
                        slot.scheduledAt >= Date(timeIntervalSince1970: 4_070_908_800) {
                        Text("Venter på at alle fullfører forrige øvelse")
                            .font(.caption2)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    if tournament.releaseMode != "" &&
                        slot.deadlineAt <= Date() &&
                        ownCompletion?.reviewStatus != "approved" &&
                        ownCompletion?.reviewStatus != "submitted" {
                        Text("0 poeng · fristen er utløpt")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if slot.state == "walkover" {
                        Text(tournament.releaseMode == "everyone_finished" ||
                             tournament.releaseEvery > 0
                             ? "Øvelsen er avgjort"
                             : "Walkover registrert")
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
                    Text(ownCompletion?.reviewStatus == "approved"
                         ? "Godkjent" :
                         ownCompletion?.reviewStatus == "disputed"
                         ? "Bestridt" : "Til godkjenning")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                } else if match.status != "confirmed" &&
                          slot.state == "pending" &&
                          slot.deadlineAt > Date() &&
                          slot.scheduledAt.addingTimeInterval(
                             tournament.raceRules.discipline == .sprint
                             ? TimeInterval(tournament.raceRules.countdownSeconds)
                             : 0) <= Date() {
                    Button("Registrer") { reportSlot = slot }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
            }
            .padding(.vertical,8)
            if let opponent = unreviewedOpponent,
               slot.state == "pending" {
                VStack(alignment: .leading,spacing: 7) {
                    Text("Motstanderen har registrert øvelsen.")
                        .font(.caption)
                    HStack(spacing: 15) {
                        Button("Godkjenn") {
                            Task { await review(slot: slot,
                                athleteID: opponent.userID,
                                approved: true) }
                        }
                        Button("Bestrid") {
                            Task { await review(slot: slot,
                                athleteID: opponent.userID,
                                approved: false) }
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
                .padding(10)
                .frame(maxWidth: .infinity,alignment: .leading)
                .background(ATHLTHArenaV3Style.cream,
                    in: RoundedRectangle(cornerRadius: 11))
            }
            Divider().opacity(0.45)

        }
    }

    @MainActor
    private func review(
        slot: ATHLTHTournamentMatchExerciseRemote,
        athleteID: UUID, approved: Bool
    ) async {
        do {
            try await cloud.reviewExercise(
                slotID: slot.id,athleteID: athleteID,approve: approved
            )
            await reload()
        } catch {
            errorMessage = error.localizedDescription
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
            async let exerciseNamesTask = cloud.candidateNames(newCandidates)
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
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var phone: IPhoneWorkoutStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    let requiresVerifiedWorkout: Bool
    let userID: UUID
    let earliestStart: Date
    let exerciseName: String
    let deadline: Date
    let onSubmit: @MainActor (String, UUID?) async throws -> Void

    @State private var evidence = ""
    @State private var verifiedWorkouts: [ATHLTHTournamentEligibleWorkout] = []
    @State private var selectedWorkoutID: UUID?
    @State private var selectedLocalID: UUID?
    @State private var submitting = false
    @State private var errorMessage: String?

    private var localWorkouts: [SocialPublishableWorkout] {
        ATHLTHArenaWorkoutIdentity.distinct(
            (phone.history.filter { $0.end != nil }.map(SocialPublishableWorkout.init(phoneWorkout:)) +
             strength.workoutHistory.filter(\.isFinished).map(SocialPublishableWorkout.init(strengthWorkout:)) +
             health.workouts.map(SocialPublishableWorkout.init(summary:)))
                .filter { $0.startDate >= earliestStart && $0.endDate <= deadline && $0.endDate <= Date() &&
                    ATHLTHArenaLocalEvidenceCheck.verify($0, health: health.workouts,
                        phone: phone.history, strength: strength.workoutHistory).isUsable }
                .sorted { $0.endDate > $1.endDate })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                if !requiresVerifiedWorkout && !localWorkouts.isEmpty {
                    Picker("Hent fra treningshistorikken", selection: Binding(
                        get: { selectedLocalID },
                        set: { id in
                            selectedLocalID = id
                            if let workout = localWorkouts.first(where: { $0.id == id }) {
                                evidence = "Fra lokal økthistorikk: " + workout.title + " · " +
                                    workout.endDate.formatted(date: .abbreviated, time: .shortened)
                                if let distance = workout.distanceMeters {
                                    evidence += " · " + (distance/1000).formatted() + " km"
                                }
                                evidence += " · " + (workout.duration/60).formatted(.number.precision(.fractionLength(0...1))) + " min"
                            }
                        })) {
                        Text("Manuelt").tag(UUID?.none)
                        ForEach(localWorkouts) { workout in
                            Text(workout.title + " · " + workout.endDate.formatted(date: .abbreviated, time: .shortened))
                                .tag(Optional(workout.id))
                        }
                    }
                    Text("Kontroller at den valgte økten gjelder konkurranseøvelsen. Lokal historikk er ikke serververifisering.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Beskriv gjennomføringen",text: $evidence,axis: .vertical)
                    .lineLimit(3...6)
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())
                if requiresVerifiedWorkout {
                    if verifiedWorkouts.isEmpty {
                        Label("Ingen verifiserte ATHLTH-økter funnet etter startsignalet. Start og fullfør en økt før du registrerer sprintresultatet.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Picker("Verifisert sprintøkt", selection: $selectedWorkoutID) {
                            Text("Velg økt").tag(UUID?.none)
                            ForEach(verifiedWorkouts) { workout in
                                Text(workout.startedAt.map {
                                    $0.formatted(date: .abbreviated,
                                                 time: .shortened)
                                } ?? "Verifisert økt")
                                    .tag(workout.sourceWorkoutID)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Button {
                    Task {
                        submitting=true
                        defer { submitting=false }
                        do {
                            try await onSubmit(evidence.trimmingCharacters(
                                in: .whitespacesAndNewlines),
                                selectedWorkoutID)
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
                    deadline<=Date() ||
                    (requiresVerifiedWorkout && selectedWorkoutID == nil))
                Spacer()
            }
            .padding(18)
            }
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Gjennomføring")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard requiresVerifiedWorkout else { return }
                verifiedWorkouts = (try? await ATHLTHTournamentSingleEventCloud()
                    .eligibleWorkouts(userID: userID, after: earliestStart)) ?? []
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium,.large])
    }
}
