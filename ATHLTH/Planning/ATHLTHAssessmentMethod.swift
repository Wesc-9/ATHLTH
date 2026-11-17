import SwiftUI

/// A prescribed measurement attached to one main exercise or test step.
/// Selecting a method does NOT record a result, prescribe a pace, or infer
/// physiological values. Warm-up, rest and cool-down are excluded by default.
enum ATHLTHAssessmentMethod: String, Codable, Hashable, CaseIterable, Identifiable {
    case threeMinuteAllOut = "three_minute_all_out"
    case cooperTwelveMinute = "cooper_twelve_minute"
    case sixMinuteRun = "six_minute_run"
    case distanceTimeTrial = "distance_time_trial"
    case conconiStep = "conconi_step"
    case lactateStep = "lactate_step"
    case estimatedOneRepMax = "estimated_one_rep_max"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeMinuteAllOut: return "3MT · CS og D′"
        case .cooperTwelveMinute: return "Cooper · estimert VO₂-maks"
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
        case .cooperTwelveMinute:
            return "Løp så langt du kan på 12 minutter. Målt distanse gir et usikkert, indirekte VO₂-maks-estimat."
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

    static func available(for activity: ATHLTHExerciseActivity) -> [Self] {
        switch activity {
        case .running:
            return allCases.filter { !$0.isStrength }
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
            return allCases.filter { !$0.isStrength }
        }
        return []
    }

    /// The selected measurement never expands the measurement window to
    /// warm-up or cool-down, even when the workout contains those sections.
    static func normalized(
        _ method: Self?, for block: WorkoutTemplateBlock
    ) -> Self? {
        guard let method, available(for: block).contains(method) else { return nil }
        return method
    }

    /// Use explicit source identifiers, not a fuzzy title match; a 3-min
    /// interval and a 3MT field test have different requirements.
    static func bundledTest(for workoutID: String) -> Self? {
        switch workoutID {
        case "ASS-009": return .threeMinuteAllOut
        case "ASS-005": return .cooperTwelveMinute
        case "ASS-001": return .sixMinuteRun
        case "ASS-003": return .distanceTimeTrial
        case "ASS-006": return .conconiStep
        case "ASS-010": return .lactateStep
        default: return nil
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
                Text("Målingen gjelder kun hovedøvelsen eller testdraget. Oppvarming og nedtrapping er ikke med.")
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
