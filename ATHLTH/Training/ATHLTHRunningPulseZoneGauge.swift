import SwiftUI

/// The same live target / measured pulse surface for ATHLTH run/walk engines
/// on iPhone and for the consented iPad mirror. Targets come from a workout
/// prescription; pulse comes only from a fresh sensor measurement.
/// Never fill missing pulse with a planned or historical value.
struct ATHLTHRunningPulseZoneGauge: View {
    let heartRateBPM: Double?
    let maximumHeartRateBPM: Double?
    let targetHeartRateZone: Int?
    let targetMinimumBPM: Double?
    let targetMaximumBPM: Double?
    var targetPercentMin: Double? = nil
    var targetPercentMax: Double? = nil
    var compact: Bool = false

    private var gold: Color { ATHLTHPlanDesign.accentInk }
    private var ink: Color { ATHLTHPlanDesign.ink }
    private var muted: Color { ATHLTHPlanDesign.secondaryInk }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var maximum: Double? {
        guard let maximumHeartRateBPM,
              maximumHeartRateBPM.isFinite,
              (100...240).contains(maximumHeartRateBPM)
        else { return nil }
        return maximumHeartRateBPM
    }

    private var measured: Double? {
        guard let heartRateBPM, heartRateBPM.isFinite,
              (35...240).contains(heartRateBPM)
        else { return nil }
        return heartRateBPM
    }

    private var band: ClosedRange<Int>? {
        if let targetMinimumBPM, let targetMaximumBPM,
           targetMinimumBPM.isFinite, targetMaximumBPM.isFinite,
           (35...240).contains(targetMinimumBPM),
           (35...240).contains(targetMaximumBPM),
           targetMinimumBPM <= targetMaximumBPM {
            let lower = Int(targetMinimumBPM.rounded())
            let upper = Int(targetMaximumBPM.rounded())
            return lower...upper
        }
        if let percent = ATHLTHHeartRateZones.range(
            fromPercent: targetPercentMin, toPercent: targetPercentMax,
            maximumBPM: maximum
        ) {
            return percent
        }
        if let targetHeartRateZone {
            return ATHLTHHeartRateZones.range(
                for: targetHeartRateZone, maximumBPM: maximum
            )
        }
        return nil
    }

    private var currentZone: Int? {
        ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: measured, maximumBPM: maximum
        )
    }

    private var highlightedZones: Set<Int> {
        let matching = ATHLTHHeartRateZones.matchingZones(
            for: band, maximumBPM: maximum
        )
        if !matching.isEmpty { return matching }
        if let targetHeartRateZone, (1...5).contains(targetHeartRateZone) {
            return [targetHeartRateZone]
        }
        return []
    }

    private var targetTitle: String {
        guard let highlighted = highlightedZones.min(),
              let last = highlightedZones.max()
        else { return tr("No zone target", "Ingen målsone") }
        return highlighted == last ? "Z\(highlighted)" : "Z\(highlighted)–Z\(last)"
    }

    private var feedback: String {
        guard let measured else {
            return tr("Waiting for live pulse", "Venter på målt puls")
        }
        guard let band else {
            return tr("No calculated target available", "Ingen beregnet målpuls")
        }
        if measured < Double(band.lowerBound) {
            return tr("Below target", "Under målsonen")
        }
        if measured > Double(band.upperBound) {
            return tr("Above target", "Over målsonen")
        }
        return tr("Within target", "Innenfor målsonen")
    }

    private var feedbackSymbol: String {
        guard let measured else { return "waveform.path.ecg" }
        guard let band else { return "info.circle" }
        return band.contains(Int(measured.rounded()))
            ? "checkmark.circle.fill" : "arrow.up.right.circle"
    }

    private var positionFraction: CGFloat? {
        guard let measured, let maximum else { return nil }
        return CGFloat(min(max((measured / maximum - 0.5) / 0.5, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("YOUR PULSE", "DIN PULS"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(measured.map { "\(Int($0.rounded()))" } ?? "—")
                            .font(.system(size: compact ? 28 : 38, weight: .semibold,
                                          design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                        Text("bpm")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                    }
                    Text(currentZone.map { "Z\($0)" } ??
                         (maximum == nil
                            ? tr("Set HRmax", "Sett makspuls")
                            : measured == nil
                                ? tr("Waiting", "Venter")
                                : tr("Below Z1", "Under Z1")))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(gold)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(tr("TARGET", "MÅL"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(muted)
                    Text(band.map { "\($0.lowerBound)–\($0.upperBound)" } ?? "—")
                        .font(.system(size: compact ? 22 : 29, weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.7)
                    Text("\(targetTitle) · bpm")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(gold)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { zone in
                            let selected = highlightedZones.contains(zone)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selected
                                    ? gold.opacity(0.85)
                                    : ATHLTHPlanDesign.selectedSurface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            currentZone == zone ? ink : .clear,
                                            lineWidth: 2.5
                                        )
                                }
                                .frame(height: compact ? 12 : 15)
                        }
                    }

                    if let fraction = positionFraction {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(ink)
                            .position(
                                x: max(7, min(geometry.size.width - 7,
                                             fraction * geometry.size.width)),
                                y: compact ? 20 : 23
                            )
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(height: compact ? 26 : 30)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { zone in
                    VStack(spacing: 2) {
                        Text("Z\(zone)")
                            .font(.caption2.weight(currentZone == zone ? .bold : .medium))
                            .foregroundStyle(currentZone == zone ? ink : muted)
                        if !compact,
                           let zoneBPM = ATHLTHHeartRateZones.range(
                            for: zone, maximumBPM: maximum
                           ) {
                            Text("\(zoneBPM.lowerBound)–\(zoneBPM.upperBound)")
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(muted)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: feedbackSymbol)
                Text(feedback)
                Spacer(minLength: 0)
                if let maximum {
                    Text("\(tr("HRmax", "Makspuls")) \(Int(maximum.rounded()))")
                        .foregroundStyle(muted)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(gold)
        }
        .padding(compact ? 12 : 17)
        .background(
            ATHLTHPlanDesign.surface,
            in: RoundedRectangle(cornerRadius: compact ? 16 : 22)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            tr("Heart rate", "Puls") + ": " +
            (measured.map { "\(Int($0.rounded())) bpm" } ?? "—") + ". " +
            tr("Target", "Mål") + " " + targetTitle + ": " +
            (band.map { "\($0.lowerBound)–\($0.upperBound) bpm" } ?? "—") +
            ". " + feedback
        )
        .accessibilityIdentifier("athlth-running-live-pulse-zone-gauge")
    }
}
