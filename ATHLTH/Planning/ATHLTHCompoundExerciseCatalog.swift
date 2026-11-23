import Foundation
import CryptoKit

/// A reusable MAIN phase, not a second workout recording engine. It contains
/// the original executable run/exercise/recovery blocks and is explicitly
/// separate from warm-up and cool-down. Built-in/published sources are public;
/// athlete-created main sections remain private to the signed-in account.
struct ATHLTHCompoundExercise: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case intervals, threshold, hills, fartlek, running, strength, hybrid, other

        var id: String { rawValue }
        var title: String {
            switch self {
            case .intervals: return ATHLTHLocalization.choose(english: "Intervals", norwegian: "Intervaller")
            case .threshold: return ATHLTHLocalization.choose(english: "Threshold", norwegian: "Terskel")
            case .hills: return ATHLTHLocalization.choose(english: "Hills", norwegian: "Bakkeløp")
            case .fartlek: return ATHLTHLocalization.choose(english: "Fartlek", norwegian: "Fartslek")
            case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
            case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
            case .hybrid: return ATHLTHLocalization.choose(english: "Hybrid", norwegian: "Hybrid")
            case .other: return ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")
            }
        }
    }

    let id: String
    let title: String
    let category: Category
    let blocks: [WorkoutTemplateBlock]
    let sourceIDs: [UUID]
    let isPersonal: Bool
    let familyID: String
    let protocolID: String

    var isRunning: Bool { [.intervals, .threshold, .hills, .fartlek, .running].contains(category) }

    var detail: String {
        let main = blocks.filter { $0.kind == .run && !$0.isActiveRecovery }
        let rests = blocks.filter(\.isRestOrActiveRecovery)
        let durations = main.compactMap(\.durationSeconds).reduce(0, +) +
            rests.compactMap(\.durationSeconds).reduce(0, +)
        let amount = main.count > 1
            ? ATHLTHLocalization.choose(english: "\(main.count) efforts", norwegian: "\(main.count) drag")
            : ATHLTHLocalization.choose(english: "\(blocks.count) steps", norwegian: "\(blocks.count) deler")
        guard durations > 0 else { return amount }
        return amount + " · " + "\(Int(durations / 60)) min"
    }

    /// Reusing a compound exercise never changes the public original or
    /// doubles its warm-up. All internal group IDs are new for this insertion.
    func blocksForReuse(in phase: WorkoutPhaseKind = .main) -> [WorkoutTemplateBlock] {
        var groupIDs: [UUID: UUID] = [:]
        // Legacy 4×4 recipes are expanded work/recovery rows without group
        // metadata. Group only genuinely alternating running intervals;
        // never recast mixed sport/strength blocks as running intervals.
        let canGroupIntervals = category == .intervals &&
            blocks.count >= 3 &&
            blocks.enumerated().allSatisfy { index, step in
                index.isMultiple(of: 2)
                    ? step.kind == .run && !step.isActiveRecovery
                    : step.isRestOrActiveRecovery
            }
        let generatedGroup = canGroupIntervals ? UUID() : nil
        return blocks.enumerated().map { index, original in
            var copy = original
            // Keep effort and recovery classifications distinct so Watch
            // records pause seconds as recovery, never as work performance.
            copy.phase = original.isRestOrActiveRecovery ? .recovery : phase
            copy.sequence = index + 1
            copy.editorDragID = UUID()
            copy.compoundExerciseID = id
            copy.compoundExerciseFamilyID = familyID
            copy.compoundExerciseProtocolID = protocolID
            if let originalGroup = original.groupID {
                if groupIDs[originalGroup] == nil {
                    groupIDs[originalGroup] = UUID()
                }
                copy.groupID = groupIDs[originalGroup]
            } else if let generatedGroup {
                copy.groupID = generatedGroup
                copy.groupKind = .intervals
                copy.groupRounds = 1
            }
            return copy
        }
    }
}

/// Canonical directory of extracted main sections from EVERY available
/// built-in running workout, every published/offline workout catalog entry,
/// the existing run exercise presets and athlete-owned saved main sections.
/// Does not create duplicate strength movements in the ExerciseLibraryStore.
@MainActor
enum ATHLTHCompoundExerciseCatalog {
    private static let personalPrefix = "athlth-personal-main:"
    private static let publicPrefix = "athlth-main:"

