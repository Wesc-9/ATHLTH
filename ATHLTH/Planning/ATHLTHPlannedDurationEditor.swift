import SwiftUI

/// One precise, always-visible H:M:S editor for all timed workout steps.
struct ATHLTHPlannedDurationEditor: View {
    @Binding var durationSeconds: TimeInterval?

    private var total: Int {
        min(max(Int((durationSeconds ?? 60).rounded()), 1), 86_399)
    }

    private func component(_ part: Int) -> Binding<Int> {
        Binding(
            get: {
                switch part {
                case 0: return total / 3600
                case 1: return (total / 60) % 60
                default: return total % 60
                }
            },
            set: { value in
                var hours = total / 3600
                var minutes = (total / 60) % 60
                var seconds = total % 60
                switch part {
                case 0: hours = min(max(value, 0), 23)
                case 1: minutes = min(max(value, 0), 59)
                default: seconds = min(max(value, 0), 59)
                }
                durationSeconds = TimeInterval(
                    min(max(hours * 3600 + minutes * 60 + seconds, 1), 86_399)
                )
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(ATHLTHLocalization.choose(
                english: "DURATION", norwegian: "VARIGHET"
            ))
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHTrainDesign.bronze)

            HStack(spacing: 9) {
                timeCell(
                    ATHLTHLocalization.choose(english: "Hours", norwegian: "Timer"),
                    value: component(0)
                )
                Text(":").font(.title3.weight(.medium)).padding(.top, 15)
                timeCell(
                    ATHLTHLocalization.choose(english: "Minutes", norwegian: "Minutter"),
                    value: component(1)
                )
                Text(":").font(.title3.weight(.medium)).padding(.top, 15)
                timeCell(
                    ATHLTHLocalization.choose(english: "Seconds", norwegian: "Sekunder"),
                    value: component(2)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeCell(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title3.monospacedDigit())
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .frame(maxWidth: 100, minHeight: 46)
                .background(ATHLTHPlanDesign.canvas,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8))
                .accessibilityLabel(label)
        }
        .frame(maxWidth: 110)
    }
}
