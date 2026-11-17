import Foundation
import SwiftUI

/// Calculations for the running 3-minute all-out test (3MT).
/// Uses only ACTUAL measurements from the 180-second main effort:
/// - cumulative distance during the full 180 seconds
/// - distance completed during seconds 150...180
/// Never uses a planning estimate, HR zone, generic km splits or target pace.
enum ATHLTHThreeMinuteAllOut {
    static let testSeconds = 180.0
    static let terminalSeconds = 30.0

    struct Result: Equatable {
        let totalDistanceMeters: Double
        let finalThirtySecondsMeters: Double
        let criticalSpeedMetersPerSecond: Double
        let distanceAboveCriticalSpeedMeters: Double

        var criticalSpeedKilometersPerHour: Double {
            criticalSpeedMetersPerSecond * 3.6
        }

        var criticalPaceSecondsPerKilometer: Double {
            1_000 / criticalSpeedMetersPerSecond
        }
    }

    /// CS is the mean speed over the last 30 s. D' is the residual
    /// distance after subtracting CS × 180 s (distance-time model).
    /// Reject implausible/non-positive samples rather than generating a
    /// convincing but meaningless physiological result.
    static func calculate(
        totalDistanceMeters: Double,
        finalThirtySecondsMeters: Double
    ) -> Result? {
        guard totalDistanceMeters.isFinite, finalThirtySecondsMeters.isFinite,
              totalDistanceMeters > 0, finalThirtySecondsMeters > 0,
              totalDistanceMeters <= 2_160,
              finalThirtySecondsMeters <= 360,
              finalThirtySecondsMeters <= totalDistanceMeters else {
            return nil
        }
        let criticalSpeed = finalThirtySecondsMeters / terminalSeconds
        let dPrime = totalDistanceMeters - criticalSpeed * testSeconds
        // D' should be positive in a valid all-out decline. Near-zero or
        // negative values suggest pacing, poor measurement or invalid input.
        guard criticalSpeed.isFinite, criticalSpeed > 0,
              dPrime.isFinite, dPrime > 0,
              dPrime < totalDistanceMeters else { return nil }
        return Result(
            totalDistanceMeters: totalDistanceMeters,
            finalThirtySecondsMeters: finalThirtySecondsMeters,
            criticalSpeedMetersPerSecond: criticalSpeed,
            distanceAboveCriticalSpeedMeters: dPrime
        )
    }

    static func isRunningTest(
        title: String, blocks: [WorkoutTemplateBlock]
    ) -> Bool {
        let normalized = title.lowercased()
        let knownName = normalized.contains("3-minute all-out") ||
            normalized.contains("3-minutt all-out") ||
            normalized.contains("3 min maksimaltest") ||
            normalized.contains("3mt")
        let mainTest = blocks.contains {
            $0.kind == .run && $0.resolvedPhase == .main &&
                $0.durationSeconds == testSeconds &&
                ($0.title.lowercased().contains("maksimaltest") ||
                 $0.title.lowercased().contains("all-out"))
        }
        return knownName && mainTest
    }

    static func paceText(secondsPerKilometer: Double) -> String {
        let rounded = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

/// Compact, opt-in 3MT protocol + manual measured-distance calculator.
/// This doesn't alter the original workout, recorded runs or Apple Health.
struct ATHLTHThreeMinuteAllOutGuide: View {
    @State private var totalMeters = ""
    @State private var lastThirtyMeters = ""
    @State private var expanded = false

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func meters(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "."))
    }

    private var calculated: ATHLTHThreeMinuteAllOut.Result? {
        guard let total = meters(totalMeters),
              let terminal = meters(lastThirtyMeters) else { return nil }
        return ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: total,
            finalThirtySecondsMeters: terminal
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr(
                    "Use a flat, measured 400 m track. Avoid a treadmill: you must be able to slow down naturally.",
                    "Bruk en flat, oppmålt 400-metersbane. Unngå tredemølle, slik at farten kan falle naturlig."
                ))
                Text(tr(
                    "Warm up for 15–20 minutes with easy jogging, mobility and 2–3 short 10-second strides.",
                    "Varm opp i 15–20 minutter med rolig jogg, mobilitet og 2–3 korte stigningsløp på 10 sekunder."
                ))
                Text(tr(
                    "Start all-out from the first second and continue for 180 seconds. Do not pace. Hide live pace; use only the finish alert.",
                    "Start maksimalt fra første sekund, og fortsett i 180 sekunder. Ikke spar på kreftene. Skjul fart og tempo underveis, og bruk bare sluttvarselet."
                ))
                Text(tr(
                    "Record the distance covered during the entire 180-second effort and, separately, the distance during seconds 150–180.",
                    "Noter distansen på hele testdraget (180 sekunder) og separat distansen mellom 2:30 og 3:00."
                ))
                .fontWeight(.medium)

                Divider()

                Text(tr("Calculate after the test", "Beregn etter testen"))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Total (m)", "Totaldistanse (m)"))
                            .font(.caption)
                        TextField("—", text: $totalMeters)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("athlth-3mt-total-meters")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Last 30 s (m)", "Siste 30 sek (m)"))
                            .font(.caption)
                        TextField("—", text: $lastThirtyMeters)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("athlth-3mt-final30-meters")
                    }
                }
                if let result = calculated {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(format: tr(
                            "Estimated CS: %.2f m/s · %.1f km/h · %@ min/km",
                            "Estimert CS: %.2f m/s · %.1f km/t · %@ min/km"
                        ), result.criticalSpeedMetersPerSecond,
                            result.criticalSpeedKilometersPerHour,
                            ATHLTHThreeMinuteAllOut.paceText(
                                secondsPerKilometer: result.criticalPaceSecondsPerKilometer
                            )))
                        Text(String(format: tr("Estimated D′: %.0f m",
                                               "Estimert D′: %.0f m"),
                                    result.distanceAboveCriticalSpeedMeters))
                    }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("athlth-3mt-calculated-result")
                } else if !totalMeters.isEmpty || !lastThirtyMeters.isEmpty {
                    Text(tr(
                        "Enter valid, measured distances. D′ must be positive; if not, check the test or measurements.",
                        "Oppgi gyldige, faktisk målte distanser. D′ må være positiv; ellers bør testen eller målingene kontrolleres."
                    ))
                    .font(.caption)
                }

                Text(tr(
                    "CS and D′ are estimates, not a directly measured lactate threshold. This calculator does not save results or infer them from planned pace.",
                    "CS og D′ er estimater, ikke en direkte målt laktatterskel. Beregningen lagres ikke og henter aldri tall fra planlagt tempo."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .padding(.top, 10)
        } label: {
            Label(
                tr("3MT protocol and results", "3MT · protokoll og resultat"),
                systemImage: "stopwatch"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
        }
        .padding(12)
        .background(
            ATHLTHPlanDesign.selectedSurface,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .accessibilityIdentifier("athlth-three-minute-all-out-guide")
    }
}
