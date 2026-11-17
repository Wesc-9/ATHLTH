import SwiftUI

/// A user-selected measurement, independent of the workout/test name.
/// Keeping the old enum case lets saved recipes decode. A selected
/// measurement is NOT an actual recorded physiological result.
enum ATHLTHAssessmentMethod: String, Codable, Hashable, CaseIterable, Identifiable {
    case threeMinuteAllOut = "three_minute_all_out"
    case cooperTwelveMinute = "cooper_twelve_minute" // legacy decode
    case estimatedVO2Max = "estimated_vo2_max"
    case sixMinuteRun = "six_minute_run"
    case distanceTimeTrial = "distance_time_trial"
    case conconiStep = "conconi_step"
    case lactateStep = "lactate_step"
    case estimatedOneRepMax = "estimated_one_rep_max"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeMinuteAllOut: return "3MT · CS og D′"
        case .cooperTwelveMinute, .estimatedVO2Max: return "Estimert VO₂-maks"
        case .sixMinuteRun: return "6 minutter · distanse og snittfart"
        case .distanceTimeTrial: return "Testløp · tid, tempo og rekord"
        case .conconiStep: return "Conconi · puls og fart per trinn"
        case .lactateStep: return "Laktattest · laktat, puls og fart"
        case .estimatedOneRepMax: return "Styrke · estimert 1RM"
        }
    }

    var explanatoryText: String {
        switch self {
        case .threeMinuteAllOut:
            return "Mål distansen i testdraget på 180 sekunder og separat de siste 30 sekundene. CS og D′ beregnes fra disse målingene."
        case .cooperTwelveMinute, .estimatedVO2Max:
            return "Estimert VO₂-maks er en måling, ikke en bestemt øvelse. Velg hvilke deløkter som inngår, og hvilken validert testprotokoll som skal brukes."
        case .sixMinuteRun:
            return "Registrer kun distanse fra de 6 testminuttene og beregn gjennomsnittsfart. Ikke beregn VO₂-maks uten en validert modell."
        case .distanceTimeTrial:
            return "Mål tid og distanse fra selve testløpet. Vis snittempo og sammenlign med tidligere forsøk på samme distanse."
        case .conconiStep:
            return "Registrer faktisk fart og puls for hvert trinn. En terskel vurderes først når hele kurven er tilgjengelig."
        case .lactateStep:
            return "Legg inn målte laktatverdier samt puls og fart for hvert trinn. Ingen automatisk terskel uten måleserien."
        case .estimatedOneRepMax:
            return "Beregn et anslag på 1RM fra faktisk løftet vekt og antall repetisjoner. Mer usikkert ved mange repetisjoner."
        }
    }

    var isStrength: Bool { self == .estimatedOneRepMax }
    var isEstimatedVO2: Bool {
        self == .estimatedVO2Max || self == .cooperTwelveMinute
    }
    private static var availableRunning: [Self] {
        allCases.filter { !$0.isStrength && $0 != .cooperTwelveMinute }
    }

    static func available(for activity: ATHLTHExerciseActivity) -> [Self] {
        switch activity {
        case .running:
            return availableRunning
        case .strength:
            return [.estimatedOneRepMax]
        default:
            return []
        }
    }

    static func available(for block: WorkoutTemplateBlock) -> [Self] {
        guard block.resolvedPhase == .main else { return [] }
        if block.kind == .exercise { return [.estimatedOneRepMax] }
        if block.kind == .run, block.cardioActivity != .walking {
            return availableRunning
        }
        return []
    }

    /// A measurement's data window is controlled by its saved scope, not
    /// the name of this method. The anchor must still be a real main step.
    static func normalized(
        _ method: Self?, for block: WorkoutTemplateBlock
    ) -> Self? {
        guard let method else { return nil }
        if method == .cooperTwelveMinute {
            return available(for: block).contains(.estimatedVO2Max)
                ? .cooperTwelveMinute : nil
        }
        return available(for: block).contains(method) ? method : nil
    }

    /// Use explicit source identifiers, not a fuzzy title match; a 3-min
    /// interval and a 3MT field test have different requirements.
    static func bundledTest(for workoutID: String) -> Self? {
        switch workoutID {
        case "ASS-009": return .threeMinuteAllOut
        case "ASS-005": return .estimatedVO2Max
        case "ASS-001": return .sixMinuteRun
        case "ASS-003": return .distanceTimeTrial
        case "ASS-006": return .conconiStep
        case "ASS-010": return .lactateStep
        default: return nil
        }
    }
}

