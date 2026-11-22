import SwiftUI

/// Read-only projection of the executable recipe. Never changes workouts,
/// group rounds, recoveries, exercise identities, or personal target storage.
enum ATHLTHWorkoutCompactOutline {
    enum Kind: Equatable {
        case warmup, work, recovery, cooldown
    }

    struct Row: Identifiable {
        let id: Int
        let kind: Kind
        let title: String
        let blocks: [WorkoutTemplateBlock]
        let effortIndex: Int?
        let effortTotal: Int

        /// The first real effort anchors the visible Hoveddel group heading.
        /// Recovery blocks never create additional main-section headings.
        var beginsMainSection: Bool {
            kind == .work && effortIndex == 1
        }

        var estimatedSeconds: TimeInterval? {
            guard !blocks.isEmpty,
                  blocks.allSatisfy({ ($0.durationSeconds ?? 0) > 0 }) else {
                return nil
            }
            return blocks.compactMap(\.durationSeconds).reduce(0, +)
        }
    }

    private struct Group {
        var kind: Kind
        var blocks: [WorkoutTemplateBlock]
    }

    static func rows(for source: [WorkoutTemplateBlock]) -> [Row] {
        // A group with four rounds has four real efforts, not one source
        // block. Pauses belong to the preceding effort, never to drag count.
        let executable = source.expandedForExecution()
        var groups: [Group] = []

        for block in executable {
            let kind: Kind
            if block.kind == .rest || block.resolvedPhase == .recovery {
                kind = .recovery
            } else {
                switch block.resolvedPhase {
                case .warmup: kind = .warmup
                case .main: kind = .work
                case .cooldown: kind = .cooldown
                case .recovery: kind = .recovery
                }
            }

            if let last = groups.indices.last {
                if (kind == .warmup || kind == .cooldown) &&
                   groups[last].kind == kind {
                    groups[last].blocks.append(block)
                    continue
                }
                if kind == .recovery &&
                   groups[last].kind != .recovery {
                    // Keep the exact recovery beside its preceding workout
                    // section without counting it as a new drag.
                    groups[last].blocks.append(block)
                    continue
                }
            }
            groups.append(Group(kind: kind, blocks: [block]))
        }

        let totalEfforts = groups.filter { $0.kind == .work }.count
        var effort = 0
        return groups.enumerated().map { index, group in
            let title: String
            let effortIndex: Int?
            switch group.kind {
            case .warmup:
                title = ATHLTHLocalization.choose(
                    english: "Warm-up", norwegian: "Oppvarming")
                effortIndex = nil
            case .work:
                effort += 1
                title = ATHLTHLocalization.choose(
                    english: "Part \(effort)", norwegian: "Deløkt \(effort)")
                effortIndex = effort
            case .recovery:
                title = ATHLTHLocalization.choose(
                    english: "Recovery", norwegian: "Pause")
                effortIndex = nil
            case .cooldown:
                title = ATHLTHLocalization.choose(
                    english: "Cool-down", norwegian: "Avslutning")
                effortIndex = nil
            }
            return Row(id: index, kind: group.kind, title: title,
                       blocks: group.blocks, effortIndex: effortIndex,
                       effortTotal: totalEfforts)
        }
    }

    /// Show only explicit main-effort prescriptions. Do not mistake the
    /// recovery's Z1 for the target of a Z5 interval, or invent a zone.
    static func headlineZone(for blocks: [WorkoutTemplateBlock]) -> String? {
        var zones: Set<Int> = []
        for block in blocks where block.resolvedPhase == .main &&
            block.kind != .rest {
            if let target = block.targetHeartRateZone, (1...5).contains(target) {
                zones.insert(target)
            } else if let label = block.sourceIntensityZoneLabel {
                // Legacy imported labels are often "Z5" or "Z5 (90–100%)".
                let characters = Array(label.uppercased())
                for i in characters.indices where characters[i] == "Z" {
                    let next = characters.index(after: i)
                    if next < characters.endIndex,
                       let digit = characters[next].wholeNumberValue,
                       (1...5).contains(digit) {
                        zones.insert(digit)
                    }
                }
            }
        }
        guard !zones.isEmpty else { return nil }
        let ordered = zones.sorted().map { "Z\($0)" }.joined(separator: ", ")
        return ATHLTHLocalization.choose(
            english: zones.count == 1 ? "HR zone \(ordered)" : "HR zones \(ordered)",
            norwegian: zones.count == 1 ? "Pulssone \(ordered)" : "Pulssoner \(ordered)"
        )
    }

    /// Percent-of-max is displayed only if all prescribed main efforts agree.
    static func headlineHeartRatePercent(for blocks: [WorkoutTemplateBlock]) -> String? {
        let efforts = blocks.filter { $0.resolvedPhase == .main && $0.kind != .rest }
        guard let first = efforts.first,
              let low = first.targetHeartRatePercentMin,
              let high = first.targetHeartRatePercentMax,
              low.isFinite, high.isFinite, low >= 0, high <= 100, high >= low,
              efforts.allSatisfy({
                  $0.targetHeartRatePercentMin == low &&
                  $0.targetHeartRatePercentMax == high
              }) else { return nil }
        return "\(Int(low.rounded()))–\(Int(high.rounded())) % " +
            ATHLTHLocalization.choose(english: "HR max", norwegian: "makspuls")
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        if minutes == 0 { return "\(total) s" }
        if remainder == 0 { return "\(minutes) min" }
        return "\(minutes) min \(remainder) s"
    }
}

