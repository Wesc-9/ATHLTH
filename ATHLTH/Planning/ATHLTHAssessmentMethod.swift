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
        guard block.resolvedPhase == .main,
              !block.isRestOrActiveRecovery else { return [] }
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

    /// The only safe entry point for Cooper estimates linked to a
    /// configured workout recipe. An invalid scope suppresses the number.
    static func validatedCooperVO2Max(
        measuredMeters: Double,
        measuredDurationSeconds: Double,
        scope: ATHLTHAssessmentScope,
        blocks: [WorkoutTemplateBlock],
        anchorIndex: Int
    ) -> Double? {
        guard scope.canCalculateCooper(
            from: blocks, anchorIndex: anchorIndex
        ) else { return nil }
        return cooperVO2Max(
            measuredMeters: measuredMeters,
            testDurationSeconds: measuredDurationSeconds
        )
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

enum ATHLTHAssessmentValidation: Equatable {
    case valid
    case needsConfiguration(String)
    case needsMeasurements(String)
    case invalid(String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
    var isBlocking: Bool {
        if case .invalid = self { return true }
        return false
    }
    var message: String? {
        switch self {
        case .valid: return nil
        case .needsConfiguration(let message),
             .needsMeasurements(let message),
             .invalid(let message): return message
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

    /// Validation never changes the user's chosen area. It only prevents
    /// presenting invalid test data as a physiological estimate.
    func validate(
        method: ATHLTHAssessmentMethod,
        in blocks: [WorkoutTemplateBlock],
        anchorIndex: Int
    ) -> ATHLTHAssessmentValidation {
        guard blocks.indices.contains(anchorIndex) else {
            return .invalid("Målingen er ikke knyttet til en gyldig deløkt.")
        }
        let selected = includedIndices(in: blocks, anchorIndex: anchorIndex)
        guard !selected.isEmpty else {
            return .invalid("Velg minst én deløkt som skal inngå i målingen.")
        }

        if method.isEstimatedVO2 {
            guard vo2Protocol == .cooperTwelveMinutes else {
                return .needsConfiguration(
                    "Velg en gyldig beregningsmetode for estimert VO₂-maks. " +
                    "Å velge et måleområde alene gir ikke et VO₂-maks-resultat."
                )
            }
            return singleContinuousEffort(
                in: blocks, selected: selected, requiredSeconds: 720,
                testName: "Cooper-testen"
            )
        }
        switch method {
        case .threeMinuteAllOut:
            let status = singleContinuousEffort(
                in: blocks, selected: selected, requiredSeconds: 180,
                testName: "3MT-testen"
            )
            if status.isValid {
                return .needsMeasurements(
                    "3MT krever målt totaldistanse fra 180 sekunder og " +
                    "målt distanse fra 2:30 til 3:00. Planlagte verdier brukes ikke."
                )
            }
            return status
        case .sixMinuteRun:
            return singleContinuousEffort(
                in: blocks, selected: selected, requiredSeconds: 360,
                testName: "6-minutterstesten"
            )
        case .distanceTimeTrial:
            guard !includePauses else {
                return .invalid(
                    "Et testløp kan ikke bruke pauser som del av løpstiden. " +
                    "Slå av «Inkluder pauser»."
                )
            }
            guard selected.count == 1,
                  blocks[selected[0]].kind == .run,
                  blocks[selected[0]].resolvedPhase == .main,
                  !blocks[selected[0]].isRestOrActiveRecovery,
                  (blocks[selected[0]].groupRounds ?? 1) <= 1 else {
                return .invalid(
                    "Testløp krever én sammenhengende løpedel. " +
                    "Bruk en generell tempomåling for flere deløkter."
                )
            }
            return .valid
        case .estimatedOneRepMax:
            guard !includePauses && selected.count == 1 &&
                  blocks[selected[0]].kind == .exercise else {
                return .invalid(
                    "Estimert 1RM skal beregnes fra ett styrkesett, " +
                    "uten pauser eller andre øvelser."
                )
            }
            return .needsMeasurements(
                "Registrer faktisk løftet vekt og antall repetisjoner " +
                "(maksimalt 10) for et 1RM-estimat."
            )
        case .conconiStep, .lactateStep:
            guard selected.contains(where: {
                blocks[$0].kind == .run &&
                blocks[$0].resolvedPhase == .main &&
                !blocks[$0].isRestOrActiveRecovery
            }) else {
                return .invalid(
                    "Velg minst ett faktisk testtrinn i hoveddelen. " +
                    "Kun pauser, oppvarming eller nedtrapping er ikke gyldig."
                )
            }
            return .needsMeasurements(
                "Denne testen krever egne målte verdier for hvert trinn. " +
                "Ingen terskel beregnes fra en planlagt økt alene."
            )
        case .cooperTwelveMinute, .estimatedVO2Max:
            // Handled by isEstimatedVO2 above.
            return .invalid("Ukjent VO₂-maks-protokoll.")
        }
    }

    private func singleContinuousEffort(
        in blocks: [WorkoutTemplateBlock],
        selected: [Int],
        requiredSeconds: TimeInterval,
        testName: String
    ) -> ATHLTHAssessmentValidation {
        if includePauses {
            return .invalid(
                "\(testName) tillater ikke pauser i målingen. " +
                "Slå av «Inkluder pauser»."
            )
        }
        if selected.contains(where: {
            let phase = blocks[$0].resolvedPhase
            return phase == .warmup || phase == .cooldown
        }) {
            return .invalid(
                "\(testName) kan ikke inkludere oppvarming eller nedtrapping. " +
                "Velg bare testdraget."
            )
        }
        guard selected.count == 1 else {
            return .invalid(
                "\(testName) krever ett sammenhengende testdrag. " +
                "Du har valgt \(selected.count) deløkter."
            )
        }
        let effort = blocks[selected[0]]
        guard effort.kind == .run,
              effort.cardioActivity != .walking,
              !effort.isRestOrActiveRecovery,
              effort.resolvedPhase == .main,
              (effort.groupRounds ?? 1) <= 1,
              (effort.setCount ?? 1) <= 1,
              (effort.restBetweenSetsSeconds ?? 0) <= 0,
              effort.groupKind == nil else {
            return .invalid(
                "\(testName) krever ett sammenhengende løpsdrag " +
                "i hoveddelen, uten intervallpauser."
            )
        }
        guard effort.durationSeconds == requiredSeconds else {
            let current = effort.durationSeconds.map {
                ATHLTHWorkoutDurationEstimator.conciseDuration($0)
            } ?? "ukjent"
            return .invalid(
                "\(testName) krever nøyaktig " +
                ATHLTHWorkoutDurationEstimator.conciseDuration(requiredSeconds) +
                ". Valgt deløkt er \(current). Endre varigheten eller " +
                "velg en annen måling."
            )
        }
        return .valid
    }

    func canCalculateCooper(
        from blocks: [WorkoutTemplateBlock], anchorIndex: Int
    ) -> Bool {
        validate(
            method: .estimatedVO2Max, in: blocks, anchorIndex: anchorIndex
        ).isValid
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
                        if value == .chosenSteps && changed.selectedStepIDs.isEmpty {
                            if blocks[anchorIndex].measurementStepID == nil {
                                blocks[anchorIndex].measurementStepID = UUID()
                            }
                            if let id = blocks[anchorIndex].measurementStepID {
                                changed.selectedStepIDs = [id]
                            }
                        }
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
                        if !included {
                            let pausedIDs = Set(blocks.compactMap { block -> UUID? in
                                guard block.isRestOrActiveRecovery ||
                                      block.resolvedPhase == .recovery else {
                                    return nil
                                }
                                return block.measurementStepID
                            })
                            changed.selectedStepIDs.removeAll {
                                pausedIDs.contains($0)
                            }
                        }
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

                }

                if let method = blocks[anchorIndex].assessmentMethod {
                    let validation = scope.validate(
                        method: method, in: blocks, anchorIndex: anchorIndex
                    )
                    if let message = validation.message {
                        Label(
                            message,
                            systemImage: validation.isBlocking
                                ? "exclamationmark.triangle.fill" : "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            validation.isBlocking ? Color.red : Color.secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            validation.isBlocking
                                ? "athlth-assessment-invalid-protocol"
                                : "athlth-assessment-requires-data"
                        )
                    } else {
                        Label(
                            "Testoppsettet oppfyller protokollkravene. " +
                            "Resultatet krever fortsatt faktisk målte verdier.",
                            systemImage: "checkmark.circle"
                        )
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
