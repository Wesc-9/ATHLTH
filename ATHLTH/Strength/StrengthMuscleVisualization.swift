import SwiftUI

enum StrengthMuscleRegion: String, CaseIterable, Identifiable {
    case chest
    case frontDelts
    case sideDelts
    case rearDelts
    case biceps
    case triceps
    case forearms
    case traps
    case lats
    case upperBack
    case lowerBack
    case abs
    case obliques
    case serratus
    case glutes
    case outerHip
    case innerThigh
    case hipFlexors
    case quads
    case hamstrings
    case calves
    case shins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: return "Chest"
        case .frontDelts: return "Front delts"
        case .sideDelts: return "Side delts"
        case .rearDelts: return "Rear delts"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .traps: return "Traps"
        case .lats: return "Lats"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .serratus: return "Serratus"
        case .glutes: return "Glutes"
        case .outerHip: return "Outer hip"
        case .innerThigh: return "Inner thigh"
        case .hipFlexors: return "Hip flexors"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .calves: return "Calves"
        case .shins: return "Shins"
        }
    }
}

struct StrengthMuscleActivation: Identifiable {
    let region: StrengthMuscleRegion
    let score: Double

    var id: String { region.rawValue }
}

struct StrengthMuscleProfile {
    let activations: [StrengthMuscleActivation]

    static let empty =
        StrengthMuscleProfile(
            activations: []
        )

    private var maximumScore: Double {
        activations
            .map(\.score)
            .max() ?? 0
    }

    func intensity(
        for region: StrengthMuscleRegion
    ) -> Double {
        guard maximumScore > 0,
              let score =
                activations.first(
                    where: {
                        $0.region == region
                    }
                )?
                .score
        else {
            return 0
        }

        return min(
            max(
                score / maximumScore,
                0
            ),
            1
        )
    }

    func absoluteScore(
        for region: StrengthMuscleRegion
    ) -> Double {
        let score =
            activations.first(
                where: {
                    $0.region == region
                }
            )?
            .score ?? 0

        return min(
            max(score, 0),
            1
        )
    }

    var topActivations:
        [StrengthMuscleActivation] {
        activations
            .sorted {
                $0.score > $1.score
            }
    }
}

struct StrengthExerciseMuscleSummary:
    Identifiable {
    let id: UUID
    let name: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let completedSets: Int
    let totalReps: Int
    let volumeKilograms: Double
}

struct StrengthMuscleSessionSummary {
    let profile: StrengthMuscleProfile
    let exercises:
        [StrengthExerciseMuscleSummary]
    let totalSets: Int
    let totalReps: Int
    let totalVolumeKilograms: Double

    static let empty =
        StrengthMuscleSessionSummary(
            profile: .empty,
            exercises: [],
            totalSets: 0,
            totalReps: 0,
            totalVolumeKilograms: 0
        )
}

enum StrengthMuscleProfileBuilder {
    private static let primaryWeight = 1.0
    private static let secondaryWeight = 0.55

