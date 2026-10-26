import Foundation
import SwiftUI

/// Read-only, source-driven overview shared by Train / I dag and Plan.
/// Prefer the unified ordered blocks when present so mixed workouts are
/// never displayed twice (once as blocks and again as legacy exercises).
enum ATHLTHWorkoutPlanOutline {
    struct Item: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        var isPause: Bool { symbol == "pause.circle" || symbol == "pause" || symbol == "pause.circle.fill" }
    }

    static func items(for workout: PlannedSession) -> [Item] {
        let blocks = workout.resolvedWorkoutBlocks.sorted {
            $0.sequence < $1.sequence
        }
        if !blocks.isEmpty {
            return blocks.map { block in
                Item(
                    id: "block-\(block.id)",
                    title: block.title,
                    detail: [
                        block.kind == .rest
                            ? block.durationSeconds.map { "\(Int($0.rounded())) sek pause" }
                            : block.targetText,
                        block.notes
                    ]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "),
                    symbol: block.kind == .rest ? "pause.circle.fill" : block.kind.systemImage
                )
            }
        }

        var items: [Item] = []
        for run in workout.resolvedRunningWorkouts {
            if run.blocks.isEmpty {
                items.append(Item(
                    id: "run-\(run.id)",
                    title: run.title,
                    detail: run.summary,
                    symbol: "figure.run"
                ))
                continue
            }

            // Work and recovery stay separate: 4 × 4 with 2-minute
            // recoveries means four work intervals and three recoveries,
            // not four recoveries or an invented combined duration.
            for block in run.blocks {
                items.append(Item(
                    id: "run-\(run.id)-\(block.id)",
                    title: localizedTitle(for: block),
                    detail: target(block.work, repetitions: block.repetitions),
                    symbol: symbol(for: block.kind)
                ))
                if block.repetitions > 1, let recovery = block.recovery {
                    items.append(Item(
                        id: "recovery-\(run.id)-\(block.id)",
                        title: ATHLTHLocalization.choose(
                            english: "Recoveries",
                            norwegian: "Pauser"
                        ),
                        detail: target(
                            recovery,
                            repetitions: block.repetitions - 1
                        ),
                        symbol: "pause.circle"
                    ))
                }
            }
        }

        for exercise in workout.exercises {
            var parts = [exercise.compactTargetSummary]
            if let load = exercise.compactLoadSummary {
                parts.append(load)
            }
            if let note = exercise.notes, !note.isEmpty {
                parts.append(note)
            }
            items.append(Item(
                id: "exercise-\(exercise.id)",
                title: exercise.embeddedExercise.name,
                detail: parts.joined(separator: " · "),
                symbol: "dumbbell"
            ))
        }
        return items
    }

    private static func localizedTitle(for block: RunningWorkoutBlock) -> String {
        let provided = block.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !provided.isEmpty { return provided }
        switch block.kind {
        case .warmup:
            return ATHLTHLocalization.choose(
                english: "Warm-up", norwegian: "Oppvarming"
            )
        case .work:
            return ATHLTHLocalization.choose(
                english: "Work intervals", norwegian: "Arbeidsdrag"
            )
        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Recovery", norwegian: "Pause"
            )
        case .steady:
            return ATHLTHLocalization.choose(
                english: "Steady run", norwegian: "Jevn løping"
            )
        case .cooldown:
            return ATHLTHLocalization.choose(
                english: "Cool-down", norwegian: "Nedjogg"
            )
        }
    }

    private static func symbol(for kind: RunningBlockKind) -> String {
        switch kind {
        case .warmup: return "figure.walk"
        case .work: return "figure.run"
        case .recovery: return "pause.circle"
        case .steady: return "figure.run"
        case .cooldown: return "figure.walk"
        }
    }

    private static func target(
        _ step: RunningStepTarget,
        repetitions: Int
    ) -> String {
        let amount: String
        switch step.measure {
        case .time:
            guard let duration = step.durationSeconds, duration > 0 else {
                return ATHLTHLocalization.choose(
                    english: "Open target", norwegian: "Åpent mål"
                )
            }
            let seconds = Int(duration.rounded())
            if seconds % 60 == 0 {
                amount = "\(seconds / 60) min"
            } else {
                amount = String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
        case .distance:
            guard let distance = step.distanceMeters, distance > 0 else {
                return ATHLTHLocalization.choose(
                    english: "Open target", norwegian: "Åpent mål"
                )
            }
            amount = distance >= 1_000
                ? String(format: "%.1f km", distance / 1_000)
                : "\(Int(distance.rounded())) m"
        case .open:
            amount = ATHLTHLocalization.choose(
                english: "Open", norwegian: "Åpent"
            )
        }
        let repeated = max(repetitions, 1) > 1
            ? "\(repetitions) × \(amount)"
            : amount
        let intensity = intensityText(step.intensity)
        return intensity.isEmpty ? repeated : "\(repeated) · \(intensity)"
    }

    private static func intensityText(_ target: RunningIntensityTarget) -> String {
        switch target.kind {
        case .heartRateZone:
            guard let zone = target.heartRateZone else { return "" }
            return ATHLTHLocalization.choose(
                english: "Zone \(zone)", norwegian: "Pulssone \(zone)"
            )
        case .pace:
            let minimum = target.paceMinSecondsPerKilometer
            let maximum = target.paceMaxSecondsPerKilometer
            guard let pace = minimum ?? maximum,
                  pace > 0 else { return "" }

            func formatted(_ pace: Double) -> String {
                let seconds = Int(pace.rounded())
                return String(format: "%d:%02d", seconds / 60, seconds % 60)
            }

            if let minimum, let maximum, minimum > 0, maximum > 0,
               abs(maximum - minimum) > 0.5 {
                return "\(formatted(minimum))–\(formatted(maximum)) min/km"
            }
            return "\(formatted(pace)) min/km"
        case .easy:
            return ATHLTHLocalization.choose(
                english: "Easy", norwegian: "Rolig"
            )
        case .rpe:
            guard let rpe = target.rpe else { return "" }
            return String(format: "RPE %.0f", rpe)
        case .none:
            return ""
        }
    }
}

