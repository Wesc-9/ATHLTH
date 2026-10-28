import Foundation
import SwiftUI

/// Read-only workout presentation shared by running, strength and hybrid
/// recipes. It uses the same light plan tokens and phase-oriented timeline as
/// WorkoutTemplateBuilderView, without exposing editing controls by accident.
struct ATHLTHWorkoutRecipePreview: View {
    let title: String
    let summary: String
    let category: String
    let symbol: String
    let difficulty: String?
    let durationMinutes: Int?
    let blocks: [WorkoutTemplateBlock]
    // Hide the duplicate hero/statistics when this detailed timeline is
    // embedded below an existing workout overview sheet.
    var embeddedInDetails = false

    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @State private var advanced = false
    @State private var selectedExercise: WorkoutTemplateBlock?

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var recipeTint: Color {
        if embeddedInDetails { return ATHLTHPlanDesign.accentInk }
        switch category {
        case "running": return ATHLTHTheme.vitality
        case "hybrid": return ATHLTHTheme.accentDeep
        case "strength": return ATHLTHTheme.accentDeep
        default: return ATHLTHPlanDesign.ink
        }
    }

    private var categoryTitle: String {
        switch category {
        case "running": return tr("RUNNING", "LØPING")
        case "strength": return tr("STRENGTH", "STYRKE")
        case "hybrid": return tr("HYBRID", "HYBRID")
        case "walking": return tr("WALKING", "GÅING")
        case "mobility": return tr("MOBILITY", "MOBILITET")
        default: return tr("WORKOUT", "TRENINGSØKT")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            if !embeddedInDetails {
                introduction
                statistics
            }
            if let meters = ATHLTHRunningEstimate.distanceMeters(for: blocks),
               category == "running" || category == "walking" {
                Label(
                    tr("Estimated distance", "Estimert distanse") + " · " +
                    String(format: "%.2f km", meters / 1_000),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHint(tr(
                    "Calculated from planned speeds and distances, not a recorded result",
                    "Beregnet fra planlagte hastigheter og distanser – ikke en registrert økt"
                ))
            }
            modeControl
            if advanced {
                timeline
            } else {
                simpleOutline
            }
        }
        .sheet(item: $selectedExercise) { step in
            ATHLTHLinkedExerciseDetailView(block: step)
        }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(recipeTint)
                .frame(width: 55, height: 55)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 7) {
                Text(categoryTitle)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(recipeTint)

                Text(title)
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [ATHLTHPlanDesign.surface, ATHLTHPlanDesign.selectedSurface],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
    }

    private var statistics: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 9),
            GridItem(.flexible(), spacing: 9),
            GridItem(.flexible(), spacing: 9)
        ], spacing: 9) {
            metric(
                value: "\(blocks.count)",
                label: tr("Steps", "Deler"), icon: "square.stack"
            )
            metric(
                value: difficulty ?? tr("All levels", "Alle nivåer"),
                label: tr("Level", "Nivå"), icon: "figure.strengthtraining.traditional"
            )
            metric(
                value: durationMinutes.map { "~\($0) min" } ?? "—",
                label: tr("Duration", "Varighet"), icon: "clock"
            )
        }
    }

    private func metric(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(recipeTint)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(13)
        .athlthPlanCard(radius: 19)
    }

    private var modeControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(embeddedInDetails
                     ? tr("WORKOUT PROGRAM", "ØKTPROGRAM")
                     : tr("SESSION DETAILS", "ØKTDETALJER"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                Spacer()
                Text(advanced
                     ? tr("Targets and recovery", "Mål og pauser")
                     : tr("Quick overview", "Enkel oversikt"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Picker(tr("Detail level", "Detaljnivå"), selection: $advanced) {
                Text(tr("Simple", "Enkel")).tag(false)
                Text(tr("Advanced", "Avansert")).tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityHint(tr(
                "Choose a quick overview or full training details.",
                "Velg en enkel oversikt eller alle treningsdetaljene."
            ))
        }
    }

    // Simple mode is a concise prescription, not the advanced step-by-step timeline.
    private var simpleOutline: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: block.resolvedPhase.symbol)
                        .font(.subheadline)
                        .foregroundStyle(recipeTint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localizedTitle(block))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        if let target = block.targetText, !target.isEmpty {
                            Text(target)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                if index < blocks.count - 1 {
                    Divider().overlay(ATHLTHPlanDesign.outline)
                }
            }
        }
        .padding(15)
        .background(ATHLTHPlanDesign.surface, in: RoundedRectangle(cornerRadius: 19))
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if shouldShowPhaseHeader(at: index) {
                    Label(block.resolvedPhase.title.uppercased(),
                          systemImage: block.resolvedPhase.symbol)
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(recipeTint)
                        .padding(.top, index == 0 ? 0 : 8)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(recipeTint)
                        .frame(width: 31, height: 31)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                        .padding(.top, 10)

                    recipeStep(block)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(recipeTint.opacity(0.15))
                        .frame(width: 2)
                        .padding(.leading, 15)
                        .padding(.vertical, 7)
                }
            }
        }
    }

    // A recovery belongs to the preceding interval. Do not repeat the
    // HOVEDDEL heading after every pause; show the pause inside its work set.
    private func shouldShowPhaseHeader(at index: Int) -> Bool {
        guard blocks.indices.contains(index) else { return false }
        let phase = blocks[index].resolvedPhase
        if phase == .recovery {
            return blocks.prefix(index).allSatisfy { $0.resolvedPhase == .recovery }
        }
        let previous = blocks.prefix(index).reversed()
            .first { $0.resolvedPhase != .recovery }
        return previous?.resolvedPhase != phase
    }

    @ViewBuilder
    private func recipeStep(_ block: WorkoutTemplateBlock) -> some View {
        if block.kind == .exercise {
            Button {
                selectedExercise = block
            } label: {
                recipeStepCard(block)
            }
            .buttonStyle(.plain)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "View exercise instructions, muscles and demonstration",
                norwegian: "Vis utførelse, muskler og øvelsesinformasjon"
            ))
        } else {
            Button {
                selectedExercise = block
            } label: {
                recipeStepCard(block)
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("View step details", "Vis detaljer for øktdelen"))
        }
    }

    private func recipeStepCard(_ block: WorkoutTemplateBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if block.resolvedPhase == .recovery {
                Label(
                    tr("ACTIVE RECOVERY", "AKTIV PAUSE"),
                    systemImage: "pause.circle.fill"
                )
                .font(.caption2.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
            HStack(alignment: .top, spacing: 11) {
                thumbnail(for: block)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedTitle(block))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let target = block.targetText, !target.isEmpty {
                        Text(target)
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    if let pace = block.targetPaceSecondsPerKilometer,
                       pace.isFinite, pace > 0 {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Target speed ",
                                norwegian: "Målhastighet "
                            ) + String(format: "%.1f km/t", 3_600 / pace)
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                }
                Spacer(minLength: 0)
                if block.kind == .exercise {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }

            if advanced {
                let detail = advancedDetails(for: block)
                if !detail.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(detail, id: \.self) { value in
                            Label(value, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 50)
                }
            } else if block.kind == .note, let notes = block.notes,
                      !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 50)
            }
        }
        .padding(13)
        .athlthPlanCard(radius: 19, warm: block.resolvedPhase != .recovery)
        .overlay(alignment: .leading) {
            if block.resolvedPhase == .recovery {
                RoundedRectangle(cornerRadius: 3)
                    .fill(ATHLTHPlanDesign.accentInk.opacity(0.6))
                    .frame(width: 4)
                    .padding(.leading, 2)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for block: WorkoutTemplateBlock) -> some View {
        if let match = ATHLTHExerciseReferenceResolver.resolve(
            block, in: exerciseLibrary.allExercises
        ) {
            ExerciseArtwork(entry: match, size: 39)
        } else {
            Image(systemName: blockIcon(block))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(recipeTint)
                .frame(width: 39, height: 39)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func localizedTitle(_ block: WorkoutTemplateBlock) -> String {
        guard block.kind == .exercise else { return block.title }
        if let match = ATHLTHExerciseReferenceResolver.resolve(
            block, in: exerciseLibrary.allExercises
        ) {
            return exerciseLibrary.localizedExerciseName(match)
        }
        if ATHLTHLocalization.isNorwegian {
            return ATHLTHExerciseNameLocalization.norwegianName(
                for: block.exerciseSnapshot?.name ?? block.title
            )
        }
        return block.exerciseSnapshot?.name ?? block.title
    }

    private func blockIcon(_ block: WorkoutTemplateBlock) -> String {
        if block.resolvedPhase == .recovery { return "pause.fill" }
        if block.kind == .run && block.cardioActivity == .walking { return "figure.walk" }
        return block.kind.systemImage
    }

    private func advancedDetails(for block: WorkoutTemplateBlock) -> [String] {
        var result: [String] = []
        if let sets = block.setCount, sets > 0, block.kind == .exercise {
            result.append("\(sets) " + tr("sets", "sett"))
        }
        if let rest = block.restBetweenSetsSeconds, rest > 0 {
            result.append(tr("Rest between sets: ", "Pause mellom sett: ") +
                          "\(Int(rest)) " + tr("sec", "sek"))
        }
        if let weight = block.targetWeightKilograms, weight > 0 {
            result.append(tr("Target load: ", "Målvekt: ") + "\(weight) kg")
        }
        if let zone = block.targetHeartRateZone {
            result.append(tr("Heart-rate zone ", "Pulssone ") + "\(zone)")
        }
        if let pace = block.targetPaceSecondsPerKilometer, pace > 0 {
            let seconds = Int(pace.rounded())
            result.append(tr("Target pace: ", "Måltempo: ") +
                          String(format: "%d:%02d min/km", seconds / 60, seconds % 60))
        }
        if let group = block.groupKind {
            let rounds = block.groupRounds.map { "\($0) × " } ?? ""
            result.append(rounds + group.title)
        }
        if let load = block.loadNote, !load.isEmpty {
            result.append(load)
        }
        if let notes = block.notes, !notes.isEmpty {
            result.append(notes)
        }
        return result
    }
}

/// Convert an existing detailed running prescription into the same read-only
/// timeline as a structured workout. All reps and recovery overrides survive.
extension RunningWorkoutTemplate {
    var recipePreviewBlocks: [WorkoutTemplateBlock] {
        var steps: [WorkoutTemplateBlock] = []
        for block in blocks {
            let phase: WorkoutPhaseKind
            switch block.kind {
            case .warmup: phase = .warmup
            case .cooldown: phase = .cooldown
            case .recovery: phase = .recovery
            case .work, .steady: phase = .main
            }

            for repetition in 1...min(max(block.repetitions, 1), 60) {
                let work = block.resolvedWork(at: repetition)
                let label = block.repetitions > 1
                    ? "\(block.title) · \(repetition)/\(block.repetitions)"
                    : block.title
                steps.append(previewStep(
                    title: label, target: work, phase: phase,
                    notes: block.override(for: repetition)?.notes ?? block.notes,
                    sequence: steps.count + 1
                ))
                if let recovery = block.resolvedRecovery(after: repetition) {
                    steps.append(previewStep(
                        title: ATHLTHLocalization.choose(
                            english: "Recovery", norwegian: "Pause"
                        ),
                        target: recovery, phase: .recovery, notes: nil,
                        sequence: steps.count + 1
                    ))
                }
            }
        }
        return steps
    }

    private func previewStep(
        title: String, target: RunningStepTarget, phase: WorkoutPhaseKind,
        notes: String?, sequence: Int
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence, kind: .run, title: title,
            exerciseSlug: nil, distanceMeters: target.distanceMeters,
            repetitions: nil, durationSeconds: target.durationSeconds,
            targetWeightKilograms: nil, loadNote: nil, notes: notes,
            phase: phase,
            targetPaceSecondsPerKilometer:
                target.intensity.kind == .pace
                    ? target.intensity.paceMinSecondsPerKilometer : nil,
            targetHeartRateZone:
                target.intensity.kind == .heartRateZone
                    ? target.intensity.heartRateZone : nil
        )
    }
}
