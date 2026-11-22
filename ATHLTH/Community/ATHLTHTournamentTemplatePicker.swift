import SwiftUI

/// Reusable private templates for Advanced and future Basic competition cards.
struct ATHLTHTournamentTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    let onChoose: (ATHLTHTournamentDraft) -> Void

    @State private var templates: [ATHLTHTournamentPersonalTemplate] = []
    @State private var loading = true
    @State private var error: String?
    private let service = ATHLTHTournamentTemplateCloudService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Mine konkurransemaler")
                        .font(.system(size: 28, design: .serif))
                    Text("Velg en mal for å hente tilbake oppsett, regler, øvelser og frister. Deltakere velges på nytt.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    if loading { ProgressView("Henter maler…") }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    if !loading && templates.isEmpty {
                        ContentUnavailableView(
                            "Ingen maler enda", systemImage: "square.stack",
                            description: Text("Lagre en konkurranse som mal fra det avanserte oppsettet.")
                        )
                    }
                    ForEach(templates) { template in
                        HStack(spacing: 12) {
                            Button {
                                do {
                                    onChoose(try template.draft(
                                        for: session.profile.userID))
                                    dismiss()
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: "square.stack.3d.up")
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text("Lagret " + template.createdAt.formatted(
                                            date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                }
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                Task { await remove(template) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Slett mal \(template.name)")
                        }
                        .padding(15)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                }
                .padding(18)
            }
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Maler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lukk") { dismiss() }
                }
            }
            .task { await refresh() }
        }
    }

    @MainActor private func refresh() async {
        loading = true
        defer { loading = false }
        do { templates = try await service.load(for: session.profile.userID) }
        catch { self.error = "Kunne ikke hente malene." }
    }

    @MainActor private func remove(
        _ template: ATHLTHTournamentPersonalTemplate
    ) async {
        do {
            try await service.delete(template, userID: session.profile.userID)
            await refresh()
        } catch {
            self.error = "Malen kunne ikke slettes."
        }
    }
}