/// Deliberately narrow calculators. Callers must supply measurements
/// from the actual MAIN test block; no whole-workout aggregates or guessed
/// values are accepted as physiological results.
enum ATHLTHAssessmentCalculation {
    /// Cooper 12-minute field estimate in ml/kg/min. Do not use for
    /// six-minute tests or if the athlete stopped early.
    static func cooperVO2Max(
        measuredMeters: Double,
        testDurationSeconds: Double
    ) -> Double? {
        guard testDurationSeconds == 720,
              measuredMeters.isFinite, (600...6_000).contains(measuredMeters)
        else { return nil }
        let value = (measuredMeters - 504.9) / 44.73
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Epley estimate; valid only for a limited maximal-repetition effort.
    /// One repetition is a directly reported top lift, not a 1RM prediction.
    static func estimatedOneRepMax(
        weightKilograms: Double, completedRepetitions: Int
    ) -> Double? {
        guard weightKilograms.isFinite, weightKilograms > 0,
              weightKilograms <= 1_000,
              (1...10).contains(completedRepetitions) else { return nil }
        if completedRepetitions == 1 { return weightKilograms }
        return weightKilograms * (1 + Double(completedRepetitions) / 30.0)
    }

    static func measuredAveragePace(
        distanceMeters: Double, elapsedSeconds: Double
    ) -> Double? {
        guard distanceMeters.isFinite, elapsedSeconds.isFinite,
              distanceMeters > 0, elapsedSeconds > 0 else { return nil }
        return elapsedSeconds * 1_000 / distanceMeters
    }
}

/// Scope selection describes which recorded segments can contribute to a
/// measurement. It is part of the workout recipe, not derived from its title.
enum ATHLTHAssessmentArea: String, Codable, Hashable, CaseIterable, Identifiable {
    case currentStep = "current_step"
    case mainSection = "main_section"
    case chosenSteps = "chosen_steps"
    case entireWorkout = "entire_workout"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .currentStep: return "Bare denne deløkten"
        case .mainSection: return "Hele hoveddelen"
        case .chosenSteps: return "Velg deløkter"
        case .entireWorkout: return "Hele treningsøkten"
        }
    }
}

/// Estimation protocols must remain separate from the requested metric.
/// A Cooper formula is NOT valid for arbitrary intervals or a 6-minute run.
enum ATHLTHVO2Protocol: String, Codable, Hashable, CaseIterable, Identifiable {
    case unspecified = "not_selected"
    case cooperTwelveMinutes = "cooper_12_minute"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unspecified: return "Ingen beregningsmetode valgt"
        case .cooperTwelveMinutes: return "Cooper · 12 minutter"
        }
    }
}

struct ATHLTHAssessmentScope: Codable, Hashable {
    var area: ATHLTHAssessmentArea = .currentStep
    var includePauses: Bool = false
    /// Stable IDs refer to authored source steps, not transient editor rows.
    var selectedStepIDs: [UUID] = []
    var vo2Protocol: ATHLTHVO2Protocol? = nil

    /// Respect exact segments, including explicit pause opt-in.
    /// A .recovery step between two main efforts counts as a main-set rest.
    func includedIndices(
        in blocks: [WorkoutTemplateBlock], anchorIndex: Int
    ) -> [Int] {
        guard blocks.indices.contains(anchorIndex) else { return [] }
        func isPause(_ block: WorkoutTemplateBlock) -> Bool {
            block.isRestOrActiveRecovery || block.resolvedPhase == .recovery
        }
        func mainSetPause(_ index: Int) -> Bool {
            guard isPause(blocks[index]) else { return false }
            let before = blocks[..<index].last {
                $0.resolvedPhase != .recovery && !$0.isRestOrActiveRecovery
            }
            let after = blocks[(index+1)...].first {
                $0.resolvedPhase != .recovery && !$0.isRestOrActiveRecovery
            }
            return before?.resolvedPhase == .main &&
                after?.resolvedPhase == .main
        }
        return blocks.indices.filter { index in
            let block = blocks[index]
            if !includePauses && isPause(block) { return false }
            switch area {
            case .currentStep: return index == anchorIndex
            case .mainSection:
                return block.resolvedPhase == .main ||
                    (includePauses && mainSetPause(index))
            case .chosenSteps:
                guard let id = block.measurementStepID else { return false }
                return selectedStepIDs.contains(id)
            case .entireWorkout: return true
            }
        }
    }

    /// A formula cannot silently use a different scope or include breaks.
    /// Cooper 12 min is valid only for a single continuous 720 s effort.
    func canCalculateCooper(
        from blocks: [WorkoutTemplateBlock], anchorIndex: Int
    ) -> Bool {
        let selected = includedIndices(in: blocks, anchorIndex: anchorIndex)
        guard vo2Protocol == .cooperTwelveMinutes,
              selected.count == 1, let index = selected.first else { return false }
        let block = blocks[index]
        return block.kind == .run && !block.isRestOrActiveRecovery &&
            block.cardioActivity != .walking &&
            block.durationSeconds == 720
    }
}

/// Compact drop-down for the owner of one measurement, enabling cross-step
/// selection with stable identity and optional pauses. New exercise defaults
/// may choose an area but individual steps are selected in Workout Studio.
struct ATHLTHAssessmentScopeEditor: View {
    @Binding var blocks: [WorkoutTemplateBlock]
    let anchorIndex: Int

