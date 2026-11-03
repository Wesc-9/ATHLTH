import Foundation
import Supabase
import SwiftUI

/// A treadmill console can be more accurate than wrist-based distance.
/// Only the WORK intervals are scored, and the athlete may submit one
/// correction within 15% of the original verified ATHLTH workout result.
/// Never edit the HealthKit workout or pretend the adjustment is sensor data.
enum ATHLTHChallengeTreadmillReviewPolicy {
    static let maximumDeviation = 0.15
    static let reviewWindow: TimeInterval = 24 * 3600

    static func mayReview(
        _ attempt: ChallengeAttempt,
        challenge: ATHLTHChallenge,
        currentUserID: UUID,
        now: Date = Date()
    ) -> Bool {
        guard attempt.userID == currentUserID,
              challenge.rules.runningFocus == .intervals,
              challenge.rules.runningVenue == .treadmill,
              challenge.rules.runningComparison == .mostWorkDistance,
              attempt.verification == .athlth, attempt.isEligible,
              attempt.sourceWorkoutID != nil,
              let value = attempt.distanceMeters, value > 0,
              let end = attempt.endedAt,
              now >= end && now.timeIntervalSince(end) <= reviewWindow
        else { return false }
        return !attempt.detail.contains("corrected treadmill distance")
    }

    static func withinMargin(measured: Double, submitted: Double) -> Bool {
        measured.isFinite && measured > 0 &&
        submitted.isFinite && submitted > 0 &&
        submitted >= measured * (1 - maximumDeviation) &&
        submitted <= measured * (1 + maximumDeviation)
    }
}

private struct ATHLTHCorrectIntervalDistanceParams: Encodable {
    let p_attempt_id: UUID
    let p_corrected_distance_meters: Double
}

struct ATHLTHChallengeTreadmillReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let attempt: ChallengeAttempt
    let onSaved: @MainActor () async -> Void

    @State private var enteredDistance = ""
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var confirmedTreadmillReading = false

    private var measuredKm: Double { (attempt.distanceMeters ?? 0) / 1_000 }

    private var enteredMeters: Double? {
        let clean = enteredDistance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let kilometers = Double(clean) else { return nil }
        return kilometers * 1_000
    }

    private var valid: Bool {
        guard let submitted = enteredMeters else { return false }
        return confirmedTreadmillReading &&
            ATHLTHChallengeTreadmillReviewPolicy.withinMargin(
                measured: attempt.distanceMeters ?? 0, submitted: submitted
            )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                        Text("ETTERKONTROLL")
                            .tracking(2)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    Text("Se over intervalløkten")
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text("Bare arbeidsdrag teller i utfordringen. Oppvarming, pauser og nedjogging holdes utenfor.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Registrert på klokken")
                            Spacer()
                            Text(String(format: "%.2f km", measuredKm))
                                .font(.headline.monospacedDigit())
                        }
                        Divider()
                        HStack {
                            Text("Konkurransegrunnlag")
                            Spacer()
                            Text("Arbeidsdrag")
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                        }
                        Divider()
                        HStack {
                            Text("Tillatt avvik")
                            Spacer()
                            Text("±15 %").font(.headline)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .padding(17)
                    .background(ATHLTHArenaV3Style.panel())

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Faktisk distanse på tredemøllen")
                            .font(.headline)
                            .foregroundStyle(ATHLTHArenaV3Style.ink)
                        HStack {
                            TextField("0,00", text: $enteredDistance)
                                .keyboardType(.decimalPad)
                                .font(.title2.weight(.semibold))
                            Text("km")
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        .padding(15)
                        .background(ATHLTHArenaV3Style.panel())
                        Text("Skriv inn distansen tredemøllen viser for arbeidsdragene, ikke hele treningsøkten. Kun én korrigering kan sendes.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        if let input = enteredMeters, !ATHLTHChallengeTreadmillReviewPolicy
                            .withinMargin(measured: attempt.distanceMeters ?? 0, submitted: input) {
                            Label(
                                "Avviket er over 15 %. Kontroller distansen.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }

                    Toggle(isOn: $confirmedTreadmillReading) {
                        Text("Jeg bekrefter at distansen er avlest fra tredemøllen.")
                            .font(.subheadline)
                    }
                    .tint(ATHLTHArenaV3Style.gold)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if submitting { ProgressView().tint(.white) }
                            Text(submitting ? "Lagrer…" : "Bekreft korrigeringen")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    }
                    .disabled(!valid || submitting)
                    .opacity(valid ? 1 : 0.5)
                }
                .padding(18)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Gjennomgå resultat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                        .disabled(submitting)
                }
            }
            .onAppear {
                enteredDistance = String(format: "%.2f", measuredKm)
            }
        }
        .environment(\.colorScheme, .light)
    }

    @MainActor
    private func submit() async {
        guard !submitting, valid, let meters = enteredMeters else { return }
        submitting = true
        defer { submitting = false }
        do {
            try await SupabaseEnvironment.client
                .rpc("athlth_correct_treadmill_work_distance",
                     params: ATHLTHCorrectIntervalDistanceParams(
                        p_attempt_id: attempt.id,
                        p_corrected_distance_meters: meters
                     ))
                .execute()
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
