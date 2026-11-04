import SwiftUI

/// A compact group row shown in the actual plan-day card. It is a projection
/// of real workout blocks, not a second copy of the workout or a draft editor.
struct ATHLTHAdvancedPlanGroupSummaryRow: View {
    let kind: WorkoutBlockGroupKind
    let blocks: [WorkoutTemplateBlock]
    let onEditStep: (UUID) -> Void

    @State private var expanded = false

    private let gold = ATHLTHTrainDesign.bronze
    private let ink = ATHLTHTrainDesign.ink

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var subtitle: String {
        if kind == .superset {
            let exercises = blocks.filter { $0.kind == .exercise }.count
            let rounds = blocks.first?.groupRounds ?? 1
            return "\(exercises) " + tr("exercises", "øvelser") +
                " · \(rounds) " + tr("rounds", "runder")
        }
        let steps = blocks.expandedForExecution()
        let efforts = steps.filter { $0.kind == .run && !$0.isActiveRecovery }.count
        let pauses = steps.filter { $0.isRestOrActiveRecovery }.count
        return "\(efforts) " + tr("efforts", "drag") +
            " · \(pauses) " + tr("recoveries", "pauser")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(gold)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.62),
                                    in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(gold)
                }
                .frame(minHeight: 47)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(kind.title + ", " + subtitle)
            .accessibilityHint(tr(
                "Show or hide individual workout steps.",
                "Vis eller skjul de enkelte deløktene."
            ))

            if expanded {
                ForEach(blocks, id: \.editorDragID) { block in
                    Button {
                        onEditStep(block.editorDragID)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: block.isRestOrActiveRecovery
                                  ? "pause.fill" : block.kind.systemImage)
                                .foregroundStyle(gold)
                                .frame(width: 22)
                            Text(block.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Text(block.targetText ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 9)
                        .frame(minHeight: 39)
                        .background(.white.opacity(0.75),
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(ATHLTHTrainDesign.canvas.opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(gold.opacity(0.25), lineWidth: 0.8)
        }
    }
}
