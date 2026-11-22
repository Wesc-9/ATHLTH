import Foundation
import SwiftUI

/// Library presets are private presentation choices. None of these paths
/// modifies the published WorkoutTemplateCatalogEntry or its recording owner.
enum ATHLTHLibraryWorkoutStartChoice: String, CaseIterable {
    case withoutPersonalSettings
    case mySettings
    case adjustOnce
}

/// Pure conversion policy shared by the saved private settings editor and
/// the one-time launch editor. Examples are placeholders, not recommended pace.
enum ATHLTHPersonalWorkoutPaceUnit: String, CaseIterable {
    case kilometersPerHour
    case minutesPerKilometer
}

enum ATHLTHPersonalWorkoutSpeedPolicy {
    /// Only actual running efforts in the main workout are changed. Existing
    /// warm-up, cool-down and active recovery targets remain intact.
    static func workIndices(in blocks: [WorkoutTemplateBlock]) -> [Int] {
        blocks.indices.filter {
            let block = blocks[$0]
            return block.kind == .run &&
                block.resolvedPhase == .main &&
                !block.isRestOrActiveRecovery
        }
    }

    /// Athlete-entered 5:00 or 5.00 both mean five minutes per kilometre.
    /// Decimal speed accepts both comma and period (e.g. 12,5 km/t).
    static func kilometersPerHour(
        input: String,
        unit: ATHLTHPersonalWorkoutPaceUnit
    ) -> Double? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        switch unit {
        case .kilometersPerHour:
            let normalized = value.replacingOccurrences(of: ",", with: ".")
            guard let speed = Double(normalized), speed.isFinite,
                  (2...30).contains(speed)
            else { return nil }
            return speed
        case .minutesPerKilometer:
            let normalized = value
                .replacingOccurrences(of: ",", with: ":")
                .replacingOccurrences(of: ".", with: ":")
            let fields = normalized.split(
                separator: ":", omittingEmptySubsequences: false
            )
            guard (1...2).contains(fields.count),
                  let minutes = Int(fields[0]), minutes >= 0
            else { return nil }
            let seconds: Int
            if fields.count == 2 {
                // Require two digits so "5.3" cannot silently mean 5:03
                // when an athlete intended a different pace.
                guard fields[1].count == 2,
                      let parsed = Int(fields[1]), (0...59).contains(parsed)
                else { return nil }
                seconds = parsed
            } else {
                seconds = 0
            }
            let total = Double(minutes * 60 + seconds)
            guard (120...1800).contains(total) else { return nil }
            return 3600 / total
        }
    }

    static func display(
        kilometersPerHour speed: Double,
        unit: ATHLTHPersonalWorkoutPaceUnit
    ) -> String {
        guard speed.isFinite, speed > 0 else { return "" }
        switch unit {
        case .kilometersPerHour:
            var result = String(format: "%.2f", speed)
            while result.last == "0" { result.removeLast() }
            if result.last == "." { result.removeLast() }
            return result
        case .minutesPerKilometer:
            let seconds = Int((3600 / speed).rounded())
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    static func applying(
        kilometersPerHour: Double,
        to blocks: [WorkoutTemplateBlock]
    ) -> [WorkoutTemplateBlock] {
        guard kilometersPerHour.isFinite, (2...30).contains(kilometersPerHour)
        else { return blocks }
        let pace = 3600 / kilometersPerHour
        var updated = blocks
        for index in workIndices(in: blocks) {
            updated[index].targetPaceSecondsPerKilometer = pace
        }
        return updated
    }
}

/// The same editor is used when saving private workout preferences and when
/// changing an individual launch. Editing text affects only this small view;
/// the larger timeline is updated once after tapping Apply.
struct ATHLTHWorkoutWorkSpeedEditor: View {
    let blocks: [WorkoutTemplateBlock]
    let onApply: ([WorkoutTemplateBlock]) -> Void
    @State private var inputText = ""
    @State private var unit: ATHLTHPersonalWorkoutPaceUnit = .kilometersPerHour

    private var indices: [Int] {
        ATHLTHPersonalWorkoutSpeedPolicy.workIndices(in: blocks)
    }

    private var selectedSpeed: Double? {
        ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
            input: inputText, unit: unit
        )
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Label(
                    tr("Your target pace for work intervals",
                       "Din målfart på arbeidsdragene"),
                    systemImage: "speedometer"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)

                Picker(
                    tr("Pace unit", "Fartenhet"), selection: $unit
                ) {
                    Text("km/t").tag(ATHLTHPersonalWorkoutPaceUnit.kilometersPerHour)
                    Text("min/km").tag(ATHLTHPersonalWorkoutPaceUnit.minutesPerKilometer)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("athlth-personal-pace-unit")

                HStack(spacing: 10) {
                    TextField(
                        unit == .kilometersPerHour
                            ? tr("Your speed", "Din fart")
                            : tr("e.g. 5:00", "f.eks. 5:00"),
                        text: $inputText
                    )
                    .keyboardType(unit == .kilometersPerHour ? .decimalPad : .numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("athlth-personal-work-speed")

                    Text(unit == .kilometersPerHour ? "km/t" : "min/km")
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer(minLength: 0)
                    Button(tr("Apply to all", "Bruk på alle")) {
                        guard let speed = selectedSpeed else { return }
                        onApply(ATHLTHPersonalWorkoutSpeedPolicy.applying(
                            kilometersPerHour: speed, to: blocks
                        ))
                    }
                    .disabled(selectedSpeed == nil)
                    .buttonStyle(.bordered)
                    .tint(ATHLTHPlanDesign.accentInk)
                }

                if let speed = selectedSpeed {
                    Text(
                        ATHLTHPersonalWorkoutSpeedPolicy.display(
                            kilometersPerHour: speed, unit: .kilometersPerHour
                        ) + " km/t · " +
                        ATHLTHPersonalWorkoutSpeedPolicy.display(
                            kilometersPerHour: speed, unit: .minutesPerKilometer
                        ) + " min/km"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .accessibilityIdentifier("athlth-personal-pace-conversion")
                }

                Text(tr(
                    "You choose the speed. Applies to \(indices.count) work intervals only; edit each interval individually above. Warm-up, rests and cool-down are unchanged.",
                    "Du bestemmer farten. Gjelder bare \(indices.count) arbeidsdrag; du kan også justere hvert drag separat over. Oppvarming, pauser og nedjogging endres ikke."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(15)
            .athlthPlanCard(radius: 19)
            .onChange(of: unit) { previous, current in
                // Preserve the athlete's typed value when switching units.
                if let speed = ATHLTHPersonalWorkoutSpeedPolicy.kilometersPerHour(
                    input: inputText, unit: previous
                ) {
                    inputText = ATHLTHPersonalWorkoutSpeedPolicy.display(
                        kilometersPerHour: speed, unit: current
                    )
                } else {
                    inputText = ""
                }
            }
            .onAppear {
                guard inputText.isEmpty, let first = indices.first,
                      let pace = blocks[first].targetPaceSecondsPerKilometer,
                      pace.isFinite, pace > 0
                else { return }
                let samePaceForAll = indices.allSatisfy {
                    guard let other = blocks[$0].targetPaceSecondsPerKilometer
                    else { return false }
                    return abs(other - pace) < 0.02
                }
                if samePaceForAll {
                    inputText = ATHLTHPersonalWorkoutSpeedPolicy.display(
                        kilometersPerHour: 3600 / pace, unit: unit
                    )
                }
            }
        }
    }
}

/// A lightweight launch decision, with an ephemeral step editor only when
/// "Adjust now" is selected. Saved preferences are read by the parent once;
/// live editing never writes back into the user's saved preset.
struct ATHLTHLibraryWorkoutLaunchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore

    let title: String
    let summary: String
    let category: String
    let symbol: String
    let difficulty: String?
    let durationMinutes: Int?
    let originalBlocks: [WorkoutTemplateBlock]
    let savedBlocks: [WorkoutTemplateBlock]?
    let savedOptions: ATHLTHWorkoutPersonalOptions
    let onStart: ([WorkoutTemplateBlock], ATHLTHWorkoutPersonalOptions, ATHLTHLibraryWorkoutStartChoice) -> Void

    @State private var adjustingOnce = false
    @State private var draftBlocks: [WorkoutTemplateBlock]
    @State private var draftOptions: ATHLTHWorkoutPersonalOptions
    @State private var coachDraft = AudioCoachDraft()
    @State private var showingCoach = false
    @State private var showingSpotify = false
    @State private var advanced = true

    init(
        title: String, summary: String, category: String, symbol: String,
        difficulty: String?, durationMinutes: Int?,
        originalBlocks: [WorkoutTemplateBlock],
        savedBlocks: [WorkoutTemplateBlock]?,
        savedOptions: ATHLTHWorkoutPersonalOptions,
        onStart: @escaping ([WorkoutTemplateBlock], ATHLTHWorkoutPersonalOptions, ATHLTHLibraryWorkoutStartChoice) -> Void
    ) {
        self.title = title
        self.summary = summary
        self.category = category
        self.symbol = symbol
        self.difficulty = difficulty
        self.durationMinutes = durationMinutes
        self.originalBlocks = originalBlocks
        self.savedBlocks = savedBlocks
        self.savedOptions = savedOptions
        self.onStart = onStart
        _draftBlocks = State(initialValue: savedBlocks ?? originalBlocks)
        _draftOptions = State(initialValue: savedOptions)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var hasSavedChoices: Bool {
        savedBlocks != nil || savedOptions != ATHLTHWorkoutPersonalOptions()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if adjustingOnce {
                        adjustmentContent
                    } else {
                        choiceContent
                    }
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(adjustingOnce
                ? tr("Adjust for this workout", "Juster denne gangen")
                : tr("Start workout", "Start treningsøkt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
                if adjustingOnce {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Start", "Start")) {
                            onStart(draftBlocks, draftOptions, .adjustOnce)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCoach) {
                NavigationStack {
                    ScrollView {
                        PerWorkoutAudioCoachView(
                            draft: $coachDraft,
                            showRouteOptions: false,
                            showStructuredOptions: !draftBlocks.isEmpty
                        )
                        .padding(16)
                    }
                    .navigationTitle("Audio Coach")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(tr("Cancel", "Avbryt")) { showingCoach = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Apply", "Bruk")) {
                                draftOptions.audioCoachConfiguration = coachDraft.configuration()
                                showingCoach = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSpotify) {
                ATHLTHWorkoutSpotifyOptionsSheet(
                    playlist: $draftOptions.spotifyPlaylist,
                    autoplay: $draftOptions.spotifyAutoplayOnStart,
                    intervalTrack: $draftOptions.spotifyIntervalTrack,
                    supportsIntervals: !ATHLTHPersonalWorkoutSpeedPolicy.workIndices(
                        in: draftBlocks
                    ).isEmpty
                )
            }
        }
        .presentationDetents([.large])
    }

    private var choiceContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(tr(
                "Choose which settings to use. Your private changes are never visible to other athletes.",
                "Velg hvilke innstillinger du vil bruke. Dine private endringer er aldri synlige for andre."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            choiceRow(
                icon: "circle.slash",
                title: tr("No personal settings", "Ingen innstillinger"),
                subtitle: tr(
                    "Use the library workout as published.",
                    "Bruk økten slik den ligger i biblioteket."
                ),
                enabled: true
            ) {
                onStart(originalBlocks, .init(), .withoutPersonalSettings)
            }
            choiceRow(
                icon: "person.crop.circle.badge.checkmark",
                title: tr("My settings", "Mine innstillinger"),
                subtitle: hasSavedChoices
                    ? tr("Use saved pace, music and Audio Coach.",
                         "Bruk lagret fart, musikk og Audio Coach.")
                    : tr("No personal settings saved yet.",
                         "Du har ikke lagret egne valg ennå."),
                enabled: hasSavedChoices
            ) {
                onStart(savedBlocks ?? originalBlocks, savedOptions, .mySettings)
            }
            choiceRow(
                icon: "slider.horizontal.3",
                title: tr("Adjust now", "Juster nå"),
                subtitle: tr(
                    "Change this workout without overwriting your saved choices.",
                    "Tilpass denne økten uten å overskrive det du har lagret."
                ),
                enabled: true
            ) {
                adjustingOnce = true
            }
        }
    }

    private func choiceRow(
        icon: String, title: String, subtitle: String,
        enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 36, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .athlthPlanCard(radius: 20)
            .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.52)
        .buttonStyle(.plain)
    }

    private var adjustmentContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr(
                "These changes apply only to this start, not your saved preset.",
                "Endringene gjelder bare denne starten, ikke dine lagrede innstillinger."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            ATHLTHWorkoutRecipePreview(
                title: title, summary: summary,
                category: category, symbol: symbol,
                difficulty: difficulty, durationMinutes: durationMinutes,
                blocks: draftBlocks,
                compactDetailLayout: true,
                detailAdvancedMode: $advanced,
                onUpdateBlock: { index, updated in
                    guard draftBlocks.indices.contains(index) else { return }
                    draftBlocks[index] = updated
                }
            )
            ATHLTHWorkoutWorkSpeedEditor(blocks: draftBlocks) {
                draftBlocks = $0
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Other workout settings", "Andre øktinnstillinger"))
                    .font(.headline)
                Button {
                    var draft = AudioCoachDraft()
                    draft.load(configuration: draftOptions.audioCoachConfiguration ??
                        settings.audioCoachConfiguration(
                            enabled: settings.audioCoachEnabledByDefault
                        ))
                    coachDraft = draft
                    showingCoach = true
                } label: {
                    Label("Audio Coach", systemImage: "waveform")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Button {
                    showingSpotify = true
                } label: {
                    Label("Spotify", systemImage: "music.note")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
            .padding(15)
            .athlthPlanCard(radius: 19)

            Button(tr("Start with these settings", "Start med disse innstillingene")) {
                onStart(draftBlocks, draftOptions, .adjustOnce)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHPlanDesign.accentInk)
            .frame(maxWidth: .infinity)
        }
    }
}
