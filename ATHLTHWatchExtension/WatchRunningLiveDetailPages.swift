import SwiftUI

/// A dedicated heart-rate screen for the active run/walk pager.
/// Reads HealthKit-derived data from the existing WatchWorkoutManager.
struct WatchRunHeartRateDetailPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @ScaledMetric(relativeTo: .largeTitle) private var pulseSize: CGFloat = 48

    private var spokenNorwegian: Bool {
        ATHLTHLocalization.choose(english: "en", norwegian: "no") == "no"
    }

    private var target: WatchWorkoutTargetAlertConfiguration? {
        workout.targetAlertConfiguration?.heartRateEnabled == true
            ? workout.targetAlertConfiguration : nil
    }

    private var liveZone: Int? {
        ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: workout.hasFreshHeartRate ? workout.heartRate : nil,
            maximumBPM: workout.liveZoneMaximumHeartRateBPM
        )
    }

    private var targetBand: ClosedRange<Int>? {
        guard let target,
              let lower = target.heartRateMinimumBPM,
              let upper = target.heartRateMaximumBPM,
              lower.isFinite, upper.isFinite,
              lower <= upper
        else { return nil }
        return Int(lower.rounded())...Int(upper.rounded())
    }

    private var highlightedZones: Set<Int> {
        ATHLTHHeartRateZones.matchingZones(
            for: targetBand,
            maximumBPM: workout.liveZoneMaximumHeartRateBPM
        )
    }

    private var fiveZoneGuide: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "YOUR ZONE", norwegian: "DIN SONE"
                ))
                .font(.system(size: 10, weight: .bold))
                Spacer()
                Text(liveZone.map { "Z\($0)" } ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { zone in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(highlightedZones.contains(zone)
                                  ? WatchTheme.premiumGold
                                  : WatchTheme.planSelected)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(liveZone == zone
                                            ? WatchTheme.textPrimary : .clear,
                                            lineWidth: 2)
                            }
                            .frame(height: 12)
                        Text("Z\(zone)")
                            .font(.system(size: 9,
                                          weight: liveZone == zone ? .heavy : .medium))
                            .foregroundStyle(liveZone == zone
                                             ? WatchTheme.textPrimary
                                             : WatchTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let max = workout.liveZoneMaximumHeartRateBPM {
                Text(ATHLTHLocalization.choose(
                    english: "Based on HRmax", norwegian: "Fra makspuls"
                ) + " \(Int(max.rounded())) bpm")
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.textSecondary)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "Set HRmax in your profile for the Z1–Z5 pointer.",
                    norwegian: "Sett makspuls i profilen for Z1–Z5-markøren."
                ))
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .padding(10)
        .watchSurface(radius: 17)
        .accessibilityIdentifier("athlth-watch-five-zone-live-pulse")
    }

    /// One Watch screen; never intercept the pager's vertical swipe.
    var body: some View {
        GeometryReader { viewport in
            let compact = viewport.size.height < 205
            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                Label(ATHLTHLocalization.choose(
                    english: "HEART RATE", norwegian: "PULS"
                ), systemImage: "heart.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WatchTheme.liveHeart)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(bpm(workout.hasFreshHeartRate ? workout.heartRate : nil))
                        .font(.system(size: compact ? 40 : 49,
                                      weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("bpm").font(.system(size: 10, weight: .bold))
                    Spacer(minLength: 0)
                    Text(liveZone.map { "Z\($0)" } ?? "—")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchTheme.premiumGold)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Current heart rate", norwegian: "Nåværende puls"
                ))
                .accessibilityValue(ATHLTHWorkoutAccessibleMetric.pulse(
                    workout.heartRate,
                    isFresh: workout.hasFreshHeartRate,
                    norwegian: spokenNorwegian
                ))
                .accessibilityIdentifier("athlth-watch-five-zone-live-pulse")

                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { zone in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(highlightedZones.contains(zone)
                                      ? WatchTheme.premiumGold
                                      : WatchTheme.planSelected)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(liveZone == zone
                                                ? WatchTheme.textPrimary : .clear,
                                                lineWidth: 2)
                                }
                                .frame(height: compact ? 10 : 13)
                            Text("Z\(zone)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WatchTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ATHLTHLocalization.choose(
                            english: "AVERAGE", norwegian: "SNITT"
                        )).font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WatchTheme.muted)
                        Text(bpm(workout.averageHeartRate))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ATHLTHLocalization.choose(
                            english: "MAX", norwegian: "MAKS"
                        )).font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WatchTheme.muted)
                        Text(bpm(workout.maxHeartRate))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                    }
                }

                if let targetBand {
                    Label("\(targetBand.lowerBound)–\(targetBand.upperBound) bpm",
                          systemImage: "target")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WatchTheme.premiumGold)
                        .lineLimit(1)
                } else if !workout.hasFreshHeartRate {
                    Text(ATHLTHLocalization.choose(
                        english: "Waiting for sensor", norwegian: "Venter på sensor"
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 2 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .topLeading)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private func readout(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.textSecondary)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text("bpm")
                .font(.system(size: 9))
                .foregroundStyle(WatchTheme.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 16)
    }

    private func guidanceText(_ status: ATHLTHRunPulseTargetStatus)
        -> String {
        switch status {
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "Target not configured",
                norwegian: "Pulsmål ikke konfigurert"
            )
        case .waiting:
            return ATHLTHLocalization.choose(
                english: "Waiting for heart rate",
                norwegian: "Venter på puls"
            )
        case .below:
            return ATHLTHLocalization.choose(
                english: "Below target zone",
                norwegian: "Under målsonen"
            )
        case .within:
            return ATHLTHLocalization.choose(
                english: "Within target zone",
                norwegian: "Innenfor målsonen"
            )
        case .above:
            return ATHLTHLocalization.choose(
                english: "Above target zone",
                norwegian: "Over målsonen"
            )
        }
    }

    private func bpm(_ value: Double?) -> String {
        guard let value, value.isFinite && value > 0 else { return "—" }
        return String(Int(value.rounded()))
    }
}

