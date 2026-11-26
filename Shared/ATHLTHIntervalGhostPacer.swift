import Foundation

/// Independent of GPS route Ghost Race: the target runner is restarted at the
/// beginning of every work repetition. Recovery/warmup/cooldown contribute
/// neither elapsed seconds nor meters and never change the comparison.
enum ATHLTHIntervalGhostPacer {

    /// A segment-aware virtual pacer. Callers provide one completed segment
    /// at a time, so the same calculation works for iPhone and Apple Watch.
    /// Work and recovery remain separate: resting never consumes work pace.
    enum SegmentKind {
        case warmup
        case work
        case passiveRecovery
        case activeRecovery
        case cooldown
    }

    enum RecoveryPolicy {
        case freeze
        case followActualDistance
        case targetPace(secondsPerKilometer: Double)
    }

    enum Scope {
        case wholeWorkout
        case mainOnly
    }

    struct VirtualProgress {
        var ghostMeters: Double = 0
        var runnerMeters: Double = 0

        var leadMeters: Double { runnerMeters - ghostMeters }
    }

    /// Persisted per-workout Ghost preferences. Stable raw values allow the
    /// same settings to travel with a planned workout to Apple Watch.
    struct WorkoutConfiguration: Codable, Hashable {
        enum Coverage: String, Codable {
            case entireWorkout
            case mainOnly
            case selectedSegments
        }

        enum PauseBehavior: String, Codable {
            case freeze
            case followActualDistance
            case customPace
        }

        struct SegmentSetting: Codable, Hashable, Identifiable {
            var id: UUID
            var enabled: Bool
            var paceSecondsPerKilometer: Double?
        }

        var isEnabled: Bool = false
        var defaultPaceSecondsPerKilometer: Double = 300
        var coverage: Coverage = .mainOnly
        var pauseBehavior: PauseBehavior = .freeze
        var recoveryPaceSecondsPerKilometer: Double? = nil
        var segments: [SegmentSetting] = []

        var isValid: Bool {
            guard defaultPaceSecondsPerKilometer.isFinite,
                  (30...3_600).contains(defaultPaceSecondsPerKilometer),
                  segments.count <= 500,
                  Set(segments.map(\.id)).count == segments.count
            else { return false }
            if pauseBehavior == .customPace {
                guard let recoveryPaceSecondsPerKilometer,
                      recoveryPaceSecondsPerKilometer.isFinite,
                      (30...3_600).contains(recoveryPaceSecondsPerKilometer)
                else { return false }
            }
            return segments.allSatisfy { segment in
                guard let pace = segment.paceSecondsPerKilometer else { return true }
                return pace.isFinite && (30...3_600).contains(pace)
            }
        }

        var scope: Scope {
            coverage == .entireWorkout ? .wholeWorkout : .mainOnly
        }

        var recoveryPolicy: RecoveryPolicy {
            switch pauseBehavior {
            case .freeze: return .freeze
            case .followActualDistance: return .followActualDistance
            case .customPace:
                return .targetPace(secondsPerKilometer:
                    recoveryPaceSecondsPerKilometer ?? defaultPaceSecondsPerKilometer)
            }
        }

        func progress(
            from previous: VirtualProgress,
            segmentID: UUID,
            kind: SegmentKind,
            elapsedSeconds: TimeInterval,
            actualMeters: Double
        ) -> VirtualProgress? {
            guard isEnabled, isValid else { return nil }
            if coverage == .selectedSegments &&
                !segments.contains(where: { $0.id == segmentID && $0.enabled }) {
                return previous
            }
            return advanceSegment(
                previous, segmentID: segmentID, kind: kind,
                scope: coverage == .selectedSegments ? .wholeWorkout : scope,
                elapsedSeconds: elapsedSeconds,
                actualMeters: actualMeters,
                defaultPaceSecondsPerKilometer: defaultPaceSecondsPerKilometer,
                recovery: recoveryPolicy,
                overrides: segments.map {
                    SegmentOverride(segmentID: $0.id, enabled: $0.enabled,
                                    paceSecondsPerKilometer: $0.paceSecondsPerKilometer)
                }
            )
        }
    }

