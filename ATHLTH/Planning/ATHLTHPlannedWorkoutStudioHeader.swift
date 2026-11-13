import SwiftUI

/// Train-style workout identity and editable schedule in one compact surface.
/// The timeline remains the source of truth for duration and intensity.
struct ATHLTHPlannedWorkoutStudioHeader: View {
    @Environment(\.locale) private var locale
    @Binding var workoutName: String
    let activity: ATHLTHPlannedWorkoutType?
    let blocks: [WorkoutTemplateBlock]
    let durationMinutes: Int?
    let route: TrainingRoute?
    let scheduledAt: Binding<Date>?
    /// Only supplied for running workouts. Other activities never expose
    /// the running environment selector.
    let runningEnvironment: Binding<RunEnvironment>?

    init(
        workoutName: Binding<String>,
        activity: ATHLTHPlannedWorkoutType?,
        blocks: [WorkoutTemplateBlock],
        durationMinutes: Int?,
        route: TrainingRoute?,
        scheduledAt: Binding<Date>?,
        runningEnvironment: Binding<RunEnvironment>? = nil
    ) {
        _workoutName = workoutName
        self.activity = activity
        self.blocks = blocks
        self.durationMinutes = durationMinutes
        self.route = route
        self.scheduledAt = scheduledAt
        self.runningEnvironment = runningEnvironment
    }

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private var plannedDurationText: String {
        if let seconds = ATHLTHWorkoutDurationEstimator.previewSeconds(
            for: blocks, defaultActivity: activity == .walking ? .walking : .running
        ) {
            return "~ " + ATHLTHWorkoutDurationEstimator.conciseDuration(seconds)
        }
        return durationMinutes.map { "~ \($0) min" } ?? "–"
    }

    private var distanceText: String {
        guard let kilometers = ATHLTHPlannedWorkoutMetrics.estimatedDistanceKilometers(
            for: blocks
        ) else { return "–" }
        return "~ " + kilometers.formatted(
            .number.precision(.fractionLength(1)).locale(locale)
        ) + " km"
    }

    private var runningLocation: ATHLTHPlannedWorkoutMetrics.RunningLocation? {
        ATHLTHPlannedWorkoutMetrics.runningLocation(for: blocks)
    }

    private var commonPace: Double? {
        ATHLTHPlannedWorkoutMetrics.commonPaceSecondsPerKilometer(for: blocks)
    }

    private var paceText: String {
        guard let commonPace else { return "–" }
        let rounded = Int(commonPace.rounded())
        let seconds = rounded % 60
        return "\(rounded / 60):" + (seconds < 10 ? "0" : "") + "\(seconds)"
    }

    private var treadmillSpeedText: String? {
        guard let commonPace else { return nil }
        let value = 3_600 / commonPace
        return value.formatted(
            .number.precision(.fractionLength(1)).locale(locale)
        ) + (ATHLTHLocalization.isNorwegian ? " km/t" : " km/h")
    }

    private var runningLocationText: String? {
        guard let runningLocation else { return nil }
        switch runningLocation {
        case .outdoor:
            return ATHLTHLocalization.choose(english: "Outdoor", norwegian: "Ute")
        case .indoor:
            return ATHLTHLocalization.choose(english: "Indoor", norwegian: "Innendørs")
        case .treadmill:
            return ATHLTHLocalization.choose(english: "Treadmill", norwegian: "Tredemølle")
        case .mixed:
            return ATHLTHLocalization.choose(
                english: "Indoor + outdoor", norwegian: "Ute + inne"
            )
        }
    }

    private var runningLocationSymbol: String {
        switch runningLocation {
        case .treadmill: return "figure.run.treadmill"
        case .indoor: return "building.2"
        case .outdoor: return "figure.run"
        case .mixed, .none: return "figure.mixed.cardio"
        }
    }

    private var zoneText: String {
        let zones = blocks.compactMap(\.targetHeartRateZone)
        guard let lowest = zones.min(), let highest = zones.max() else { return "–" }
        let letter = ATHLTHLocalization.isNorwegian ? "S" : "Z"
        return lowest == highest ? "\(letter)\(lowest)" :
            "\(letter)\(lowest)–\(letter)\(highest)"
    }

