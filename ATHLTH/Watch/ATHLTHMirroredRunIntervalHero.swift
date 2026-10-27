import SwiftUI

/// Presentation-only interval focus; recording and phase transitions remain
/// exclusively owned by the Apple Watch HealthKit workout engine.
struct ATHLTHMirroredRunIntervalHero: View {
    let snapshot: WatchWorkoutLiveSnapshot

    private var isPaused: Bool { snapshot.state != .running }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let remaining = effectiveRemaining(now: tick.date)
            let progress = min(max(snapshot.runningStepProgress ?? 0, 0), 1)
            VStack(spacing: 17) {
                HStack {
                    Label(phaseName, systemImage: phaseIcon)
                        .font(.caption.weight(.bold))
                        .tracking(1)
                    Spacer()
                    if let index = snapshot.runningStepIndex,
                       let count = snapshot.runningStepCount, count > 0 {
                        Text("\(index + 1) / \(count)")
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
                .foregroundStyle(Color.white.opacity(0.88))

                if snapshot.runningAwaitingMainStart == true {
                    Text(ATHLTHLocalization.choose(
                        english: "READY", norwegian: "KLAR"
                    ))
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    Text(ATHLTHLocalization.choose(
                        english: "Start the main set when ready",
                        norwegian: "Start hoveddelen når du er klar"
                    ))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 9)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: progress)
                        VStack(spacing: 2) {
                            Text(remaining.map(ATHLTHRunStepCountdown.display) ?? "—")
                                .font(.system(size: 66, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.55)
                                .lineLimit(1)
                                .contentTransition(.numericText(countsDown: true))
                            Text(remaining == nil
                                 ? ATHLTHLocalization.choose(
                                     english: "OPEN STEP", norwegian: "ÅPENT DRAG")
                                 : ATHLTHLocalization.choose(
                                     english: "REMAINING", norwegian: "GJENSTÅR"))
                                .font(.system(size: 11, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(width: 252, height: 252)
                    .accessibilityElement(children: .combine)
                }

                Text(snapshot.runningStepTitle ?? "")
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let next = snapshot.runningNextStepTitle, !next.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text(ATHLTHLocalization.choose(
                            english: "Next:", norwegian: "Neste:"
                        ) + " " + next)
                            .lineLimit(2)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                }
                if let all = snapshot.runningOverallProgress, all.isFinite {
                    ProgressView(value: min(max(all, 0), 1))
                        .tint(.white)
                    Text(ATHLTHLocalization.choose(
                        english: "Full workout", norwegian: "Hele økten"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
                }
                if isPaused {
                    Label(ATHLTHLocalization.choose(
                        english: "Workout paused", norwegian: "Økten er pauset"
                    ), systemImage: "pause.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: snapshot.runningStepPhase == "recovery"
                        ? [Color(red: 0.31, green: 0.39, blue: 0.40),
                           Color(red: 0.12, green: 0.18, blue: 0.24)]
                        : [Color(red: 0.48, green: 0.34, blue: 0.20),
                           Color(red: 0.11, green: 0.10, blue: 0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 27, style: .continuous)
            )
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)),
            removal: .opacity.combined(with: .scale(scale: 1.03))
        ))
    }

    private var phaseName: String {
        switch snapshot.runningStepPhase {
        case "warmup": return ATHLTHLocalization.choose(
            english: "WARM-UP", norwegian: "OPPVARMING")
        case "recovery": return ATHLTHLocalization.choose(
            english: "RECOVERY", norwegian: "PAUSE")
        case "cooldown": return ATHLTHLocalization.choose(
            english: "COOL-DOWN", norwegian: "NEDJOGGING")
        default: return ATHLTHLocalization.choose(
            english: "INTERVAL", norwegian: "INTERVALL")
        }
    }

    private var phaseIcon: String {
        snapshot.runningStepPhase == "recovery" ? "pause.circle.fill" : "figure.run"
    }

    private func effectiveRemaining(now: Date) -> TimeInterval? {
        guard let seconds = snapshot.runningStepRemainingSeconds,
              seconds.isFinite, seconds >= 0 else { return nil }
        guard snapshot.state == .running else { return seconds }
        // Don't extrapolate stale Watch snapshots into a false zero.
        let age = max(now.timeIntervalSince(snapshot.capturedAt), 0)
        guard age <= 25 else { return seconds }
        return max(0, seconds - age)
    }
}
