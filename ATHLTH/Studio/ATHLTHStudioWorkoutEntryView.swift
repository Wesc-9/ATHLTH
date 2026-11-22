import SwiftUI

/// The iPad planner uses the SAME six activity types and the SAME workout
/// editor as iPhone. Only the choice surface and the workspace layout differ.
enum ATHLTHStudioWorkoutEntryLayoutPolicy {
    static func columns(for width: CGFloat, accessibility: Bool = false) -> Int {
        if accessibility || width < 440 { return 1 }
        if width < 800 { return 2 }
        return 3
    }

    static func showsContextPanel(for width: CGFloat, accessibility: Bool = false) -> Bool {
        !accessibility && width >= 1_030
    }

    static func tileHeight(for width: CGFloat, accessibility: Bool = false) -> CGFloat {
        if accessibility { return 216 }
        return width < 620 ? 160 : 179
    }
}

/// Editorial, image-led activity choice for the iPad planning flow.
/// The selected date/time stay on the same screen and the call back opens
/// WorkoutTemplateBuilderView, never a second parallel workout engine.
struct ATHLTHStudioWorkoutEntryView: View {
    let date: Date
    let plannedWorkouts: [PlannedSession]
    @Binding var scheduledTime: Date
    @Binding var advanced: Bool
    let onChoose: (ATHLTHPlannedWorkoutType) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let gold = ATHLTHStudioStyle.gold
    private let ink = ATHLTHStudioStyle.ink
    private let outline = ATHLTHStudioStyle.outline

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 650 || dynamicTypeSize.isAccessibilitySize
            let hasSidePanel = ATHLTHStudioWorkoutEntryLayoutPolicy.showsContextPanel(
                for: geometry.size.width,
                accessibility: dynamicTypeSize.isAccessibilitySize
            )
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        intro(compact: narrow)
                        if !hasSidePanel {
                            compactPlanningStrip
                        }
                        activityGrid(
                            width: geometry.size.width - (hasSidePanel ? 310 : 56),
                            narrow: narrow
                        )
                        workflowFooter
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    if hasSidePanel {
                        planningInspector
                            .frame(width: 268, alignment: .top)
                    }
                }
                .padding(.horizontal, narrow ? 16 : 27)
                .padding(.top, narrow ? 20 : 28)
                .padding(.bottom, 44)
                .frame(maxWidth: 1_440)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(ATHLTHStudioStyle.canvas)
        .accessibilityIdentifier("athlth-ipad-premium-workout-entry")
    }

    @ViewBuilder
    private func intro(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if compact {
                heading
                modeSelector
            } else {
                HStack(alignment: .bottom, spacing: 20) {
                    heading
                    Spacer(minLength: 8)
                    modeSelector
                }
            }
            Text(advanced
                 ? tr("Design every part of your session: exercises, intervals, rests, goals and audio guidance.",
                      "Bygg hele økten med øvelser, intervaller, pauser, mål og Audio Coach.")
                 : tr("Choose an activity to plan quickly. You can always switch to Advanced inside the editor.",
                      "Velg aktivitet og kom raskt i gang. Du kan alltid bytte til Avansert inne i øktbyggeren."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                Text(tr("ATHLTH · WORKOUT STUDIO", "ATHLTH · ØKTSTUDIO"))
                    .tracking(2)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(gold)

            Text(tr("Plan your next workout", "Planlegg din neste økt"))
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(ink)
                .minimumScaleFactor(0.76)
                .fixedSize(horizontal: false, vertical: true)

            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("BUILD MODE", "BYGGEMODUS"))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            Picker(tr("Build mode", "Byggemodus"), selection: $advanced) {
                Text(tr("Simple", "Enkel")).tag(false)
                Text(tr("Advanced", "Avansert")).tag(true)
            }
            .pickerStyle(.segmented)
            .tint(gold)
            .frame(width: 218)
            .accessibilityIdentifier("athlth-ipad-planner-mode")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func activityGrid(width: CGFloat, narrow: Bool) -> some View {
        let columnCount = ATHLTHStudioWorkoutEntryLayoutPolicy.columns(
            for: width, accessibility: dynamicTypeSize.isAccessibilitySize
        )
        let columns = Array(repeating:
            GridItem(.flexible(minimum: 130), spacing: 13),
            count: columnCount
        )
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Choose your activity", "Velg treningsform"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ink)
                Spacer()
                Text(tr("6 choices", "6 valg"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 13) {
                ForEach(ATHLTHPlannedWorkoutType.defaultOrder) { type in
                    activityCard(
                        type,
                        height: ATHLTHStudioWorkoutEntryLayoutPolicy.tileHeight(
                            for: width,
                            accessibility: dynamicTypeSize.isAccessibilitySize
                        )
                    )
                }
            }
        }
        .accessibilityIdentifier("athlth-ipad-planner-activity-grid")
    }

    private func activityCard(
        _ type: ATHLTHPlannedWorkoutType,
        height: CGFloat
    ) -> some View {
        Button {
            onChoose(type)
        } label: {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    Image(type.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.98), location: 0),
                        .init(color: Color.white.opacity(0.90), location: 0.36),
                        .init(color: Color.white.opacity(0.43), location: 0.73),
                        .init(color: Color.white.opacity(0.08), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: type.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(gold)
                        .frame(width: 37, height: 37)
                        .background(
                            Color.white.opacity(0.83),
                            in: RoundedRectangle(cornerRadius: 12)
                        )

                    Spacer(minLength: 4)

                    Text(type.title)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(type.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink.opacity(0.70))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        Text(tr("Plan workout", "Planlegg økt"))
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gold)
                    .padding(.top, 3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(outline.opacity(0.62), lineWidth: 0.8)
            }
            .shadow(color: ink.opacity(0.045), radius: 13, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel(type.title)
        .accessibilityHint(tr(
            "Opens the shared workout builder for this activity",
            "Åpner den felles øktbyggeren for denne aktiviteten"
        ))
        .accessibilityIdentifier("athlth-ipad-planner-activity-\(type.rawValue)")
    }

    private var compactPlanningStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(gold)
                .frame(width: 33)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Scheduled for", "Planlagt til"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
            }
            Spacer(minLength: 8)
            DatePicker(
                tr("Start time", "Starttid"),
                selection: $scheduledTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .tint(gold)
            .fixedSize()
            .accessibilityIdentifier("athlth-ipad-planner-start-time")
            if !plannedWorkouts.isEmpty {
                Text(tr("\(plannedWorkouts.count) planned",
                        "\(plannedWorkouts.count) planlagt"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(gold)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(outline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var planningInspector: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 13) {
                Label(
                    tr("YOUR WORKOUT", "DIN ØKTPLAN"),
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(gold)

                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ink)

                Text(date.formatted(.dateTime.day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider().overlay(outline.opacity(0.5))

                Text(tr("START TIME", "STARTTID"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                DatePicker(
                    tr("Start time", "Starttid"),
                    selection: $scheduledTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .tint(gold)
                .accessibilityIdentifier("athlth-ipad-planner-start-time")

                Divider().overlay(outline.opacity(0.5))

                Text(tr("Already planned", "Allerede planlagt"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)

                if plannedWorkouts.isEmpty {
                    Text(tr("No workouts planned for this day yet.",
                            "Ingen økter planlagt denne dagen ennå."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(plannedWorkouts.prefix(4)) { workout in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: workout.kind.systemImage)
                                .font(.caption)
                                .foregroundStyle(gold)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(workout.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ink)
                                    .lineLimit(2)
                                if let duration = workout.durationMinutes {
                                    Text("\(duration) min")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if plannedWorkouts.count > 4 {
                        Text(tr("And \(plannedWorkouts.count - 4) more",
                                "Og \(plannedWorkouts.count - 4) til"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(outline.opacity(0.7), lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(tr("Next step", "NESTE STEG"), systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(gold)
                Text(tr("Choose an activity. The shared editor lets you build from scratch or reuse workouts from the library.",
                        "Velg aktivitet. I den felles øktbyggeren kan du starte tomt eller bruke økter fra biblioteket."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHStudioStyle.paper.opacity(0.8),
                in: RoundedRectangle(cornerRadius: 17)
            )
        }
        .accessibilityIdentifier("athlth-ipad-planner-day-inspector")
    }

    private var workflowFooter: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(gold)
                .frame(width: 22)
            Text(tr(
                "Your workout is built in the same editor as iPhone. Nothing is added to the calendar until you save, and your draft is preserved when you switch days.",
                "Du bygger økten i samme øktbygger som på iPhone. Ingenting legges til i kalenderen før du lagrer, og utkastet bevares når du bytter dag."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
