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
        return width < 620 ? 146 : 154
    }
}

/// Editorial, image-led activity choice for the iPad planning flow.
/// The selected date/time stay on the same screen and the call back opens
/// WorkoutTemplateBuilderView, never a second parallel workout engine.
struct ATHLTHStudioWorkoutEntryView: View {
    let date: Date
    let plannedWorkouts: [PlannedSession]
    var drafts: [ATHLTHStudioFocusedWorkoutDraft] = []
    var favoriteWorkouts: [PlannedSession] = []
    @Binding var scheduledTime: Date
    @Binding var advanced: Bool
    let onChoose: (ATHLTHPlannedWorkoutType) -> Void
    var onResumeDraft: (ATHLTHStudioFocusedWorkoutDraft) -> Void = { _ in }
    var onDeleteDraft: (ATHLTHStudioFocusedWorkoutDraft) -> Void = { _ in }
    var onFavorite: (PlannedSession) -> Void = { _ in }
    var onRestDay: () -> Void = {}

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
                        dayOverview
                        activityGrid(
                            width: geometry.size.width - (hasSidePanel ? 310 : 56),
                            narrow: narrow
                        )
                        restDayButton
                        if !hasSidePanel { planningInspector }
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
                .padding(13)
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

    private var hasRestDay: Bool { plannedWorkouts.contains(where: \.isExplicitRestDay) }

    private var dayOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(tr("YOUR TRAINING DAY", "DIN TRENINGSDAG"), systemImage: "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(gold)
                Spacer()
                DatePicker(tr("Start time", "Starttid"), selection: $scheduledTime,
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .tint(gold)
                    .fixedSize()
                    .accessibilityIdentifier("athlth-ipad-planner-start-time")
            }
            if plannedWorkouts.isEmpty {
                Label(tr("No workout planned", "Ingen økt planlagt"), systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
            } else {
                ForEach(plannedWorkouts) { workout in
                    HStack(spacing: 10) {
                        Image(systemName: workout.isExplicitRestDay ? "moon.zzz" : workout.kind.systemImage)
                            .foregroundStyle(gold)
                            .frame(width: 22)
                        Text(workout.isExplicitRestDay ? tr("Rest day", "Hviledag") : workout.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                        Spacer()
                        if !workout.isExplicitRestDay, let time = workout.scheduledStart {
                            Text(time.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                        }
                        if !workout.isExplicitRestDay, let minutes = workout.durationMinutes {
                            Text("\(minutes) min").font(.caption)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(outline.opacity(0.65), lineWidth: 0.8) }
        .padding(.bottom, 4)
        .accessibilityIdentifier("athlth-ipad-planner-day-overview")
    }

    private var restDayButton: some View {
        Button(action: onRestDay) {
            Label(tr("Add rest day", "Legg til hviledag"), systemImage: "moon.zzz")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(gold)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).stroke(outline, lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
        .disabled(!plannedWorkouts.isEmpty)
        .opacity(plannedWorkouts.isEmpty ? 1 : 0.55)
        .accessibilityIdentifier("athlth-ipad-add-rest-day")
    }

    private var planningInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("DRAFTS", "UTKAST"), systemImage: "doc.text")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(gold)
                    Spacer()
                    Text("\(drafts.count)").font(.caption).foregroundStyle(.secondary)
                }
                if drafts.isEmpty {
                    Text(tr("No drafts yet", "Ingen utkast ennå"))
                        .font(.subheadline.weight(.semibold))
                    Text(tr("Keep a workout draft to continue later.", "Behold et øktutkast for å fortsette senere."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(drafts) { draft in
                        HStack(alignment: .center, spacing: 7) {
                            Button { onResumeDraft(draft) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.title.isEmpty ? draft.activity.title : draft.title)
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                                        .lineLimit(2)
                                    Text(draft.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(tr("\(draft.blockCount) steps", "\(draft.blockCount) deløkter"))
                                        .font(.caption2).foregroundStyle(gold)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { onDeleteDraft(draft) } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(tr("Delete draft", "Slett utkast"))
                        }
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(minHeight: 245, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 19))
            .overlay { RoundedRectangle(cornerRadius: 19).stroke(outline.opacity(0.7), lineWidth: 0.8) }
            .accessibilityIdentifier("athlth-ipad-workout-drafts")

            VStack(alignment: .leading, spacing: 10) {
                Label(tr("FAVORITE WORKOUTS", "FAVORITTØKTER"), systemImage: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(gold)
                if favoriteWorkouts.isEmpty {
                    Text(tr("Star a workout in the library to add it here.", "Merk en økt som favoritt i biblioteket for å få den her."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(favoriteWorkouts) { workout in
                        Button { onFavorite(workout) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: workout.kind.systemImage).foregroundStyle(gold)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workout.title).font(.caption.weight(.semibold)).foregroundStyle(ink)
                                    if let duration = workout.durationMinutes {
                                        Text("\(duration) min").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(gold)
                            }
                            .frame(minHeight: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(hasRestDay)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(outline.opacity(0.7), lineWidth: 0.8) }
            .accessibilityIdentifier("athlth-ipad-favorite-workouts")
        }
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