    /// A protocol signature describes exercise execution, not a personal
    /// pace/heart-rate target or a mutable display title.
    static func protocolSignature(_ blocks: [WorkoutTemplateBlock]) -> String {
        blocks.filter { $0.kind != .note }.map { block in
            [
                block.kind.rawValue,
                block.cardioActivity?.rawValue ?? "",
                block.isActiveRecovery ? "active" : "passive",
                String(Int((block.durationSeconds ?? 0).rounded())),
                String(Int((block.distanceMeters ?? 0).rounded())),
                String(block.repetitions ?? 0),
                String(block.setCount ?? 0),
                block.kind == .exercise
                    ? (block.exerciseSlug ?? ATHLTHWorkoutLibraryExerciseIndex.normalize(block.title))
                    : "",
                block.groupKind?.rawValue ?? "",
                block.activityTag ?? "",
                block.isIndoor == true ? "indoor" : "outdoor",
                String(Int((block.treadmillInclinePercent ?? 0).rounded())),
                String(Int((block.targetGradientPercent ?? 0).rounded())),
                block.targetTerrainType ?? ""
            ].joined(separator: ":")
        }.joined(separator: "|")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(12).map {
            String(format: "%02x", $0)
        }.joined()
    }

    /// Two- and three-minute recoveries belong to the same 4×4 exercise
    /// family but never share a record/PR category.
    nonisolated static func fourByFourRecovery(_ blocks: [WorkoutTemplateBlock]) -> Int? {
        let relevant = blocks.filter {
            $0.kind == .run || $0.kind == .rest
        }
        let work = relevant.filter { $0.kind == .run && !$0.isActiveRecovery }
        let recovery = relevant.filter(\.isRestOrActiveRecovery)
        guard work.count == 4, (3...4).contains(recovery.count),
              work.allSatisfy { abs(($0.durationSeconds ?? -1) - 240) < 2 },
              let first = recovery.first?.durationSeconds,
              [120, 180].contains(Int(first.rounded())),
              recovery.allSatisfy({ abs(($0.durationSeconds ?? -1) - first) < 2 })
        else { return nil }
        return Int(first.rounded())
    }

