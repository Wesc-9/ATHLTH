import SwiftUI

/// No personal data is used by this pilot; results are ephemeral view state.
struct ATHLTHIntelligenceAdminPilotView: View {
    let isAdministrator: Bool
    @State private var enabled = false
    @AppStorage(ATHLTHIntelligenceRoutingPolicy.recommendationPilotKey) private var recommendationPilot = false
    @State private var norwegian = true
    @State private var busy = false
    @State private var result: ATHLTHIntelligenceDiagnosticResult?
    @State private var failed = false
    @State private var task: Task<Void, Never>?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if isAdministrator {
            Section(tr("Intelligence Engine", "Intelligence Engine")) {
                LabeledContent("Apple · On-device",
                    value: ATHLTHIntelligenceEngine.isLocalAvailable
                        ? tr("Available", "Tilgjengelig") : tr("Unavailable", "Ikke tilgjengelig"))
                LabeledContent("Apple · Private Cloud Compute",
                    value: tr("Awaiting access", "Avventer tilgang"))
                Toggle(tr("Enable local test", "Aktiver lokal test"), isOn: $enabled)
                    .disabled(busy)
                Toggle(tr("Pilot: daily recommendation", "Pilot: dagens anbefaling"), isOn: $recommendationPilot)
                Text(tr("Only administrators can request a local wording selection from the daily recommendation details. No new training advice is generated.",
                        "Kun administratorer kan be om et lokalt formuleringvalg i detaljene for dagens anbefaling. Det genereres ingen nye treningsråd."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(tr("Test in Norwegian", "Test på norsk"), isOn: $norwegian)
                    .disabled(busy)
                Text(tr("Synthetic sample only. No health data or remote fallback.",
                        "Kun fiktivt eksempel. Ingen helsedata eller ekstern reserveleverandør."))
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    run()
                } label: {
                    if busy { ProgressView() }
                    else { Label(tr("Run local test", "Kjør lokal test"), systemImage: "sparkles") }
                }
                .disabled(!enabled || busy || !ATHLTHIntelligenceEngine.isLocalAvailable)
                if let result {
                    LabeledContent(tr("Response time", "Svartid"),
                                   value: "\(result.elapsedMilliseconds) ms")
                    Text(result.text).font(.subheadline)
                }
                if failed {
                    Text(tr("The local test failed or did not pass validation.",
                            "Den lokale testen feilet eller bestod ikke valideringen."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(tr("Current feature routing", "Dagens leverandørvalg")) {
                ForEach(ATHLTHIntelligenceFeature.allCases.filter { $0 != .localDiagnostic }, id: \.rawValue) { feature in
                    LabeledContent(feature.title,
                        value: ATHLTHIntelligenceRoutingPolicy.provider(for: feature,
                            adminPilotEnabled: recommendationPilot, isAdministrator: isAdministrator,
                            localAvailable: ATHLTHIntelligenceEngine.isLocalAvailable)?.title ?? "—")
                }
                Text(tr("External planning and experimental voice remain separate. Equipment photos and private health insights have no remote AI fallback. Competition drafts only fetch catalog entries.",
                        "Ekstern planlegging og eksperimentell tale er fortsatt separate. Apparatbilder og privat helseinnsikt har ingen ekstern AI-reserve. Konkurranseforslag henter kun bibliotekoppføringer."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onDisappear { task?.cancel(); task = nil; enabled = false; result = nil; busy = false }
        }
    }

    private func run() {
        guard isAdministrator, enabled, !busy else { return }
        busy = true
        failed = false
        result = nil
        task = Task { @MainActor in
            defer { busy = false; task = nil }
            do {
                let value = try await ATHLTHIntelligenceEngine.runLocalDiagnostic(
                    enabled: enabled, isAdministrator: isAdministrator, norwegian: norwegian)
                if !Task.isCancelled { result = value }
            } catch is CancellationError {
                // Closing the admin view must not surface a failure.
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}
