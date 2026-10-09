import SwiftUI

/// The light "I dag" surface is deliberately separate from workout recording.
/// Plans feed this view, while launching still goes through ATHLTHTrainView.
struct ATHLTHTrainTodayPremiumView: View {
    let plan: TrainingPlan?
    let sessions: [PlannedSession]
    let completedIDs: Set<UUID>
    let healthCompletedIDs: Set<UUID>
    let nextWorkoutTitle: String?
    let nextWorkoutDate: Date?
    let completionFraction: Double
    let planPosition: String
    let onOpenPlan: () -> Void
    let onCreatePlan: () -> Void
    let onOpenLibrary: () -> Void
    let onStartWorkout: (PlannedSession, Bool) -> Void
    let onWorkoutDetails: (PlannedSession, Bool) -> Void
    let onQuickTrain: (WorkoutKind) -> Void
    let onGhostRace: () -> Void

    @State private var quickTrainExpanded = false

    private let ink = Color(red: 0.16, green: 0.16, blue: 0.16)
    private let muted = Color(red: 0.47, green: 0.45, blue: 0.42)
    private let champagne = Color(red: 0.65, green: 0.55, blue: 0.41)
    private let hairline = Color(red: 0.88, green: 0.86, blue: 0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Today", "I dag"))
                    .font(.system(size: 35, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Spacer()
                Text(
                    Date().formatted(
                        .dateTime.weekday(.wide).day().month(.wide)
                    )
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.bottom, 2)

            if let plan {
                if let workout = primaryWorkout {
                    workoutCard(workout, plan: plan)
                } else {
                    restDayCard(plan)
                }
            } else {
                emptyPlanCard
            }

            quickTrainSection
            ghostRaceSection

            if let plan {
                activePlanSection(plan)
            } else {
                Button(action: onOpenLibrary) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 19, weight: .light))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("Explore programs", "Utforsk treningsplaner"))
                                .font(.subheadline.weight(.semibold))
                            Text(tr("Templates and your saved plans", "Maler og dine lagrede planer"))
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(ink)
                    .padding(15)
                    .premiumTrainSurface(line: hairline)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryWorkout: PlannedSession? {
        sessions.first { !completedIDs.contains($0.id) } ?? sessions.first
    }

    private func workoutCard(
        _ workout: PlannedSession,
        plan: TrainingPlan
    ) -> some View {
        let finished = completedIDs.contains(workout.id)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Image(workoutImage(for: workout.kind))
                    .resizable()
                    .scaledToFill()
                    .saturation(0.45)
                    .frame(height: 147)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.46), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(
                    finished
                        ? tr("COMPLETED TODAY", "GJENNOMFØRT I DAG")
                        : tr("TODAY'S WORKOUT", "DAGENS ØKT")
                )
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white)
                .padding(15)
            }
            .frame(height: 147)
            .clipped()

            VStack(alignment: .leading, spacing: 15) {
                Button {
                    onWorkoutDetails(
                        workout,
                        healthCompletedIDs.contains(workout.id)
                    )
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title)
                                .font(.system(size: 22, weight: .medium, design: .serif))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(plan.title)
                                .font(.caption)
                                .foregroundStyle(muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ink)
                            .padding(.top, 7)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    detailLabel(
                        icon: "clock",
                        text: workout.scheduledStart?.formatted(
                            date: .omitted,
                            time: .shortened
                        ) ?? tr("Today", "I dag")
                    )
                    Spacer(minLength: 3)
                    detailLabel(
                        icon: "timer",
                        text: workout.durationMinutes.map { "\($0) min" }
                            ?? tr("Open", "Åpen")
                    )
                }
                HStack(spacing: 8) {
                    detailLabel(icon: workout.kind.systemImage, text: workout.kind.title)
                    Spacer(minLength: 3)
                    detailLabel(
                        icon: "list.bullet",
                        text: workout.exercises.isEmpty
                            ? tr("Planned workout", "Planlagt økt")
                            : tr(
                                "\(workout.exercises.count) exercises",
                                "\(workout.exercises.count) øvelser"
                            )
                    )
                }

                Button {
                    onStartWorkout(
                        workout,
                        healthCompletedIDs.contains(workout.id)
                    )
                } label: {
                    HStack {
                        Spacer()
                        Text(
                            finished
                                ? tr("View workout", "Se økten")
                                : tr("Start workout", "Start økt")
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(
                            systemName: finished
                                ? "checkmark"
                                : "arrow.right"
                        )
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 17)
                    .frame(height: 47)
                    .background(ink, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)

                if sessions.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("ALSO TODAY", "OGSÅ I DAG"))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.3)
                            .foregroundStyle(muted)
                        ForEach(sessions.filter { $0.id != workout.id }) { extra in
                            Button {
                                onWorkoutDetails(
                                    extra,
                                    healthCompletedIDs.contains(extra.id)
                                )
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: extra.kind.systemImage)
                                    Text(extra.title).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 3)
                }
            }
            .padding(16)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(hairline.opacity(0.7), lineWidth: 0.65)
        }
        .shadow(color: ink.opacity(0.065), radius: 14, y: 7)
    }

    private func restDayCard(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stateImage("GoalRecovery", label: tr("RECOVERY DAY", "HVILEDAG"))
            VStack(alignment: .leading, spacing: 11) {
                Text(tr("A day to recover", "Treningsfri i dag"))
                    .font(.system(size: 23, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(
                    tr(
                        "No workout is planned today. Recovery is part of your program.",
                        "Ingen økt i planen i dag. Restitusjon er også en del av treningen."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)

                if let nextWorkoutTitle {
                    Button(action: onOpenPlan) {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .foregroundStyle(champagne)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tr("NEXT WORKOUT", "NESTE ØKT"))
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(1.1)
                                    .foregroundStyle(muted)
                                Text(nextWorkoutTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                if let nextWorkoutDate {
                                    Text(nextWorkoutDate.formatted(.dateTime.weekday(.wide).day().month()))
                                        .font(.caption)
                                        .foregroundStyle(muted)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                        }
                        .padding(13)
                        .background(Color(red: 0.97, green: 0.96, blue: 0.94),
                                    in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onOpenPlan) {
                        Label(tr("View plan", "Se treningsplan"), systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .premiumTrainSurface(line: hairline)
    }

    private var emptyPlanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            stateImage("TrainHero", label: tr("START YOUR JOURNEY", "DIN TRENINGSREISE"))
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Build your training plan", "Bygg din treningsplan"))
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(
                    tr(
                        "Choose your goals, duration and weekly sessions. Create your own plan or start from a template.",
                        "Velg mål, varighet og økter per uke. Bygg selv, eller start med en lagret plan."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                Button(action: onCreatePlan) {
                    HStack {
                        Spacer()
                        Text(tr("Create training plan", "Bygg treningsplan"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(height: 47)
                    .background(ink, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .premiumTrainSurface(line: hairline)
    }

    private func stateImage(_ assetName: String, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .saturation(0.35)
                .frame(height: 143)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.25)
                .foregroundStyle(.white)
                .padding(15)
        }
        .frame(height: 143)
        .clipped()
    }

    private var quickTrainSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    quickTrainExpanded.toggle()
                }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "bolt")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(champagne)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Train")
                            .font(.system(size: 18, weight: .medium, design: .serif))
                            .foregroundStyle(ink)
                        Text(tr("Run, walk or strength – anytime", "Løping, gåing eller styrke – når som helst"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: quickTrainExpanded ? "chevron.up" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Choose a training type", "Velg treningsform"))

            if quickTrainExpanded {
                HStack(spacing: 8) {
                    quickChoice("figure.run", tr("Run", "Løping"), kind: .running)
                    quickChoice("figure.walk", tr("Walk", "Gåing"), kind: .walking)
                    quickChoice("dumbbell", tr("Strength", "Styrke"), kind: .strength)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.92, blue: 0.89),
                    Color(red: 0.97, green: 0.96, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(hairline.opacity(0.75), lineWidth: 0.7)
        }
    }

    private func quickChoice(
        _ icon: String, _ title: String, kind: WorkoutKind
    ) -> some View {
        Button { onQuickTrain(kind) } label: {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(.white.opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private var ghostRaceSection: some View {
        Button(action: onGhostRace) {
            ZStack(alignment: .leading) {
                Image("GoalRunning")
                    .resizable()
                    .scaledToFill()
                    .saturation(0.25)
                    .frame(height: 79)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.69),
                        Color.black.opacity(0.43)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                HStack(spacing: 13) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ghost Race")
                            .font(.system(size: 17, weight: .medium, design: .serif))
                        Text(tr("Race your previous results", "Tren mot dine tidligere tider"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(15)
            }
            .frame(height: 79)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func activePlanSection(_ plan: TrainingPlan) -> some View {
        Button(action: onOpenPlan) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(champagne)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("ACTIVE PLAN", "AKTIV PLAN"))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.15)
                            .foregroundStyle(muted)
                        Text(plan.title)
                            .font(.system(size: 17, weight: .medium, design: .serif))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(planPosition)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                }

                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(hairline.opacity(0.52))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(champagne)
                                    .frame(
                                        width: geometry.size.width
                                            * min(max(completionFraction, 0), 1)
                                    )
                            }
                    }
                    .frame(height: 5)
                    Text("\(Int((min(max(completionFraction, 0), 1) * 100).rounded())) %")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(muted)
                }
            }
            .padding(15)
            .premiumTrainSurface(line: hairline)
        }
        .buttonStyle(.plain)
    }

    private func detailLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 15)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workoutImage(for kind: WorkoutKind) -> String {
        switch kind {
        case .strength: return "StrengthQuickHero"
        case .running: return "GoalRunning"
        case .walking: return "GoalWalking"
        case .recovery, .mobility: return "GoalRecovery"
        case .custom: return "TrainHero"
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

private extension View {
    func premiumTrainSurface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(line.opacity(0.68), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.035), radius: 10, y: 5)
    }
}
