import SwiftUI

/// New presentation for the existing dated ATHLTHPlanWeekDayEdit engine.
/// Never owns a separate draft: every action updates the parent wizard.
struct ATHLTHAdvancedGuidedDayView: View {
    let date: Date
    let weekNumber: Int
    let totalWeeks: Int
    let dayIndex: Int
    let startDate: Date
    let workouts: [ATHLTHPlanStructuredWorkoutBlueprint]
    let isRestDay: Bool
    let onSelectDay: (Int) -> Void
    let onAddExercise: (WorkoutPhaseKind, Int) -> Void
    let onAddWorkout: () -> Void
    let onQuick: (String) -> Void
    let onEditWorkout: (Int) -> Void
    let onRestDay: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private let ink = ATHLTHTrainDesign.ink
    private let secondary = ATHLTHTrainDesign.secondary
    private let gold = ATHLTHTrainDesign.bronze
    private let canvas = ATHLTHTrainDesign.canvas
    private let rule = ATHLTHTrainDesign.rule

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            dayStrip
            if isRestDay {
                restDayCard
            } else if workouts.isEmpty {
                emptyDayCard
            } else {
                ForEach(Array(workouts.enumerated()), id: \.offset) { pair in
                    workoutCard(pair.element, index: pair.offset)
                }
            }
            quickActions
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                Image("PlanGoalHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.96), location: 0.34),
                    .init(color: canvas.opacity(0.58), location: 0.68),
                    .init(color: canvas.opacity(0.05), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(tr("WEEK", "UKE") + " \(weekNumber)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(secondary)
                    Spacer()
                    Menu {
                        ForEach(0..<7, id: \.self) { offset in
                            Button(dayDate(offset).formatted(.dateTime.weekday(.wide).day().month())) {
                                onSelectDay(offset)
                            }
                        }
                    } label: {
                        Label(tr("Change day", "Skift dag"), systemImage: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(.white.opacity(0.85), in: Capsule())
                    }
                }
                Text(date.formatted(.dateTime.weekday(.wide)).capitalized)
                    .font(.system(size: typeSize.isAccessibilitySize ? 28 : 35,
                                  weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(date.formatted(.dateTime.day().month(.wide)))
                    .font(.subheadline).foregroundStyle(secondary)
            }
            .padding(9)
        }
        .frame(height: typeSize.isAccessibilitySize ? 155 : 128)
        .clipped()
    }

    private func dayDate(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day,
            value: (weekNumber - 1) * 7 + offset,
            to: Calendar.current.startOfDay(for: startDate)) ?? date
    }

    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let value = dayDate(offset)
                let active = dayIndex == offset
                Button { onSelectDay(offset) } label: {
                    VStack(spacing: 4) {
                        Text(value.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                        Text(value.formatted(.dateTime.day()))
                            .font(.system(size: 10))
                        Circle()
                            .fill(active ? .white : gold.opacity(0.45))
                            .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(active ? .white : ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(active ? gold : .white.opacity(0.88),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.formatted(.dateTime.weekday(.wide).day().month()))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private var emptyDayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("No workouts planned", "Ingen økter planlagt"),
                  systemImage: "calendar.badge.plus")
                .font(.system(size: 16, weight: .semibold, design: .serif))
            Text(tr("Add exercises or a complete workout, or mark this date as a rest day.",
                    "Legg til øvelser eller en komplett treningsøkt, eller sett dagen som hviledag."))
                .font(.caption).foregroundStyle(secondary)
            HStack(spacing: 8) {
                actionButton(tr("Exercise", "Øvelse"), symbol: "dumbbell") {
                    onAddExercise(.main, 0)
                }
                actionButton(tr("Workout", "Treningsøkt"), symbol: "list.bullet") {
                    onAddWorkout()
                }
            }
            Button(action: onRestDay) {
                Label(tr("Rest day", "Hviledag"), systemImage: "moon.stars")
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
    }

    private var restDayCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 28)).foregroundStyle(gold)
            Text(tr("Rest and recovery", "Hvile og restitusjon"))
                .font(.system(size: 20, weight: .semibold, design: .serif))
            Button {
                onAddWorkout()
            } label: {
                Label(tr("Replace with workout", "Legg inn en treningsøkt"),
                      systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 152)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
    }

    private func workoutCard(
        _ workout: ATHLTHPlanStructuredWorkoutBlueprint, index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { onEditWorkout(index) } label: {
                HStack(spacing: 9) {
                    Image(systemName: workout.kind.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(gold)
                        .frame(width: 37, height: 37)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.65),
                                    in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                        Text("\(workout.blocks.count) " + tr("blocks", "blokker"))
                            .font(.caption).foregroundStyle(secondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundStyle(secondary)
                }
            }
            .buttonStyle(.plain)
            phaseSection(.warmup, workout: workout, workoutIndex: index)
            phaseSection(.main, workout: workout, workoutIndex: index)
            phaseSection(.cooldown, workout: workout, workoutIndex: index)
            if workout.blocks.contains(where: { $0.resolvedPhase == .recovery }) {
                phaseSection(.recovery, workout: workout, workoutIndex: index)
            }
            if index == 0 {
                Button(action: onAddWorkout) {
                    Label(tr("Add another workout", "Legg til en treningsøkt"),
                          systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(gold)
                        .frame(maxWidth: .infinity, minHeight: 37)
                        .background(canvas.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(rule.opacity(0.38), lineWidth: 0.7)
        }
    }

    private func phaseSection(
        _ phase: WorkoutPhaseKind,
        workout: ATHLTHPlanStructuredWorkoutBlueprint,
        workoutIndex: Int
    ) -> some View {
        let blocks = workout.blocks.filter { $0.resolvedPhase == phase }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: phase.symbol).foregroundStyle(gold)
                    .frame(width: 18)
                Text(phase.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                Text("(\(blocks.count))")
                    .font(.caption2).foregroundStyle(secondary)
                Spacer()
                Button { onAddExercise(phase, workoutIndex) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(gold)
                        .frame(width: 27, height: 27)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.55), in: Circle())
                }
                .accessibilityLabel(tr("Add to", "Legg til i") + " " + phase.title)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { pair in
                HStack(spacing: 9) {
                    Image(systemName: pair.element.kind == .rest ? "pause.circle.fill" :
                          pair.element.kind == .exercise ? "dumbbell" :
                          pair.element.kind == .run ? "figure.run" : "figure.cooldown")
                        .font(.caption)
                        .foregroundStyle(pair.element.kind == .rest ? gold : secondary)
                        .frame(width: 19)
                    Text(pair.element.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(pair.element.targetText ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(pair.element.kind == .rest
                    ? ATHLTHTrainDesign.paleGold.opacity(0.43) : canvas.opacity(0.70),
                    in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private func actionButton(_ text: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(gold)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(canvas, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    quick("running", "figure.run", tr("Running", "Løping"))
                    quick("walking", "figure.walk", tr("Walking", "Gå"))
                    quick("cycling", "bicycle", tr("Cycling", "Sykling"))
                    quick("yoga", "figure.yoga", "Yoga")
                    quick("meditation", "leaf", tr("Meditation", "Meditasjon"))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Button { onAddExercise(.main) } label: {
                        Label(tr("Exercise", "Øvelse"), systemImage: "dumbbell")
                    }
                    Button(action: onAddWorkout) {
                        Label(tr("Workout", "Treningsøkt"), systemImage: "list.bullet")
                    }
                    quick("interval", "waveform.path", tr("Interval", "Intervall"))
                    quick("superset", "link", "Supersett")
                    quick("rest", "pause.fill", tr("Rest", "Pause"))
                    Button { onAddExercise(.cooldown, 0) } label: {
                        Label(tr("Stretching", "Uttøying"), systemImage: "figure.cooldown")
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .tint(gold)
            }
            Button { onAddExercise(.main) } label: {
                Label(tr("Add block", "Legg til blokk"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(gold.gradient, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func quick(_ id: String, _ symbol: String, _ text: String) -> some View {
        Button { onQuick(id) } label: {
            Label(text, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 31)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
