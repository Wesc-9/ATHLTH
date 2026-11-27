import SwiftUI

struct ATHLTHTournamentCoachDraft: Decodable {
    let title: String
    let exerciseIDs: [UUID]
    let exerciseNames: [String]
    let startMode: String
    let environment: String
    let releaseEvery: Int
    let completionHours: Int
    let allowedRules: String
    let prohibitedRules: String
    let explanation: String
}

/// Local selection over server-supported catalog entries. The free-text goal
/// never goes to the catalog service or an external language model.
enum ATHLTHTournamentLocalCoachPolicy {
    static func suggest(prompt: String, activities: [ATHLTHTournamentActivity],
                        exerciseCount: Int, catalog: [ATHLTHTournamentExerciseSearchResult]) -> ATHLTHTournamentCoachDraft? {
        let allowed = Set(activities.filter(\.isAvailableForCreation))
        guard !allowed.isEmpty, (1...12).contains(exerciseCount) else { return nil }
        let clean = prompt.lowercased()
        let environment: ATHLTHCompetitionEnvironment =
            clean.contains("kun ute") || clean.contains("only outdoor") ? .outdoor :
            clean.contains("kun treningssenter") || clean.contains("gym only") ? .gym : .any
        guard environment.canPublish(for: allowed) else { return nil }
        // Only match words against known entries. Never manufacture IDs or
        // exercise names. If an explicit muscle focus cannot be resolved,
        // ask the athlete to choose manually rather than silently ignore it.
        let focusAliases: [(String, [String])] = [
            ("rygg", ["row", "pull", "lat", "back", "roing", "rygg"]),
            ("bryst", ["chest", "bench press", "push up", "bryst"]),
            ("bein", ["squat", "lunge", "leg", "knebøy", "utfall"]),
            ("lår", ["squat", "lunge", "leg", "knebøy", "utfall"])
        ]
        let focus = focusAliases.first { clean.contains($0.0) }?.1
        let tokens = clean.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 4 }
        var seen = Set<UUID>()
        let eligible = catalog.filter { item in
            guard allowed.contains(item.activity), seen.insert(item.id).inserted else { return false }
            if let focus, item.activity == .strength {
                return focus.contains { item.name.lowercased().contains($0) }
            }
            return true
        }
        func score(_ item: ATHLTHTournamentExerciseSearchResult) -> Int {
            let name = item.name.lowercased()
            return tokens.filter { name.contains($0) }.count
        }
        let sorted = eligible.sorted {
            let left = score($0), right = score($1)
            if left != right { return left > right }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
        // Every selected branch gets a supported exercise first, when the
        // requested count permits it. Then fill with distinct catalog IDs.
        guard exerciseCount >= allowed.count else { return nil }
        var selected: [ATHLTHTournamentExerciseSearchResult] = []
        for activity in allowed.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let first = sorted.first(where: { $0.activity == activity }) else { return nil }
            selected.append(first)
        }
        for item in sorted where selected.count < exerciseCount && !selected.contains(where: { $0.id == item.id }) {
            selected.append(item)
        }
        guard selected.count == exerciseCount else { return nil }
        let start = clean.contains("alle er klare") || clean.contains("everyone is ready") ? "when_ready" : "manual"
        return ATHLTHTournamentCoachDraft(
            title: "Konkurranse · " + allowed.sorted(by: { $0.rawValue < $1.rawValue }).map(\.title).joined(separator: " og "),
            exerciseIDs: selected.map(\.id), exerciseNames: selected.map(\.name),
            startMode: start, environment: environment.rawValue,
            releaseEvery: 1, completionHours: 24, allowedRules: "", prohibitedRules: "",
            explanation: "Lokalt forslag basert på tilgjengelige konkurranseøvelser. Kontroller øvelser, frister, poeng og regler før publisering. Uspesifiserte regler er ikke fastsatt av Coach.")
    }
}

@MainActor
struct ATHLTHTournamentCoachService {
    func suggest(prompt: String, format: ATHLTHTournamentFormat,
                 activities: [ATHLTHTournamentActivity], exerciseCount: Int) async throws -> ATHLTHTournamentCoachDraft {
        // Use only the existing bounded public catalog browse; no user prompt
        // or participant information is included in this network request.
        let catalog = try await ATHLTHTournamentLobbyCloudService()
            .searchCompetitionExercises("", allowed: activities, browse: true)
        try Task.checkCancellation()
        guard let proposal = ATHLTHTournamentLocalCoachPolicy.suggest(prompt: prompt,
            activities: activities, exerciseCount: exerciseCount, catalog: catalog) else {
            throw ATHLTHTournamentCoachFailure.unavailable("Fant ikke nok passende konkurranseøvelser. Juster antallet eller velg øvelser manuelt.")
        }
        return proposal
    }
}

