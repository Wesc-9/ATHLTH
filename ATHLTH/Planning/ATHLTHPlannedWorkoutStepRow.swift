import SwiftUI

/// ScrollView-compatible native-feeling swipe to reveal Delete.
/// Drag begins on the separate grip, so horizontal swipes never reorder steps.
struct ATHLTHPlannedWorkoutStepRow: View {
    let block: WorkoutTemplateBlock
    let position: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveBy: (Int) -> Void
    let onBeginDrag: () -> NSItemProvider

    @State private var deleteRevealed = false
    @State private var swipeTranslation: CGFloat = 0

    private let deleteWidth: CGFloat = 72
    private var rowOffset: CGFloat {
        max(-deleteWidth, min(0,
            (deleteRevealed ? -deleteWidth : 0) + swipeTranslation
        ))
    }
    private var isPause: Bool { block.isRestOrActiveRecovery }

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
                    deleteRevealed = false
                    onDelete()
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Delete step", norwegian: "Slett deløkt"
                    ), systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth, height: 49)
                    .background(Color.red.opacity(0.88),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityHidden(!deleteRevealed)

                Button {
                    if deleteRevealed {
                        withAnimation(.easeOut(duration: 0.18)) { deleteRevealed = false }
                    } else {
                        onEdit()
                    }
                } label: {
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
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(minHeight: 49)
                    .background(
                        isPause ? ATHLTHPlanDesign.warmSurface.opacity(0.56)
                            : ATHLTHPlanDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .offset(x: rowOffset)
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Edit details; swipe left for Delete",
                    norwegian: "Rediger detaljer. Sveip mot venstre for å slette."
                ))
                .accessibilityAction(named: Text(ATHLTHLocalization.choose(
                    english: "Delete step", norwegian: "Slett deløkt"
                )), onDelete)
            }
            .frame(maxWidth: .infinity, minHeight: 49)
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard abs(value.translation.width) >
                              abs(value.translation.height) * 1.2 else { return }
                        swipeTranslation = value.translation.width
                    }
                    .onEnded { value in
                        let horizontal = abs(value.translation.width) >
                            abs(value.translation.height) * 1.2
                        withAnimation(.easeOut(duration: 0.18)) {
                            if horizontal {
                                deleteRevealed = deleteRevealed
                                    ? value.translation.width < 35
                                    : value.translation.width < -38
                            }
                            swipeTranslation = 0
                        }
                    }
            )
        }
    }
}
