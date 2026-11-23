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

/// Shared read-only workout overview. The stored exercise names and targets
/// are visible immediately; only whole sections may be collapsed.
struct ATHLTHWorkoutCompactOutlineView: View {
    let blocks: [WorkoutTemplateBlock]
    let isRunning: Bool

    @State private var collapsedSections: Set<Int> = []

    private var ink: Color { ATHLTHPlanDesign.ink }
    private var muted: Color { ATHLTHPlanDesign.secondaryInk }
    private var tint: Color { ATHLTHPlanDesign.accentInk }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        let sections = ATHLTHWorkoutSelectionOverview.sections(for: blocks)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("WORKOUT OVERVIEW", "ØKTOVERSIKT"))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(muted)
                Spacer(minLength: 8)
                if !sections.isEmpty {
                    Text(isRunning ? tr("Target", "Mål") : tr("Sets / reps", "Sett / reps"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(muted)
                }
            }

            if sections.isEmpty {
                Text(tr("No detailed workout steps are available.",
                        "Ingen detaljerte øktdeler er tilgjengelige."))
                    .font(.subheadline)
                    .foregroundStyle(muted)
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 21))
        .accessibilityIdentifier("athlth-compact-workout-outline")
    }

    private func sectionSymbol(_ phase: WorkoutPhaseKind) -> String {
        switch phase {
        case .warmup: return "flame"
        case .main: return isRunning ? "figure.run" : "dumbbell"
        case .recovery: return "pause"
        case .cooldown: return "wind"
        }
    }

    private func sectionView(_ section: ATHLTHWorkoutSelectionOverview.Section) -> some View {
        let expanded = !collapsedSections.contains(section.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if expanded { collapsedSections.insert(section.id) }
                    else { collapsedSections.remove(section.id) }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: sectionSymbol(section.phase))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tint)
                        .frame(width: 24)
                    Text(section.phase == .cooldown ? tr("Cool-down", "Avslutning") : section.phase.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer(minLength: 4)
                    Text("\(section.rows.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(muted)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(muted)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHPlanDesign.selectedSurface.opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(expanded ? tr("Expanded", "Åpen") : tr("Collapsed", "Lukket"))
            .accessibilityIdentifier(section.phase == .main
                ? "athlth-workout-outline-main-heading"
                : "athlth-workout-outline-section-\(section.id)")

            if expanded {
                ForEach(section.rows) { row in
                    exerciseRow(row)
                    if row.id != section.rows.last?.id {
                        Divider()
                            .overlay(ATHLTHPlanDesign.outline.opacity(0.35))
                            .padding(.leading, 35)
                    }
                }
            }
        }
    }

    private func setPauseDetail(_ row: ATHLTHWorkoutSelectionOverview.Row) -> String {
        let rests = row.steps.filter { ATHLTHWorkoutSelectionOverview.isBetweenSetPause($0) }
        let durations = rests.compactMap(\.durationSeconds).filter { $0.isFinite && $0 >= 0 }
        guard durations.count == rests.count, let first = durations.first else { return "" }
        if durations.allSatisfy({ $0 == first }) {
            return " · " + ATHLTHWorkoutCompactOutline.timeText(first)
        }
        return " · " + durations.map { ATHLTHWorkoutCompactOutline.timeText($0) }.joined(separator: " / ")
    }

    private func exerciseRow(_ row: ATHLTHWorkoutSelectionOverview.Row) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: row.isPause
                  ? (row.first.isActiveRecovery ? "figure.walk" : "pause.fill")
                  : row.first.kind.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(ATHLTHPlanDesign.selectedSurface.opacity(0.55), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(row.isPause ? .caption.weight(.medium) : .subheadline.weight(.semibold))
                    .foregroundStyle(row.isPause ? muted : ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let round = row.first.executionRound,
                   let total = row.first.executionTotalRounds, total > 1 {
                    Text(tr("Round \(round) of \(total)", "Runde \(round) av \(total)"))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
                if row.betweenSetPauses > 0 {
                    Text(tr("Rest between sets", "Pause mellom sett") +
                         setPauseDetail(row))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
                if let notes = row.first.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.prescription)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(row.isPause ? muted : tint)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 150, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("athlth-workout-outline-row-\(row.id)")
    }
}
