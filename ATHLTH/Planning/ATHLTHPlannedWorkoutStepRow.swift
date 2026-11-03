import SwiftUI

/// A workout step with a separate reorder grip and a clean full-swipe delete.
/// There is no persistent red delete tray or always-visible delete control.
/// A normal tap edits; the more menu remains accessible. Swiping never reorders.
struct ATHLTHPlannedWorkoutStepRow: View {
    @Environment(\.locale) private var locale
    let block: WorkoutTemplateBlock
    let position: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveBy: (Int) -> Void
    let onReorderMove: (CGPoint) -> Void
    let onReorderEnd: () -> Void

    @State private var horizontalDrag: CGFloat = 0
    @State private var measuredRowWidth: CGFloat = 320

    /// Require a deliberate leftward gesture across most of the row,
    /// rather than exposing a red destructive button on a small swipe.
    static func shouldDeleteSwipe(
        horizontal: CGFloat,
        vertical: CGFloat,
        rowWidth: CGFloat
    ) -> Bool {
        guard horizontal < 0, abs(horizontal) > abs(vertical) * 1.35 else {
            return false
        }
        let threshold = max(150, min(270, rowWidth * 0.62))
        return abs(horizontal) >= threshold
    }
    private var isPause: Bool { block.isRestOrActiveRecovery }

    private var paceSummary: String? {
        guard block.kind == .run,
              let secondsPerKm = block.targetPaceSecondsPerKilometer,
              secondsPerKm.isFinite, secondsPerKm > 0 else { return nil }
        if block.treadmillInclinePercent != nil {
            let kilometersPerHour = 3_600 / secondsPerKm
            return kilometersPerHour.formatted(
                .number.precision(.fractionLength(1)).locale(locale)
            ) + (ATHLTHLocalization.isNorwegian ? " km/t" : " km/h")
        }
        let seconds = Int(secondsPerKm.rounded())
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder) min/km"
    }

    // A local, long-press-driven gesture avoids iOS system drag-and-drop's
    // green plus badge and keeps the whole card attached to the finger.
    private var reorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("athlthWorkoutStudio")
            ))
            .onChanged { gesture in
                if case .second(true, let drag?) = gesture {
                    onReorderMove(drag.location)
                }
            }
            .onEnded { _ in onReorderEnd() }
    }

    // Subtle movement confirms the gesture without exposing a red tray.
    private var swipeOffset: CGFloat {
        max(-55, min(0, horizontalDrag * 0.30))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.width) >
                      abs(value.translation.height) * 1.35 else { return }
                horizontalDrag = min(0, value.translation.width)
            }
            .onEnded { value in
                let delete = Self.shouldDeleteSwipe(
                    horizontal: value.translation.width,
                    vertical: value.translation.height,
                    rowWidth: measuredRowWidth
                )
                withAnimation(.easeOut(duration: 0.16)) {
                    horizontalDrag = 0
                }
                if delete {
                    onDelete()
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
                .gesture(reorderGesture)
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
                                .foregroundStyle(
                                    isPause ? .secondary : ATHLTHTrainDesign.bronze
                                )
                                .frame(width: 21)
                            Image(systemName: isPause
                                  ? "pause.fill"
                                  : block.kind == .run &&
                                    block.treadmillInclinePercent != nil
                                        ? "figure.run.treadmill" : block.kind.systemImage)
                                .font(.system(size: 15))
                                .foregroundStyle(
                                    isPause ? .secondary : ATHLTHTrainDesign.ink
                                )
                                .frame(width: 23)
                            Text(isPause
                                ? ATHLTHLocalization.choose(
                                    english: "Recovery", norwegian: "Pause"
                                )
                                : ATHLTHWorkoutNameSuggestion.displayStepTitle(block))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHTrainDesign.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(block.durationSeconds.map { "\(Int($0 / 60)) min" }
                                    ?? block.distanceMeters.map { "\(Int($0)) m" } ?? "–")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ATHLTHTrainDesign.ink)
                                if let paceSummary {
                                    Text(paceSummary)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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
                        english: "Edit step details. Swipe fully left to delete, or use options.",
                        norwegian: "Rediger deløkten. Sveip helt til venstre for å slette, eller bruk menyen."
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
                .offset(x: swipeOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(swipeGesture)
            }
            .frame(maxWidth: .infinity, minHeight: 49)
            .clipped()
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { _, width in
                if width > 0 { measuredRowWidth = width }
            }
        }
    }
