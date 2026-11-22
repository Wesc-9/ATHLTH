import SwiftUI
import Supabase

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

private struct ATHLTHTournamentCoachRequest: Encodable {
    let prompt: String
    let format: String
    let activities: [String]
    let maxExercises: Int
}
private struct ATHLTHTournamentCoachError: Decodable {
    let error: String
}

@MainActor
struct ATHLTHTournamentCoachService {
    private let client = SupabaseEnvironment.client

    func suggest(
        prompt: String, format: ATHLTHTournamentFormat,
        activities: [ATHLTHTournamentActivity],
        exerciseCount: Int
    ) async throws -> ATHLTHTournamentCoachDraft {
        do {
            return try await client.functions.invoke(
                "generate-competition-draft",
                options: FunctionInvokeOptions(
                    body: ATHLTHTournamentCoachRequest(
                        prompt: prompt,
                        format: format.rawValue,
                        activities: activities.map(\.rawValue),
                        maxExercises: min(12, max(1, exerciseCount))
                    ),
                    timeoutInterval: 40
                )
            )
        } catch FunctionsError.httpError(_, let data) {
            let response = try? JSONDecoder().decode(
                ATHLTHTournamentCoachError.self, from: data
            )
            throw ATHLTHTournamentCoachFailure.unavailable(
                response?.error ?? "Coach var utilgjengelig akkurat nå."
            )
        } catch {
            throw ATHLTHTournamentCoachFailure.unavailable(
                "Coach var utilgjengelig akkurat nå."
            )
        }
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

                    Text("Bare teksten du skriver her og tilgjengelige øvelsesnavn sendes til AI-tjenesten. Ingen helseopplysninger eller deltakerdata sendes.")
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
