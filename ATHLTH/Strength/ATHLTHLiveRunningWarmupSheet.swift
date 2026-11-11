import SwiftUI

/// Modifies only the session copy used for the active workout, never
/// a catalog/library template or a completed exercise history entry.
enum ATHLTHLiveRunningWarmupRecipe {
    static func make(
        session: PlannedSession,
        minutes: Int = 10,
        paceSecondsPerKilometer: Double? = nil,
        heartRateZone: Int? = nil,
        inclinePercent: Double? = nil,
        skipWarmup: Bool = false
    ) -> PlannedSession {
        var copy = session
        guard var template = copy.runningWorkout else { return copy }

        if skipWarmup {
            template.blocks.removeAll { $0.kind == .warmup }
        } else {
            let cleanPace = paceSecondsPerKilometer.flatMap {
                $0.isFinite && $0 > 0 ? min(max($0, 180), 900) : nil
            }
            let cleanZone = heartRateZone.map { min(max($0, 1), 5) }
            let intensity = RunningIntensityTarget(
                kind: cleanPace != nil ? .pace :
                    (cleanZone != nil ? .heartRateZone : .easy),
                paceMinSecondsPerKilometer: cleanPace,
                paceMaxSecondsPerKilometer: cleanPace,
                heartRateZone: cleanZone,
                rpe: nil
            )
            var warmup = template.blocks.first(where: { $0.kind == .warmup })
                ?? RunningWorkoutBlock(
                    kind: .warmup,
                    title: ATHLTHLocalization.choose(
                        english: "Warm-up", norwegian: "Oppvarming"
                    ),
                    work: .time(Double(minutes * 60), intensity: intensity)
                )
            warmup.repetitions = 1
            warmup.work = .time(
                Double(min(max(minutes, 1), 60) * 60),
                intensity: intensity
            )
            warmup.work.treadmillInclinePercent = inclinePercent.flatMap {
                $0.isFinite ? min(max($0, 0), 15) : nil
            }
            template.blocks.removeAll { $0.kind == .warmup }
            template.blocks.insert(warmup, at: 0)
            template.autoStartMainAfterWarmup = true
        }

        copy.runningWorkout = template
        return copy
    }
}

/// A short setup stage between choosing an interval and attaching it to an
/// ongoing free run. Reuses the same RunningWorkoutTemplate engine and HK
/// recording; neither the selected library item nor history is modified.
struct ATHLTHLiveRunningWarmupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PlannedSession
    let onChoose: (PlannedSession, Bool) -> Void

    @State private var minutes = 10
    @State private var hasPaceTarget = false
    @State private var paceSecondsPerKilometer = 360
    @State private var hasPulseZone = false
    @State private var pulseZone = 2
    @State private var hasIncline = false
    @State private var inclinePercent = 1.0

    private func configuredSession(skipWarmup: Bool) -> PlannedSession {
        ATHLTHLiveRunningWarmupRecipe.make(
            session: session,
            minutes: minutes,
            paceSecondsPerKilometer:
                hasPaceTarget ? Double(paceSecondsPerKilometer) : nil,
            heartRateZone: hasPulseZone ? pulseZone : nil,
            inclinePercent: hasIncline ? inclinePercent : nil,
            skipWarmup: skipWarmup
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.title)
                            .font(.title3.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Your existing run keeps recording. Choose a warm-up or begin the intervals immediately.",
                            norwegian: "Løpeøkten fortsetter å registrere. Velg oppvarming eller start dragene med én gang."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label(ATHLTHLocalization.choose(
                            english: "Warm-up", norwegian: "Oppvarming"
                        ), systemImage: "timer")
                        .font(.headline)
                        Stepper(
                            ATHLTHLocalization.format(
                                english: "%d minutes", norwegian: "%d minutter", minutes
                            ),
                            value: $minutes, in: 1...60
                        )
                        Toggle(ATHLTHLocalization.choose(
                            english: "Set warm-up pace", norwegian: "Angi oppvarmingstempo"
                        ), isOn: $hasPaceTarget)
                        if hasPaceTarget {
                            Stepper(String(format: "%d:%02d min/km",
                                paceSecondsPerKilometer / 60,
                                paceSecondsPerKilometer % 60),
                                value: $paceSecondsPerKilometer, in: 180...900, step: 5)
                        }
                        Toggle(ATHLTHLocalization.choose(
                            english: "Target heart-rate zone", norwegian: "Målsone for puls"
                        ), isOn: $hasPulseZone)
                        if hasPulseZone {
                            Stepper(ATHLTHLocalization.choose(
                                english: "Zone", norwegian: "Sone"
                            ) + " \(pulseZone)", value: $pulseZone, in: 1...5)
                        }
                        Toggle(ATHLTHLocalization.choose(
                            english: "Treadmill incline target", norwegian: "Mål for møllestigning"
                        ), isOn: $hasIncline)
                        if hasIncline {
                            Stepper(String(format: "%.1f %%", inclinePercent),
                                value: $inclinePercent, in: 0...15, step: 0.5)
                        }
                    }
                    .tint(ATHLTHTrainDesign.bronze)
                    .padding(17)
                    .athlthTrainPaper()

                    Text(ATHLTHLocalization.choose(
                        english: "The first interval starts after the warm-up timer, or as soon as you press Next step during the warm-up.",
                        norwegian: "Første drag starter etter oppvarmingstiden, eller når du trykker Neste steg under oppvarmingen."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Prepare intervals", norwegian: "Forbered intervaller"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Back", norwegian: "Tilbake"
                    )) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 9) {
                    Button {
                        onChoose(configuredSession(skipWarmup: false), true)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Start warm-up", norwegian: "Start oppvarming"
                        ), systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTrainDesign.bronze)
                    Button {
                        onChoose(configuredSession(skipWarmup: true), true)
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Start intervals now", norwegian: "Start intervallene nå"
                        ))
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        onChoose(configuredSession(skipWarmup: false), false)
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Queue warm-up and intervals",
                            norwegian: "Legg oppvarming og intervaller i kø"
                        ))
                        .frame(maxWidth: .infinity, minHeight: 43)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.regularMaterial)
            }
        }
    }
}
