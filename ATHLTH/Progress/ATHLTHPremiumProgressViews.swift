import Charts
import SwiftUI

// One visual language for General, Running and Strength. The hero displays
// measured/logged quantities, never an invented progress or fitness score.
enum ATHLTHProgressScope: String, CaseIterable, Identifiable {
    case general, running, strength

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return ATHLTHLocalization.choose(english: "All training", norwegian: "All trening")
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        }
    }

    var imageName: String {
        switch self {
        case .general: return "ProgressHero"
        case .running: return "GoalRunning"
        case .strength: return "StrengthPostWorkoutHero"
        }
    }

    var accent: Color {
        switch self {
        case .general: return ATHLTHTheme.champagne
        case .running: return Color(red: 0.77, green: 0.87, blue: 0.80)
        case .strength: return Color(red: 0.86, green: 0.83, blue: 0.74)
        }
    }
}

struct ATHLTHPremiumProgressHero: View {
    let scope: ATHLTHProgressScope
    let value: String
    let metricLabel: String
    let secondaryLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(ATHLTHLocalization.choose(english: "TRAINING", norwegian: "TRENING"))
                .font(.system(size: 11, weight: .medium))
                .tracking(3)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Text(ATHLTHLocalization.choose(english: "Progress", norwegian: "Fremdrift"))
                .font(.system(size: 42, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "Follow your development. Build on what works.",
                norwegian: "Se utviklingen din. Bygg videre på det som fungerer."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)

            HStack(spacing: 12) {
                Image(systemName: scope == .running ? "figure.run" :
                    scope == .strength ? "dumbbell" : "chart.xyaxis.line")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 57, height: 57)
                    .background(ATHLTHTheme.champagneSoft, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(scope.title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "Your training, over time",
                        norwegian: "Din trening over tid"
                    ))
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(secondaryLabel)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(metricLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    Text(value)
                        .font(.system(size: 28, weight: .medium, design: .serif))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .monospacedDigit()
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(ATHLTHTheme.premiumGold.opacity(0.22), lineWidth: 0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 58)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHTheme.canvasTop)
    }
}

struct ATHLTHPremiumProgressScopePicker: View {
    @Binding var selection: ATHLTHProgressScope

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ATHLTHProgressScope.allCases) { scope in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selection = scope
                    }
                } label: {
                    Text(scope.title)
                        .font(.system(size: 13, weight: selection == scope ? .semibold : .medium))
                        .foregroundStyle(selection == scope ? ATHLTHTheme.primaryText : ATHLTHTheme.mutedText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            selection == scope ? Color.white.opacity(0.93) : .clear,
                            in: Capsule()
                        )
                        .shadow(
                            color: selection == scope ? Color.black.opacity(0.07) : .clear,
                            radius: 7,
                            y: 3
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == scope ? .isSelected : [])
            }
        }
        .padding(5)
        .background(ATHLTHTheme.cardWarm.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1))
    }
}

struct ATHLTHPremiumProgressStat: Identifiable {
    let title: String
    let value: String
    let icon: String
    var id: String { title }
}

struct ATHLTHPremiumProgressStats: View {
    let stats: [ATHLTHPremiumProgressStat]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
            spacing: 9
        ) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: stat.icon)
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                    Text(stat.value)
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text(stat.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
                .padding(15)
                .background(ATHLTHTheme.card, in: RoundedRectangle(cornerRadius: 19))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .stroke(ATHLTHTheme.border, lineWidth: 0.8)
                }
            }
        }
    }
}

struct ATHLTHPremiumRunningChart: View {
    let workouts: [WorkoutSummary]

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let minutesPerKilometer: Double
    }

    private var points: [Point] {
        workouts.compactMap { workout -> Point? in
            guard let meters = workout.distanceMeters, meters >= 500,
                  workout.duration > 0 else { return nil }
            let pace = workout.duration / (meters / 1_000) / 60
            guard pace >= 2, pace <= 20, pace.isFinite else { return nil }
            return Point(date: workout.startDate, minutesPerKilometer: pace)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(
                ATHLTHLocalization.choose(english: "Pace development", norwegian: "Utvikling i tempo"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Average pace in recorded runs · min/km",
                    norwegian: "Snittempo i registrerte løpeøkter · min/km"
                )
            )
            if points.isEmpty {
                placeholder(
                    ATHLTHLocalization.choose(
                        english: "Not enough recorded runs to show pace",
                        norwegian: "Ingen registrerte løpeøkter med gyldig tempo"
                    ),
                    icon: "figure.run"
                )
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Dato", point.date),
                        y: .value("min/km", point.minutesPerKilometer)
                    )
                    .foregroundStyle(ATHLTHTheme.vitality)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Dato", point.date),
                        y: .value("min/km", point.minutesPerKilometer)
                    )
                    .foregroundStyle(ATHLTHTheme.vitality)
                    .symbolSize(23)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 178)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }
}

struct ATHLTHPremiumStrengthChart: View {
    let workouts: [StrengthWorkoutLog]

    private var chartWorkouts: [StrengthWorkoutLog] {
        Array(
            workouts
                .filter { $0.totalVolumeKilograms > 0 }
                .sorted { $0.startedAt < $1.startedAt }
                .suffix(12)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(
                ATHLTHLocalization.choose(english: "Training volume", norwegian: "Treningsvolum"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Completed working sets · kg per session",
                    norwegian: "Fullførte arbeidssett · kg per økt"
                )
            )
            if chartWorkouts.isEmpty {
                placeholder(
                    ATHLTHLocalization.choose(
                        english: "No logged strength volume in this period",
                        norwegian: "Ingen registrert styrkevolum i perioden"
                    ),
                    icon: "dumbbell"
                )
            } else {
                Chart(chartWorkouts) { workout in
                    BarMark(
                        x: .value("Dato", workout.startedAt),
                        y: .value("kg", workout.totalVolumeKilograms)
                    )
                    .foregroundStyle(ATHLTHTheme.accentDeep.gradient)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 178)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }
}

struct ATHLTHPremiumProgressRecordItem: Identifiable {
    let title: String
    let value: String
    let subtitle: String
    var id: String { title + subtitle }
}

struct ATHLTHPremiumProgressRecords: View {
    let title: String
    let items: [ATHLTHPremiumProgressRecordItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(title)
                    .font(.system(size: 21, weight: .medium, design: .serif))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Records appear after completed workouts.",
                        norwegian: "Rekorder vises etter fullførte økter."
                    ),
                    systemImage: "trophy"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(3)) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "trophy")
                            .font(.system(size: 15))
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                            .frame(width: 26)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(item.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if item.id != items.prefix(3).last?.id {
                        Divider().overlay(ATHLTHTheme.divider)
                    }
                }
            }
        }
        .padding(18)
        .progressReferenceCard()
    }
}

private func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.system(size: 21, weight: .medium, design: .serif))
            .foregroundStyle(ATHLTHTheme.primaryText)
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private func placeholder(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 150)
}
