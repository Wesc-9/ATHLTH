import SwiftUI

/// Global defaults and the workout editor now share exactly one presentation
/// and one Watch configuration model. No secondary global list to maintain.
struct ATHLTHAudioCoachGlobalEditorView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var draft = AudioCoachDraft()
    @State private var loaded = false

    private var liveDraft: Binding<AudioCoachDraft> {
        Binding(
            get: { draft },
            set: { value in
                draft = value
                if loaded {
                    settings.updateAudioCoachDefaults(from: value)
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            ATHLTHAudioCoachActiveListView(
                draft: liveDraft,
                showRouteOptions: true,
                showStructuredOptions: true,
                globalScope: true
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 110)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .onAppear {
            guard !loaded else { return }
            draft.load(from: settings)
            draft.enabled = settings.audioCoachEnabledByDefault
            loaded = true
        }
    }
}