    private var scope: ATHLTHAssessmentScope {
        guard blocks.indices.contains(anchorIndex) else { return .init() }
        return blocks[anchorIndex].assessmentScope ?? .init()
    }

    private func setScope(_ updated: ATHLTHAssessmentScope) {
        guard blocks.indices.contains(anchorIndex) else { return }
        var next = updated
        if next.area == .chosenSteps {
            for index in blocks.indices where blocks[index].measurementStepID == nil {
                blocks[index].measurementStepID = UUID()
            }
            if next.selectedStepIDs.isEmpty,
               let id = blocks[anchorIndex].measurementStepID {
                next.selectedStepIDs = [id]
            }
        }
        blocks[anchorIndex].assessmentScope = next
    }

    private func toggleStep(_ index: Int, _ include: Bool) {
        guard blocks.indices.contains(index),
              let id = blocks[index].measurementStepID else { return }
        var changed = scope
        if include {
            if !changed.selectedStepIDs.contains(id) {
                changed.selectedStepIDs.append(id)
            }
        } else {
            changed.selectedStepIDs.removeAll { $0 == id }
        }
        setScope(changed)
    }

    var body: some View {
        if blocks.indices.contains(anchorIndex) {
            VStack(alignment: .leading, spacing: 11) {
                Picker("Hvilke deler skal måles?", selection: Binding(
                    get: { scope.area },
                    set: { value in
                        var changed = scope
                        changed.area = value
                        setScope(changed)
                    }
                )) {
                    ForEach(ATHLTHAssessmentArea.allCases) { area in
                        Text(area.label).tag(area)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("athlth-assessment-area-selector")

                Toggle("Inkluder pauser / aktiv hvile", isOn: Binding(
                    get: { scope.includePauses },
                    set: { included in
                        var changed = scope
                        changed.includePauses = included
                        setScope(changed)
                    }
                ))
                .font(.subheadline)
                .accessibilityIdentifier("athlth-assessment-include-breaks")

                if scope.area == .chosenSteps {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Velg deløkter som skal inngå")
                            .font(.caption.weight(.semibold))
                        ForEach(blocks.indices, id: \.self) { index in
                            let block = blocks[index]
                            let isPause = block.isRestOrActiveRecovery ||
                                block.resolvedPhase == .recovery
                            Toggle(isOn: Binding(
                                get: {
                                    block.measurementStepID.map {
                                        scope.selectedStepIDs.contains($0)
                                    } ?? false
                                },
                                set: { toggleStep(index, $0) }
                            )) {
                                Text("\(index + 1). \(block.title)")
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                            .disabled(isPause && !scope.includePauses)
                        }
                    }
                    .accessibilityIdentifier("athlth-assessment-chosen-steps")
                }

                if blocks[anchorIndex].assessmentMethod?.isEstimatedVO2 == true {
                    Picker("Beregningsmetode for VO₂-maks", selection: Binding(
                        get: { scope.vo2Protocol ?? .unspecified },
                        set: { value in
                            var changed = scope
                            changed.vo2Protocol = value
                            setScope(changed)
                        }
                    )) {
                        ForEach(ATHLTHVO2Protocol.allCases) { formula in
                            Text(formula.title).tag(formula)
                        }
                    }
                    .pickerStyle(.menu)

                    if scope.vo2Protocol == .cooperTwelveMinutes &&
                       !scope.canCalculateCooper(
                           from: blocks, anchorIndex: anchorIndex
                       ) {
                        Text("Cooper-formelen krever ett sammenhengende testdrag på nøyaktig 12 minutter uten pauser. Valget lagres, men det beregnes ikke VO₂-maks før datagrunnlaget oppfyller kravene.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Måleområdet brukes for registrerte resultater. Oppvarming og nedtrapping er bare med hvis du velger dem. En fysiologisk beregning krever i tillegg en gyldig testprotokoll.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("athlth-assessment-scope-editor")
        }
    }
}

/// Shared compact picker for new exercises and individual MAIN workout steps.
struct ATHLTHAssessmentMethodPicker: View {
    @Binding var selection: ATHLTHAssessmentMethod?
    let available: [ATHLTHAssessmentMethod]
    @State private var expanded = false

    var body: some View {
        if !available.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                Picker("Ekstramåling", selection: $selection) {
                    Text("Ingen ekstra måling").tag(ATHLTHAssessmentMethod?.none)
                    ForEach(available) { method in
                        Text(method.title)
                            .tag(Optional(method))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("athlth-assessment-method-picker")
                if let selection {
                    Text(selection.explanatoryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Velg måleområde i øktbyggeren: én deløkt, hoveddel, valgte deløkter eller hele økten. Du bestemmer om pauser skal være med.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } label: {
                Label("Ekstramålinger", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("athlth-assessment-selector")
        }
    }
}
