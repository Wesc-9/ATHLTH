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

    /// Never show this assessment on generic runs or other field tests.
    static func isTestTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let accepted: Set<String> = [
            "3-minute all-out test", "3-minutt all-out test",
            "3 min maksimaltest", "3min maksimaltest", "3mt"
        ]
        let aliases = [
            "3-minute all-out test ·", "3-minutt all-out test ·",
            "3 min maksimaltest ·", "3min maksimaltest ·", "3mt ·"
        ]
        return accepted.contains(normalized) ||
            aliases.contains(where: { normalized.hasPrefix($0) })
    }

    static func isRunningTest(
        title: String, blocks: [WorkoutTemplateBlock]
    ) -> Bool {
        let mainTest = blocks.contains {
            $0.kind == .run && $0.resolvedPhase == .main &&
                $0.durationSeconds == testSeconds &&
                ($0.title.lowercased().contains("maksimaltest") ||
                 $0.title.lowercased().contains("all-out"))
        }
        return isTestTitle(title) && mainTest
    }

    static func paceText(secondsPerKilometer: Double) -> String {
        let rounded = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
    static var protocolSections: [(title: String, detail: String)] {
        [
            (
                localized("Location and equipment", "Underlag og utstyr"),
                localized(
                    "Use a flat, measured 400 m athletics track, preferably in similar conditions between tests. Avoid a treadmill because you must be free to slow down naturally. Use reliable distance measurement.",
                    "Bruk en flat, oppmålt friidrettsbane på 400 meter, helst under sammenlignbare forhold mellom testene. Unngå tredemølle, fordi du må kunne senke farten naturlig. Bruk pålitelig distansemåling."
                )
            ),
            (
                localized("Warm-up · 15–20 min", "Oppvarming · 15–20 min"),
                localized(
                    "Jog easily, do dynamic mobility and running drills, then 2–3 progressive strides of about 10 seconds. Walk or jog very lightly between strides and be ready to start the test fully recovered.",
                    "Jogg rolig, gjør dynamisk bevegelighet og løpsdriller, og avslutt med 2–3 progressive stigningsløp på omtrent 10 sekunder. Gå eller jogg svært rolig mellom dragene, slik at du er klar til testen."
                )
            ),
            (
                localized("Test effort · exactly 3:00", "Testdrag · nøyaktig 3:00"),
                localized(
                    "Start at maximum effort from the first second. Do not reserve energy or pace yourself. Continue to push as your speed naturally declines until 180 seconds have passed.",
                    "Start med maksimal innsats fra første sekund. Ikke spar på kreftene eller forsøk å holde en bestemt fart. Fortsett å presse hele veien mens farten gradvis avtar, til 180 sekunder er gått."
                )
            ),
            (
                localized("Watch and audio", "Klokke og lyd"),
                localized(
                    "Hide current speed and pace on the watch. Use a clear sound alert to know when the 180 seconds are over. You must still collect accurate distance measurements.",
                    "Skjul fart og tempo på klokka under testdraget. Bruk et tydelig lydvarsel når de 180 sekundene er over. Distansen må fortsatt måles nøyaktig."
                )
            ),
            (
                localized("Measurements", "Målinger"),
                localized(
                    "Record the distance covered during the complete 180-second test effort, and separately the distance covered from 2:30 to 3:00. Do not use the whole workout's total distance, which includes warm-up and cool-down.",
                    "Noter distansen i selve testdraget på 180 sekunder, og separat distansen mellom 2:30 og 3:00. Ikke bruk totaldistansen for hele treningsøkten, som også inkluderer oppvarming og nedtrapping."
                )
            ),
            (
                localized("Cool-down", "Nedtrapping"),
                localized(
                    "Walk first and then jog very easily, following the planned cool-down. Stop if you feel unwell.",
                    "Start med gange og fortsett med svært rolig jogg, slik nedtrappingen er planlagt. Avbryt dersom du føler deg uvel."
                )
            ),
            (
                localized("How results are calculated", "Slik beregnes resultatene"),
                localized(
                    "Estimated critical speed (CS) = distance covered in the final 30 seconds / 30 seconds. Estimated D′ = total test distance − CS × 180 seconds. CS is not a directly measured lactate threshold, and D′ is not a direct lactate measurement.",
                    "Estimert kritisk hastighet (CS) = distansen de siste 30 sekundene / 30 sekunder. Estimert D′ = distansen i testdraget − CS × 180 sekunder. CS er ikke en direkte målt laktatterskel, og D′ er ikke en direkte måling av melkesyre."
                )
            )
        ]
    }


    private static func localized(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    /// Persist the actual full protocol in the 3MT main-step notes, rather
    /// than relying only on an ephemeral editor or generic title lookup.
    static var fullProtocolNotes: String {
        protocolSections.map { $0.title + "\n" + $0.detail }
            .joined(separator: "\n\n")
    }


}

/// One complete and reusable description, shown only for the ATHLTH 3MT.
/// The same content follows the prescription from editor to planned summary
/// and structured iPhone player. No new generic exercise schema is necessary.
struct ATHLTHThreeMinuteAllOutProtocol: View {
    @State private var expanded = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var items: [(title: String, detail: String)] {
        ATHLTHThreeMinuteAllOut.protocolSections
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { entry in
                    let item = entry.element
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 11)
        } label: {
            Label(
                tr("Description and test protocol", "Beskrivelse og testprotokoll"),
                systemImage: "doc.text"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
        }
        .padding(14)
        .background(
            ATHLTHPlanDesign.selectedSurface,
            in: RoundedRectangle(cornerRadius: 15)
        )
        .accessibilityIdentifier("athlth-3mt-full-workout-description")
    }
}

/// The result is stored only for the matching, completed running workout.
/// It does not replace HealthKit data and is not posted to social feeds.
enum ATHLTHThreeMinuteAllOutMeasurementStore {
    struct Measurement: Codable, Equatable {
        let totalMeters: Double
        let finalThirtyMeters: Double
        let updatedAt: Date
    }

    private static let storageName = "threeMinuteAllOutMeasuredResults.v1"

    static func load(workoutID: UUID, userID: UUID) -> Measurement? {
        AccountLocalStorage.read(
            [UUID: Measurement].self,
            name: storageName,
            userID: userID
        )?[workoutID]
    }

    @discardableResult
    static func save(
        workoutID: UUID,
        userID: UUID,
        totalMeters: Double,
        finalThirtyMeters: Double
    ) -> Bool {
        guard ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: totalMeters,
            finalThirtySecondsMeters: finalThirtyMeters
        ) != nil else { return false }
        var stored = AccountLocalStorage.read(
            [UUID: Measurement].self,
            name: storageName,
            userID: userID
        ) ?? [:]
        stored[workoutID] = Measurement(
            totalMeters: totalMeters,
            finalThirtyMeters: finalThirtyMeters,
            updatedAt: Date()
        )
        AccountLocalStorage.write(stored, name: storageName, userID: userID)
        return true
    }
}