    private static func category(
        title: String, blocks: [WorkoutTemplateBlock]
    ) -> ATHLTHCompoundExercise.Category {
        let lowered = title.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: Locale(identifier: "nb_NO")).lowercased()
        let running = blocks.contains { $0.kind == .run }
        let strength = blocks.contains { $0.kind == .exercise }
        if running && strength { return .hybrid }
        if strength { return .strength }
        guard running else { return .other }
        if blocks.contains(where: { $0.groupKind == .intervals }) ||
            fourByFourRecovery(blocks) != nil ||
            lowered.contains("interval") || lowered.contains("intervall") ||
            lowered.contains("30/30") || lowered.contains("45/15") {
            return .intervals
        }
        if lowered.contains("terskel") || lowered.contains("threshold") ||
            lowered.contains("tempo") { return .threshold }
        if lowered.contains("bakke") || lowered.contains("hill") { return .hills }
        if lowered.contains("fartslek") || lowered.contains("fartlek") {
            return .fartlek
        }
        return .running
    }

    /// Keep each source protocol intact. Recovery rows belong to Main even
    /// when the legacy timeline marked them as a separate recovery phase.
    static func mainBlocks(_ source: [WorkoutTemplateBlock]) -> [WorkoutTemplateBlock] {
        ATHLTHWorkoutTimelinePresentation.sections(for: source)
            .filter { $0.phase == .main }.flatMap(\.blocks)
            .enumerated().map { index, original in
                var block = original
                block.sequence = index + 1
                return block
            }
    }

    private static func make(
        sourceID: UUID, title: String, source: [WorkoutTemplateBlock],
        isPersonal: Bool, preferredCategory: ATHLTHCompoundExercise.Category? = nil
    ) -> ATHLTHCompoundExercise? {
        let main = mainBlocks(source)
        guard main.contains(where: {
            $0.kind == .run || $0.kind == .exercise ||
            ($0.kind == .note && $0.durationSeconds != nil)
        }) else { return nil }

        let category = preferredCategory ?? category(title: title, blocks: main)
        let protocolKey = protocolSignature(main)
        // A private section keeps its immutable source identity. Public
        // sources with the same complete prescription share one exercise.
        // Personal target speeds, pulse zones and per-step edits are part
        // of the athlete's OWN source, not grounds for public deduplication.
        // Never collapse two different private workouts just because their
        // interval timing protocol matches.
        let key = isPersonal
            ? personalPrefix + sourceID.uuidString
            : publicPrefix + digest(protocolKey)
        let family = fourByFourRecovery(main) != nil
            ? "athlth:running:interval:4x4"
            : "athlth:main:" + digest(protocolKey)
        return ATHLTHCompoundExercise(
            id: key, title: title, category: category, blocks: main,
            sourceIDs: [sourceID], isPersonal: isPersonal,
            familyID: family, protocolID: digest(protocolKey)
        )
    }

    static let bundled: [ATHLTHCompoundExercise] = {
        let runs = RunningWorkoutLibraryStore.builtInTemplates
        let workouts = WorkoutTemplateCatalogEntry.bundledCatalog
        return build(running: runs, workoutCatalog: workouts, saved: [])
    }()

    static func build(
        running: [RunningWorkoutTemplate],
        workoutCatalog: [WorkoutTemplateCatalogEntry],
        saved: [ATHLTHWorkoutMainSection]
    ) -> [ATHLTHCompoundExercise] {
        var found: [ATHLTHCompoundExercise] = []
        for run in running {
            let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: run.plannedSession())
            if let item = make(sourceID: run.id, title: run.title, source: blocks,
                               isPersonal: !run.isBuiltIn) {
                found.append(item)
            }
        }
        for workout in workoutCatalog {
            if let item = make(sourceID: workout.id, title: workout.title,
                               source: workout.blocks, isPersonal: false) {
                found.append(item)
            }
        }
        // Presets omitted from complete sessions (e.g. the alternative
        // 3-minute recovery in 4×4) must also be selectable as exercises.
        // B400 IDs are owned by ATHLTHZonedPlanLibrary's published workouts.
        // Using them here gave two distinct compound exercises the same
        // source workout ID and made published main phases look duplicated.
        for preset in ATHLTHRunningExercisePreset.allCases {
            let sourceID = UUID(uuidString: String(
                format: "B4100000-0000-0000-0000-%012d",
                (ATHLTHRunningExercisePreset.allCases.firstIndex(of: preset) ?? 0) + 1
            ))!
            let category: ATHLTHCompoundExercise.Category? =
                preset == .fourByFour || preset == .thirtyThirty ||
                preset == .fortyFiveFifteen || preset == .fiveByThree ||
                preset == .sixByFourHundred || preset == .fiveByOneKilometer ||
                preset == .shortIntervals ? .intervals : nil
            if let item = make(sourceID: sourceID, title: preset.title,
                               source: preset.blocks(in: .main),
                               isPersonal: false, preferredCategory: category) {
                found.append(item)
            }
        }
        for section in saved {
            if let item = make(sourceID: section.sourceWorkoutID,
                               title: section.title, source: section.blocks,
                               isPersonal: true) {
                found.append(ATHLTHCompoundExercise(
                    id: item.id, title: item.title, category: item.category,
                    blocks: item.blocks,
                    sourceIDs: [section.id, section.sourceWorkoutID],
                    isPersonal: true, familyID: item.familyID,
                    protocolID: item.protocolID
                ))
            }
        }

        var index: [String: Int] = [:]
        var unique: [ATHLTHCompoundExercise] = []
        for item in found {
            if let existing = index[item.id] {
                // Merge source identifiers so historical workouts remain
                // attributable even when two source recipes are identical.
                let old = unique[existing]
                unique[existing] = ATHLTHCompoundExercise(
                    id: old.id, title: old.title, category: old.category,
                    blocks: old.blocks,
                    sourceIDs: Array(Set(old.sourceIDs + item.sourceIDs)),
                    isPersonal: old.isPersonal, familyID: old.familyID,
                    protocolID: old.protocolID
                )
            } else {
                index[item.id] = unique.count
                unique.append(item)
            }
        }
        return unique.sorted {
            if $0.category.rawValue != $1.category.rawValue {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}