/// One disclosure-based overview for catalog, personal and scheduled workouts.
/// Only names, exact drag ordinal and estimated duration are visible until tap.
struct ATHLTHWorkoutCompactOutlineView: View {
    let blocks: [WorkoutTemplateBlock]
    let isRunning: Bool

    @State private var expandedRows: Set<Int> = []

    private var ink: Color { ATHLTHPlanDesign.ink }
    private var muted: Color { ATHLTHPlanDesign.secondaryInk }
    private var tint: Color { ATHLTHPlanDesign.accentInk }

    var body: some View {
        let rows = ATHLTHWorkoutCompactOutline.rows(for: blocks)
        return VStack(alignment: .leading, spacing: 8) {
            Text(ATHLTHLocalization.choose(
                english: "WORKOUT OVERVIEW", norwegian: "ØKTOVERSIKT"
            ))
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(muted)
            .padding(.bottom, 4)

            if rows.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "No detailed workout steps are available.",
                    norwegian: "Ingen detaljerte øktdeler er tilgjengelige."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(rows) { row in
                        if row.beginsMainSection {
                            mainSectionHeading
                        }
                        disclosure(row)
                            // Visually nest efforts under Hoveddel without
                            // adding another large expandable container.
                            .padding(.leading, row.kind == .work ? 14 : 0)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 21))
        .accessibilityIdentifier("athlth-compact-workout-outline")
    }

    /// Hoveddel is always visible, while the individual descriptions
    /// and recovery details remain hidden until a subsection is opened.
    private var mainSectionHeading: some View {
        HStack(spacing: 9) {
            Image(systemName: "figure.run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 23)
                .accessibilityHidden(true)
            Text(ATHLTHLocalization.choose(
                english: "Main workout", norwegian: "Hoveddel"
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("athlth-workout-outline-main-heading")
    }

    private func disclosure(_ row: ATHLTHWorkoutCompactOutline.Row) -> some View {
        let expanded = expandedRows.contains(row.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if expanded { expandedRows.remove(row.id) }
                    else { expandedRows.insert(row.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: row.kind == .warmup ? "flame" :
                          row.kind == .cooldown ? "wind" :
                          row.kind == .recovery ? "pause" : "figure.run")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tint)
                        .frame(width: 23)
                        .accessibilityHidden(true)

                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 3) {
                        if isRunning,
                           let effort = row.effortIndex,
                           row.effortTotal > 1 {
                            Text(ATHLTHLocalization.choose(
                                english: "Rep \(effort) of \(row.effortTotal)",
                                norwegian: "Drag \(effort) av \(row.effortTotal)"
                            ))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                        }
                        if let seconds = row.estimatedSeconds {
                            Text("~" + ATHLTHWorkoutCompactOutline.timeText(seconds))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(muted)
                        }
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(muted.opacity(0.5))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 14)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.title)
            .accessibilityValue(expanded
                ? ATHLTHLocalization.choose(english: "Expanded", norwegian: "Åpen")
                : ATHLTHLocalization.choose(english: "Collapsed", norwegian: "Lukket"))
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Show step names, descriptions and targets",
                norwegian: "Vis øktnavn, beskrivelser og mål"))
            .accessibilityIdentifier("athlth-workout-outline-row-\(row.id)")

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(row.blocks.indices, id: \.self) { index in
                        let block = row.blocks[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ink)
                            let details = stepFacts(block)
                            if !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let notes = block.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if index < row.blocks.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 33)
                .padding(.trailing, 17)
                .padding(.bottom, 13)
            }
        }
        .padding(.horizontal, 5)
        .background(expanded ? ATHLTHPlanDesign.selectedSurface.opacity(0.32) :
                    Color.clear,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func stepFacts(_ block: WorkoutTemplateBlock) -> String {
        var facts: [String] = []
        if block.kind == .rest || block.resolvedPhase == .recovery {
            facts.append(ATHLTHLocalization.choose(
                english: "Recovery", norwegian: "Pause"))
        }
        if let seconds = block.durationSeconds, seconds > 0 {
            facts.append(ATHLTHWorkoutCompactOutline.timeText(seconds))
        }
        if let distance = block.distanceMeters, distance > 0 {
            facts.append(distance >= 1000
                ? String(format: "%.1f km", distance / 1000)
                : "\(Int(distance.rounded())) m")
        }
        if let zone = block.targetHeartRateZone, (1...5).contains(zone) {
            facts.append("Z\(zone)")
        } else if let source = block.sourceIntensityZoneLabel,
                  !source.isEmpty {
            facts.append(source)
        }
        if let low = block.targetHeartRatePercentMin,
           let high = block.targetHeartRatePercentMax {
            facts.append("\(Int(low.rounded()))–\(Int(high.rounded())) % " +
                ATHLTHLocalization.choose(english: "HR max", norwegian: "makspuls"))
        }
        if let pace = block.targetPaceSecondsPerKilometer, pace > 0 {
            let s = Int(pace.rounded())
            facts.append(String(format: "%d:%02d min/km", s / 60, s % 60))
        }
        if let repetitions = block.repetitions, repetitions > 0 {
            facts.append("\(repetitions) " + ATHLTHLocalization.choose(
                english: "reps", norwegian: "repetisjoner"))
        }
        return facts.joined(separator: " · ")
    }
}