/// Standalone 3MT measurements, used in completion review AND history.
/// A calculated result requires both manually verified test-leg distances.
struct ATHLTHThreeMinuteAllOutMeasurementsView: View {
    let workoutID: UUID
    let userID: UUID

    @State private var totalMeters = ""
    @State private var lastThirtyMeters = ""
    @State private var savedMeasurement: ATHLTHThreeMinuteAllOutMeasurementStore.Measurement?
    @State private var editing = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func measured(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "."))
    }

    private var draftResult: ATHLTHThreeMinuteAllOut.Result? {
        guard let total = measured(totalMeters),
              let terminal = measured(lastThirtyMeters) else { return nil }
        return ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: total,
            finalThirtySecondsMeters: terminal
        )
    }

    private var savedResult: ATHLTHThreeMinuteAllOut.Result? {
        guard let savedMeasurement else { return nil }
        return ATHLTHThreeMinuteAllOut.calculate(
            totalDistanceMeters: savedMeasurement.totalMeters,
            finalThirtySecondsMeters: savedMeasurement.finalThirtyMeters
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("3MT · measurements and summary", "3MT · målinger og sammendrag"),
                  systemImage: "stopwatch")
                .font(.headline)
                .foregroundStyle(ATHLTHPlanDesign.ink)

            if let result = savedResult, !editing {
                HStack(alignment: .top, spacing: 14) {
                    resultValue(
                        tr("Critical speed (CS)", "Kritisk hastighet (CS)"),
                        ATHLTHThreeMinuteAllOut.paceText(
                            secondsPerKilometer: result.criticalPaceSecondsPerKilometer
                        ) + " min/km"
                    )
                    resultValue(
                        tr("D′", "D′"),
                        String(format: "%.0f m", result.distanceAboveCriticalSpeedMeters)
                    )
                }
                Text(String(format: "%.0f m", result.totalDistanceMeters) + " · " +
                     String(format: "%.0f m", result.finalThirtySecondsMeters) + " " +
                     tr("in the last 30 seconds", "de siste 30 sekundene"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                Button(tr("Edit measurements", "Endre målinger")) {
                    editing = true
                }
                .font(.subheadline.weight(.medium))
            } else {
                Text(tr(
                    "Enter measured distance from the 180-second test effort, not the full workout. The last 30 seconds must be measured separately.",
                    "Legg inn målt distanse fra testdraget på 180 sekunder, ikke hele treningsøkten. De siste 30 sekundene må måles separat."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                HStack(spacing: 12) {
                    measurementInput(tr("Total test (m)", "Testdrag (m)"),
                                     value: $totalMeters,
                                     id: "athlth-3mt-result-total")
                    measurementInput(tr("Last 30 s (m)", "Siste 30 sek (m)"),
                                     value: $lastThirtyMeters,
                                     id: "athlth-3mt-result-last30")
                }
                if let result = draftResult {
                    HStack(alignment: .top, spacing: 14) {
                        resultValue(
                            tr("Estimated CS", "Estimert CS"),
                            ATHLTHThreeMinuteAllOut.paceText(
                                secondsPerKilometer: result.criticalPaceSecondsPerKilometer
                            ) + " min/km"
                        )
                        resultValue(tr("Estimated D′", "Estimert D′"),
                                    String(format: "%.0f m",
                                           result.distanceAboveCriticalSpeedMeters))
                    }
                }
                Button {
                    guard let result = draftResult,
                          ATHLTHThreeMinuteAllOutMeasurementStore.save(
                            workoutID: workoutID,
                            userID: userID,
                            totalMeters: result.totalDistanceMeters,
                            finalThirtyMeters: result.finalThirtySecondsMeters
                          ) else { return }
                    savedMeasurement = ATHLTHThreeMinuteAllOutMeasurementStore.load(
                        workoutID: workoutID, userID: userID
                    )
                    editing = false
                } label: {
                    Label(tr("Save 3MT measurements", "Lagre 3MT-målinger"),
                          systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.accentInk)
                .disabled(draftResult == nil)
            }

            Text(tr(
                "CS and D′ are physiological estimates from recorded distances. They are private to this result and do not change the recorded Apple Health workout.",
                "CS og D′ er fysiologiske estimater basert på målte distanser. De er private for dette resultatet og endrer ikke den registrerte økten i Apple Helse."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 19))
        .accessibilityIdentifier("athlth-3mt-measurements-and-summary")
        .task(id: userID.uuidString + "|" + workoutID.uuidString) {
            let previous = ATHLTHThreeMinuteAllOutMeasurementStore.load(
                workoutID: workoutID, userID: userID
            )
            savedMeasurement = previous
            totalMeters = previous.map { String(format: "%.1f", $0.totalMeters) } ?? ""
            lastThirtyMeters = previous.map {
                String(format: "%.1f", $0.finalThirtyMeters)
            } ?? ""
            editing = previous == nil
        }
    }

    private func resultValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func measurementInput(
        _ title: String,
        value: Binding<String>,
        id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption)
            TextField("–", text: value)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
