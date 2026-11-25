import SwiftUI

/// One shared competition event, not a league with fake pairwise fixtures.
/// Actual workout recording stays with the universal ATHLTH workout engine.
struct ATHLTHTournamentSingleEventView: View {
    @Environment(\.scenePhase) private var scenePhase
    let tournament: ATHLTHTournamentRemote
    let userID: UUID
    let names: [UUID: String]
    let onChanged: () async -> Void

    @State private var entries: [ATHLTHTournamentSingleEventResult] = []
    @State private var eligible: [ATHLTHTournamentEligibleWorkout] = []
    @State private var chosenWorkout: UUID?
    @State private var scoreText = ""
    @State private var exercises: [ATHLTHTournamentScoredExercise] = []
    @State private var exerciseValues: [UUID: String] = [:]
    @State private var exerciseDetails: [ATHLTHTournamentExerciseScoreDetail] = []
    @State private var evidence = ""
    @State private var busy = false
    @State private var loading = true
    @State private var errorMessage: String?
    private let cloud = ATHLTHTournamentSingleEventCloud()

    private var isOrganizer: Bool { tournament.ownerID == userID }
    private var started: Bool {
        tournament.status == "active" || tournament.status == "completed"
    }
    private var usesExerciseScores: Bool { tournament.raceRules.exerciseScoringVersion == 1 }

    private var parsedExerciseScores: [String: Double]? {
        guard !exercises.isEmpty else { return nil }
        var scores: [String: Double] = [:]
        for exercise in exercises {
            guard let raw = exerciseValues[exercise.id],
                  let value = Double(raw.replacingOccurrences(of: ",", with: ".")),
                  exercise.accepts(value) else { return nil }
            scores[exercise.id.uuidString.lowercased()] = value
        }
        return scores
    }

    private var canReport: Bool {
        guard started, tournament.status == "active",
              tournament.raceSignalAt.map({ Date() >= $0 }) == true,
              !busy,
              (3...500).contains(evidence.trimmingCharacters(
                  in: .whitespacesAndNewlines).count),
              entries.contains(where: { $0.userID == userID &&
                  $0.progress != "finished" })
        else { return false }
        if usesExerciseScores { return parsedExerciseScores != nil }
        guard let score = Double(scoreText.replacingOccurrences(of: ",", with: ".")),
              score.isFinite, score >= 0, score <= 100_000_000 else { return false }
        if tournament.raceRules.recordingDevice == .appleWatch {
            return false // Secure source provenance must arrive from Watch.
        }
        if tournament.raceRules.discipline == .sprint {
            return chosenWorkout != nil
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(tournament.displayFormatTitle, systemImage: tournament.displayFormatSymbol)
                    .font(.headline)
                Spacer()
                Text("\(entries.count) utøvere")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(usesExerciseScores ? "Øvelser og sammenlagtpoeng" : tournament.raceRules.discipline.title)
                    .font(.system(size: 25, design: .serif))
                if usesExerciseScores {
                    Text(tournament.selectedBranchesLabel).font(.subheadline)
                    Text("Hver øvelse rangeres separat. Førsteplass gir poeng lik antall deltakere, andreplass ett mindre. Like resultater får like poeng.")
                        .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                    ForEach(exercises) { exercise in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.title).font(.subheadline.weight(.semibold))
                            Text(exercise.instruction).font(.caption)
                        }
                    }
                }
                if tournament.raceRules.discipline == .sprint {
                    Text(tournament.raceRules.sprintMode.title)
                        .font(.subheadline)
                }
                if tournament.raceRules.discipline == .laps {
                    Text("\(tournament.raceRules.lapCount) runder · " +
                         tournament.raceRules.lapCourseName)
                        .font(.subheadline)
                }
                if tournament.raceRules.recordingDevice != .any {
                    Label(tournament.raceRules.recordingDevice.title,
                          systemImage: "applewatch")
                        .font(.caption)
                }
                if !tournament.raceRules.equipmentRules.isEmpty {
                    Text("Utstyr: " + tournament.raceRules.equipmentRules)
                        .font(.caption)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHArenaV3Style.panel())

