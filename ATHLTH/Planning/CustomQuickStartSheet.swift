import SwiftUI

enum CustomQuickWorkoutActivity: String, CaseIterable, Identifiable, Hashable, Codable {
    case hiit
    case circuit
    case functional
    case cycling
    case rowing
    case stairClimber
    case mobility
    case yoga
    case sports
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hiit: return "HIIT"
        case .circuit: return "Circuit"
        case .functional: return "Functional"
        case .cycling: return "Cycling"
        case .rowing: return "Rowing"
        case .stairClimber: return "Stairs"
        case .mobility: return "Mobility"
        case .yoga: return "Yoga"
        case .sports: return "Sports"
        case .other: return "Other"
        }
    }

    var subtitle: String {
        switch self {
        case .hiit: return "High intensity"
        case .circuit: return "Stations"
        case .functional: return "Mixed movement"
        case .cycling: return "Indoor / outdoor"
        case .rowing: return "Erg / water"
        case .stairClimber: return "Stepper"
        case .mobility: return "Move better"
        case .yoga: return "Flow"
        case .sports: return "Game / practice"
        case .other: return "Anything else"
        }
    }

    var systemImage: String {
        switch self {
        case .hiit: return "figure.highintensity.intervaltraining"
        case .circuit: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .functional: return "figure.cross.training"
        case .cycling: return "figure.outdoor.cycle"
        case .rowing: return "figure.rower"
        case .stairClimber: return "figure.stair.stepper"
        case .mobility: return "figure.flexibility"
        case .yoga: return "figure.yoga"
        case .sports: return "sportscourt.fill"
        case .other: return "figure.mixed.cardio"
        }
    }

    var localizedTitle: String {
        switch self {
        case .hiit: return "HIIT"
        case .circuit: return tr("Circuit", "Sirkeltrening")
        case .functional: return tr("Functional", "Funksjonell")
        case .cycling: return tr("Cycling", "Sykling")
        case .rowing: return tr("Rowing", "Roing")
        case .stairClimber: return tr("Stairs", "Trapper")
        case .mobility: return tr("Mobility", "Mobilitet")
        case .yoga: return "Yoga"
        case .sports: return tr("Sports", "Idrett")
        case .other: return tr("Other", "Annet")
        }
    }

    var localizedSubtitle: String {
        switch self {
        case .hiit: return tr("High intensity", "Høy intensitet")
        case .circuit: return tr("Stations", "Flere stasjoner")
        case .functional: return tr("Mixed movement", "Variert trening")
        case .cycling: return tr("Indoor / outdoor", "Inne eller ute")
        case .rowing: return tr("Erg / water", "Maskin eller vann")
        case .stairClimber: return tr("Stair machine", "Trapper eller stepper")
        case .mobility: return tr("Move better", "Bevegelighet")
        case .yoga: return tr("Flow", "Flyt og kontroll")
        case .sports: return tr("Game / practice", "Kamp eller trening")
        case .other: return tr("Anything else", "Andre aktiviteter")
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var watchKind: WatchWorkoutKind {
        switch self {
        case .hiit: return .hiit
        case .circuit, .functional: return .functional
        case .cycling: return .cycling
        case .rowing: return .rowing
        case .stairClimber: return .stairClimbing
        case .mobility, .yoga: return .yoga
        case .sports, .other: return .other
        }
    }
}

enum CustomQuickWorkoutMethod: String, CaseIterable, Identifiable, Hashable, Codable {
    case open
    case intervals
    case emom
    case amrap
    case tabata
    case forTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .intervals: return "Intervals"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .tabata: return "Tabata"
        case .forTime: return "For Time"
        }
    }

    var subtitle: String {
        switch self {
        case .open: return "Stop when done"
        case .intervals: return "Work + rest"
        case .emom: return "Every minute"
        case .amrap: return "Max rounds"
        case .tabata: return "20 / 10"
        case .forTime: return "Beat the clock"
        }
    }

    var localizedTitle: String {
        switch self {
        case .open: return tr("Open", "Fri økt")
        case .intervals: return tr("Intervals", "Intervaller")
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .tabata: return "Tabata"
        case .forTime: return tr("For Time", "På tid")
        }
    }

    var localizedSubtitle: String {
        switch self {
        case .open: return tr("Stop when done", "Stopp når du er ferdig")
        case .intervals: return tr("Work and rest", "Drag og pause")
        case .emom: return tr("Every minute", "Hvert minutt")
        case .amrap: return tr("As many rounds as possible", "Flest mulig runder")
        case .tabata: return "20 / 10"
        case .forTime: return tr("Beat the clock", "Mot klokken")
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var systemImage: String {
        switch self {
        case .open: return "play.fill"
        case .intervals: return "timer"
        case .emom: return "clock.arrow.circlepath"
        case .amrap: return "repeat"
        case .tabata: return "bolt.fill"
        case .forTime: return "stopwatch.fill"
        }
    }
}

struct CustomQuickWorkoutConfiguration: Hashable {
    var activity: CustomQuickWorkoutActivity
    var method: CustomQuickWorkoutMethod
    var durationMinutes: Int
    var workSeconds: Int
    var restSeconds: Int
    var rounds: Int
    var audioCoach: WatchAudioCoachConfiguration = .disabled

    var title: String {
        method == .open
            ? activity.localizedTitle
            : "\(activity.localizedTitle) · \(method.localizedTitle)"
    }

    var detail: String {
        switch method {
        case .open:
            return "Open workout"
        case .intervals:
            return "\(rounds) rounds · \(workSeconds)s work / \(restSeconds)s rest"
        case .emom:
            return "\(durationMinutes) min · every minute"
        case .amrap:
            return "\(durationMinutes) min · as many rounds as possible"
        case .tabata:
            return "\(rounds) rounds · 20s work / 10s rest"
        case .forTime:
            return "For time · \(durationMinutes) min cap"
        }
    }
}

enum CustomQuickStartDestination {
    case watch
    case phoneTimer
    case retrospective
}

struct CustomQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (CustomQuickWorkoutConfiguration, CustomQuickStartDestination) -> Void

    @State private var activity: CustomQuickWorkoutActivity = .hiit
    @State private var method: CustomQuickWorkoutMethod = .open
    @State private var captureDevice: WorkoutCaptureDevice = .iPhone
    @State private var durationMinutes = 20
    @State private var workSeconds = 40
    @State private var restSeconds = 20
    @State private var rounds = 8
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var audioCoachLoaded = false

    private let ink = ATHLTHTheme.primaryText
    private let muted = ATHLTHTheme.mutedText
    private let accent = ATHLTHTheme.accentDeep
    private let columns = [
        GridItem(.flexible(), spacing: 9),
        GridItem(.flexible(), spacing: 9)
    ]

    private var canUseWatch: Bool {
        trainingDeviceProvider == .appleWatch && watchConnected
    }

    private var recordedWorkouts: [CustomQuickWorkoutRecord] {
        Array(CustomQuickWorkoutJournal.load(
            userID: session.profile.userID
        ).prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    header
                    devicePicker

                    sectionTitle(tr("Activity", "Aktivitet"))
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(CustomQuickWorkoutActivity.allCases) { kind in
                            activityTile(kind)
                        }
                    }

                    sectionTitle(tr("How will you train?", "Øktoppsett"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(CustomQuickWorkoutMethod.allCases) { option in
                                methodTile(option)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    configurationControls

                    if captureDevice == .appleWatch {
                        DisclosureGroup(tr("Audio coach (optional)", "Lydcoach (valgfritt)")) {
                            AudioCoachSetupCard(
                                draft: $audioCoachDraft,
                                showRouteOptions: false,
                                showStructuredOptions: false
                            )
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                    }

                    workoutPreview

                    if !recordedWorkouts.isEmpty {
                        recentRecordings
                    }
                }
                .padding(20)
                .padding(.bottom, 110)
            }
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(tr("Custom workout", "Egendefinert økt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 9) {
                    Button {
                        if captureDevice == .appleWatch && !canUseWatch { return }
                        onStart(
                            previewConfiguration,
                            captureDevice == .appleWatch ? .watch : .phoneTimer
                        )
                        dismiss()
                    } label: {
                        Label(
                            captureDevice == .appleWatch
                                ? tr("Start on Apple Watch", "Start på Apple Watch")
                                : tr("Start iPhone timer", "Start tidtaking på iPhone"),
                            systemImage: captureDevice == .appleWatch
                                ? "applewatch" : "play.fill"
                        )
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        captureDevice == .appleWatch && !canUseWatch
                            ? Color.gray.opacity(0.45) : accent,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .disabled(captureDevice == .appleWatch && !canUseWatch)

                    if captureDevice == .iPhone {
                        Button {
                            onStart(previewConfiguration, .retrospective)
                            dismiss()
                        } label: {
                            Label(
                                tr("Log a completed workout", "Registrer økt i etterkant"),
                                systemImage: "square.and.pencil"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            if !audioCoachLoaded {
                audioCoachDraft.load(from: settings)
                audioCoachLoaded = true
            }
            if !canUseWatch {
                captureDevice = .iPhone
            }
        }
        .onChange(of: watchConnected) { _, connected in
            if !connected { captureDevice = .iPhone }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Your workout. Your way.", "Din økt. Ditt oppsett."))
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
            Text(tr(
                "Choose an activity and setup. Use an iPhone timer or Apple Watch, or record the workout afterwards.",
                "Velg aktivitet og oppsett. Ta tiden på iPhone eller Apple Watch, eller registrer økten i etterkant."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
        }
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle(tr("Record with", "Registrer med"))
            HStack(spacing: 10) {
                deviceTile(
                    title: "iPhone",
                    icon: "iphone",
                    subtitle: tr("Timer + manual input", "Tidtaker + manuell føring"),
                    selected: captureDevice == .iPhone,
                    enabled: true
                ) {
                    captureDevice = .iPhone
                }
                deviceTile(
                    title: "Apple Watch",
                    icon: "applewatch",
                    subtitle: canUseWatch
                        ? tr("Watch capture", "Måling på klokken")
                        : tr("Not available", "Ikke tilgjengelig"),
                    selected: captureDevice == .appleWatch,
                    enabled: canUseWatch
                ) {
                    captureDevice = .appleWatch
                }
            }
            if !canUseWatch {
                Label(
                    tr(
                        "No Apple Watch connected. Use your iPhone or enter the workout manually.",
                        "Ingen Apple Watch tilkoblet. Bruk iPhone eller registrer økten manuelt."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            } else if captureDevice == .appleWatch && method != .open {
                Text(tr(
                    "Apple Watch records the activity. Custom work/rest instructions are not yet transferred to Watch.",
                    "Apple Watch registrerer aktiviteten. Egendefinerte drag og pauser overføres ennå ikke til klokken."
                ))
                .font(.caption)
                .foregroundStyle(muted)
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
    }

    private func deviceTile(
        title: String, icon: String, subtitle: String,
        selected: Bool, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill") }
                    else if !enabled { Image(systemName: "lock.fill") }
                }
                .foregroundStyle(selected ? accent : muted)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(muted)
                    .lineLimit(2)
                    .frame(height: 28, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(
                selected ? ATHLTHTheme.accentSoft : ATHLTHTheme.canvasTop,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(selected ? accent.opacity(0.40)
                                           : ATHLTHTheme.border, lineWidth: 1)
            }
            .opacity(enabled ? 1 : 0.56)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func activityTile(_ kind: CustomQuickWorkoutActivity) -> some View {
        let selected = activity == kind
        return Button {
            activity = kind
        } label: {
            HStack(spacing: 9) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? accent : muted)
                    .frame(width: 33, height: 33)
                    .background(
                        selected ? ATHLTHTheme.accentSoft : ATHLTHTheme.canvasTop,
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(kind.localizedSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 63)
            .background(
                selected ? ATHLTHTheme.accentSoft.opacity(0.55) : .white,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(selected ? accent.opacity(0.32)
                                           : ATHLTHTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func methodTile(_ choice: CustomQuickWorkoutMethod) -> some View {
        let selected = choice == method
        return Button {
            method = choice
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: choice.systemImage)
                    Text(choice.localizedTitle)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? accent : ink)
                Text(choice.localizedSubtitle)
                    .font(.caption2)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
            .padding(12)
            .background(
                selected ? ATHLTHTheme.accentSoft.opacity(0.60) : .white,
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(selected ? accent.opacity(0.35)
                                           : ATHLTHTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var previewConfiguration: CustomQuickWorkoutConfiguration {
        CustomQuickWorkoutConfiguration(
            activity: activity,
            method: method,
            durationMinutes: durationMinutes,
            workSeconds: workSeconds,
            restSeconds: restSeconds,
            rounds: rounds,
            audioCoach: audioCoachDraft.configuration()
        )
    }

    @ViewBuilder
    private var configurationControls: some View {
        if method != .open {
            VStack(alignment: .leading, spacing: 11) {
                sectionTitle(tr("Details", "Detaljer"))
                switch method {
                case .open:
                    EmptyView()
                case .intervals:
                    stepperRow(tr("Rounds", "Drag"), value: $rounds, range: 1...30)
                    stepperRow(tr("Work", "Arbeid"), value: $workSeconds,
                               range: 10...300, suffix: " sek", step: 5)
                    stepperRow(tr("Rest", "Pause"), value: $restSeconds,
                               range: 5...180, suffix: " sek", step: 5)
                case .emom, .amrap:
                    stepperRow(tr("Duration", "Varighet"), value: $durationMinutes,
                               range: 5...60, suffix: " min", step: 5)
                case .tabata:
                    stepperRow(tr("Rounds", "Drag"), value: $rounds, range: 4...20)
                    Text(tr("20 seconds work / 10 seconds rest",
                            "20 sekunder arbeid / 10 sekunder pause"))
                        .font(.caption)
                        .foregroundStyle(muted)
                case .forTime:
                    stepperRow(tr("Time cap", "Tidsgrense"), value: $durationMinutes,
                               range: 5...120, suffix: " min", step: 5)
                }
            }
            .padding(15)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var workoutPreview: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.systemImage)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(previewConfiguration.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Text(method.localizedSubtitle)
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 19))
    }

    private var recentRecordings: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("RECENTLY LOGGED", "SIST REGISTRERT"))
            ForEach(recordedWorkouts) { workout in
                HStack(spacing: 10) {
                    Image(systemName: workout.activity.systemImage)
                        .foregroundStyle(accent)
                        .frame(width: 33, height: 33)
                        .background(ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Text(workout.evidence.label)
                            .font(.caption2)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Text("\\(Int(workout.durationSeconds / 60)) min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(muted)
                }
                .padding(11)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(muted)
    }

    private func stepperRow(
        _ title: String, value: Binding<Int>,
        range: ClosedRange<Int>, suffix: String = "", step: Int = 1
    ) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text("\\(value.wrappedValue)\\(suffix)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(muted)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .tint(accent)
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}
