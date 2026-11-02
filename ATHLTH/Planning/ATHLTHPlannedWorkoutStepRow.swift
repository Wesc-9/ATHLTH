import SwiftUI

/// A workout step with a dedicated drag handle and a reliable options menu.
/// Editing and deletion are separate actions: horizontal scrolling never
/// reveals an offscreen button or interferes with the workout's timeline.
struct ATHLTHPlannedWorkoutStepRow: View {
    let block: WorkoutTemplateBlock
    let position: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveBy: (Int) -> Void
    let onBeginDrag: () -> NSItemProvider

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
                    english: "Edit step details; use the options menu to delete",
                    norwegian: "Rediger deløkten. Bruk menyen med tre prikker for å slette."
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
            .frame(maxWidth: .infinity, minHeight: 49)
        }
    }
}
