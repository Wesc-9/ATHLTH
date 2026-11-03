import SwiftUI

/// Admin-only exercise deadline editor for one competition matchup. Changes
/// are checked again on the server and appended to the tournament audit.
struct ATHLTHTournamentExerciseDeadlineEditor: View {
    @Environment(\.dismiss) private var dismiss
    let match: ATHLTHTournamentRemoteMatch
    let onChanged: @MainActor () async -> Void

    @State private var exercises: [ATHLTHTournamentMatchExerciseRemote] = []
    @State private var proposals: [ATHLTHTournamentExerciseCandidateRemote] = []
    @State private var names: [UUID: String] = [:]
    @State private var dates: [UUID: Date] = [:]
    @State private var busy = false
    @State private var errorMessage: String?

    private let cloud = ATHLTHTournamentLobbyCloudService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 17) {
                    Text("Øvelsesfrister")
                        .font(.system(size: 29,design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text("Hver øvelse har sin egen siste frist. Du kan justere den uten å endre resultatene i tidligere kamper.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    if let errorMessage {
                        Label(errorMessage,systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if exercises.isEmpty {
                        Text("Ingen øvelser å endre i dette oppgjøret.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    ForEach(exercises.sorted {
                        $0.position < $1.position
                    }) { slot in
                        VStack(alignment: .leading,spacing: 11) {
                            Text(exerciseName(slot))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                            if slot.state == "pending",
                               let maxDate = match.deadlineAt,
                               maxDate > Date().addingTimeInterval(61) {
                                DatePicker(
                                    "Siste frist",
                                    selection: Binding(
                                        get: { dates[slot.id] ?? slot.deadlineAt },
                                        set: { dates[slot.id]=$0 }
                                    ),
                                    in: Date().addingTimeInterval(60)...maxDate,
                                    displayedComponents: [.date,.hourAndMinute]
                                )
                                .font(.subheadline)
                                .datePickerStyle(.compact)
                                Button {
                                    Task { await save(slot) }
                                } label: {
                                    Label("Oppdater frist",
                                          systemImage: "calendar.badge.clock")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                }
                                .disabled(busy ||
                                    (dates[slot.id] ?? slot.deadlineAt) == slot.deadlineAt)
                            } else {
                                Text(slot.state == "pending"
                                     ? "Forleng først kampfristen, hvis du trenger mer tid."
                                     : "Øvelsen er avsluttet og kan ikke endres.")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                        }
                        .padding(15)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                }
                .padding(18)
            }
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Kampfrister")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium,.large])
        .task(id: match.id) { await reload() }
    }

    private func exerciseName(_ slot: ATHLTHTournamentMatchExerciseRemote) -> String {
        guard let exercise = proposals.first(where: {
            $0.id == slot.candidateID
        }) else {
            return "Øvelse \(slot.position)"
        }
        return names[exercise.exerciseID] ?? "Øvelse \(slot.position)"
    }

    @MainActor
    private func reload() async {
        do {
            async let slotRecords = cloud.matchExercises(matchIDs: [match.id])
            async let proposalRecords = cloud.candidates(tournamentID: match.tournamentID)
            let loadedSlots=try await slotRecords
            let loadedProposals=try await proposalRecords
            exercises=loadedSlots
            proposals=loadedProposals
            names=try await cloud.exerciseNames(
                ids: Set(loadedProposals.map(\.exerciseID))
            )
            dates=Dictionary(uniqueKeysWithValues:
                loadedSlots.map { ($0.id,$0.deadlineAt) })
            errorMessage=nil
        } catch {
            errorMessage="Kunne ikke hente frister: " + error.localizedDescription
        }
    }

    @MainActor
    private func save(_ slot: ATHLTHTournamentMatchExerciseRemote) async {
        guard let selected=dates[slot.id], !busy else { return }
        busy=true
        defer { busy=false }
        do {
            try await cloud.setExerciseDeadline(
                slotID: slot.id,deadline: selected
            )
            await reload()
            await onChanged()
        } catch {
            errorMessage=error.localizedDescription
        }
    }
}