private enum ATHLTHTournamentCoachFailure: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

/// ATHLTH Coach proposes real catalogue exercises and simple tournament
/// rules. It does not publish or change participant consent on its own.
struct ATHLTHTournamentCoachWizard: View {
    @Environment(\.dismiss) private var dismiss
    let format: ATHLTHTournamentFormat
    let activities: [ATHLTHTournamentActivity]
    let onApply: (ATHLTHTournamentCoachDraft) -> Void

    @State private var goal = ""
    @State private var count = 4
    @State private var proposal: ATHLTHTournamentCoachDraft?
    @State private var busy = false
    @State private var errorMessage: String?
    private let service = ATHLTHTournamentCoachService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Label("Coach bygger konkurransen", systemImage: "sparkles")
                        .font(.system(size: 25, design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text("Beskriv konkurransen du ønsker. Coach foreslår regler og øvelser fra det eksisterende biblioteket, som du kan kontrollere og endre før publisering.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    TextField(
                        "F.eks. fire ukers løpeliga med varierte distanser, kun ute",
                        text: $goal, axis: .vertical
                    )
                    .lineLimit(3...5)
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())
                    .onChange(of: goal) { _, updated in
                        if updated.count > 500 {
                            goal = String(updated.prefix(500))
                        }
                    }

                    Stepper("Antall øvelser: inntil \(count)",
                            value: $count, in: 1...12)
                        .padding(15)
                        .background(ATHLTHArenaV3Style.panel())

                    Text("Coach henter godkjente konkurranseøvelser fra biblioteket. Teksten du skriver, behandles lokalt. Ingen helseopplysninger eller deltakerdata sendes til AI.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    Button {
                        Task { await generate() }
                    } label: {
                        HStack(spacing: 9) {
                            if busy { ProgressView().tint(.white) }
                            Image(systemName: "sparkles")
                            Text(busy ? "Coach setter opp…" : "Lag konkurranseforslag")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 49)
                        .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    }
                    .disabled(busy || goal.trimmingCharacters(in:
                        .whitespacesAndNewlines).count < 8 || activities.isEmpty)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let proposal {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(proposal.title)
                                .font(.system(size: 23, design: .serif))
                            Text(proposal.explanation)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            Divider()
                            Text("Øvelser fra biblioteket")
                                .font(.subheadline.weight(.semibold))
                            ForEach(proposal.exerciseNames.indices, id: \.self) { index in
                                Label("\(index + 1). \(proposal.exerciseNames[index])",
                                      systemImage: "checkmark.circle")
                                    .font(.subheadline)
                            }
                            Divider()
                            Text("Start: " + (
                                proposal.startMode == "when_ready"
                                ? "Når alle er klare" : "Manuell"
                            )).font(.caption)
                            Text("Mellom øvelser: \(proposal.releaseEvery) dager · Frist: \(proposal.completionHours) timer")
                                .font(.caption)
                            if !proposal.allowedRules.isEmpty {
                                Text("Tillatt: " + proposal.allowedRules)
                                    .font(.caption)
                            }
                            if !proposal.prohibitedRules.isEmpty {
                                Text("Ikke tillatt: " + proposal.prohibitedRules)
                                    .font(.caption)
                            }
                            Button {
                                onApply(proposal)
                                dismiss()
                            } label: {
                                Label("Bruk forslaget – jeg vil gjennomgå det",
                                      systemImage: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(ATHLTHArenaV3Style.gold,
                                                in: Capsule())
                            }
                        }
                        .padding(16)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                }
                .padding(18)
            }
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("ATHLTH Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func generate() async {
        guard !busy else { return }
        busy = true
        proposal = nil
        errorMessage = nil
        defer { busy = false }
        do {
            let next = try await service.suggest(
                prompt: goal, format: format,
                activities: activities, exerciseCount: count
            )
            if next.exerciseIDs.isEmpty {
                errorMessage = "Fant ingen tilgjengelige øvelser. Prøv et annet mål."
            } else {
                proposal = next
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