/// Audio Coach is reachable as a first-class active-running page, instead
/// of requiring the user to find its controls inside the stop/pause screen.
struct WatchRunAudioCoachDetailPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    /// Live audio controls remain on one page. Vertical swipe belongs to
    /// the parent TabView, never an inner ScrollView.
    var body: some View {
        GeometryReader { viewport in
            let compact = viewport.size.height < 205
            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                Label("AUDIO COACH", systemImage: "waveform")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(WatchTheme.accentDeep)
                HStack(spacing: 8) {
                    Image(systemName: workout.audioCoachConfiguration.enabled
                          ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(WatchTheme.liveAction)
                    Text(workout.audioCoachConfiguration.enabled
                        ? ATHLTHLocalization.choose(
                            english: "Coach active", norwegian: "Coach aktiv")
                        : ATHLTHLocalization.choose(
                            english: "Coach off", norwegian: "Coach av"))
                        .font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 0)
                }

                Button {
                    workout.setAudioCoachEnabled(
                        !workout.audioCoachConfiguration.enabled
                    )
                } label: {
                    Text(workout.audioCoachConfiguration.enabled
                        ? ATHLTHLocalization.choose(
                            english: "Turn coach off", norwegian: "Slå av coach")
                        : ATHLTHLocalization.choose(
                            english: "Turn coach on", norwegian: "Slå på coach"))
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity,
                           minHeight: compact ? 31 : 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.liveAction)

                if workout.audioCoachConfiguration.enabled {
                    HStack(spacing: 7) {
                        Button {
                            workout.setCoachSpeechPaused(
                                !workout.coachSpeechPaused
                            )
                        } label: {
                            Label(workout.coachSpeechPaused
                                ? ATHLTHLocalization.choose(
                                    english: "Voice on", norwegian: "Tale på")
                                : ATHLTHLocalization.choose(
                                    english: "Voice off", norwegian: "Tale av"),
                                  systemImage: workout.coachSpeechPaused
                                    ? "play.fill" : "pause.fill")
                            .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            workout.announceCoachStatusNow()
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Status", norwegian: "Status"
                            ), systemImage: "waveform")
                            .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(workout.coachSpeechPaused)
                    }
                    if let message = workout.lastCoachMessage,
                       !message.isEmpty {
                        HStack(spacing: 6) {
                            Text(message)
                                .font(.system(size: 10))
                                .foregroundStyle(WatchTheme.muted)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Button {
                                workout.replayLastCoachMessage()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .disabled(!workout.canReplayLastCoachMessage)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 2 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .topLeading)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
    }
}
