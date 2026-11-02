import SwiftUI

/// A workout step with a separate reorder grip, persistent swipe-to-delete,
/// and an independent options menu. Swiping never changes the step order.
struct ATHLTHPlannedWorkoutStepRow: View {
    let block: WorkoutTemplateBlock
    let position: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveBy: (Int) -> Void
    let onBeginDrag: () -> NSItemProvider

    @State private var isDeleteRevealed = false
    @State private var horizontalDrag: CGFloat = 0

    private let deleteWidth: CGFloat = 76
    private var isPause: Bool { block.isRestOrActiveRecovery }

    // The settled offset comes from retained state, rather than the gesture
    // translation. Releasing the finger never closes an exposed delete action.
    private var stepOffset: CGFloat {
        let base: CGFloat = isDeleteRevealed ? -deleteWidth : 0
        return min(0, max(-deleteWidth, base + horizontalDrag))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) >
                      abs(value.translation.height) * 1.15 else { return }
                horizontalDrag = value.translation.width
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width) >
                    abs(value.translation.height) * 1.15
                withAnimation(.easeOut(duration: 0.18)) {
                    if horizontal {
                        if value.translation.width < -34 {
                            isDeleteRevealed = true
                        } else if value.translation.width > 34 {
                            isDeleteRevealed = false
                        }
                    }
                    horizontalDrag = 0
                }
            }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTrainDesign.ink.opacity(0.42))
                .frame(width: 27, height: 49)
                .contentShape(Rectangle())
                .onDrag(onBeginDrag)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Drag to reorder step", norwegian: "Dra for å flytte deløkten"
                ))
                .accessibilityAction(named: Text(ATHLTHLocalization.choose(
                    english: "Move up", norwegian: "Flytt opp"
                ))) {
                    if canMoveUp { onMoveBy(-1) }
                }
                .accessibilityAction(named: Text(ATHLTHLocalization.choose(
                    english: "Move down", norwegian: "Flytt ned"
                ))) {
                    if canMoveDown { onMoveBy(1) }
                }

            ZStack(alignment: .trailing) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Delete step", norwegian: "Slett deløkt"
                    ), systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth, height: 49)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isDeleteRevealed)
                .accessibilityHidden(!isDeleteRevealed)

                HStack(spacing: 0) {
                    Button(action: onEdit) {
                    HStack(spacing: 8) {
                        Text("\(position)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isPause ? .secondary : ATHLTHTrainDesign.bronze)
                            .frame(width: 21)
                        Image(systemName: isPause ? "pause.fill" : block.kind.systemImage)
                            .font(.system(size: 15))
                            .foregroundStyle(isPause ? .secondary : ATHLTHTrainDesign.ink)
                            .frame(width: 23)
                        Text(isPause
                            ? ATHLTHLocalization.choose(english: "Recovery", norwegian: "Pause")
                            : ATHLTHWorkoutNameSuggestion.displayStepTitle(block))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        Text(block.durationSeconds.map { "\(Int($0 / 60)) min" }
                            ?? block.distanceMeters.map { "\(Int($0)) m" } ?? "–")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .lineLimit(1)
                        Text(block.targetHeartRateZone.map { "Z\($0)" }
                            ?? (isPause ? "Pause" : "–"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                            .frame(minWidth: 26)
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Edit step details. Swipe left or use options to delete.",
                        norwegian: "Rediger deløkten. Sveip til venstre eller bruk menyen for å slette."
                    ))

                    Menu {
                    Button(action: onEdit) {
                        Label(ATHLTHLocalization.choose(
                            english: "Edit step", norwegian: "Rediger deløkt"
                        ), systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label(ATHLTHLocalization.choose(
                            english: "Delete step", norwegian: "Slett deløkt"
                        ), systemImage: "trash")
                    }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Step options", norwegian: "Alternativer for deløkt"
                    ), systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .frame(width: 44, height: 49)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(
                    isPause ? ATHLTHPlanDesign.warmSurface.opacity(0.56)
                        : ATHLTHPlanDesign.canvas,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .offset(x: stepOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(swipeGesture)
            }
            .frame(maxWidth: .infinity, minHeight: 49)
            .clipped()
        }
    }
}
