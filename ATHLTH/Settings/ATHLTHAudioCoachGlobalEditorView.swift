import SwiftUI

/// Global Audio Coach defaults use a staged draft. Editing a profile no longer
/// silently persists each toggle before the athlete chooses Save or Discard.
struct ATHLTHAudioCoachGlobalEditorView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AudioCoachDraft()
    @State private var loaded = false
    @State private var showingExitConfirmation = false

    private var liveDraft: Binding<AudioCoachDraft> {
        Binding(get: { draft }, set: { draft = $0 })
    }

    private var hasUnsavedChanges: Bool {
        guard loaded else { return false }
        var saved = AudioCoachDraft()
        saved.load(from: settings)
        saved.enabled = settings.audioCoachEnabledByDefault
        return draft.configuration() != saved.configuration()
    }

    private func requestExit() {
        if hasUnsavedChanges {
            showingExitConfirmation = true
        } else {
            dismiss()
        }
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: requestExit) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Back", norwegian: "Tilbake"
                ))
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Save Audio Coach changes?",
                norwegian: "Lagre endringene i Audio Coach?"
            ),
            isPresented: $showingExitConfirmation,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Save", norwegian: "Lagre"
            )) {
                settings.updateAudioCoachDefaults(from: draft)
                dismiss()
            }
            Button(ATHLTHLocalization.choose(
                english: "Discard", norwegian: "Forkast"
            ), role: .destructive) {
                dismiss()
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Keep your changes or leave the current settings unchanged.",
                norwegian: "Behold endringene, eller gå ut uten å endre lagrede innstillinger."
            ))
        }
        .onAppear {
            guard !loaded else { return }
            draft.load(from: settings)
            draft.enabled = settings.audioCoachEnabledByDefault
            loaded = true
        }
    }
}
