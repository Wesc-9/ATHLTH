import SwiftUI

enum CustomQuickWorkoutActivity: String, CaseIterable, Identifiable, Hashable {
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

enum CustomQuickWorkoutMethod: String, CaseIterable, Identifiable, Hashable {
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

    var title: String {
        method == .open
            ? activity.title
            : "\(activity.title) · \(method.title)"
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

struct CustomQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (CustomQuickWorkoutConfiguration) -> Void

    @State private var activity: CustomQuickWorkoutActivity = .hiit
    @State private var method: CustomQuickWorkoutMethod = .open
    @State private var durationMinutes = 20
    @State private var workSeconds = 40
    @State private var restSeconds = 20
    @State private var rounds = 8

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Build a quick workout")
                            .font(.title2.weight(.bold))

                        Text("Choose what you're doing, then pick the structure. ATHLTH keeps the setup fast and sends the workout to Apple Watch when available.")
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    sectionTitle("Workout type")

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CustomQuickWorkoutActivity.allCases) { item in
                            selectionTile(
                                title: item.title,
                                subtitle: item.subtitle,
                                icon: item.systemImage,
                                selected: activity == item
                            ) {
                                activity = item
                            }
                        }
                    }

                    sectionTitle("Training method")

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CustomQuickWorkoutMethod.allCases) { item in
                            selectionTile(
                                title: item.title,
                                subtitle: item.subtitle,
                                icon: item.systemImage,
                                selected: method == item
                            ) {
                                method = item
                            }
                        }
                    }

                    configurationControls

                    ATHLTHCard {
                        HStack(spacing: 12) {
                            Image(systemName: activity.systemImage)
                                .font(.title2)
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 42, height: 42)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 13)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(previewConfiguration.title)
                                    .font(.headline)

                                Text(previewConfiguration.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }

                    if !canStart {
                        Label(deviceMessage, systemImage: deviceIcon)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.canvasTop,
                        ATHLTHTheme.canvasBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Custom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()

                    Button {
                        onStart(previewConfiguration)
                        dismiss()
                    } label: {
                        Label(
                            canStart ? "Start on Apple Watch" : "Apple Watch required",
                            systemImage: canStart ? "applewatch" : "exclamationmark.circle"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        canStart ? ATHLTHTheme.accent : ATHLTHTheme.mutedText.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .disabled(!canStart)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var previewConfiguration: CustomQuickWorkoutConfiguration {
        CustomQuickWorkoutConfiguration(
            activity: activity,
            method: method,
            durationMinutes: durationMinutes,
            workSeconds: workSeconds,
            restSeconds: restSeconds,
            rounds: rounds
        )
    }

    private var canStart: Bool {
        trainingDeviceProvider == .appleWatch && watchConnected
    }

    private var deviceMessage: String {
        switch trainingDeviceProvider {
        case .appleWatch:
            return "Connect Apple Watch before starting this custom live workout."
        case .garmin:
            return "Garmin live workout launch is not available yet. Your custom setup stays ready for Apple Watch capture."
        case .none:
            return "Choose Apple Watch as your training device to launch and record this custom workout live."
        }
    }

    private var deviceIcon: String {
        switch trainingDeviceProvider {
        case .appleWatch: return "applewatch"
        case .garmin: return "watch.analog"
        case .none: return "iphone"
        }
    }

    @ViewBuilder
    private var configurationControls: some View {
        switch method {
        case .open:
            EmptyView()

        case .intervals:
            VStack(spacing: 10) {
                sectionTitle("Interval setup")
                stepperRow("Rounds", value: $rounds, range: 1...30)
                stepperRow("Work", value: $workSeconds, range: 10...300, suffix: " sec", step: 5)
                stepperRow("Rest", value: $restSeconds, range: 5...180, suffix: " sec", step: 5)
            }

        case .emom:
            VStack(spacing: 10) {
                sectionTitle("EMOM setup")
                stepperRow("Duration", value: $durationMinutes, range: 5...60, suffix: " min", step: 5)
            }

        case .amrap:
            VStack(spacing: 10) {
                sectionTitle("AMRAP setup")
                stepperRow("Duration", value: $durationMinutes, range: 5...60, suffix: " min", step: 5)
            }

        case .tabata:
            VStack(spacing: 10) {
                sectionTitle("Tabata setup")
                stepperRow("Rounds", value: $rounds, range: 4...20)
                Text("Classic Tabata uses 20 seconds work and 10 seconds rest.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .forTime:
            VStack(spacing: 10) {
                sectionTitle("For Time setup")
                stepperRow("Time cap", value: $durationMinutes, range: 5...120, suffix: " min", step: 5)
            }
        }
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.15)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func selectionTile(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selected ? .white : ATHLTHTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        selected
                            ? ATHLTHTheme.accent
                            : ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(
                selected
                    ? ATHLTHTheme.accentSoft
                    : Color.white.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(
                        selected
                            ? ATHLTHTheme.accent.opacity(0.28)
                            : ATHLTHTheme.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stepperRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String = "",
        step: Int = 1
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text("\(value.wrappedValue)\(suffix)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(ATHLTHTheme.mutedText)

            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
        .padding(14)
        .background(
            Color.white.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }
}
