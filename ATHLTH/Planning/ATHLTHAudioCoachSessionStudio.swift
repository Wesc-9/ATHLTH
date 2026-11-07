import SwiftUI

/// The same premium, workout-scoped Audio Coach controls are used by Quick
/// Train and the advanced planned-workout editor. This view never writes app
/// defaults unless the athlete explicitly saves a named reusable profile.
struct ATHLTHAudioCoachSessionStudio: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool

    @State private var showRules = false
    @State private var ruleTrigger: ATHLTHAudioCoachRule.Trigger = .distance
    @State private var ruleMetric: ATHLTHAudioCoachRule.Metric = .pace
    @State private var ruleInterval = 1_000
    @State private var profileName = ""
    @State private var customPhrase = ""

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var accent: Color { ATHLTHPlanDesign.accentInk }

    private var zoneEnabled: Binding<Bool> {
        Binding(
            get: { draft.smartPrompts.announceCurrentHeartRateZone ?? false },
            set: { draft.smartPrompts.announceCurrentHeartRateZone = $0 }
        )
    }

    private var manualMaximumEnabled: Binding<Bool> {
        Binding(
            get: { draft.smartPrompts.maximumHeartRateBPM != nil },
            set: { draft.smartPrompts.maximumHeartRateBPM = $0 ? 185 : nil }
        )
    }

    private var manualMaximumValue: Binding<Int> {
        Binding(
            get: { Int((draft.smartPrompts.maximumHeartRateBPM ?? 185).rounded()) },
            set: { draft.smartPrompts.maximumHeartRateBPM = Double($0) }
        )
    }

    private var contextualEnabled: Binding<Bool> {
        Binding(
            get: { draft.smartPrompts.contextualFeedbackEnabled ?? true },
            set: { draft.smartPrompts.contextualFeedbackEnabled = $0 }
        )
    }

    private var encouragementStyle: Binding<ATHLTHCoachEncouragementStyle> {
        Binding(
            get: { draft.smartPrompts.encouragementStyle ?? .encouragement },
            set: { draft.smartPrompts.encouragementStyle = $0 }
        )
    }

    // The long stacked editor is replaced by a single active-list
    // workspace; the existing model and Watch configuration stay unchanged.
    var body: some View {
        ATHLTHAudioCoachActiveListView(
            draft: $draft,
            showRouteOptions: showRouteOptions,
            showStructuredOptions: showStructuredOptions
        )
    }

    private var presetCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            sectionTitle("How much guidance?", "Hvor mye veiledning?",
                         icon: "slider.horizontal.3")
            HStack(spacing: 8) {
                ForEach(ATHLTHCoachExperiencePreset.allCases) { preset in
                    Button {
                        draft.applyExperience(preset)
                    } label: {
                        VStack(spacing: 4) {
                            Text(preset.title).font(.subheadline.weight(.semibold))
                            Text(preset.subtitle)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .padding(.horizontal, 5)
                        .foregroundStyle(
                            draft.experiencePreset == preset ? .white :
                                ATHLTHPlanDesign.ink
                        )
                        .background(
                            draft.experiencePreset == preset
                                ? accent : ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        draft.experiencePreset == preset ? [.isSelected] : []
                    )
                }
            }
            Text(tr("Presets adjust basic updates, not your motivation or voice.",
                    "Valgene endrer vanlige oppdateringer, ikke motivasjon eller stemme."))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
    }

    private var motivationCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            sectionTitle("Motivational coaching", "Motivasjonssnakk",
                         icon: "sparkles")
            Text(tr(
                "Vary the encouragement, respond to hills and the finish, and avoid the same phrase repeatedly.",
                "Varierte oppmuntringer, bakker og siste etappe – uten samme setning hver gang."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            Toggle(tr("Encouragement during the run", "Oppmuntring under økten"),
                   isOn: $draft.smartPrompts.motivationEnabled)
                .tint(accent)
            if draft.smartPrompts.motivationEnabled {
                Picker(tr("Frequency", "Hvor ofte"),
                       selection: $draft.smartPrompts.motivationIntervalSeconds) {
                    Text("30 s").tag(30)
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                }
                .pickerStyle(.menu)
                Picker(tr("Coaching style", "Motivasjonsstil"),
                       selection: encouragementStyle) {
                    ForEach(ATHLTHCoachEncouragementStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider().overlay(ATHLTHPlanDesign.warmDivider)
            Toggle(tr("React to hills and final stretch",
                      "Reager på bakker og siste etappe"),
                   isOn: contextualEnabled)
                .tint(accent)

            Toggle(tr("Surprise encouragement", "Tilfeldig oppmuntring"),
                   isOn: $draft.smartPrompts.randomEncouragementEnabled)
                .tint(accent)
            if draft.smartPrompts.randomEncouragementEnabled {
                Picker(tr("Approximate frequency", "Omtrent hvor ofte"),
                       selection: $draft.smartPrompts.randomIntervalSeconds) {
                    Text("2 min").tag(120)
                    Text("4 min").tag(240)
                    Text("6 min").tag(360)
                    Text("10 min").tag(600)
                }
                .pickerStyle(.menu)
            }

            Text(tr("Your own motivational phrases", "Dine egne motivasjonsmeldinger"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            ForEach(Array(draft.smartPrompts.customEncouragements.enumerated()), id: \.offset) { index, phrase in
                HStack {
                    Text(phrase)
                        .font(.subheadline)
                        .lineLimit(3)
                    Spacer()
                    Button(role: .destructive) {
                        draft.smartPrompts.customEncouragements.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Remove phrase", "Fjern melding"))
                }
            }
            HStack {
                TextField(tr("e.g. Great rhythm, keep going!",
                             "F.eks. God rytme, fortsett slik!"),
                          text: $customPhrase, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let phrase = customPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !phrase.isEmpty,
                          draft.smartPrompts.customEncouragements.count < 20 else { return }
                    draft.smartPrompts.customEncouragements.append(
                        String(phrase.prefix(180))
                    )
                    draft.smartPrompts.randomEncouragementEnabled = true
                    customPhrase = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(customPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          draft.smartPrompts.customEncouragements.count >= 20)
                .accessibilityLabel(tr("Add phrase", "Legg til melding"))
            }
        }
    }

    private var pulseCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            sectionTitle("Heart rate and zones", "Puls og pulssoner", icon: "heart.text.square")
            Toggle(tr("Say current heart rate", "Les opp puls i slag/min"),
                   isOn: $draft.announceHeartRate)
                .tint(accent)
            Toggle(tr("Say current measured zone", "Fortell hvilken pulssone jeg er i"),
                   isOn: zoneEnabled)
                .tint(accent)
            if zoneEnabled.wrappedValue {
                Toggle(tr("Override maximum heart rate for this workout",
                          "Overstyr makspuls for denne økten"),
                       isOn: manualMaximumEnabled)
                    .tint(accent)
                if manualMaximumEnabled.wrappedValue {
                    Stepper(value: manualMaximumValue, in: 100...240, step: 1) {
                        Text(tr("Maximum heart rate: \(manualMaximumValue.wrappedValue) bpm",
                                "Makspuls: \(manualMaximumValue.wrappedValue) slag/min"))
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }
            }
            Text(tr(
                "The coach announces a stable measured zone and important changes. A configured maximum heart rate and recent Watch heart-rate data are required; target-zone warnings take precedence.",
                "Coachen leser opp stabil, målt pulssone og endringer. Krever registrert makspuls og ferske pulsmålinger. Varsler om planlagt pulssone prioriteres."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
    }

    private var announcementsCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            sectionTitle("Workout announcements", "Øktoppdateringer", icon: "waveform")
            Toggle(tr("Distance updates", "Oppdatering etter distanse"),
                   isOn: $draft.distanceTriggerEnabled)
                .tint(accent)
            if draft.distanceTriggerEnabled {
                Picker(tr("Distance interval", "Distanseintervall"),
                       selection: $draft.distanceIntervalKilometers) {
                    Text("250 m").tag(0.25)
                    Text("500 m").tag(0.5)
                    Text("1 km").tag(1.0)
                    Text("2 km").tag(2.0)
                    Text("5 km").tag(5.0)
                }
                .pickerStyle(.menu)
            }
            Toggle(tr("Timed updates", "Oppdatering etter tid"),
                   isOn: $draft.timeTriggerEnabled)
                .tint(accent)
            if draft.timeTriggerEnabled {
                Picker(tr("Time interval", "Tidsintervall"),
                       selection: $draft.timeIntervalMinutes) {
                    Text("1 min").tag(1)
                    Text("2 min").tag(2)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                .pickerStyle(.menu)
            }
            Divider().overlay(ATHLTHPlanDesign.warmDivider)
            Toggle(tr("Distance", "Distanse"), isOn: $draft.announceDistance)
            Toggle(tr("Elapsed time", "Tid"), isOn: $draft.announceElapsedTime)
            Toggle(tr("Average pace", "Gjennomsnittstempo"), isOn: $draft.announceAveragePace)
            Toggle(tr("Clock time", "Klokkeslett"), isOn: $draft.announceClockTime)
            Toggle(tr("Workout start", "Øktstart"), isOn: $draft.announceWorkoutStart)
            Toggle(tr("Pause and resume", "Pause og fortsett"), isOn: $draft.announcePauseResume)
            Toggle(tr("Finish summary", "Oppsummering ved mål"),
                   isOn: $draft.announceWorkoutComplete)
            Divider().overlay(ATHLTHPlanDesign.warmDivider)
            DisclosureGroup(isExpanded: $showRules) {
                Text(tr(
                    "Each rule can have its own metric and interval. When custom rules are active, they replace basic distance/time announcements.",
                    "Hver regel kan ha eget innhold og intervall. Egendefinerte regler erstatter de vanlige distanse- og tidsoppdateringene."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                ForEach(draft.customRules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.metric.title).font(.subheadline.weight(.semibold))
                            Text(rule.trigger == .time
                                ? tr("Every \(rule.validatedInterval) sec",
                                     "Hvert \(rule.validatedInterval). sekund")
                                : tr("Every \(rule.validatedInterval) m",
                                     "Hver \(rule.validatedInterval). meter"))
                                .font(.caption)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            draft.customRules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(tr("Remove rule", "Fjern regel"))
                    }
                }
                Picker(tr("What to say", "Hva skal leses opp"), selection: $ruleMetric) {
                    ForEach(ATHLTHAudioCoachRule.Metric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                Picker(tr("Trigger", "Utløser"), selection: $ruleTrigger) {
                    ForEach(ATHLTHAudioCoachRule.Trigger.allCases) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                }
                Stepper(
                    ruleTrigger == .time
                        ? tr("Every \(ruleInterval) sec", "Hvert \(ruleInterval). sekund")
                        : tr("Every \(ruleInterval) m", "Hver \(ruleInterval). meter"),
                    value: $ruleInterval,
                    in: ruleTrigger == .time ? 15...7_200 : 100...42_000,
                    step: ruleTrigger == .time ? 15 : 100
                )
                .onChange(of: ruleTrigger) { _, trigger in
                    ruleInterval = trigger == .time ? 60 : 1_000
                }
                Button {
                    guard draft.customRules.count < 20 else { return }
                    draft.customRules.append(ATHLTHAudioCoachRule(
                        trigger: ruleTrigger, metric: ruleMetric, interval: ruleInterval
                    ))
                } label: {
                    Label(tr("Add announcement", "Legg til beskjed"), systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(draft.customRules.count >= 20)
            } label: {
                Label(tr("Custom announcements", "Egne beskjeder"),
                      systemImage: "waveform.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var voiceCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            sectionTitle("Voice and music", "Stemme og musikk", icon: "speaker.wave.2")
            Picker(tr("Language", "Språk"), selection: $draft.language) {
                ForEach(WatchAudioCoachLanguage.allCases, id: \.rawValue) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: draft.language) { _, _ in draft.voiceIdentifier = nil }

            Picker(tr("Speaking style", "Snakkestil"), selection: $draft.speechStyle) {
                ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)
            NavigationLink {
                ATHLTHCoachVoiceChoices(
                    selectedIdentifier: $draft.voiceIdentifier,
                    language: draft.language,
                    speechRate: draft.speechRate,
                    speechVolume: draft.speechVolume,
                    duckOtherAudio: draft.duckOtherAudio,
                    speechStyle: draft.speechStyle
                )
            } label: {
                Label(tr("Choose and preview voice", "Velg og forhåndslytt til stemme"),
                      systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(tr("Voice speed", "Stemmehastighet"))
                    Spacer()
                    Text(draft.speechRate.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                }
                .font(.subheadline)
                Slider(value: $draft.speechRate, in: 0.35...0.65, step: 0.01)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(tr("Coach volume", "Coach-volum"))
                    Spacer()
                    Text("\(Int((draft.speechVolume * 100).rounded())) %")
                        .monospacedDigit()
                }
                .font(.subheadline)
                Slider(value: $draft.speechVolume, in: 0.2...1, step: 0.05)
            }
            Toggle(tr("Lower music only while coach speaks",
                      "Demp musikken bare mens coachen snakker"),
                   isOn: $draft.duckOtherAudio)
                .tint(accent)
        }
    }

    private var workoutContextCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            sectionTitle("Relevant to this workout", "Relevant for økten", icon: "figure.run")
            if showRouteOptions {
                Toggle(tr("Remaining route distance", "Gjenstående distanse"),
                       isOn: $draft.announceRemainingRouteDistance)
                Toggle(tr("Estimated time to finish", "Estimert tid til mål"),
                       isOn: $draft.announceEstimatedRemainingRouteTime)
            }
            if showStructuredOptions {
                Toggle(tr("Current and next interval", "Nåværende og neste intervall"),
                       isOn: $draft.announceCurrentWorkoutStep)
                Toggle(tr("Remaining interval time", "Gjenstående intervalltid"),
                       isOn: $draft.announceRemainingStepTime)
                Toggle(tr("Remaining interval distance", "Gjenstående intervalldistanse"),
                       isOn: $draft.announceRemainingStepDistance)
            }
        }
    }

    private var profilesCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            sectionTitle("Save and reuse", "Lagre og bruk igjen", icon: "square.stack")
            if !settings.audioCoachProfiles.isEmpty {
                Menu {
                    ForEach(settings.audioCoachProfiles) { profile in
                        Button(profile.name) { draft.load(profile: profile) }
                    }
                } label: {
                    Label(tr("Load saved profile", "Hent lagret profil"),
                          systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            TextField(tr("Profile name", "Navn på oppsett"), text: $profileName)
                .textFieldStyle(.roundedBorder)
            Button {
                let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, settings.audioCoachProfiles.count < 30 else { return }
                settings.audioCoachProfiles.append(ATHLTHAudioCoachProfile(
                    name: String(name.prefix(60)), configuration: draft.configuration()
                ))
                profileName = ""
            } label: {
                Label(tr("Save coach profile", "Lagre coach-profil"),
                      systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      settings.audioCoachProfiles.count >= 30)
        }
    }

    private func sectionTitle(_ english: String, _ norwegian: String,
                              icon: String) -> some View {
        Label(tr(english, norwegian), systemImage: icon)
            .font(.system(size: 19, weight: .semibold, design: .serif))
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .padding(.bottom, 2)
    }
}
