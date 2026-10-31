import SwiftUI

/// Train-style workout identity and editable schedule in one compact surface.
/// The timeline remains the source of truth for duration and intensity.
struct ATHLTHPlannedWorkoutStudioHeader: View {
    @Binding var workoutName: String
    let activity: ATHLTHPlannedWorkoutType?
    let blocks: [WorkoutTemplateBlock]
    let durationMinutes: Int?
    let route: TrainingRoute?
    let plannedDate: Date?
    let onDateChanged: ((Date) -> Void)?

    @State private var selectedDate: Date

    init(
        workoutName: Binding<String>,
        activity: ATHLTHPlannedWorkoutType?,
        blocks: [WorkoutTemplateBlock],
        durationMinutes: Int?,
        route: TrainingRoute?,
        plannedDate: Date?,
        onDateChanged: ((Date) -> Void)?
    ) {
        _workoutName = workoutName
        self.activity = activity
        self.blocks = blocks
        self.durationMinutes = durationMinutes
        self.route = route
        self.plannedDate = plannedDate
        self.onDateChanged = onDateChanged
        _selectedDate = State(initialValue: plannedDate ?? Date())
    }

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private var distanceText: String {
        let kilometers = route?.distanceKilometers ??
            (blocks.compactMap(\.distanceMeters).reduce(0, +) / 1_000)
        return kilometers > 0 ? String(format: "~ %.1f km", kilometers) : "–"
    }

    private var zoneText: String {
        let zones = blocks.compactMap(\.targetHeartRateZone)
        guard let lowest = zones.min(), let highest = zones.max() else { return "–" }
        return lowest == highest ? "Z\(lowest)" : "Z\(lowest)–Z\(highest)"
    }

    private var inclineText: String {
        let slopes = blocks.compactMap(\.treadmillInclinePercent)
        guard let maxSlope = slopes.max() else { return "–" }
        return String(format: "%.0f %%", maxSlope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: activity?.symbol ?? "figure.run")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(bronze)
                    .frame(width: 52, height: 52)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "WORKOUT DETAILS", norwegian: "ØKTDETALJER"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(bronze)
                    Text(activity?.title ?? ATHLTHLocalization.choose(
                        english: "Your workout", norwegian: "Din økt"
                    ))
                    .font(.system(size: 23, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
            }
            TextField(
                "", text: $workoutName,
                prompt: Text(ATHLTHWorkoutNameSuggestion.suggested(
                    activity: activity, blocks: blocks,
                    durationMinutes: durationMinutes, routeTitle: route?.title
                ))
                .foregroundStyle(.secondary.opacity(0.55))
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ink)
            .tint(bronze)
            .textInputAutocapitalization(.sentences)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Workout name (optional)", norwegian: "Øktnavn (valgfritt)"
            ))
            .frame(minHeight: 43, alignment: .leading)
            .padding(.horizontal, 13)
            .background(ATHLTHPlanDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 0) {
                metric("clock", ATHLTHLocalization.choose(
                    english: "Duration", norwegian: "Varighet"
                ), durationMinutes.map { "~ \($0) min" } ?? "–")
                metric("point.topleft.down.to.point.bottomright.curvepath",
                       ATHLTHLocalization.choose(
                            english: "Distance", norwegian: "Distanse"
                       ), distanceText)
                metric("heart", ATHLTHLocalization.choose(
                    english: "Zone", norwegian: "Sone"
                ), zoneText)
                metric("mountain.2", ATHLTHLocalization.choose(
                    english: "Incline", norwegian: "Stigning"
                ), inclineText)
            }

            if plannedDate != nil {
                HStack(spacing: 8) {
                    if onDateChanged != nil {
                        DatePicker(
                            ATHLTHLocalization.choose(
                                english: "Date", norwegian: "Dato"
                            ), selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        DatePicker(
                            ATHLTHLocalization.choose(
                                english: "Time", norwegian: "Tid"
                            ), selection: $selectedDate,
                            displayedComponents: .hourAndMinute
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                    } else {
                        Label(selectedDate.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                        Spacer()
                        Label(selectedDate.formatted(date: .omitted, time: .shortened),
                              systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(ink)
                .onChange(of: selectedDate) { _, newValue in
                    onDateChanged?(newValue)
                }
            }
        }
        .padding(16)
        .athlthPlanCard(radius: 22, warm: true)
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