    private var inclineText: String {
        guard let range = ATHLTHPlannedWorkoutMetrics.treadmillInclineRange(
            for: blocks
        ) else { return "–" }
        func format(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        }
        if range.upperBound - range.lowerBound < 0.01 {
            return format(range.lowerBound) + " %"
        }
        return format(range.lowerBound) + "–" + format(range.upperBound) + " %"
    }

    var body: some View {
        // Planlegg økt and Quick Run now render the same shared
        // workout-details card. The planned date is editable, whereas
        // Quick Run continues to show a read-only start-now timestamp.
        ATHLTHWorkoutDetailsCard(
            activityTitle: activity?.title ?? ATHLTHLocalization.choose(
                english: "Your workout", norwegian: "Din økt"
            ),
            symbol: activity?.symbol ?? "figure.run",
            name: $workoutName,
            scheduledAt: scheduledAt,
            namePlaceholder: ATHLTHWorkoutNameSuggestion.suggested(
                activity: activity,
                blocks: blocks,
                durationMinutes: durationMinutes,
                routeTitle: route?.title
            ),
            showsTimingLabel: scheduledAt != nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let runningLocationText {
                    HStack(spacing: 6) {
                        Image(systemName: runningLocationSymbol)
                            .accessibilityHidden(true)
                        Text(runningLocationText)
                        if let treadmillSpeedText {
                            Text("·")
                            Text(treadmillSpeedText)
                            Text("·")
                            Text(paceText + " min/km")
                        } else if ATHLTHPlannedWorkoutMetrics.hasVariablePace(
                            for: blocks
                        ) {
                            Text("·")
                            Text(ATHLTHLocalization.choose(
                                english: "Variable pace", norwegian: "Varierende tempo"
                            ))
                        } else if runningLocation == .outdoor && route != nil {
                            Text("·")
                            Text(ATHLTHLocalization.choose(
                                english: "Route", norwegian: "Rute"
                            ))
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(bronze)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityElement(children: .combine)
                }

                HStack(spacing: 0) {
                    metric("clock", ATHLTHLocalization.choose(
                        english: "Duration", norwegian: "Varighet"
                    ), plannedDurationText)
                    metric("point.topleft.down.to.point.bottomright.curvepath",
                           ATHLTHLocalization.choose(
                               english: "Distance", norwegian: "Distanse"
                           ), distanceText)
                    metric("heart", ATHLTHLocalization.choose(
                        english: "Zone", norwegian: "Sone"
                    ), zoneText)
                    if runningLocation == .treadmill || blocks.contains(where: {
                        $0.kind == .run && $0.treadmillInclinePercent != nil
                    }) {
                        metric("mountain.2", ATHLTHLocalization.choose(
                            english: "Incline", norwegian: "Stigning"
                        ), inclineText)
                    } else if runningLocation != nil {
                        metric("speedometer", ATHLTHLocalization.choose(
                            english: "Pace (min/km)", norwegian: "Tempo (min/km)"
                        ), paceText)
                    } else {
                        metric("mountain.2", ATHLTHLocalization.choose(
                            english: "Incline", norwegian: "Stigning"
                        ), inclineText)
                    }
                }

                if activity == .running, let runningEnvironment {
                    ATHLTHRunEnvironmentDetailRow(environment: runningEnvironment)
                }

                if let scheduledAt {
                    HStack(spacing: 8) {
                        DatePicker(
                            ATHLTHLocalization.choose(
                                english: "Date", norwegian: "Dato"
                            ),
                            selection: scheduledAt,
                            displayedComponents: .date
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        DatePicker(
                            ATHLTHLocalization.choose(
                                english: "Time", norwegian: "Tid"
                            ),
                            selection: scheduledAt,
                            displayedComponents: .hourAndMinute
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(ink)
                }
            }
        }
        .accessibilityIdentifier("athlth-planned-shared-workout-details")
    }

    private func metric(
        _ symbol: String, _ title: String, _ value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(bronze)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
