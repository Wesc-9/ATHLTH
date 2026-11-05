import SwiftUI

/// Consistent floating return control for iPhone- and Watch-recorded workouts.
struct ATHLTHMinimizedWorkoutReturnPill: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var attention = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        attention
                            ? Color.orange
                            : ATHLTHTheme.primaryText.opacity(0.84)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText.opacity(0.88)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .opacity(0.93)
            }
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(0.45),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: Color.black.opacity(0.10),
                radius: 14,
                y: 6
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
