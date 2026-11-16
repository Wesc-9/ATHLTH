import SwiftUI

/// Shows the exact Home recommendation without changing its workout or
/// start-flow semantics. The execution actions remain in the pinned footer.
struct HomeDailyRecommendedWorkoutSheet: View {
    let workout: PlannedSession
    let isPlanWorkout: Bool
    let canStartWithWatch: Bool
    let onOpenPlannedWorkout: () -> Void
    let onStartOnPhone: () -> Void
    let onStartOnWatch: () -> Void
    var onSendToWatch: (() -> Void)? = nil
    var onDelayOnPhone: ((TimeInterval) -> Void)? = nil
    var onDelayOnWatch: (() -> Void)? = nil

    var isCalendarWorkout = false
    var canStart = true
    var isCancelled = false
    var onEdit: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var confirmingDeletion = false
    @State private var confirmingCancellation = false

    @Environment(\.dismiss) private var dismiss

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .frame(width: 42, height: 42)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Close", "Lukk"))

                    Spacer(minLength: 0)

                    Text(isCalendarWorkout ? tr("Planned workout", "Planlagt treningsøkt") : tr("Recommended workout", "Anbefalt treningsøkt"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)
                    // Calendar actions are distinct: edit, cancel and delete.
                    // Never display these controls for a completed workout.
                    if onEdit != nil || onCancel != nil || onDelete != nil {
                        Menu {
                            if let onEdit {
                                Button {
                                    onEdit()
                                    dismiss()
                                } label: {
                                    Label(tr("Edit workout", "Rediger økt"),
                                          systemImage: "pencil")
                                }
                            }
                            if onCancel != nil {
                                Button {
                                    confirmingCancellation = true
                                } label: {
                                    Label(tr("Cancel workout", "Avlys økt"),
                                          systemImage: "calendar.badge.minus")
                                }
                            }
                            if onDelete != nil {
                                Button(role: .destructive) {
                                    confirmingDeletion = true
                                } label: {
                                    Label(tr("Delete workout", "Slett økt"),
                                          systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(ATHLTHTrainDesign.ink)
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel(tr("Workout actions", "Økthandlinger"))
                    } else {
                        Color.clear.frame(width: 42, height: 42).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 7)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HomeDailyRecommendedWorkoutHero(workout: workout)

                        if !workout.resolvedWorkoutBlocks.isEmpty {
                            // Use the same grouped phases as the Simple
                            // workout details, never 26 flat repetitions.
                            ATHLTHWorkoutRecipePreview(
                                title: workout.title,
                                summary: "",
                                category: workout.workoutCategory ??
                                    (workout.kind == .running ? "running" :
                                     workout.kind == .walking ? "walking" : "hybrid"),
                                symbol: workout.kind.systemImage,
                                difficulty: nil,
                                durationMinutes: workout.durationMinutes,
                                blocks: workout.resolvedWorkoutBlocks,
                                embeddedInDetails: true
                            )
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.white,
                                in: RoundedRectangle(cornerRadius: 19)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 19)
                                    .strokeBorder(
                                        ATHLTHPlanDesign.outline.opacity(0.75),
                                        lineWidth: 0.8
                                    )
                            }
                        }

                        if isPlanWorkout && !isCalendarWorkout {
                            Label {
                                Text(tr(
                                    "This is the workout in your plan. Open it to use the plan's existing tracking and completion rules.",
                                    "Dette er økten i treningsplanen. Åpne den for å bruke planens registrering og fullføringsregler."
                                ))
                            } icon: {
                                Image(systemName: "checkmark.seal")
                            }
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                        }
                    }
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
            }
            .background {
                LinearGradient(
                    colors: [
                        ATHLTHTrainDesign.paper,
                        ATHLTHPlanDesign.canvas
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .alert(tr("Cancel planned workout?", "Avlyse planlagt økt?"),
                   isPresented: $confirmingCancellation) {
                Button(tr("Keep", "Behold"), role: .cancel) {}
                Button(tr("Cancel workout", "Avlys økt"), role: .destructive) {
                    onCancel?()
                    dismiss()
                }
            } message: {
                Text(tr(
                    "The session stays in your calendar as cancelled. It is not deleted.",
                    "Økten blir stående som avlyst i kalenderen. Den slettes ikke."
                ))
            }
            .alert(tr("Delete planned workout?", "Slette planlagt økt?"), isPresented: $confirmingDeletion) {
                Button(tr("Cancel", "Avbryt"), role: .cancel) {}
                Button(tr("Delete", "Slett"), role: .destructive) { onDelete?(); dismiss() }
            } message: {
                Text(tr("This removes the planned workout. Completed training stays in your history.", "Dette sletter den planlagte økten. Fullført trening beholdes i historikken."))
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeDailyRecommendedWorkoutActions(
                    // Calendar plan sessions can start directly on either
                    // device; only Coach recommendations open plan details.
                    isPlanWorkout: isPlanWorkout && !isCalendarWorkout,
                    canStartWithWatch: canStartWithWatch,
                    onOpenPlannedWorkout: onOpenPlannedWorkout,
                    onStartOnPhone: onStartOnPhone,
                    onStartOnWatch: onStartOnWatch,
                    onSendToWatch: onSendToWatch,
                    onDelayOnPhone: onDelayOnPhone,
                    onDelayOnWatch: onDelayOnWatch
                )
                .disabled(!canStart)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: 660)
                .frame(maxWidth: .infinity)
                .background {
                    ATHLTHPlanDesign.canvas
                        .ignoresSafeArea(edges: .bottom)
                }
                .overlay(alignment: .top) {
                    ATHLTHPlanDesign.outline.opacity(0.55)
                        .frame(height: 0.75)
                }
            }
        }
    }
}
