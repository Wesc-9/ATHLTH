import SwiftUI
import UIKit

/// iPad's full-screen, read-only companion for an iPhone/Apple Watch workout.
/// Uses exactly the same private snapshot as the small Home return pill.
/// This view never starts/stops workouts, opens HealthKit, or controls Watch.
struct ATHLTHiPadLiveWorkoutView: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    let onMinimize: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("athlth_ipad_live_keep_awake") private var keepAwake = false
    @State private var previousIdleTimerDisabled = false
    @EnvironmentObject private var session: AppSessionStore

    private var measuredZone: Int? {
        ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: snapshot.heartRateBPM,
            maximumBPM: ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: session.onboardingProfile?.maximumHeartRateBPM,
                dateOfBirth: session.onboardingProfile?.dateOfBirth
            )
        )
    }

    private let ink = ATHLTHPlanDesign.ink
    private let secondary = ATHLTHPlanDesign.secondaryInk
    private let bronze = ATHLTHPlanDesign.accentInk
    private let surface = ATHLTHPlanDesign.surface
    private let pale = ATHLTHPlanDesign.selectedSurface

    private var isStrength: Bool { snapshot.kind == "strength" }
    private var isCardio: Bool {
        snapshot.kind == "running" || snapshot.kind == "walking" ||
        snapshot.kind == "cycling" || snapshot.kind == "rowing"
    }
    private var isWatch: Bool { snapshot.sourceDevice == "watch" }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 840

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    topBar

                    identity
                        .padding(.top, 4)

                    if wide {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 20) {
                                elapsedHero
                                metrics
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            VStack(spacing: 20) {
                                activeStepCard
                                if isStrength {
                                    strengthProgress
                                } else {
                                    workoutProgress
                                }
                                if isStrength {
                                    ATHLTHiPadLiveStrengthDetailsPanel(snapshot: snapshot)
                                } else {
                                    ATHLTHiPadLiveTimelinePanel(snapshot: snapshot)
                                }
                                ATHLTHiPadLiveGhostDuelPanel(snapshot: snapshot)
                                if isCardio && (snapshot.routeTitle != nil ||
                                    (snapshot.liveLatitude != nil &&
                                     snapshot.liveLongitude != nil)) {
                                    ATHLTHiPadLiveGPSMap(snapshot: snapshot)
                                }
                                ATHLTHiPadLiveRouteProgressPanel(snapshot: snapshot)
                                ATHLTHiPadLiveWorkoutExtrasPanel(snapshot: snapshot)
                                additionalDetails
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        elapsedHero
                        metrics
                        activeStepCard
                        if isStrength {
                            strengthProgress
                        } else {
                            workoutProgress
                        }
                        if isStrength {
                            ATHLTHiPadLiveStrengthDetailsPanel(snapshot: snapshot)
                        } else {
                            ATHLTHiPadLiveTimelinePanel(snapshot: snapshot)
                        }
                        ATHLTHiPadLiveGhostDuelPanel(snapshot: snapshot)
                        if isCardio && (snapshot.routeTitle != nil ||
                                    (snapshot.liveLatitude != nil &&
                                     snapshot.liveLongitude != nil)) {
                            ATHLTHiPadLiveGPSMap(snapshot: snapshot)
                        }
                        ATHLTHiPadLiveRouteProgressPanel(snapshot: snapshot)
                        ATHLTHiPadLiveWorkoutExtrasPanel(snapshot: snapshot)
                        additionalDetails
                    }

                    Label(
                        tr(
                            "Read-only companion. The source device stays responsible for recording.",
                            "Kun visning. Enheten som registrerer økten, har fortsatt ansvaret for opptaket."
                        ),
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, wide ? 32 : 18)
                .padding(.top, 22)
                .padding(.bottom, 36)
                .frame(maxWidth: 1370)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        }
        .accessibilityIdentifier("athlth-ipad-live-workout-fullscreen")
        .onAppear {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            if keepAwake { UIApplication.shared.isIdleTimerDisabled = true }
        }
        .onChange(of: keepAwake) { _, enabled in
            UIApplication.shared.isIdleTimerDisabled =
                enabled || previousIdleTimerDisabled
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Circle()
                    .fill(snapshot.paused == true ? Color.orange : bronze)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                Text(snapshot.paused == true
                    ? tr("PAUSED", "PAUSE")
                    : tr("LIVE WORKOUT", "TRENING PÅGÅR"))
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(bronze)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 5)) { context in
                Label(
                    ATHLTHiPadLiveMetrics.isDelayed(snapshot, at: context.date)
                        ? tr("Waiting for updates", "Venter på oppdatering")
                        : tr("Synced", "Synkronisert"),
                    systemImage: ATHLTHiPadLiveMetrics.isDelayed(
                        snapshot, at: context.date
                    ) ? "arrow.clockwise" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(secondary)
                .lineLimit(1)
            }

            Toggle(isOn: $keepAwake) {
                Label(tr("Keep screen awake", "Hold skjermen på"),
                      systemImage: "sun.max")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .tint(bronze)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("athlth-ipad-live-keep-awake")

            Button(action: onMinimize) {
                Label(tr("Minimize", "Minimer"), systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-ipad-live-minimize")
        }
        .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 17) {
            Image(systemName: snapshot.symbol)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(bronze)
                .frame(width: 66, height: 66)
                .background(pale, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.title)
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    isWatch
                        ? tr("LIVE FROM APPLE WATCH", "LIVE FRA APPLE WATCH")
                        : tr("LIVE FROM IPHONE", "LIVE FRA IPHONE"),
                    systemImage: isWatch ? "applewatch" : "iphone"
                )
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(bronze)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var elapsedHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("WORKOUT TIME", "ØKTTID"))
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(secondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(ATHLTHiPadLiveMetrics.duration(
                    ATHLTHiPadLiveMetrics.elapsed(snapshot, at: context.date)
                ))
                .font(.system(size: 76, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.60)
                .lineLimit(1)
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .linear(duration: 0.15),
                           value: Int(context.date.timeIntervalSince1970))
            }

            HStack(spacing: 10) {
                Label(
                    snapshot.paused == true
                        ? tr("Workout paused", "Økten er satt på pause")
                        : tr("Recording on source device", "Registreres på kildeenheten"),
                    systemImage: snapshot.paused == true
                        ? "pause.circle" : "record.circle"
                )
                .font(.subheadline)
                .foregroundStyle(bronze)
            }
        }
        .padding(25)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white, pale.opacity(0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(bronze.opacity(0.13), lineWidth: 1)
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 175), spacing: 13)],
            spacing: 13
        ) {
            if isStrength {
                metric(
                    tr("Completed sets", "Utførte sett"),
                    value: ATHLTHiPadLiveMetrics.sets(snapshot),
                    symbol: "checkmark.circle",
                    detail: tr("Workout progress", "Fremdrift")
                )
            } else {
                metric(
                    tr("Distance", "Distanse"),
                    value: ATHLTHiPadLiveMetrics.distance(snapshot.distanceMeters),
                    symbol: "point.topleft.down.to.point.bottomright.curvepath",
                    detail: snapshot.distanceMeters == nil
                        ? tr("Not available", "Ikke tilgjengelig") : nil
                )
            }

            if isCardio {
                metric(
                    tr("Current pace", "Nåværende tempo"),
                    value: ATHLTHiPadLiveMetrics.pace(
                        snapshot.currentPaceSecondsPerKilometer
                    ),
                    symbol: "speedometer",
                    detail: snapshot.paceIsTreadmillTarget == true
                        ? tr("Belt speed", "Møllehastighet") :
                        tr("min/km", "min/km")
                )
            }

            metric(
                tr("Heart rate", "Puls"),
                value: ATHLTHiPadLiveMetrics.heartRate(snapshot.heartRateBPM),
                symbol: "heart",
                detail: snapshot.heartRateBPM == nil
                    ? tr("Awaiting sensor data", "Ingen pulsdata fra kilden")
                    : tr("bpm", "slag/min")
            )

            if isCardio {
                if let zone = measuredZone {
                    metric(
                        tr("Heart rate zone now", "Pulssone nå"),
                        value: tr("Zone", "Sone") + " \(zone)",
                        symbol: "heart.text.square",
                        detail: tr("From measured pulse", "Fra målt puls")
                    )
                } else if let target = snapshot.targetHeartRateZone,
                          (1...5).contains(target) {
                    metric(
                        tr("Target heart rate zone", "Målpulssone"),
                        value: tr("Zone", "Sone") + " \(target)",
                        symbol: "heart.text.square",
                        detail: tr("Planned, not measured", "Planlagt, ikke målt")
                    )
                } else {
                    metric(
                        tr("Heart rate zone", "Pulssone"),
                        value: "—",
                        symbol: "heart.text.square",
                        detail: tr("Awaiting pulse and HRmax",
                                   "Venter på puls og makspuls")
                    )
                }
                metric(
                    tr("Average pace", "Snittempo"),
                    value: ATHLTHiPadLiveMetrics.averagePace(snapshot),
                    symbol: "chart.line.uptrend.xyaxis",
                    detail: tr("Based on distance and active time",
                               "Beregnet fra distanse og aktiv tid")
                )
            } else {
                metric(
                    tr("Active calories", "Aktive kalorier"),
                    value: ATHLTHiPadLiveMetrics.calories(snapshot.activeCalories),
                    symbol: "flame",
                    detail: snapshot.activeCalories == nil
                        ? tr("No source data", "Ingen måling fra kilden") : "kcal"
                )
            }
        }
    }

    private func metric(
        _ label: String,
        value: String,
        symbol: String,
        detail: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(bronze)
                    .accessibilityHidden(true)
                Spacer()
            }
            Text(value)
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 153, alignment: .topLeading)
        .background(surface, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(bronze.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var activeStepCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(
                    isStrength ? tr("CURRENT EXERCISE", "AKTIV ØVELSE")
                               : tr("CURRENT PHASE", "AKTIV DELØKT"),
                    systemImage: isStrength ? "dumbbell" : "square.stack.3d.up"
                )
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(bronze)

                Spacer()

                if let ordinal = snapshot.runningIntervalOrdinal,
                   let count = snapshot.runningIntervalTotal,
                   count > 1 {
                    Text(tr("Interval", "Drag") + " \(ordinal) / \(count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(bronze)
                        .monospacedDigit()
                }
            }

            Text(snapshot.currentStep ??
                (isStrength
                    ? tr("Preparing next exercise", "Forbereder neste øvelse")
                    : tr("Free workout", "Fri trening")))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)

            if let seconds = snapshot.runningStepRemainingSeconds,
               seconds.isFinite, seconds >= 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = ATHLTHiPadLiveMetrics.remaining(
                        snapshot, at: context.date
                    ) ?? seconds

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.runningInRecovery == true
                            ? tr("NEXT EFFORT IN", "NESTE DRAG OM")
                            : tr("TIME REMAINING", "GJENSTÅENDE TID"))
                            .font(.caption.weight(.medium))
                            .tracking(1)
                            .foregroundStyle(secondary)
                        Text(ATHLTHiPadLiveMetrics.duration(remaining))
                            .font(.system(size: 49, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                }
            }

            if snapshot.runningStepRemainingSeconds == nil,
               let remaining = snapshot.runningStepRemainingMeters,
               remaining.isFinite, remaining >= 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("DISTANCE REMAINING", "GJENSTÅENDE DISTANSE"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondary)
                    Text(String(format: "%.0f m", remaining))
                        .font(.system(size: 43, weight: .bold,
                                      design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                }
            }

            if let progress = ATHLTHiPadLiveMetrics.normalized(
                snapshot.runningStepProgress
            ) {
                ProgressView(value: progress)
                    .tint(bronze)
                    .accessibilityLabel(tr("Phase progress", "Deløktens fremdrift"))
            }

            if let next = snapshot.nextStep, !next.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(bronze)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("UP NEXT", "NESTE"))
                            .font(.caption2.weight(.semibold))
                            .tracking(1)
                            .foregroundStyle(secondary)
                        Text(next)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(pale.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 25))
    }

    @ViewBuilder
    private var strengthProgress: some View {
        if let total = snapshot.totalSets, total > 0 {
            VStack(alignment: .leading, spacing: 13) {
                Text(tr("STRENGTH PROGRESS", "STYRKEFREMDRIFT"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)
                HStack {
                    Text(ATHLTHiPadLiveMetrics.sets(snapshot))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(tr("sets completed", "sett fullført"))
                        .font(.subheadline)
                        .foregroundStyle(secondary)
                }
                ProgressView(
                    value: min(1, Double(max(0, snapshot.completedSets ?? 0)) /
                        Double(total))
                )
                .tint(bronze)
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        }
    }

    @ViewBuilder
    private var workoutProgress: some View {
        if let progress = ATHLTHiPadLiveMetrics.normalized(
            snapshot.runningOverallProgress
        ) {
            VStack(alignment: .leading, spacing: 13) {
                Text(tr("WORKOUT PROGRESS", "ØKTENS FREMDRIFT"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)
                HStack {
                    Text("\(Int((progress * 100).rounded())) %")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(tr("planned structure", "planlagt struktur"))
                        .font(.caption)
                        .foregroundStyle(secondary)
                }
                ProgressView(value: progress)
                    .tint(bronze)
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        } else if let interval = snapshot.runningIntervalOrdinal,
                  let total = snapshot.runningIntervalTotal, total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("INTERVALS", "INTERVALLER"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)
                Text("\(interval) / \(total)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                ProgressView(value: min(1, max(0, Double(interval) / Double(total))))
                    .tint(bronze)
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        }
    }

    @ViewBuilder
    private var additionalDetails: some View {
        let hasTargets = snapshot.targetPaceSecondsPerKilometer != nil ||
            snapshot.targetHeartRateZone != nil
        if hasTargets {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("WORKOUT DETAILS", "ØKTDETALJER"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)

                if let pace = snapshot.targetPaceSecondsPerKilometer,
                   pace.isFinite, pace > 0 {
                    detailLine(
                        tr("Target pace", "Måltempo"),
                        value: ATHLTHiPadLiveMetrics.pace(pace),
                        symbol: "scope"
                    )
                }
                if let zone = snapshot.targetHeartRateZone, (1...5).contains(zone) {
                    detailLine(
                        tr("Target zone", "Målsone"),
                        value: tr("Zone", "Sone") + " \(zone)",
                        symbol: "heart.text.square"
                    )
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        }
    }

    private func detailLine(
        _ label: String, value: String, symbol: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(bronze)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Pure presentation calculations can be tested without creating HealthKit
/// or remote workout sessions and never invent absent sensor measurements.
enum ATHLTHiPadLiveMetrics {
    static func elapsed(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot, at now: Date
    ) -> TimeInterval {
        let extra = snapshot.paused == true ? 0 :
            min(8, max(0, now.timeIntervalSince(snapshot.capturedAt ?? now)))
        return max(0, snapshot.elapsedSeconds + extra)
    }

    static func remaining(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot, at now: Date
    ) -> TimeInterval? {
        guard let remaining = snapshot.runningStepRemainingSeconds,
              remaining.isFinite, remaining >= 0 else { return nil }
        let extra = snapshot.paused == true ? 0 :
            min(8, max(0, now.timeIntervalSince(snapshot.capturedAt ?? now)))
        return max(0, remaining - extra)
    }

    static func isDelayed(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot, at now: Date
    ) -> Bool {
        guard let captured = snapshot.capturedAt else { return true }
        return now.timeIntervalSince(captured) > 14
    }

    static func normalized(_ progress: Double?) -> Double? {
        guard let progress, progress.isFinite, (0...1).contains(progress)
        else { return nil }
        return progress
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let sec = total % 60
        let min = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, min, sec) }
        return String(format: "%02d:%02d", total / 60, sec)
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "—" }
        return String(format: "%.2f km", meters / 1_000)
    }

    static func pace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite,
              (120...1800).contains(secondsPerKm)
        else { return "—" }
        let value = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func averagePace(_ snapshot: ATHLTHCrossDeviceWorkoutSnapshot) -> String {
        guard let meters = snapshot.distanceMeters,
              meters.isFinite, meters >= 40,
              snapshot.elapsedSeconds >= 20 else { return "—" }
        return pace(snapshot.elapsedSeconds / (meters / 1_000))
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm.isFinite, (35...240).contains(bpm) else { return "—" }
        return String(Int(bpm.rounded()))
    }

    static func calories(_ calories: Double?) -> String {
        guard let calories, calories.isFinite, calories > 0 else { return "—" }
        return "\(Int(calories.rounded()))"
    }

    static func sets(_ snapshot: ATHLTHCrossDeviceWorkoutSnapshot) -> String {
        guard let done = snapshot.completedSets else { return "—" }
        if let total = snapshot.totalSets, total > 0 {
            return "\(min(max(0, done), total)) / \(total)"
        }
        return "\(max(0, done))"
    }
}
