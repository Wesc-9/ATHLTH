import SwiftUI

/// The same-account iPad follows an iPhone session without recording a
/// duplicate workout. This card can be minimized to the existing return pill.
struct ATHLTHCrossDeviceLiveCard: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    let onMinimize: () -> Void

    private var duration: String {
        let value = Int(max(0, snapshot.elapsedSeconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: snapshot.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHTrainDesign.paleGold, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(ATHLTHLocalization.choose(
                        english: "LIVE ON IPHONE", norwegian: "LIVE PÅ IPHONE"
                    ))
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(snapshot.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button(action: onMinimize) {
                    Image(systemName: "chevron.up")
                        .font(.headline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Minimize workout", norwegian: "Minimer økten"
                ))
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "DURATION", norwegian: "ØKTTID"
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(duration)
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                if let distance = snapshot.distanceMeters {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "DISTANCE", norwegian: "DISTANSE"
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Text(String(format: "%.2f km", distance / 1000))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                } else if let count = snapshot.completedSets {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "COMPLETED SETS", norwegian: "UTFØRTE SETT"
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Text(snapshot.totalSets.map { "\(count)/\($0)" } ?? "\(count)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }

            if let step = snapshot.currentStep {
                Divider()
                Label(step, systemImage: "figure.run.circle")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            if let next = snapshot.nextStep {
                Text(ATHLTHLocalization.choose(
                    english: "Next", norwegian: "Neste"
                ) + " · " + next)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Text(ATHLTHLocalization.choose(
                english: "Read-only view. Recording continues on iPhone.",
                norwegian: "Kun visning. Registreringen fortsetter på iPhone."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(ATHLTHTheme.primaryText)
        .padding(18)
        .frame(maxWidth: 430, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .strokeBorder(ATHLTHTheme.premiumGold.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 9)
        .accessibilityElement(children: .contain)
    }
}