    static func make(
        workout: StrengthWorkoutLog,
        library: [ExerciseLibraryEntry]
    ) -> StrengthMuscleSessionSummary {
        let performed =
            performedExercises(
                in: workout
            )

        guard !performed.isEmpty else {
            return .empty
        }

        let catalogByName =
            Dictionary(
                grouping: library
            ) {
                normalizedName(
                    $0.exercise.name
                )
            }

        var scores:
            [StrengthMuscleRegion: Double] = [:]
        var summaries:
            [StrengthExerciseMuscleSummary] = []

        for log in performed {
            let catalog =
                catalogByName[
                    normalizedName(
                        log.exercise.name
                    )
                ]?
                .first

            let primary =
                uniqueMuscles(
                    log.exercise
                        .primaryMuscles
                        .isEmpty
                        ? (
                            catalog?
                                .exercise
                                .primaryMuscles ??
                            []
                        )
                        : log.exercise
                            .primaryMuscles
                )

            let snapshotSecondary =
                log.exercise
                    .secondaryMuscles ??
                []
            let secondary =
                uniqueMuscles(
                    snapshotSecondary
                        .isEmpty
                        ? (
                            catalog?
                                .exercise
                                .secondaryMuscles ??
                            []
                        )
                        : snapshotSecondary
                )

            let meaningfulSets =
                log.sets.filter {
                    $0.isCompleted ||
                    $0.completedReps != nil ||
                    $0.completedWeightKilograms != nil
                }

            let setCount: Int
            if workout.trackingMode ==
                .advanced {
                setCount =
                    meaningfulSets.count
            } else {
                setCount =
                    max(
                        meaningfulSets.count,
                        log.sets.count,
                        1
                    )
            }

            let workload =
                Double(
                    max(setCount, 1)
                )

            var mappedAny = false

            for raw in primary {
                let regions =
                    StrengthMuscleResolver
                        .regions(
                            for: raw
                        )

                for region in regions {
                    scores[region, default: 0] +=
                        primaryWeight *
                        workload
                    mappedAny = true
                }
            }

            for raw in secondary {
                let regions =
                    StrengthMuscleResolver
                        .regions(
                            for: raw
                        )

                for region in regions {
                    scores[region, default: 0] +=
                        secondaryWeight *
                        workload
                    mappedAny = true
                }
            }

            if !mappedAny,
               let bodyPart =
                    catalog?.bodyPart {
                let fallback =
                    StrengthMuscleResolver
                        .fallbackRegions(
                            forBodyPart:
                                bodyPart
                        )

                for region in fallback {
                    scores[region, default: 0] +=
                        0.35 *
                        workload
                }
            }

            let setsForMetrics =
                meaningfulSets.isEmpty
                    ? log.sets
                    : meaningfulSets

            let reps =
                setsForMetrics.reduce(
                    0
                ) {
                    partial,
                    set in
                    partial +
                        (
                            set.completedReps ??
                            set.plannedReps ??
                            0
                        )
                }

            let volume =
                setsForMetrics.reduce(
                    0.0
                ) {
                    partial,
                    set in
                    let reps =
                        set.completedReps ??
                        set.plannedReps ??
                        0
                    let weight =
                        set.completedWeightKilograms ??
                        set.plannedWeightKilograms ??
                        0

                    guard reps > 0,
                          weight > 0
                    else {
                        return partial
                    }

                    return partial +
                        Double(reps) *
                        weight
                }

            summaries.append(
                StrengthExerciseMuscleSummary(
                    id: log.id,
                    name:
                        log.exercise.name,
                    primaryMuscles:
                        primary,
                    secondaryMuscles:
                        secondary,
                    completedSets:
                        setCount,
                    totalReps: reps,
                    volumeKilograms:
                        volume
                )
            )
        }

        let activations =
            scores
                .filter {
                    $0.value > 0
                }
                .map {
                    StrengthMuscleActivation(
                        region: $0.key,
                        score: $0.value
                    )
                }

        return StrengthMuscleSessionSummary(
            profile:
                StrengthMuscleProfile(
                    activations:
                        activations
                ),
            exercises:
                summaries,
            totalSets:
                summaries.reduce(0) {
                    $0 +
                    $1.completedSets
                },
            totalReps:
                summaries.reduce(0) {
                    $0 +
                    $1.totalReps
                },
            totalVolumeKilograms:
                summaries.reduce(0) {
                    $0 +
                    $1.volumeKilograms
                }
        )
    }

    private static func performedExercises(
        in workout: StrengthWorkoutLog
    ) -> [StrengthExerciseLog] {
        if workout.trackingMode ==
            .advanced {
            return workout.exercises
                .filter {
                    $0.isCompleted ||
                    $0.sets.contains(
                        where: {
                            $0.isCompleted ||
                            $0.completedReps != nil ||
                            $0.completedWeightKilograms != nil
                        }
                    )
                }
        }

        return workout.exercises
    }

    private static func normalizedName(
        _ value: String
    ) -> String {
        value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }

