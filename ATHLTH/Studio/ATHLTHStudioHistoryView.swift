import SwiftUI

/// A searchable workout index with a native system inspector, not an
/// invented cloud-backed history. Empty HealthKit reads remain ambiguous.
struct ATHLTHStudioHistoryView: View {
    @EnvironmentObject private var health: HealthKitManager
    let onInspect: (WorkoutSummary) -> Void
    @State private var searchText = ""
    @State private var showsFullReplay = false
    @State private var compared: [WorkoutSummary] = []
    @State private var comparisonMessage: String?


    private var workouts: [WorkoutSummary] {
        let ordered = health.workouts.sorted { $0.startDate > $1.startDate }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ordered }
        return ordered.filter {
            $0.activity.rawValue.localizedCaseInsensitiveContains(query)
            || $0.startDate.formatted(date: .abbreviated, time: .omitted)
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "Workout history", norwegian: "Treningshistorikk"
                    ))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(ATHLTHLocalization.choose(
                        english: "Select a workout to inspect the recording and, on iOS 27+, native heart-rate zones.",
                        norwegian: "Velg en økt for detaljer og, fra iOS 27, Apples registrerte pulssoner."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showsFullReplay.toggle()
                } label: {
                    Label(
                        showsFullReplay
                            ? ATHLTHLocalization.choose(english: "Zone inspector", norwegian: "Soneoversikt")
                            : "ATHLTH Replay",
                        systemImage: showsFullReplay ? "heart.text.square" : "point.topleft.down.curvedto.point.bottomright.up"
                    )
                }
                .buttonStyle(.bordered)
                Text("\(workouts.count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 25)

            if compared.count == 2 && !showsFullReplay {
                comparisonSection
                    .padding(.horizontal, 24)
            }

            if showsFullReplay {
                // Existing rich workout replay includes maps, completed
                // workout history and strength entries beyond Health summaries.
                WorkoutHistoryView()
            } else {
            List(workouts) { workout in
                HStack(spacing: 10) {
                    Button {
                        onInspect(workout)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "figure.mixed.cardio")
                                .foregroundStyle(ATHLTHStudioStyle.gold)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.activity.rawValue).font(.headline)
                                Text(workout.startDate.formatted(
                                    date: .abbreviated, time: .shortened
                                ))
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("\(Int(workout.duration / 60)) min")
                                .foregroundStyle(.secondary)
                            if let km = workout.distanceKilometers {
                                Text(String(format: "%.1f km", km))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 85, alignment: .trailing)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        toggleCompare(workout)
                    } label: {
                        Label(
                            compared.contains(where: { $0.id == workout.id })
                                ? ATHLTHLocalization.choose(
                                    english: "Selected", norwegian: "Valgt"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Compare", norwegian: "Sammenlign"
                                ),
                            systemImage: compared.contains(where: { $0.id == workout.id })
                                ? "checkmark.circle.fill" : "plus.circle"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHStudioStyle.gold)
                    .accessibilityIdentifier("athlth-ipad-history-compare")
                }
                .listRowBackground(Color.white)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: ATHLTHLocalization.choose(
                english: "Search workout type or date", norwegian: "Søk på aktivitet eller dato"
            ))
            }
        }
        .background(ATHLTHStudioStyle.canvas)
        .alert(
            ATHLTHLocalization.choose(
                english: "Cannot compare these workouts",
                norwegian: "Kan ikke sammenligne disse øktene"
            ),
            isPresented: Binding(
                get: { comparisonMessage != nil },
                set: { if !$0 { comparisonMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { comparisonMessage = nil }
        } message: {
            Text(comparisonMessage ?? "")
        }
    }

    private func toggleCompare(_ workout: WorkoutSummary) {
        if let index = compared.firstIndex(where: { $0.id == workout.id }) {
            compared.remove(at: index)
            return
        }
        if let first = compared.first,
           first.activity.rawValue != workout.activity.rawValue {
            comparisonMessage = ATHLTHLocalization.choose(
                english: "Choose two workouts of the same activity for a meaningful comparison.",
                norwegian: "Velg to økter med samme aktivitet for en meningsfull sammenligning."
            )
            return
        }
        // A third selection replaces the oldest: never a confusing 3-way
        // comparison hidden in a two-column iPad interface.
        if compared.count == 2 { compared.removeFirst() }
        compared.append(workout)
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "SIDE-BY-SIDE COMPARISON",
                        norwegian: "SAMMENLIGN ØKTER"
                    ),
                    systemImage: "rectangle.split.2x1"
                )
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Spacer(minLength: 4)
                Button {
                    compared = []
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Clear", norwegian: "Tøm"
                        ),
                        systemImage: "xmark"
                    )
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(compared) { workout in
                        comparisonCard(workout)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(compared) { workout in
                        comparisonCard(workout)
                    }
                }
            }
            Text(ATHLTHLocalization.choose(
                english: "Duration, distance and pace reflect recorded workout summaries; they are not predicted performance values.",
                norwegian: "Varighet, distanse og tempo kommer fra registrerte økter, ikke forventet prestasjon."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.65))
        }
        .accessibilityIdentifier("athlth-ipad-workout-comparison")
    }

    private func comparisonCard(_ workout: WorkoutSummary) -> some View {
        let km = workout.distanceKilometers
        let pace: String = {
            guard let km, km >= 0.25,
                  workout.duration.isFinite, workout.duration > 0 else { return "—" }
            let secondsPerKm = workout.duration / km
            guard secondsPerKm.isFinite, (120...3_600).contains(secondsPerKm)
            else { return "—" }
            let rounded = Int(secondsPerKm.rounded())
            return String(format: "%d:%02d /km", rounded / 60, rounded % 60)
        }()
        return VStack(alignment: .leading, spacing: 9) {
            Text(workout.startDate.formatted(
                date: .abbreviated, time: .shortened
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHStudioStyle.ink)
            Text(workout.activity.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            metric(
                ATHLTHLocalization.choose(english: "Duration", norwegian: "Varighet"),
                value: "\(Int(workout.duration / 60)) min"
            )
            metric(
                ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                value: km.map { String(format: "%.2f km", $0) } ?? "—"
            )
            metric(
                ATHLTHLocalization.choose(english: "Average pace", norwegian: "Snittempo"),
                value: pace
            )
            Button {
                onInspect(workout)
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Open workout", norwegian: "Åpne økten"
                    ),
                    systemImage: "arrow.up.right"
                )
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ATHLTHStudioStyle.gold)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHStudioStyle.canvas,
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(ATHLTHStudioStyle.ink)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}