            if tournament.status == "inviting" {
                Label("Venter på at alle skal godta og trykke Klar",
                      systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            } else if let signal = tournament.raceSignalAt,
                      tournament.status == "active" {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = max(0, Int(ceil(
                        signal.timeIntervalSince(timeline.date))))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(remaining > 0 ? "Start om" : "Startsignal gitt")
                            .font(.caption.weight(.semibold))
                        Text(remaining > 0 ? "\(remaining)" : "START")
                            .font(.system(size: 36, weight: .semibold,
                                          design: .rounded))
                            .monospacedDigit()
                        Text(remaining > 0
                             ? "Trening som starter før startsignalet, er ikke gyldig."
                             : "Bruk den universelle treningsmotoren til å registrere økten.")
                            .font(.caption)
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ATHLTHArenaV3Style.panel())
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Deltakere")
                        .font(.system(size: 22, design: .serif))
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Oppdater", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .tint(ATHLTHArenaV3Style.gold)
                }
                if loading { ProgressView("Henter status…") }
                if entries.isEmpty && !loading {
                    Text("Deltakerstatus kommer når konkurransen er godkjent.")
                        .font(.caption)
                }
                ForEach(entries) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 10) {
                            Image(systemName: result.progress == "finished"
                                  ? "checkmark.circle.fill" : "clock")
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                            Text(names[result.userID] ?? "Utøver")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(result.statusLabel)
                                .font(.caption)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        if let score = result.score {
                            Text((usesExerciseScores ? "Poeng: " : "Resultat: ") + score.formatted() +
                                 (result.rank.map { " · Plass \($0)" } ?? ""))
                                .font(.caption.weight(.medium))
                        } else if result.progress == "finished" ||
                                  result.progress == "awaiting_review" {
                            Label("Resultatet er skjult til alle er ferdige",
                                  systemImage: "lock")
                                .font(.caption)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        if usesExerciseScores, let detail = exerciseDetails.first(where: { $0.userID == result.userID }) {
                            ForEach(exercises) { exercise in
                                if let value = detail.exerciseScores[exercise.id.uuidString.lowercased()] {
                                    HStack {
                                        Text(exercise.title)
                                        Spacer()
                                        Text(value.formatted() + " " + exercise.unit).monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                            if let note = detail.evidenceNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                        }
                        if result.progress == "awaiting_review" &&
                            (tournament.isDuel ? (result.userID != userID && entries.contains { $0.userID == userID && ($0.progress == "awaiting_review" || $0.progress == "finished") }) : isOrganizer) {
                            HStack(spacing: 11) {
                                Button("Godkjenn") {
                                    Task { await review(result.userID, true) }
                                }
                                Button("Avslå") {
                                    Task { await review(result.userID, false) }
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .tint(ATHLTHArenaV3Style.gold)
                            .disabled(busy)
                        }
                    }
                    .padding(.vertical, 9)
                    Divider().opacity(0.3)
                }
            }
            .padding(15)
            .background(ATHLTHArenaV3Style.panel())

            if tournament.status == "active",
               entries.contains(where: { $0.userID == userID &&
                    $0.progress != "finished" }) {
                reporting
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task(id: tournament.id) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private var reporting: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registrer gjennomføring")
                .font(.system(size: 21, design: .serif))
            Text("Resultatet kontrolleres av arrangøren før alle poeng offentliggjøres.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            if tournament.raceRules.recordingDevice == .appleWatch {
                Label("Denne konkurransen krever verifisert Apple Watch-kilde. Automatisk kontroll av opptaksenhet må kobles ferdig til treningsmotoren før innlevering kan godkjennes.",
                      systemImage: "applewatch.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if usesExerciseScores {
                ForEach(exercises) { exercise in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.title).font(.subheadline.weight(.semibold))
                        Text(exercise.instruction).font(.caption).foregroundStyle(.secondary)
                        TextField(exercise.unit, text: Binding(
                            get: { exerciseValues[exercise.id, default: ""] },
                            set: { exerciseValues[exercise.id] = $0 }))
                            .keyboardType(.decimalPad)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                TextField(scoreTitle, text: $scoreText)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }

            TextField("Beskriv gjennomføringen", text: $evidence,
                      axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: evidence) { _, text in
                    if text.count > 500 {
                        evidence = String(text.prefix(500))
                    }
                }

            if tournament.raceRules.discipline == .sprint {
                if eligible.isEmpty {
                    Text("Sprint krever en verifisert ATHLTH-økt etter startsignalet. Ingen tilgjengelige økter ble funnet.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Picker("Verifisert treningsøkt", selection: $chosenWorkout) {
                        Text("Velg økt").tag(UUID?.none)
                        ForEach(eligible.filter { $0.sourceWorkoutID != nil }) {
                            item in
                            Text(item.startedAt.map {
                                $0.formatted(date: .abbreviated,
                                             time: .shortened)
                            } ?? "Verifisert økt")
                                .tag(item.sourceWorkoutID)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? "Sender resultat…" : "Send til godkjenning")
                    Spacer()
                    Image(systemName: "checkmark.shield")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(14)
                .background(ATHLTHArenaV3Style.ink,
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canReport)
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var scoreTitle: String {
        switch tournament.raceRules.discipline {
        case .sprint:
            return tournament.raceRules.sprintTarget == .duration
                ? "Distanse (meter)" : "Tid (sekunder)"
        case .distance, .laps:
            return "Tid (sekunder)"
        case .duration:
            return "Distanse (meter)"
        case .workout:
            return "Treningsresultat (volum / repetisjoner)"
        }
    }

    @MainActor private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await cloud.statuses(tournamentID: tournament.id)
            if usesExerciseScores {
                exercises = try await cloud.exercises(tournamentID: tournament.id)
                exerciseDetails = try await cloud.exerciseDetails(tournamentID: tournament.id)
                if let own = exerciseDetails.first(where: { $0.userID == userID }) {
                    for exercise in exercises where exerciseValues[exercise.id] == nil {
                        if let score = own.exerciseScores[exercise.id.uuidString.lowercased()] {
                            exerciseValues[exercise.id] = String(score)
                        }
                    }
                    if evidence.isEmpty { evidence = own.evidenceNote ?? "" }
                }
            } else if let started = tournament.raceSignalAt {
                eligible = (try? await cloud.eligibleWorkouts(
                    userID: userID, after: started)) ?? []
            }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func submit() async {
        guard canReport else { return }
        busy = true
        defer { busy = false }
        do {
            if usesExerciseScores, let scores = parsedExerciseScores {
                try await cloud.submitExercises(tournamentID: tournament.id, scores: scores, evidence: evidence)
            } else if let score = Double(scoreText.replacingOccurrences(of: ",", with: ".")) {
                try await cloud.submit(
                    tournamentID: tournament.id, score: score,
                    laps: tournament.raceRules.discipline == .laps
                        ? tournament.raceRules.lapCount : nil,
                    evidence: evidence, workoutID: chosenWorkout
                )
            } else { return }
            await refresh()
            await onChanged()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func review(_ athlete: UUID, _ approved: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.review(
                tournamentID: tournament.id, athlete: athlete, approve: approved
            )
            await refresh()
            await onChanged()
        } catch { errorMessage = error.localizedDescription }
    }
}