    private static func uniqueMuscles(
        _ values: [String]
    ) -> [String] {
        var seen: Set<String> = []

        return values.filter {
            let key =
                $0
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased()

            guard !key.isEmpty,
                  !seen.contains(key)
            else {
                return false
            }

            seen.insert(key)
            return true
        }
    }
}

enum StrengthMuscleResolver {
    static func regions(
        for raw: String
    ) -> [StrengthMuscleRegion] {
        let value =
            normalize(raw)

        if contains(
            value,
            "pectoralis",
            "chest",
            "pec"
        ) {
            return [.chest]
        }

        if contains(
            value,
            "anterior deltoid",
            "front delt"
        ) {
            return [.frontDelts]
        }

        if contains(
            value,
            "lateral deltoid",
            "side delt",
            "medial delt"
        ) {
            return [.sideDelts]
        }

        if contains(
            value,
            "posterior deltoid",
            "rear delt"
        ) {
            return [.rearDelts]
        }

        if contains(
            value,
            "deltoid",
            "shoulder"
        ) {
            return [
                .frontDelts,
                .sideDelts,
                .rearDelts
            ]
        }

        if contains(
            value,
            "triceps"
        ) {
            return [.triceps]
        }

        if contains(
            value,
            "biceps brachii",
            "bicep",
            "brachialis"
        ) {
            return [.biceps]
        }

        if contains(
            value,
            "brachioradialis",
            "forearm",
            "wrist flexor",
            "wrist extensor",
            "grip"
        ) {
            return [.forearms]
        }

        if contains(
            value,
            "latissimus",
            "lats",
            "lat "
        ) {
            return [.lats]
        }

        if contains(
            value,
            "trapezius",
            "trap"
        ) {
            return [.traps]
        }

        if contains(
            value,
            "rhomboid",
            "upper back",
            "middle back",
            "teres major",
            "teres minor",
            "infraspinatus",
            "supraspinatus",
            "subscapularis",
            "rotator cuff"
        ) {
            return [.upperBack]
        }

        if contains(
            value,
            "erector spinae",
            "quadratus lumborum",
            "lower back",
            "spinal erector"
        ) {
            return [.lowerBack]
        }

        if contains(
            value,
            "rectus abdominis",
            "transversus abdominis",
            "transverse abdominis",
            "deep core",
            "abdominal",
            "abs"
        ) {
            return [.abs]
        }

        if contains(
            value,
            "oblique"
        ) {
            return [.obliques]
        }

        if contains(
            value,
            "serratus"
        ) {
            return [.serratus]
        }

        if contains(
            value,
            "gluteus medius",
            "gluteus minimus",
            "glute med",
            "glute min",
            "abductor",
            "tensor fascia",
            "outer hip"
        ) {
            return [.outerHip]
        }

        if contains(
            value,
            "gluteus maximus",
            "glute max",
            "glutes",
            "glute "
        ) {
            return [.glutes]
        }

        if contains(
            value,
            "adductor",
            "inner thigh",
            "groin"
        ) {
            return [.innerThigh]
        }

        if contains(
            value,
            "hip flexor",
            "iliopsoas",
            "psoas",
            "iliacus"
        ) {
            return [.hipFlexors]
        }

        if contains(
            value,
            "quadriceps",
            "quad"
        ) {
            return [.quads]
        }

        if contains(
            value,
            "hamstring"
        ) {
            return [.hamstrings]
        }

        if contains(
            value,
            "gastrocnemius",
            "soleus",
            "calf",
            "calves"
        ) {
            return [.calves]
        }

        if contains(
            value,
            "tibialis",
            "shin"
        ) {
            return [.shins]
        }

        if value == "back" {
            return [
                .lats,
                .upperBack,
                .lowerBack
            ]
        }

        if value == "core" {
            return [
                .abs,
                .obliques
            ]
        }

        if value == "arms" ||
            value == "upper arms" {
            return [
                .biceps,
                .triceps
            ]
        }

        if value == "legs" ||
            value == "upper legs" {
            return [
                .quads,
                .hamstrings,
                .glutes
            ]
        }

        return []
    }

