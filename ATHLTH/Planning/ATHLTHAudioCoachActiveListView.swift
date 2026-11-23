import SwiftUI

/// When an Audio Coach editor is embedded inside a workout sheet, its host
/// owns persistence and closing that one sheet. The child supplies the Save
/// action in the toolbar instead of introducing a separate Done button.
private struct ATHLTHAudioCoachSaveAndCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var athlthAudioCoachSaveAndClose: (() -> Void)? {
        get { self[ATHLTHAudioCoachSaveAndCloseKey.self] }
        set { self[ATHLTHAudioCoachSaveAndCloseKey.self] = newValue }
    }
}

/// Premium Audio Coach overview with one trigger-first editor for groups
/// and one-trigger standalone commands. Older nested editing flows removed.
struct ATHLTHAudioCoachActiveListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.athlthAudioCoachSaveAndClose) private var saveAndClose
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool
    var globalScope: Bool = false
    var triggerAvailability: ATHLTHCoachTriggerAvailability? = nil

    @State private var composerTarget: ATHLTHCoachEditorTarget?
    @State private var interruptedComposerTarget: ATHLTHCoachEditorTarget?
    @State private var composerCheckpoint: ATHLTHCoachComposerCheckpoint?
    @State private var showingVoiceOptions = false
    @State private var showingSaveChoices = false
    @State private var showingDirtyTemplatePrompt = false
    @State private var showingResetStandardPrompt = false
    @State private var baselineConfiguration: WatchAudioCoachConfiguration?
    @State private var selectedTemplateID: UUID?
    @State private var pendingTemplateDestination: TemplateDestination?
    @State private var selectedFromProfiles: TemplateDestination?
    @State private var isNewEmptyTemplate = false
    @State private var showingProfiles = false
    @State private var saveTemplateAfterProfilesDismiss = false
    @State private var showingSaveNewProfile = false
    @State private var creatingBlankTemplate = false
    @State private var profileName = ""
    @State private var selectedProfileName: String?
    @State private var pendingProfileAction: ProfileAction?

    private enum ProfileAction { case delete(UUID) }
    private enum TemplateDestination: Equatable {
        case standard
        case profile(UUID)
        case new
    }

    /// Ignore an involuntary nil written by UIKit while the scene is
    /// inactive. Intentional Done/Save closes the editor explicitly.
    private var stableComposerBinding: Binding<ATHLTHCoachEditorTarget?> {
        Binding(
            get: { composerTarget },
            set: { incoming in
                if incoming == nil && scenePhase != .active { return }
                composerTarget = incoming
            }
        )
    }

    private let bronze = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var hasUnsavedTemplateChanges: Bool {
        guard let baselineConfiguration else { return false }
        return draft.configuration() != baselineConfiguration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Voice guidance", "Stemmeveiledning"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(draft.enabled
                        ? tr("Coach is on", "Coach er på")
                        : tr("Coach is off", "Coach er av"))
                        .font(.caption)
                        .foregroundStyle(dim)
                }
                Spacer(minLength: 0)
                Toggle("Audio Coach", isOn: $draft.enabled)
                    .labelsHidden()
                    .tint(bronze)
                    .accessibilityIdentifier("athlth-audio-coach-enabled")
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 5)

            if draft.enabled {
                ATHLTHAudioCoachCircleOverview(
                    draft: $draft,
                    selectedProfileName: $selectedProfileName,
                    showStructuredOptions: showStructuredOptions,
                    showRouteOptions: showRouteOptions,
                    onEditRule: { id in
                        if let groupID = draft.coachGroups.first(where: {
                            $0.ruleIDs.contains(id)
                        })?.id {
                            composerTarget = .group(groupID)
                        } else {
                            composerTarget = .command(id)
                        }
                    },
                    onEditOption: { option in
                        composerTarget = .legacy(option)
                    },
                    onShowProfiles: { showingProfiles = true },
                    onCreateTemplate: { requestTemplateChange(.new) },
                    onSaveTemplate: { showingSaveChoices = true },
                    onSwitchTemplate: { step in cycleSavedTemplates(step) },
                    previousTemplateName: previousTemplateName,
                    nextTemplateName: nextTemplateName,
                    onResetStandard: { showingResetStandardPrompt = true },
                    isDirty: hasUnsavedTemplateChanges,
                    onAddCommand: { groupID in composerTarget = .group(groupID) },
                    onEditGroupTrigger: { groupID in
                        composerTarget = .group(groupID, editTrigger: true)
                    },
                    onMoveCommand: { token, destination in
                        ATHLTHAudioCoachCommandMoves.move(
                            token, to: destination, draft: &draft
                        )
                    },
                    onAddGroup: { composerTarget = .newGroup() },
                    onAddGeneralCommand: { composerTarget = .newCommand() }
                )
                DisclosureGroup(isExpanded: $showingVoiceOptions) {
                    voiceAndMusicContent
                        .padding(.top, 12)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(bronze)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Voice and music", "Stemme og musikk"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            Text(tr("Language, Azure voices and playback",
                                    "Språk, Azure-stemmer og avspilling"))
                                .font(.caption)
                                .foregroundStyle(dim)
                        }
                    }
                }
                .tint(bronze)
                .padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 19))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
                }
                .accessibilityIdentifier("athlth-coach-voice-music-expand")
            }
            Text(globalScope
                ? tr("Defaults for new workouts. Saved workouts keep their own settings.",
                     "Standard for nye økter. Lagrede økter beholder sine egne innstillinger.")
                : tr("These choices apply only to this workout. You can save them as a profile.",
                     "Valgene gjelder bare denne økten. Du kan lagre dem som en profil."))
                .font(.caption)
                .foregroundStyle(dim)
                .padding(.horizontal, 4)
        }
        .tint(bronze)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let saveAndClose {
                    // Save the latest bound session state and dismiss only
                    // this Audio Coach sheet, restoring its presenting screen.
                    Button(tr("Save", "Lagre"), action: saveAndClose)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(bronze)
                        .accessibilityIdentifier("athlth-coach-save-top")
                } else if draft.enabled {
                    // Standalone profile editor retains Save / Save as new.
                    Button(tr("Save", "Lagre")) { showingSaveChoices = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(bronze)
                        .accessibilityIdentifier("athlth-coach-save-top")
                }
            }
        }
        .sheet(item: stableComposerBinding) { target in
            ATHLTHCoachRuleComposer(
                draft: $draft,
                target: target,
                supportsStructured: showStructuredOptions,
                showsRoutes: showRouteOptions,
                triggerAvailability: triggerAvailability ??
                    (globalScope ? .global :
                        .session(hasRoute: showRouteOptions,
                                 structured: showStructuredOptions)),
                onClose: {
                    interruptedComposerTarget = nil
                    composerCheckpoint = nil
                    composerTarget = nil
                },
                restoreCheckpoint: composerCheckpoint,
                onCheckpoint: { composerCheckpoint = $0 }
            )
            .interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                interruptedComposerTarget = composerTarget
            } else if composerTarget == nil,
                      let interruptedComposerTarget {
                // Recover just the same editor, never create a new rule.
                Task { @MainActor in
                    await Task.yield()
                    guard composerTarget == nil, scenePhase == .active
                    else { return }
                    composerTarget = interruptedComposerTarget
                }
            }
        }
        .sheet(isPresented: $showingSaveNewProfile) { saveNewProfileSheet }
        .sheet(isPresented: $showingProfiles, onDismiss: {
            if saveTemplateAfterProfilesDismiss {
                // Keep template Save / Save as new in the template manager
                // instead of a duplicate top-right Save in the workout.
                saveTemplateAfterProfilesDismiss = false
                showingSaveChoices = true
            } else if let destination = selectedFromProfiles {
                selectedFromProfiles = nil
                requestTemplateChange(destination)
            }
        }) { profilesSheet }
        .confirmationDialog(
            tr("Save this template?", "Lagre denne malen?"),
            isPresented: $showingSaveChoices,
            titleVisibility: .visible
        ) {
            if !isNewEmptyTemplate {
                Button(tr("Save changes", "Lagre endringer")) { saveCurrentTemplate() }
            }
            Button(tr("Save as new", "Lagre som ny")) {
                profileName = isNewEmptyTemplate ? "" : (selectedProfileName ?? "")
                showingSaveNewProfile = true
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        }
        .confirmationDialog(
            tr("Unsaved changes", "Ulagrede endringer"),
            isPresented: $showingDirtyTemplatePrompt,
            titleVisibility: .visible
        ) {
            Button(tr("Save", "Lagre")) {
                saveCurrentTemplate()
                if !isNewEmptyTemplate {
                    if let destination = pendingTemplateDestination {
                        continueTemplateChange(destination)
                    }
                    pendingTemplateDestination = nil
                } else {
                    profileName = ""
                    showingSaveNewProfile = true
                }
            }
            Button(tr("Discard changes", "Forkast endringer"), role: .destructive) {
                if let destination = pendingTemplateDestination {
                    continueTemplateChange(destination)
                }
                pendingTemplateDestination = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingTemplateDestination = nil
            }
        } message: {
            Text(tr("Save your changes or discard them before changing templates.",
                    "Lagre eller forkast endringene før du bytter mal."))
        }
        .confirmationDialog(
            tr("Restore Standard?", "Tilbakestille Standard?"),
            isPresented: $showingResetStandardPrompt,
            titleVisibility: .visible
        ) {
            Button(tr("Restore original Standard", "Tilbakestill til opprinnelig Standard"),
                   role: .destructive) {
                draft.applySimpleAudioCoach()
                selectedProfileName = nil
                selectedTemplateID = nil
                isNewEmptyTemplate = false
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        }
        .onAppear {
            guard baselineConfiguration == nil else { return }
            baselineConfiguration = draft.configuration()
            if let id = settings.activeAudioCoachProfileID,
               let profile = settings.audioCoachProfiles.first(where: { $0.id == id }),
               profile.configuration == draft.configuration() {
                selectedTemplateID = id
                selectedProfileName = profile.name
            } else {
                selectedTemplateID = nil
                selectedProfileName = nil
            }
        }
    }

    private func saveCurrentTemplate() {
        if let selectedTemplateID,
           let index = settings.audioCoachProfiles.firstIndex(where: {
               $0.id == selectedTemplateID
           }) {
            settings.audioCoachProfiles[index].configuration = draft.configuration()
            settings.activeAudioCoachProfileID = selectedTemplateID
        } else if !isNewEmptyTemplate {
            // Standard is the durable, non-deletable default template.
            settings.updateAudioCoachDefaults(from: draft)
            settings.activeAudioCoachProfileID = nil
        } else {
            profileName = ""
            showingSaveNewProfile = true
            return
        }
        baselineConfiguration = draft.configuration()
    }

    private func requestTemplateChange(_ destination: TemplateDestination) {
        if hasUnsavedTemplateChanges {
            pendingTemplateDestination = destination
            showingDirtyTemplatePrompt = true
        } else {
            continueTemplateChange(destination)
        }
    }

    private func continueTemplateChange(_ destination: TemplateDestination) {
        if destination == .new {
            profileName = ""
            creatingBlankTemplate = true
            showingSaveNewProfile = true
        } else {
            applyTemplateDestination(destination)
        }
    }

    // Creation order positions the most recently created template immediately
    // to the left of Standard; earlier personal templates remain on its left.
    private var templateIDsInCircleOrder: [UUID] {
        settings.audioCoachProfiles.map(\.id)
    }

    private var currentTemplateCircleIndex: Int {
        selectedTemplateID.flatMap(templateIDsInCircleOrder.firstIndex(of:))
            ?? templateIDsInCircleOrder.count
    }

    private func titleForTemplate(at index: Int) -> String? {
        guard index >= 0 && index <= templateIDsInCircleOrder.count else { return nil }
        if index == templateIDsInCircleOrder.count { return "Standard" }
        return settings.audioCoachProfiles.first {
            $0.id == templateIDsInCircleOrder[index]
        }?.name
    }

    private var previousTemplateName: String? {
        titleForTemplate(at: currentTemplateCircleIndex - 1)
    }

    private var nextTemplateName: String? {
        titleForTemplate(at: currentTemplateCircleIndex + 1)
    }

    private func cycleSavedTemplates(_ step: Int) {
        let ids = templateIDsInCircleOrder
        let current = currentTemplateCircleIndex
        let next = (current + step + ids.count + 1) % (ids.count + 1)
        requestTemplateChange(next == ids.count ? .standard : .profile(ids[next]))
    }

    private func applyTemplateDestination(_ destination: TemplateDestination) {
        switch destination {
        case .standard:
            var defaults = AudioCoachDraft()
            defaults.load(from: settings)
            draft = defaults
            selectedTemplateID = nil
            selectedProfileName = nil
            isNewEmptyTemplate = false
        case let .profile(id):
            guard let profile = settings.audioCoachProfiles.first(where: {
                $0.id == id
            }) else { return }
            draft.load(profile: profile)
            selectedTemplateID = profile.id
            selectedProfileName = profile.name
            isNewEmptyTemplate = false
        case .new:
            var empty = AudioCoachDraft()
            empty.distanceTriggerEnabled = false
            empty.timeTriggerEnabled = false
            empty.customRules = []
            empty.coachGroups = []
            empty.announceDistance = false
            empty.announceElapsedTime = false
            empty.announceAveragePace = false
            empty.announceClockTime = false
            empty.announceHeartRate = false
            empty.announceRemainingRouteDistance = false
            empty.announceEstimatedRemainingRouteTime = false
            empty.announceCurrentWorkoutStep = false
            empty.announceRemainingStepTime = false
            empty.announceRemainingStepDistance = false
            empty.announceWorkoutStart = false
            empty.announcePauseResume = false
            empty.announceWorkoutComplete = false
            empty.smartPrompts = ATHLTHAudioCoachSmartSettings()
            empty.smartPrompts.motivationEnabled = false
            empty.smartPrompts.randomEncouragementEnabled = false
            empty.smartPrompts.contextualFeedbackEnabled = false
            empty.smartPrompts.announceCurrentHeartRateZone = false
            empty.smartPrompts.targetZoneVoiceAlertsEnabled = false
            empty.smartPrompts.boundaryCountdownRules = []
            empty.smartPrompts.intervalCountdownToRecoverySeconds = nil
            empty.smartPrompts.intervalCountdownFromRecoverySeconds = nil
            empty.language = draft.language
            empty.voiceIdentifier = draft.voiceIdentifier
            draft = empty
            selectedTemplateID = nil
            selectedProfileName = tr("New template", "Ny mal")
            isNewEmptyTemplate = true
        }
        baselineConfiguration = draft.configuration()
    }

    private var saveNewProfileSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(bronze)
                        .frame(width: 48, height: 48)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Name your template", "Gi malen et navn"))
                            .font(.system(size: 24, weight: .medium, design: .serif))
                            .foregroundStyle(ink)
                        Text(tr("A name is required before creating a template.",
                                "Du må velge et navn før malen opprettes."))
                            .font(.caption)
                            .foregroundStyle(dim)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("TEMPLATE NAME", "MALNAVN"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(bronze)
                    TextField(tr("For example: Interval Coach", "F.eks. Intervall Coach"),
                              text: $profileName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("athlth-coach-template-name")
                }
                Button {
                    let name = String(profileName.trimmingCharacters(
                        in: .whitespacesAndNewlines).prefix(60))
                    guard !name.isEmpty, settings.audioCoachProfiles.count < 30 else { return }
                    if creatingBlankTemplate {
                        applyTemplateDestination(.new)
                    }
                    let profile = ATHLTHAudioCoachProfile(
                        name: name, configuration: draft.configuration()
                    )
                    settings.audioCoachProfiles.append(profile)
                    settings.activeAudioCoachProfileID = profile.id
                    selectedProfileName = profile.name
                    selectedTemplateID = profile.id
                    isNewEmptyTemplate = false
                    creatingBlankTemplate = false
                    baselineConfiguration = draft.configuration()
                    profileName = ""
                    showingSaveNewProfile = false
                    if let destination = pendingTemplateDestination {
                        pendingTemplateDestination = nil
                        continueTemplateChange(destination)
                    }
                } label: {
                    Label(
                        creatingBlankTemplate
                            ? tr("Create template", "Opprett mal")
                            : tr("Save as new template", "Lagre som ny mal"),
                        systemImage: "checkmark"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(bronze)
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          settings.audioCoachProfiles.count >= 30)
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("New template", "Ny mal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) {
                        showingSaveNewProfile = false
                        creatingBlankTemplate = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var voiceAndMusicContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("LANGUAGE", "SPRÅK"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(bronze)

                Picker(tr("Language", "Språk"), selection: $draft.language) {
                    ForEach(WatchAudioCoachLanguage.allCases, id: \.rawValue) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.language) { _, _ in
                    draft.voiceIdentifier = nil
                }
                .accessibilityIdentifier("athlth-coach-voice-language")
            }

            VStack(alignment: .leading, spacing: 11) {
                ATHLTHCoachVoiceChoices(
                    selectedIdentifier: $draft.voiceIdentifier,
                    language: draft.language,
                    speechRate: draft.speechRate,
                    speechVolume: draft.speechVolume,
                    duckOtherAudio: draft.duckOtherAudio,
                    speechStyle: draft.speechStyle
                )

                Divider().overlay(ATHLTHPlanDesign.warmDivider)

                HStack(spacing: 5) {
                    Text(tr("AZURE VOICES · ATHLTH+", "AZURE-STEMMER · ATHLTH+"))
                        .tracking(1.3)
                    Image(systemName: "wifi")
                        .accessibilityLabel(tr("Requires internet", "Krever internett"))
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(bronze)

                ATHLTHAzureCoachVoicePreviewView(
                    selectedIdentifier: $draft.voiceIdentifier,
                    language: $draft.language,
                    duckOtherAudio: draft.duckOtherAudio
                )
                Label(tr(
                    "Online voices need internet. Offline Apple speech is the fallback.",
                    "Nettstemmer trenger internett. Apple-stemme brukes uten nett."
                ), systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(dim)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityIdentifier("athlth-coach-unified-voice-list")

            Divider().overlay(ATHLTHPlanDesign.warmDivider)

            VStack(alignment: .leading, spacing: 12) {
                Picker(tr("Speaking style", "Snakkestil"),
                       selection: $draft.speechStyle) {
                    ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text(tr("Speaking speed", "Stemmehastighet"))
                    Spacer(minLength: 8)
                    Text(draft.speechRate.formatted(
                        .number.precision(.fractionLength(2))
                    ))
                    .monospacedDigit()
                    .foregroundStyle(dim)
                }
                .font(.subheadline)
                Slider(value: $draft.speechRate, in: 0.35...0.65, step: 0.01)
                    .tint(bronze)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)

                HStack {
                    Text(tr("Coach volume", "Coachvolum"))
                    Spacer(minLength: 8)
                    Text(String(Int((draft.speechVolume * 100).rounded())) + " %")
                        .monospacedDigit()
                        .foregroundStyle(dim)
                }
                .font(.subheadline)
                Slider(value: $draft.speechVolume, in: 0.2...1, step: 0.05)
                    .tint(bronze)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
            }

            Divider().overlay(ATHLTHPlanDesign.warmDivider)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(tr("Lower music while Coach speaks",
                          "Demp musikken mens Coach snakker"),
                       isOn: Binding(
                        get: { draft.duckOtherAudio && !draft.muteOtherAudio },
                        set: { enabled in
                            draft.duckOtherAudio = enabled
                            if enabled { draft.muteOtherAudio = false }
                        }
                       ))
                    .tint(bronze)

                Toggle(tr("Pause music while Coach speaks",
                          "Slå av musikk mens Coach snakker"),
                       isOn: Binding(
                        get: { draft.muteOtherAudio },
                        set: { enabled in
                            draft.muteOtherAudio = enabled
                            if enabled { draft.duckOtherAudio = false }
                        }
                       ))
                    .tint(bronze)
                    .accessibilityIdentifier("athlth-coach-mute-music")

                Text(tr(
                    "Choose dimming or fully interrupting other audio during a Coach cue. iOS asks the music app to resume afterwards; some players may need a manual restart.",
                    "Velg demping eller avbryt musikk mens Coach snakker. iOS ber musikkappen fortsette etterpå, men enkelte spillere må startes manuelt igjen."
                ))
                .font(.caption)
                .foregroundStyle(dim)

                Picker(tr("Quiet time after announcements",
                          "Stilleperiode etter varsler"),
                       selection: $draft.guidanceQuietPeriodSeconds) {
                    ForEach([0.0, 5.0, 10.0, 15.0, 30.0], id: \.self) { seconds in
                        Text(String(Int(seconds)) + " s").tag(seconds)
                    }
                }
                .pickerStyle(.menu)
            }

            if globalScope {
                Divider().overlay(ATHLTHPlanDesign.warmDivider)
                NavigationLink {
                    AthleteFuelView()
                } label: {
                    Label(tr("Fuel and hydration reminders", "Energi og væske"),
                          systemImage: "drop")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Your saved templates", "Dine lagrede maler"))
                        .font(.system(size: 25, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Choose a template. Changes are not lost when switching.",
                        "Velg en mal. Ulagrede endringer beskyttes ved bytte."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(dim)

                    Button {
                        saveTemplateAfterProfilesDismiss = true
                        showingProfiles = false
                    } label: {
                        Label(
                            tr("Save current setup as a template",
                               "Lagre gjeldende oppsett som mal"),
                            systemImage: "square.and.arrow.down"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(bronze)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("athlth-coach-save-template-from-profiles")

                    Button {
                        selectedFromProfiles = .standard
                        showingProfiles = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .foregroundStyle(bronze)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Standard")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                Text(tr("Always available · can be reset",
                                        "Alltid tilgjengelig · kan tilbakestilles"))
                                    .font(.caption)
                                    .foregroundStyle(dim)
                            }
                            Spacer(minLength: 0)
                            if selectedTemplateID == nil && !isNewEmptyTemplate {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(bronze)
                            }
                        }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("athlth-coach-select-standard")

                    ForEach(settings.audioCoachProfiles) { profile in
                        HStack(spacing: 9) {
                            Button {
                                selectedFromProfiles = .profile(profile.id)
                                showingProfiles = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.stack")
                                        .foregroundStyle(bronze)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ink)
                                        Text(profile.configurationSummary)
                                            .font(.caption)
                                            .foregroundStyle(dim)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if selectedTemplateID == profile.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(bronze)
                                    }
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button(tr("Use template", "Bruk mal")) {
                                    selectedFromProfiles = .profile(profile.id)
                                    showingProfiles = false
                                }
                                Button(tr("Delete saved template", "Slett lagret mal"),
                                       systemImage: "trash", role: .destructive) {
                                    pendingProfileAction = .delete(profile.id)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(dim)
                                    .frame(width: 40, height: 42)
                            }
                        }
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    if settings.audioCoachProfiles.isEmpty {
                        Text(tr("No saved personal templates yet.",
                                "Du har ingen lagrede personlige maler ennå."))
                            .font(.caption)
                            .foregroundStyle(dim)
                            .padding(.vertical, 12)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Saved templates", "Lagrede maler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { showingProfiles = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            tr("Delete saved template?", "Slette lagret mal?"),
            isPresented: Binding(
                get: { pendingProfileAction != nil },
                set: { if !$0 { pendingProfileAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(tr("Delete template", "Slett mal"), role: .destructive) {
                if case let .delete(id) = pendingProfileAction {
                    settings.audioCoachProfiles.removeAll { $0.id == id }
                    if settings.activeAudioCoachProfileID == id {
                        settings.activeAudioCoachProfileID = nil
                    }
                    if selectedTemplateID == id {
                        selectedTemplateID = nil
                        selectedProfileName = tr("New template", "Ny mal")
                        isNewEmptyTemplate = true
                    }
                }
                pendingProfileAction = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingProfileAction = nil
            }
        } message: {
            Text(tr("Only this saved template is deleted. Standard remains available.",
                    "Bare denne lagrede malen slettes. Standard beholdes."))
        }
    }

}
