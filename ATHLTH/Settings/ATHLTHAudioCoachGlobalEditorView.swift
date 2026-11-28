import SwiftUI

/// Global Audio Coach defaults use a staged draft. Editing a profile no longer
/// silently persists each toggle before the athlete chooses Save or Discard.
struct ATHLTHAudioCoachGlobalEditorView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AudioCoachDraft()
    @State private var outputPreference: ATHLTHAudioCoachOutputPreference = .automatic
    @State private var loaded = false
    @State private var showingExitConfirmation = false
    @State private var simpleMode = true

    private var outputPreferenceCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Audio Coach output",
                    norwegian: "Avspilling av Audio Coach"
                ),
                systemImage: "headphones"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHPlanDesign.ink)

            Picker(
                ATHLTHLocalization.choose(english: "Output", norwegian: "Lyd"),
                selection: $outputPreference
            ) {
                Text(ATHLTHLocalization.choose(
                    english: "Automatic", norwegian: "Automatisk"
                )).tag(ATHLTHAudioCoachOutputPreference.automatic)
                Text("iPhone").tag(ATHLTHAudioCoachOutputPreference.iPhone)
                Text("Apple Watch").tag(ATHLTHAudioCoachOutputPreference.appleWatch)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("athlth-coach-audio-output")

            Text(outputPreference == .automatic
                ? ATHLTHLocalization.choose(
                    english: "Use iPhone when it has headphones or another external output. Otherwise Apple Watch continues coaching.",
                    norwegian: "Bruk iPhone når hodetelefoner eller en ekstern lydutgang er tilgjengelig. Ellers fortsetter Apple Watch."
                )
                : outputPreference == .iPhone
                    ? ATHLTHLocalization.choose(
                        english: "Prefer iPhone when connected, even with its built-in speaker. Watch takes over without a confirmed connection.",
                        norwegian: "Foretrekk iPhone ved kontakt, også med innebygd høyttaler. Watch overtar uten bekreftet forbindelse."
                    )
                    : ATHLTHLocalization.choose(
                        english: "Keep the Audio Coach on Apple Watch throughout the workout.",
                        norwegian: "Behold Audio Coach på Apple Watch gjennom hele økten."
                    ))
            .font(.footnote)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var liveDraft: Binding<AudioCoachDraft> {
        Binding(get: { draft }, set: { draft = $0 })
    }

    private var hasUnsavedChanges: Bool {
        guard loaded else { return false }
        var saved = AudioCoachDraft()
        saved.load(from: settings)
        saved.enabled = settings.audioCoachEnabledByDefault
        return draft.configuration() != saved.configuration() ||
            outputPreference != settings.audioCoachOutputPreference
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
            if loaded {
                VStack(spacing: 12) {
                    Picker(ATHLTHLocalization.choose(english: "Mode", norwegian: "Modus"), selection: $simpleMode) {
                        Text(ATHLTHLocalization.choose(english: "Basic", norwegian: "Enkel")).tag(true)
                        Text(ATHLTHLocalization.choose(english: "Advanced", norwegian: "Avansert")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("athlth-coach-editor-mode")
                    if simpleMode {
                        ATHLTHBasicAudioCoachView(draft: liveDraft, availability: .global)
                    } else {
                        outputPreferenceCard
                        ATHLTHAudioCoachActiveListView(
                            draft: liveDraft,
                            showRouteOptions: true,
                            showStructuredOptions: true,
                            globalScope: true
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if simpleMode && loaded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(english: "Save", norwegian: "Lagre")) {
                        settings.updateAudioCoachDefaults(from: draft)
                        settings.audioCoachOutputPreference = outputPreference
                        dismiss()
                    }
                }
            }
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
                settings.audioCoachOutputPreference = outputPreference
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
            outputPreference = settings.audioCoachOutputPreference
            loaded = true
        }
    }
}