    static func fallbackRegions(
        forBodyPart raw: String
    ) -> [StrengthMuscleRegion] {
        let value = normalize(raw)

        switch value {
        case "chest":
            return [.chest]
        case "shoulders":
            return [
                .frontDelts,
                .sideDelts,
                .rearDelts
            ]
        case "back":
            return [
                .lats,
                .upperBack,
                .lowerBack
            ]
        case "core":
            return [
                .abs,
                .obliques
            ]
        case "lower arms":
            return [.forearms]
        case "lower legs":
            return [
                .calves,
                .shins
            ]
        case "upper arms":
            return [
                .biceps,
                .triceps
            ]
        case "upper legs":
            return [
                .quads,
                .hamstrings,
                .glutes,
                .innerThigh,
                .outerHip
            ]
        case "full body":
            return [
                .chest,
                .lats,
                .abs,
                .glutes,
                .quads
            ]
        default:
            return regions(for: value)
        }
    }

    private static func normalize(
        _ raw: String
    ) -> String {
        raw
            .lowercased()
            .replacingOccurrences(
                of: "_",
                with: " "
            )
            .replacingOccurrences(
                of: "-",
                with: " "
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    private static func contains(
        _ value: String,
        _ needles: String...
    ) -> Bool {
        needles.contains {
            value.contains($0)
        }
    }
}

enum StrengthMuscleMapStyle {
    case activation
    case recoveryLoad
}

struct StrengthMuscleMapView: View {
    let profile: StrengthMuscleProfile
    var compact = false
    var style: StrengthMuscleMapStyle = .activation

    var body: some View {
        HStack(spacing: compact ? 5 : 12) {
            bodyFigure(
                side: .front,
                label: "Front"
            )

            bodyFigure(
                side: .back,
                label: "Back"
            )
        }
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            accessibilityText
        )
    }

    private func bodyFigure(
        side: StrengthBodySide,
        label: String
    ) -> some View {
        VStack(spacing: compact ? 2 : 6) {
            StrengthBodyFigureCanvas(
                profile: profile,
                side: side,
                style: style
            )

            if !compact {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
        }
    }

    private var accessibilityText: String {
        let top =
            profile.topActivations
                .prefix(5)
                .map {
                    $0.region.title
                }

        guard !top.isEmpty else {
            return
                "Muscle map with no recorded muscle focus."
        }

        return
            "Muscle map. Main areas: " +
            top.joined(
                separator: ", "
            )
    }
}

private enum StrengthBodySide {
    case front
    case back
}

private struct StrengthBodyFigureCanvas:
    View {
    let profile: StrengthMuscleProfile
    let side: StrengthBodySide
    let style: StrengthMuscleMapStyle

    var body: some View {
        Canvas {
            context,
            size in

            drawBase(
                context: &context,
                size: size
            )

            for region in
                StrengthMuscleRegion
                    .allCases {
                let intensity: Double

                switch style {
                case .activation:
                    intensity =
                        profile.intensity(
                            for: region
                        )

                    guard intensity > 0.01 else {
                        continue
                    }

                case .recoveryLoad:
                    intensity =
                        profile.absoluteScore(
                            for: region
                        )

                    // Keep untouched / trivial-load areas neutral. Rendering
                    // every zero-value region was what made the recovery body
                    // look like a green/orange block figure.
                    guard intensity >= 0.08 else {
                        continue
                    }
                }

                draw(
                    region: region,
                    intensity:
                        intensity,
                    context:
                        &context,
                    size: size
                )
            }
        }
        .aspectRatio(
            0.48,
            contentMode: .fit
        )
    }

    private func drawBase(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        if style == .recoveryLoad {
            drawRecoverySilhouette(
                context: &context,
                size: size
            )
            return
        }

        let base =
            style == .recoveryLoad
                ? Color(
                    red: 0.89,
                    green: 0.87,
                    blue: 0.83
                )
                : Color(
                    red: 0.83,
                    green: 0.84,
                    blue: 0.85
                )
        let outline =
            Color.black.opacity(
                style == .recoveryLoad
                    ? 0.055
                    : 0.09
            )

        let recoverySilhouette: Bool
        switch style {
        case .activation:
            recoverySilhouette = false
        case .recoveryLoad:
            recoverySilhouette = true
        }

        let head =
            CGRect(
                x:
                    size.width *
                    (recoverySilhouette ? 0.41 : 0.39),
                y: size.height * 0.02,
                width:
                    size.width *
                    (recoverySilhouette ? 0.18 : 0.22),
                height:
                    size.width *
                    (recoverySilhouette ? 0.18 : 0.22)
            )
        context.fill(
            Path(
                ellipseIn: head
            ),
            with: .color(
                base
            )
        )

        var torso = Path()
        torso.move(
            to: CGPoint(
                x: size.width * 0.50,
                y: size.height * 0.15
            )
        )
        torso.addCurve(
            to: CGPoint(
                x:
                    size.width *
                    (recoverySilhouette ? 0.72 : 0.75),
                y: size.height * 0.28
            ),
            control1:
                CGPoint(
                    x: size.width * 0.63,
                    y: size.height * 0.16
                ),
            control2:
                CGPoint(
                    x:
                        size.width *
                        (recoverySilhouette ? 0.70 : 0.73),
                    y: size.height * 0.20
                )
        )
        torso.addCurve(
            to: CGPoint(
                x:
                    size.width *
                    (recoverySilhouette ? 0.61 : 0.64),
                y: size.height * 0.58
            ),
            control1:
                CGPoint(
                    x:
                        size.width *
                        (recoverySilhouette ? 0.68 : 0.73),
                    y: size.height * 0.40
                ),
            control2:
                CGPoint(
                    x:
                        size.width *
                        (recoverySilhouette ? 0.63 : 0.68),
                    y: size.height * 0.52
                )
        )
        torso.addLine(
            to: CGPoint(
                x:
                    size.width *
                    (recoverySilhouette ? 0.39 : 0.36),
                y: size.height * 0.58
            )
        )
        torso.addCurve(
            to: CGPoint(
                x:
                    size.width *
                    (recoverySilhouette ? 0.28 : 0.25),
                y: size.height * 0.28
            ),
            control1:
                CGPoint(
                    x:
                        size.width *
                        (recoverySilhouette ? 0.37 : 0.32),
                    y: size.height * 0.52
                ),
            control2:
                CGPoint(
                    x:
                        size.width *
                        (recoverySilhouette ? 0.32 : 0.27),
                    y: size.height * 0.40
                )
        )
        torso.addCurve(
            to: CGPoint(
                x: size.width * 0.50,
                y: size.height * 0.15
            ),
            control1:
                CGPoint(
                    x:
                        size.width *
                        (recoverySilhouette ? 0.30 : 0.27),
                    y: size.height * 0.20
                ),
            control2:
                CGPoint(
                    x: size.width * 0.37,
                    y: size.height * 0.16
                )
        )
        torso.closeSubpath()

        context.fill(
            torso,
            with: .color(base)
        )
        context.stroke(
            torso,
            with: .color(outline),
            lineWidth: 0.8
        )

        drawCapsule(
            x: recoverySilhouette ? 0.18 : 0.16,
            y: 0.23,
            width: recoverySilhouette ? 0.11 : 0.14,
            height: recoverySilhouette ? 0.36 : 0.38,
            rotation: -0.08,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: recoverySilhouette ? 0.71 : 0.70,
            y: 0.23,
            width: recoverySilhouette ? 0.11 : 0.14,
            height: recoverySilhouette ? 0.36 : 0.38,
            rotation: 0.08,
            fill: base,
            context: &context,
            size: size
        )

        drawCapsule(
            x: recoverySilhouette ? 0.35 : 0.33,
            y: 0.55,
            width: recoverySilhouette ? 0.13 : 0.16,
            height: 0.41,
            rotation: -0.015,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: recoverySilhouette ? 0.52 : 0.51,
            y: 0.55,
            width: recoverySilhouette ? 0.13 : 0.16,
            height: 0.41,
            rotation: 0.015,
            fill: base,
            context: &context,
            size: size
        )
    }

    private func drawRecoverySilhouette(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let base =
            Color(
                red: 0.90,
                green: 0.89,
                blue: 0.86
            )
        let outline =
            Color.black.opacity(0.075)

        let head =
            CGRect(
                x: size.width * 0.39,
                y: size.height * 0.015,
                width: size.width * 0.22,
                height: size.width * 0.23
            )
        context.fill(
            Path(ellipseIn: head),
            with: .color(base)
        )
        context.stroke(
            Path(ellipseIn: head),
            with: .color(outline),
            lineWidth: 0.7
        )

        drawRounded(
            x: 0.455,
            y: 0.115,
            width: 0.09,
            height: 0.07,
            radius: 0.035,
            fill: base,
            context: &context,
            size: size
        )

        var torso = Path()
        torso.move(
            to: CGPoint(
                x: size.width * 0.46,
                y: size.height * 0.155
            )
        )
        torso.addCurve(
            to: CGPoint(
                x: size.width * 0.29,
                y: size.height * 0.235
            ),
            control1: CGPoint(
                x: size.width * 0.39,
                y: size.height * 0.16
            ),
            control2: CGPoint(
                x: size.width * 0.32,
                y: size.height * 0.19
            )
        )
        torso.addCurve(
            to: CGPoint(
                x: size.width * 0.38,
                y: size.height * 0.53
            ),
            control1: CGPoint(
                x: size.width * 0.32,
                y: size.height * 0.34
            ),
            control2: CGPoint(
                x: size.width * 0.34,
                y: size.height * 0.47
            )
        )
        torso.addCurve(
            to: CGPoint(
                x: size.width * 0.50,
                y: size.height * 0.575
            ),
            control1: CGPoint(
                x: size.width * 0.41,
                y: size.height * 0.55
            ),
            control2: CGPoint(
                x: size.width * 0.46,
                y: size.height * 0.575
            )
        )
        torso.addCurve(
            to: CGPoint(
                x: size.width * 0.62,
                y: size.height * 0.53
            ),
            control1: CGPoint(
                x: size.width * 0.54,
                y: size.height * 0.575
            ),
            control2: CGPoint(
                x: size.width * 0.59,
                y: size.height * 0.55
            )
        )
        torso.addCurve(
            to: CGPoint(
                x: size.width * 0.71,
                y: size.height * 0.235
            ),
            control1: CGPoint(
                x: size.width * 0.66,
                y: size.height * 0.47
            ),
            control2: CGPoint(
                x: size.width * 0.68,
                y: size.height * 0.34
            )
        )
        torso.addCurve(
            to: CGPoint(
                x: size.width * 0.54,
                y: size.height * 0.155
            ),
            control1: CGPoint(
                x: size.width * 0.68,
                y: size.height * 0.19
            ),
            control2: CGPoint(
                x: size.width * 0.61,
                y: size.height * 0.16
            )
        )
        torso.closeSubpath()

        context.fill(
            torso,
            with: .color(base)
        )
        context.stroke(
            torso,
            with: .color(outline),
            lineWidth: 0.8
        )

        // Segmented limbs create a more recognisable human silhouette while
        // remaining a single lightweight Canvas with no image allocation.
        drawCapsule(
            x: 0.185,
            y: 0.225,
            width: 0.105,
            height: 0.205,
            rotation: -0.07,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: 0.145,
            y: 0.405,
            width: 0.078,
            height: 0.205,
            rotation: -0.025,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: 0.71,
            y: 0.225,
            width: 0.105,
            height: 0.205,
            rotation: 0.07,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: 0.777,
            y: 0.405,
            width: 0.078,
            height: 0.205,
            rotation: 0.025,
            fill: base,
            context: &context,
            size: size
        )

        drawCapsule(
            x: 0.345,
            y: 0.545,
            width: 0.135,
            height: 0.225,
            rotation: -0.012,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: 0.52,
            y: 0.545,
            width: 0.135,
            height: 0.225,
            rotation: 0.012,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: 0.365,
            y: 0.755,
            width: 0.095,
            height: 0.22,
            rotation: 0.012,
            fill: base,
            context: &context,
            size: size
        )
        drawCapsule(
            x: 0.54,
            y: 0.755,
            width: 0.095,
            height: 0.22,
            rotation: -0.012,
            fill: base,
            context: &context,
            size: size
        )
    }

    private func draw(
        region: StrengthMuscleRegion,
        intensity: Double,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let fill: Color

        switch style {
        case .activation:
            fill =
                Color(
                    red: 0.14,
                    green: 0.60,
                    blue: 0.45
                )
                .opacity(
                    0.26 +
                    intensity * 0.74
                )

        case .recoveryLoad:
            fill =
                recoveryLoadColor(
                    score: intensity
                )
        }

        switch (side, region) {
        case (.front, .chest):
            ellipsePair(
                y: 0.28,
                width: 0.21,
                height: 0.105,
                spacing: 0.12,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .frontDelts),
             (.front, .sideDelts):
            circlePair(
                y: 0.25,
                diameter: 0.15,
                spacing: 0.38,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .rearDelts),
             (.back, .sideDelts):
            circlePair(
                y: 0.25,
                diameter: 0.15,
                spacing: 0.38,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .biceps):
            capsulePair(
                y: 0.34,
                width: 0.075,
                height: 0.17,
                spacing: 0.50,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .triceps):
            capsulePair(
                y: 0.34,
                width: 0.078,
                height: 0.18,
                spacing: 0.50,
                fill: fill,
                context: &context,
                size: size
            )

        case (_, .forearms):
            capsulePair(
                y: 0.47,
                width: 0.060,
                height: 0.17,
                spacing: 0.56,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .traps):
            drawRounded(
                x: 0.39,
                y: 0.17,
                width: 0.22,
                height: 0.15,
                radius: 0.05,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .upperBack):
            drawRounded(
                x: 0.33,
                y: 0.27,
                width: 0.34,
                height: 0.13,
                radius: 0.06,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .lats):
            capsulePair(
                y: 0.33,
                width: 0.115,
                height: 0.23,
                spacing: 0.22,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .lowerBack):
            drawRounded(
                x: 0.40,
                y: 0.43,
                width: 0.20,
                height: 0.13,
                radius: 0.05,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .abs):
            drawRounded(
                x: 0.41,
                y: 0.37,
                width: 0.18,
                height: 0.20,
                radius: 0.04,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .obliques):
            capsulePair(
                y: 0.40,
                width: 0.075,
                height: 0.17,
                spacing: 0.20,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .serratus):
            capsulePair(
                y: 0.33,
                width: 0.055,
                height: 0.12,
                spacing: 0.24,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .glutes):
            ellipsePair(
                y: 0.55,
                width: 0.17,
                height: 0.105,
                spacing: 0.13,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .outerHip),
             (.back, .outerHip):
            capsulePair(
                y: 0.55,
                width: 0.065,
                height: 0.12,
                spacing: 0.25,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .innerThigh):
            capsulePair(
                y: 0.62,
                width: 0.060,
                height: 0.20,
                spacing: 0.08,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .hipFlexors):
            capsulePair(
                y: 0.55,
                width: 0.055,
                height: 0.11,
                spacing: 0.12,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .quads):
            capsulePair(
                y: 0.63,
                width: 0.105,
                height: 0.23,
                spacing: 0.17,
                fill: fill,
                context: &context,
                size: size
            )

        case (.back, .hamstrings):
            capsulePair(
                y: 0.64,
                width: 0.105,
                height: 0.23,
                spacing: 0.17,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .calves),
             (.back, .calves):
            capsulePair(
                y: 0.82,
                width: 0.075,
                height: 0.16,
                spacing: 0.17,
                fill: fill,
                context: &context,
                size: size
            )

        case (.front, .shins):
            capsulePair(
                y: 0.81,
                width: 0.044,
                height: 0.17,
                spacing: 0.17,
                fill: fill,
                context: &context,
                size: size
            )

        default:
            break
        }
    }

    private func recoveryLoadColor(
        score: Double
    ) -> Color {
        let value =
            min(max(score, 0), 1)

        let green = (
            red: 0.24,
            green: 0.70,
            blue: 0.43
        )
        let yellow = (
            red: 0.95,
            green: 0.78,
            blue: 0.18
        )
        let orange = (
            red: 0.96,
            green: 0.48,
            blue: 0.14
        )
        let red = (
            red: 0.86,
            green: 0.17,
            blue: 0.19
        )

        let color: (
            red: Double,
            green: Double,
            blue: Double
        )

        switch value {
        case ..<0.20:
            color = green

        case 0.20..<0.44:
            color = interpolate(
                from: green,
                to: yellow,
                progress:
                    (value - 0.20) /
                    0.24
            )

        case 0.44..<0.65:
            color = interpolate(
                from: yellow,
                to: orange,
                progress:
                    (value - 0.44) /
                    0.21
            )

        case 0.65..<0.84:
            color = orange

        default:
            color = interpolate(
                from: orange,
                to: red,
                progress:
                    (value - 0.84) /
                    0.16
            )
        }

        return Color(
            red: color.red,
            green: color.green,
            blue: color.blue
        )
        .opacity(0.78)
    }

    private func interpolate(
        from start: (
            red: Double,
            green: Double,
            blue: Double
        ),
        to end: (
            red: Double,
            green: Double,
            blue: Double
        ),
        progress: Double
    ) -> (
        red: Double,
        green: Double,
        blue: Double
    ) {
        let value =
            min(max(progress, 0), 1)

        return (
            red:
                start.red +
                (end.red - start.red) *
                value,
            green:
                start.green +
                (end.green - start.green) *
                value,
            blue:
                start.blue +
                (end.blue - start.blue) *
                value
        )
    }

    private func ellipsePair(
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        fill: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for sign in [-1.0, 1.0] {
            let center =
                0.5 +
                CGFloat(sign) *
                spacing / 2
            let rect =
                CGRect(
                    x:
                        size.width *
                        (
                            center -
                            width / 2
                        ),
                    y:
                        size.height * y,
                    width:
                        size.width *
                        width,
                    height:
                        size.height *
                        height
                )
            context.fill(
                Path(
                    ellipseIn: rect
                ),
                with:
                    .color(fill)
            )
        }
    }

    private func circlePair(
        y: CGFloat,
        diameter: CGFloat,
        spacing: CGFloat,
        fill: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        ellipsePair(
            y: y,
            width: diameter,
            height:
                diameter *
                size.width /
                size.height,
            spacing: spacing,
            fill: fill,
            context: &context,
            size: size
        )
    }

    private func capsulePair(
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        fill: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for sign in [-1.0, 1.0] {
            let center =
                0.5 +
                CGFloat(sign) *
                spacing / 2
            drawRounded(
                x:
                    center -
                    width / 2,
                y: y,
                width: width,
                height: height,
                radius:
                    width / 2,
                fill: fill,
                context: &context,
                size: size
            )
        }
    }

    private func drawRounded(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        radius: CGFloat,
        fill: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let rect =
            CGRect(
                x: size.width * x,
                y: size.height * y,
                width:
                    size.width *
                    width,
                height:
                    size.height *
                    height
            )
        let path =
            Path(
                roundedRect:
                    rect,
                cornerRadius:
                    size.width *
                    radius
            )
        context.fill(
            path,
            with: .color(fill)
        )
    }

    private func drawCapsule(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        rotation: Double,
        fill: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let rect =
            CGRect(
                x: size.width * x,
                y: size.height * y,
                width:
                    size.width *
                    width,
                height:
                    size.height *
                    height
            )

        context.drawLayer {
            layer in
            layer.translateBy(
                x: rect.midX,
                y: rect.midY
            )
            layer.rotate(
                by:
                    .radians(
                        rotation
                    )
            )
            layer.translateBy(
                x: -rect.midX,
                y: -rect.midY
            )
            layer.fill(
                Path(
                    roundedRect:
                        rect,
                    cornerRadius:
                        rect.width / 2
                ),
                with:
                    .color(fill)
            )
        }
    }
}
