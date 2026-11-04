import SwiftUI

/// A searchable workout index with a native system inspector, not an
/// invented cloud-backed history. Empty HealthKit reads remain ambiguous.
struct ATHLTHStudioHistoryView: View {
    @EnvironmentObject private var health: HealthKitManager
    let onInspect: (WorkoutSummary) -> Void
    @State private var searchText = ""
    @State private var showsFullReplay = false

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

            if showsFullReplay {
                // Existing rich workout replay includes maps, completed
                // workout history and strength entries beyond Health summaries.
                WorkoutHistoryView()
            } else {
            List(workouts) { workout in
                Button {
                    onInspect(workout)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "figure.mixed.cardio")
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.activity.rawValue).font(.headline)
                            Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(workout.duration / 60)) min")
                            .foregroundStyle(.secondary)
                        if let km = workout.distanceKilometers {
                            Text(String(format: "%.1f km", km))
                                .foregroundStyle(.secondary)
                                .frame(width: 85, alignment: .trailing)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.white)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: ATHLTHLocalization.choose(
                english: "Search workout type or date", norwegian: "Søk på aktivitet eller dato"
            ))
            }
        }
        .background(ATHLTHStudioStyle.canvas)
    }
}