    /// Live samples can arrive as cumulative totals, including after a pause
    /// or Watch reconnect. Convert to non-negative deltas exactly once,
    /// preventing a repeated sample from advancing Ghost twice.
    struct LiveSample: Equatable {
        var elapsedSeconds: TimeInterval
        var distanceMeters: Double
    }

    static func advanceLiveSample(
        configuration: WorkoutConfiguration,
        progress: VirtualProgress,
        previous: LiveSample,
        current: LiveSample,
        segmentID: UUID,
        kind: SegmentKind
    ) -> VirtualProgress? {
        guard previous.elapsedSeconds.isFinite,
              current.elapsedSeconds.isFinite,
              previous.distanceMeters.isFinite,
              current.distanceMeters.isFinite,
              previous.elapsedSeconds >= 0,
              previous.distanceMeters >= 0,
              current.elapsedSeconds >= previous.elapsedSeconds,
              current.distanceMeters >= previous.distanceMeters
        else { return nil }
        return configuration.progress(
            from: progress,
            segmentID: segmentID,
            kind: kind,
            elapsedSeconds: current.elapsedSeconds - previous.elapsedSeconds,
            actualMeters: current.distanceMeters - previous.distanceMeters
        )
    }

    /// Stable segment identifiers allow a workout editor to target a single
    /// interval without changing other work or recovery segments.
    struct SegmentOverride {
        let segmentID: UUID
        let enabled: Bool
        let paceSecondsPerKilometer: Double?
    }

    /// Per-segment overrides take precedence over the global Ghost pace.
    /// A disabled segment is excluded from both virtual timelines.
    static func advanceSegment(
        _ progress: VirtualProgress,
        segmentID: UUID,
        kind: SegmentKind,
        scope: Scope,
        elapsedSeconds: TimeInterval,
        actualMeters: Double,
        defaultPaceSecondsPerKilometer: Double,
        recovery: RecoveryPolicy,
        overrides: [SegmentOverride]
    ) -> VirtualProgress? {
        let override = overrides.first { $0.segmentID == segmentID }
        if override?.enabled == false { return progress }
        return advance(
            progress,
            kind: kind,
            scope: scope,
            elapsedSeconds: elapsedSeconds,
            actualMeters: actualMeters,
            workPaceSecondsPerKilometer:
                override?.paceSecondsPerKilometer ?? defaultPaceSecondsPerKilometer,
            recovery: recovery
        )
    }

    /// Returns nil rather than propagating NaN, negative elapsed time, or
    /// invalid pace into the live Ghost comparison.
    static func advance(
        _ progress: VirtualProgress,
        kind: SegmentKind,
        scope: Scope,
        elapsedSeconds: TimeInterval,
        actualMeters: Double,
        workPaceSecondsPerKilometer: Double,
        recovery: RecoveryPolicy
    ) -> VirtualProgress? {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0,
              actualMeters.isFinite, actualMeters >= 0,
              progress.ghostMeters.isFinite, progress.runnerMeters.isFinite,
              workPaceSecondsPerKilometer.isFinite,
              workPaceSecondsPerKilometer > 0
        else { return nil }

        let included: Bool
        switch scope {
        case .wholeWorkout: included = true
        case .mainOnly:
            included = kind == .work || kind == .activeRecovery ||
                kind == .passiveRecovery
        }
        guard included else { return progress }

        var next = progress
        switch kind {
        case .work, .warmup, .cooldown:
            next.ghostMeters += elapsedSeconds / workPaceSecondsPerKilometer * 1_000
            next.runnerMeters += actualMeters
        case .passiveRecovery:
            // Pause is excluded from both virtual timelines.
            break
        case .activeRecovery:
            switch recovery {
            case .freeze:
                break
            case .followActualDistance:
                next.ghostMeters += actualMeters
                next.runnerMeters += actualMeters
            case .targetPace(let secondsPerKilometer):
                guard secondsPerKilometer.isFinite,
                      secondsPerKilometer > 0 else { return nil }
                next.ghostMeters += elapsedSeconds / secondsPerKilometer * 1_000
                next.runnerMeters += actualMeters
            }
        }
        return next
    }

