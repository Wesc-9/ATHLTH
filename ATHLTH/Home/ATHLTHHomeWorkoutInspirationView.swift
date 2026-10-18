import SwiftUI

/// One-tap discovery: a real, editable workout from the shared catalog.
/// The athlete can change the time preference and browse other suggestions.
/// Picking a workout hands it to the existing day-planning confirmation flow.
struct ATHLTHHomeWorkoutInspirationView: View {
    @Environment(\.dismiss) private var dismiss

    let workouts: [PlannedSession]
    let recentActivities: [ATHLTHInspirationRecentActivity]
    let goal: AchievementGoal?
    let selectedDate: Date
    let onChoose: (PlannedSession) -> Void

    @State private var minutes = 45
    @State private var suggestionIndex = 0

    private let ink = Color(red: 0.17, green: 0.21, blue: 0.29)

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var ranked: [PlannedSession] {
        ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: workouts, recent: recentActivities, minutes: minutes, goal: goal
        )
    }

    private var selected: PlannedSession? {
        guard !ranked.isEmpty else { return nil }
        return ranked[suggestionIndex % ranked.count]
    }

    private func category(for workout: PlannedSession) -> String {
        workout.workoutCategory ?? workout.kind.rawValue
    }

    private func pictureName(for workout: PlannedSession) -> String {
        switch category(for: workout) {
        case "strength": return "StrengthQuickHero"
        case "running": return "GoalRunning"
        case "walking": return "GoalWalking"
        default: return "TrainHero"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(selectedDate.formatted(
                            .dateTime.weekday(.wide).day().month(.wide)
                        ))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ink.opacity(0.61))

                        Text(tr("YOUR WORKOUT IDEA", "DAGENS TRENINGSIDÉ"))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(tr("Find your next workout", "Finn din neste økt"))
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink)

                        Text(tr(
                            "Choose how much time you have. ATHLTH suggests a real workout from the library.",
                            "Velg hvor mye tid du har. ATHLTH finner en ferdig økt fra biblioteket."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.67))
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("HOW MUCH TIME?", "HVOR MYE TID HAR DU?"))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(ink.opacity(0.65))

                        Picker(tr("Available time", "Tilgjengelig tid"),
                               selection: $minutes) {
                            Text("25 min").tag(25)
                            Text("45 min").tag(45)
                            Text("60 min").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: minutes) { _, _ in
                            suggestionIndex = 0
                        }
                    }
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))

                    if let workout = selected {
                        suggestionCard(workout)

                        Button {
                            guard !ranked.isEmpty else { return }
                            withAnimation(.easeInOut(duration: 0.18)) {
                                suggestionIndex = (suggestionIndex + 1) % ranked.count
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(tr("Another suggestion", "Bytt forslag"))
                                Spacer()
                                Text("\((suggestionIndex % ranked.count) + 1)/\(ranked.count)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .padding(15)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ScrollView {
                                ATHLTHWorkoutRecipePreview(
                                    title: workout.title,
                                    summary: workout.notes ?? "",
                                    category: category(for: workout),
                                    symbol: workout.kind.systemImage,
                                    difficulty: nil,
                                    durationMinutes: workout.durationMinutes,
                                    blocks: ATHLTHUnifiedWorkout.editorBlocks(from: workout)
                                )
                                .padding(16)
                            }
                            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                            .navigationTitle(tr("Workout details", "Øktdetaljer"))
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label(tr("See the full workout", "Se hele treningsøkten"),
                                  systemImage: "list.bullet.rectangle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    } else {
                        ContentUnavailableView(
                            tr("No workouts available", "Ingen økter tilgjengelige"),
                            systemImage: "dumbbell",
                            description: Text(tr(
                                "The Workouts library has no ready-made sessions yet.",
                                "Workouts-biblioteket har ingen ferdige økter ennå."
                            ))
                        )
                    }
                }
                .padding(18)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Get inspired", "Bli inspirert"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let workout = selected {
                    Button {
                        onChoose(workout)
                        dismiss()
                    } label: {
                        Label(
                            tr("Plan this workout", "Planlegg denne økten"),
                            systemImage: "calendar.badge.plus"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
            }
        }
    }

    private func suggestionCard(_ workout: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(pictureName(for: workout))
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Label(
                        workout.workoutCategory == "strength"
                            ? tr("STRENGTH", "STYRKE")
                            : workout.kind == .running
                                ? tr("RUNNING", "LØPING")
                                : tr("WORKOUT", "TRENINGSØKT"),
                        systemImage: workout.kind.systemImage
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(13)
                }

            VStack(alignment: .leading, spacing: 11) {
                Text(workout.title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label("~\(workout.durationMinutes ?? minutes) min",
                          systemImage: "clock")
                    Label(tr("From Workouts", "Fra Workouts"),
                          systemImage: "square.stack")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ink.opacity(0.65))

                Divider()

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHHomeWorkoutInspirationPolicy.explanation(
                        for: workout, recent: recentActivities, goal: goal
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(17)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 23))
        .clipShape(RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .strokeBorder(ink.opacity(0.07), lineWidth: 0.8)
        }
    }
}
