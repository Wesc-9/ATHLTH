import SwiftUI

/// Only server-supported exercise and activity-template IDs can enter a
/// competition. No fictitious IDs or local workout copies are created.
struct ATHLTHCompetitionExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    let allowed: Set<ATHLTHTournamentActivity>
    let selected: Set<UUID>
    var templatesOnly: Bool? = nil
    var selectionLimit = 12
    let onSelect: (ATHLTHTournamentExerciseSearchResult) -> Void
    @State private var query = ""
    @State private var results: [ATHLTHTournamentExerciseSearchResult] = []
    @State private var added: Set<UUID> = []
    @State private var loading = true
    @State private var failure = false
    @State private var retry = 0
    @State private var filter: ATHLTHTournamentActivity?

    private var visible: [ATHLTHTournamentExerciseSearchResult] {
        results.filter { $0.activity.isAvailableForCreation && allowed.contains($0.activity) && (filter == nil || $0.activity == filter) && (templatesOnly == nil || $0.isActivityTemplate == templatesOnly) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Treningsform", selection: $filter) {
                        Text("Alle grener").tag(nil as ATHLTHTournamentActivity?)
                        ForEach(ATHLTHTournamentActivity.allCases.filter { allowed.contains($0) && $0.isAvailableForCreation }) {
                            Text($0.title).tag(Optional($0))
                        }
                    }
                    if loading {
                        ProgressView("Henter bibliotek")
                    } else if failure {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kunne ikke hente biblioteket.")
                            Button("Prøv igjen") { retry += 1 }
                        }
                    } else if visible.isEmpty {
                        Text(query.count == 1 ? "Skriv minst to tegn." : "Ingen treff. Prøv et annet søk.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !visible.filter(\.isActivityTemplate).isEmpty {
                    Section("Forhåndsdefinerte konkurranseøvelser og treningsøkter") {
                        ForEach(visible.filter(\.isActivityTemplate)) { item in row(item) }
                    }
                }
                if !visible.filter({ !$0.isActivityTemplate }).isEmpty {
                    Section("Øvelser") {
                        ForEach(visible.filter { !$0.isActivityTemplate }) { item in row(item) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Søk etter øvelse eller treningsøkt")
            .navigationTitle(templatesOnly == true ? "Forhåndsdefinerte" : templatesOnly == false ? "Bibliotekøvelser" : "Legg til")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task(id: query + "|" + (filter?.rawValue ?? "all") + "|" + String(retry)) {
                loading = true
                failure = false
                results = []
                do {
                    if !query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                    let activities = (filter.map { [$0] } ?? Array(allowed)).filter(\.isAvailableForCreation)
                    let fetched = try await ATHLTHTournamentLobbyCloudService()
                        .searchCompetitionExercises(query, allowed: activities, browse: true)
                    guard !Task.isCancelled else { return }
                    results = fetched
                    loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    failure = true
                    loading = false
                }
            }
        }
    }

    private func row(_ item: ATHLTHTournamentExerciseSearchResult) -> some View {
        let alreadySelected = selected.contains(item.id) || added.contains(item.id)
        return Button {
            guard !alreadySelected, selected.union(added).count < selectionLimit else { return }
            added.insert(item.id)
            onSelect(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.activity.symbol)
                    .font(.title3)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .frame(width: 36, height: 36)
                    .background(ATHLTHArenaV3Style.cream, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text(item.activity.title).font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                Spacer()
                Image(systemName: alreadySelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(alreadySelected || selected.union(added).count >= selectionLimit)
    }
}