    static func leadMeters(
        step: WatchRunningWorkoutStep,
        elapsedSeconds: TimeInterval,
        distanceMeters: Double
    ) -> Double? {
        guard step.phase == "work",
              let secondsPerKilometer = step.ghostPaceSecondsPerKilometer,
              secondsPerKilometer.isFinite, secondsPerKilometer > 0,
              elapsedSeconds.isFinite, elapsedSeconds >= 0,
              distanceMeters.isFinite, distanceMeters >= 0
        else { return nil }
        let expectedMeters = elapsedSeconds / secondsPerKilometer * 1_000
        return distanceMeters - expectedMeters
    }

    /// Recovery does not advance the virtual target at work pace. With
    /// follow enabled Ghost matches actual recovery progress, not a target
    /// distance. Threshold prevents misclassifying brief pace sensor spikes.
    static func followsRecovery(
        step: WatchRunningWorkoutStep,
        observedPaceSecondsPerKilometer: Double?
    ) -> Bool {
        guard step.phase == "recovery",
              step.ghostFollowsRecovery == true,
              let workPace = step.ghostPaceSecondsPerKilometer,
              workPace.isFinite, workPace > 0,
              let observedPaceSecondsPerKilometer,
              observedPaceSecondsPerKilometer.isFinite,
              observedPaceSecondsPerKilometer > 0 else { return false }
        let slowdown = Double(
            min(max(step.ghostRecoverySlowdownPercent ?? 25, 10), 60)
        ) / 100
        return observedPaceSecondsPerKilometer >= workPace / (1 - slowdown)
    }

    static func isGhostEnabled(_ step: WatchRunningWorkoutStep) -> Bool {
        (step.phase == "work" ||
         (step.phase == "recovery" && step.ghostFollowsRecovery == true)) &&
            (step.ghostPaceSecondsPerKilometer ?? 0) > 0
    }
}


/// Shared constant-pace comparison; seconds are an equivalent time gap at
/// the ghost's speed, not a prediction of future finish time.
enum ATHLTHSoloGhostComparison {
    enum Outcome: String, Codable, Hashable { case ahead, behind, tied, incomplete }
    struct Result: Codable, Hashable {
        let leadMeters: Double
        let timeGapSeconds: Double
        let outcome: Outcome
    }

    /// Use the recorded race phase rather than the enclosing workout,
    /// which can include additional running after a completed goal.
    static func result(elapsed: Double, meters: Double, pace: Double,
                       targetMeters: Double?, targetSeconds: Double?) -> Result? {
        guard let lead = lead(elapsed: elapsed, meters: meters, pace: pace),
              let gap = timeGap(leadMeters: lead, pace: pace),
              targetMeters == nil || targetSeconds == nil else { return nil }
        if let targetMeters, !targetMeters.isFinite || targetMeters <= 0 { return nil }
        if let targetSeconds, !targetSeconds.isFinite || targetSeconds <= 0 { return nil }
        let incomplete = targetMeters.map { meters < $0 } ?? targetSeconds.map { elapsed < $0 } ?? false
        // For a distance race compare against ghost's target finish time,
        // not the distance overshoot recorded on the last GPS sample.
        let finishGap: Double
        if !incomplete, let targetMeters {
            finishGap = targetMeters * pace / 1_000 - elapsed
        } else {
            finishGap = gap
        }
        guard finishGap.isFinite else { return nil }
        let outcome: Outcome = incomplete ? .incomplete
            : abs(finishGap) < 0.5 ? .tied : finishGap > 0 ? .ahead : .behind
        return Result(leadMeters: lead, timeGapSeconds: finishGap, outcome: outcome)
    }

    static func timeGap(leadMeters: Double, pace: Double) -> Double? {
        guard leadMeters.isFinite, pace.isFinite, (120...1_800).contains(pace) else { return nil }
        let gap = leadMeters * pace / 1_000
        return gap.isFinite ? gap : nil
    }

    static func lead(elapsed: Double, meters: Double, pace: Double) -> Double? {
        guard elapsed.isFinite, meters.isFinite, elapsed >= 0, meters >= 0,
              pace.isFinite, (120...1_800).contains(pace) else { return nil }
        let result = meters - elapsed * 1_000 / pace
        return result.isFinite ? result : nil
    }
}