/// Purely informational; workout launching remains in Today's coordinator,
/// and editing remains in the existing common workout editor.
struct ATHLTHWorkoutPlanOutlineView: View {
    let workout: PlannedSession
    var maxVisibleItems: Int = 8
    // Opt-in for the advanced Plan experience; Today retains its compact outline.
    var timelineStyle: Bool = false

    var body: some View {
        let items = ATHLTHWorkoutPlanOutline.items(for: workout)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.prefix(maxVisibleItems).enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 11) {
                        VStack(spacing: 0) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(item.isPause ? Color(red: 0.49, green: 0.37, blue: 0.20) : ATHLTHTheme.accentDeep)
                                .frame(width: 30, height: 30)
                                .background(
                                    item.isPause ? Color(red: 0.94, green: 0.91, blue: 0.85) : Color(red: 0.96, green: 0.95, blue: 0.92),
                                    in: Circle()
                                )
                            if timelineStyle && index < min(items.count, maxVisibleItems) - 1 {
                                Rectangle()
                                    .fill(Color(red: 0.74, green: 0.69, blue: 0.60).opacity(0.65))
                                    .frame(width: 1, height: 18)
                                    .padding(.vertical, 3)
                                    .accessibilityHidden(true)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 3)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, item.isPause ? 8 : 5)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        item.isPause
                            ? Color(red: 0.97, green: 0.95, blue: 0.91)
                            : (timelineStyle ? Color.white.opacity(0.72) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                    .overlay {
                        if item.isPause {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color(red: 0.74, green: 0.66, blue: 0.52).opacity(0.48), lineWidth: 0.7)
                        }
                    }
                }
                if items.count > maxVisibleItems {
                    Text(ATHLTHLocalization.choose(
                        english: "+ \(items.count - maxVisibleItems) more parts · Open details",
                        norwegian: "+ \(items.count - maxVisibleItems) deler · Åpne detaljer"
                    ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                timelineStyle ? Color(red: 0.97, green: 0.96, blue: 0.94) : ATHLTHTheme.champagneSoft.opacity(0.56),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .accessibilityElement(children: .contain)
        }
    }
}
