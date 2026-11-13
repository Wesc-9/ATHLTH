import SwiftUI

/// Compact two-runner comparison from the recording engine's real Ghost
/// deltas. No independent GPS race calculation and no invented lead.
struct ATHLTHGhostLiveComparisonTable: View {
    let name: String
    let distanceMeters: Double?
    let signedLeadMeters: Double?
    let timeGapSeconds: Double?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var you: Double? {
        guard let distanceMeters, distanceMeters.isFinite,
              distanceMeters >= 0 else { return nil }
        return distanceMeters
    }

    private var ghost: Double? {
        guard let you, let signedLeadMeters,
              signedLeadMeters.isFinite else { return nil }
        return max(0, you - signedLeadMeters)
    }

    private func km(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f km", value / 1_000)
    }

    private var status: String {
        guard let lead = signedLeadMeters, lead.isFinite else {
            return tr("Waiting for fresh GPS", "Venter på fersk GPS")
        }
        if abs(lead) < 8 { return tr("Neck and neck", "Jevnt løp") }
        let metres = Int(abs(lead).rounded())
        return lead > 0 ? tr("\(metres) m ahead", "\(metres) m foran")
                        : tr("\(metres) m behind", "\(metres) m bak")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(tr("YOU VS GHOST", "DU MOT GHOST"),
                      systemImage: "figure.run.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Spacer()
                Text(name)
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(tr("Participant", "Deltaker"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(tr("Distance", "Distanse"))
                    .frame(width: 92, alignment: .trailing)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            Divider()
            row(tr("You", "Du"), value: km(you), highlighted: true)
            Divider()
            row("Ghost", value: km(ghost), highlighted: false)
            Divider()

            HStack {
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                if let seconds = timeGapSeconds, seconds.isFinite {
                    Label(String(format: "%+.0f s", seconds),
                          systemImage: "timer")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.surface,
                    in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("athlth-ghost-comparison-table")
    }

    private func row(
        _ name: String, value: String, highlighted: Bool
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "figure.run")
                    .foregroundStyle(highlighted
                        ? ATHLTHPlanDesign.accentInk
                        : ATHLTHPlanDesign.secondaryInk)
                Text(name)
                    .font(.subheadline.weight(highlighted ? .bold : .medium))
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(ATHLTHPlanDesign.ink)
    }
}
