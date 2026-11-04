import SwiftUI

/// Pure geometry rules make Stage Manager and split-view sizing testable
/// without building an alternate set of workout editing views.
enum ATHLTHStudioWorkspaceLayout {
    static func planWidth(
        totalWidth: CGFloat,
        fraction: Double,
        dragging: CGFloat = 0
    ) -> CGFloat {
        let available = max(0, totalWidth - 14)
        let desired = available * CGFloat(fraction) + dragging
        let maximum = max(275, available - 530)
        return min(maximum, max(275, desired))
    }

    static func persistedFraction(
        totalWidth: CGFloat,
        currentFraction: Double,
        dragDelta: CGFloat
    ) -> Double {
        guard totalWidth > 0 else { return currentFraction }
        let next = currentFraction + Double(dragDelta / totalWidth)
        return min(0.53, max(0.26, next))
    }
}

/// One reusable iPad workspace shell around the *existing* training-plan and
/// workout editors. It owns only presentation, not training or draft data.
/// iPhone never instantiates this component.
struct ATHLTHStudioAdaptiveWorkspace<Plan: View, Editor: View, FocusRail: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shared across new and existing plans so users do not need to resize
    /// each editor separately. An individual drag is committed on release.
    @AppStorage("athlth.studio.workspace.planColumnFraction")
    private var savedPlanFraction = 0.32

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var focusOnWorkout = false
    @State private var compactShowsPlan = false

    let minimumSideBySideWidth: CGFloat
    let plan: Plan
    let editor: Editor
    let focusRail: FocusRail

    init(
        minimumSideBySideWidth: CGFloat = 925,
        @ViewBuilder plan: () -> Plan,
        @ViewBuilder editor: () -> Editor,
        @ViewBuilder focusRail: () -> FocusRail
    ) {
        self.minimumSideBySideWidth = minimumSideBySideWidth
        self.plan = plan()
        self.editor = editor()
        self.focusRail = focusRail()
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= minimumSideBySideWidth {
                HStack(spacing: 0) {
                    if focusOnWorkout {
                        focusRail
                            .frame(width: 72)
                    } else {
                        plan
                            .frame(width: planWidth(for: geometry.size.width))
                    }

                    if focusOnWorkout {
                        Rectangle()
                            .fill(ATHLTHStudioStyle.outline.opacity(0.6))
                            .frame(width: 1)
                    } else {
                        resizeHandle(availableWidth: geometry.size.width)
                    }

                    VStack(spacing: 0) {
                        header(canFocus: true, compact: false)
                        editor
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.17),
                           value: focusOnWorkout)
            } else {
                VStack(spacing: 0) {
                    header(canFocus: false, compact: true)
                    if compactShowsPlan {
                        plan
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        editor
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
    }

    private func planWidth(for width: CGFloat) -> CGFloat {
        ATHLTHStudioWorkspaceLayout.planWidth(
            totalWidth: width,
            fraction: savedPlanFraction,
            dragging: dragTranslation
        )
    }

    private func resizeHandle(availableWidth: CGFloat) -> some View {
        Rectangle()
            .fill(ATHLTHStudioStyle.outline.opacity(0.22))
            .frame(width: 14)
            .overlay {
                Capsule()
                    .fill(ATHLTHStudioStyle.gold.opacity(0.55))
                    .frame(width: 3, height: 58)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        savedPlanFraction =
                            ATHLTHStudioWorkspaceLayout.persistedFraction(
                                totalWidth: availableWidth,
                                currentFraction: savedPlanFraction,
                                dragDelta: value.translation.width
                            )
                    }
            )
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Resize plan and workout columns",
                norwegian: "Endre bredde på plan og øktbygger"
            ))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: savedPlanFraction = min(0.53, savedPlanFraction + 0.05)
                case .decrement: savedPlanFraction = max(0.26, savedPlanFraction - 0.05)
                @unknown default: break
                }
            }
    }

    private func header(canFocus: Bool, compact: Bool) -> some View {
        HStack(spacing: 10) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Workout builder",
                    norwegian: "Øktbygger"
                ),
                systemImage: "square.and.pencil"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHStudioStyle.ink)

            Spacer(minLength: 8)

            if compact {
                Button {
                    compactShowsPlan.toggle()
                } label: {
                    Label(
                        compactShowsPlan
                            ? ATHLTHLocalization.choose(
                                english: "Show workout",
                                norwegian: "Vis økten"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Show plan",
                                norwegian: "Vis planen"
                            ),
                        systemImage: compactShowsPlan ? "square.and.pencil" : "calendar"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            } else if canFocus {
                Button {
                    focusOnWorkout.toggle()
                } label: {
                    Label(
                        focusOnWorkout
                            ? ATHLTHLocalization.choose(
                                english: "Split view", norwegian: "Delt visning"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Focus mode", norwegian: "Fokusmodus"
                            ),
                        systemImage: focusOnWorkout ? "rectangle.split.2x1"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Expand or restore the workout editor without closing your plan",
                    norwegian: "Utvid eller gjenopprett øktbyggeren uten å lukke planen"
                ))
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 48)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            ATHLTHStudioStyle.outline.opacity(0.5).frame(height: 1)
        }
    }
}
