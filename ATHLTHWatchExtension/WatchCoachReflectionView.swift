import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// User-initiated read-only feedback. Local facts are always available;
/// no model request until the user explicitly approves the cloud analysis.
struct WatchCoachReflectionView: View {
    let snapshot: () -> ATHLTHCoachReflection?
    @State private var captured: ATHLTHCoachReflection?
    @State private var focus: ATHLTHCoachReflection.Focus?
    @State private var fromApple = false
    @State private var askingConsent = false
    @State private var busy = false
    @State private var request: Task<Void, Never>?

    private var norwegian: Bool {
        ATHLTHLocalization.choose(english: "en", norwegian: "no") == "no"
    }
    private func tr(_ en: String, _ no: String) -> String { norwegian ? no : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("ATHLTH Coach", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WatchTheme.premiumGold)
            Button {
                guard let data = snapshot() else { return }
                request?.cancel()
                busy = false
                captured = data
                focus = data.fallback
                fromApple = false
            } label: {
                Label(tr("Review workout", "Vurder økten"), systemImage: "waveform.path")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if let captured, let focus {
                ForEach(captured.facts(norwegian: norwegian), id: \.self) { fact in
                    Text(fact).font(.caption2.monospacedDigit())
                }
                Text(focus.title(norwegian: norwegian))
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fromApple ? "Apple AI" : tr("Local feedback", "Lokal vurdering"))
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
                if #available(watchOS 27.0, *) {
                    Button {
                        askingConsent = true
                    } label: {
                        if busy { ProgressView().controlSize(.mini) }
                        else { Text(tr("Personalize with Apple AI", "Tilpass med Apple AI")).font(.caption2) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
            }
        }
        .padding(9)
        .watchSurface(radius: 14)
        .confirmationDialog(tr("Apple AI analysis", "Apple AI-analyse"), isPresented: $askingConsent, titleVisibility: .visible) {
            Button(tr("Allow once", "Tillat én gang")) { personalize() }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr("Apple receives only activity type, approximate duration and general workout context. Pulse, precise distance, route and account stay on your device.", "Apple mottar kun aktivitetstype, omtrentlig varighet og generell øktkontekst. Puls, nøyaktig distanse, rute og konto blir på enheten."))
        }
        .onDisappear { request?.cancel(); request = nil; busy = false }
    }

    private func personalize() {
        guard let data = captured, !busy else { return }
        busy = true
        request = Task { @MainActor in
            let choice = await Self.appleFocus(data)
            guard !Task.isCancelled else { return }
            focus = choice ?? data.fallback
            fromApple = choice != nil
            busy = false
        }
    }

    private static func appleFocus(_ data: ATHLTHCoachReflection) async -> ATHLTHCoachReflection.Focus? {
        #if canImport(FoundationModels)
        if #available(watchOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            guard case .available = model.availability else { return nil }
            do {
                let session = LanguageModelSession(model: model)
                let response = try await session.respond(to: data.modelPrompt)
                return data.validatedChoice(response.content)
            } catch { return nil }
        }
        #endif
        return nil
    }
}
