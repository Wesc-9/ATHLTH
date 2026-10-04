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
                    $0.resolvedCompletedReps != nil ||
                    $0.completedWeightKilograms != nil ||
                    $0.completedResistanceLevel != nil ||
                    $0.resolvedCompletedDistanceMeters != nil
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
                            set.resolvedCompletedReps ??
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

                    if set.isCompleted {
                        return partial +
                            set.volumeKilograms
                    }

                    let reps =
                        set.plannedReps ?? 0
                    let weight =
                        set.plannedWeightKilograms ?? 0

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
                            $0.resolvedCompletedReps != nil ||
                            $0.completedWeightKilograms != nil ||
                            $0.completedResistanceLevel != nil ||
                            $0.resolvedCompletedDistanceMeters != nil
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

enum StrengthBodyPresentation:
    String,
    CaseIterable,
    Identifiable
{
    case neutral
    case female
    case male

    var id: String { rawValue }

    fileprivate var horizontalScale:
        CGFloat
    {
        switch self {
        case .neutral:
            return 1.0
        case .female:
            return 0.992
        case .male:
            return 1.008
        }
    }

    fileprivate var shoulderHalfWidth:
        CGFloat
    {
        switch self {
        case .neutral:
            return 0.205
        case .female:
            return 0.192
        case .male:
            return 0.218
        }
    }

    fileprivate var waistHalfWidth:
        CGFloat
    {
        switch self {
        case .neutral:
            return 0.116
        case .female:
            return 0.106
        case .male:
            return 0.122
        }
    }

    fileprivate var hipHalfWidth:
        CGFloat
    {
        switch self {
        case .neutral:
            return 0.154
        case .female:
            return 0.168
        case .male:
            return 0.150
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
    var figureStyle:
        StrengthBodyPresentation = .neutral
    var activationTint:
        Color = Color(
            red: 0.14,
            green: 0.60,
            blue: 0.45
        )

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
                style: style,
                figureStyle:
                    figureStyle,
                activationTint:
                    activationTint
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
    let figureStyle:
        StrengthBodyPresentation
    let activationTint:
        Color

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
        .scaleEffect(
            x:
                figureStyle
                    .horizontalScale,
            y: 1,
            anchor: .center
        )
    }

    private func drawBase(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        drawRecoverySilhouette(
            context: &context,
            size: size
        )
    }

    private func drawRecoverySilhouette(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let base: Color
        let outline: Color
        let highlight: Color

        switch style {
        case .activation:
            base =
                Color(
                    red: 0.855,
                    green: 0.862,
                    blue: 0.872
                )
            outline =
                Color(
                    red: 0.33,
                    green: 0.36,
                    blue: 0.40
                )
                .opacity(0.16)
            highlight =
                Color.white.opacity(0.38)

        case .recoveryLoad:
            base =
                Color(
                    red: 0.905,
                    green: 0.898,
                    blue: 0.875
                )
            outline =
                Color.black.opacity(0.10)
            highlight =
                Color.white.opacity(0.30)
        }

        let shoulder =
            figureStyle
                .shoulderHalfWidth
        let waist =
            figureStyle
                .waistHalfWidth
        let hip =
            figureStyle
                .hipHalfWidth

        // Limbs are drawn first so the torso naturally covers the shoulder
        // and hip joints. Tapered organic segments avoid the old toy-like
        // capsule/mannequin appearance.
        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.5 - shoulder * 0.90,
                    y: 0.235
                ),
            to:
                CGPoint(
                    x: 0.235,
                    y: 0.425
                ),
            startWidth: 0.100,
            endWidth: 0.074,
            curve: -0.018,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )
        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.235,
                    y: 0.415
                ),
            to:
                CGPoint(
                    x: 0.205,
                    y: 0.605
                ),
            startWidth: 0.073,
            endWidth: 0.052,
            curve: 0.010,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )
        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.5 + shoulder * 0.90,
                    y: 0.235
                ),
            to:
                CGPoint(
                    x: 0.765,
                    y: 0.425
                ),
            startWidth: 0.100,
            endWidth: 0.074,
            curve: 0.018,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )
        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.765,
                    y: 0.415
                ),
            to:
                CGPoint(
                    x: 0.795,
                    y: 0.605
                ),
            startWidth: 0.073,
            endWidth: 0.052,
            curve: -0.010,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )

        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.5 - hip * 0.46,
                    y: 0.555
                ),
            to:
                CGPoint(
                    x: 0.405,
                    y: 0.765
                ),
            startWidth: 0.122,
            endWidth: 0.087,
            curve: -0.006,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )
        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.5 + hip * 0.46,
                    y: 0.555
                ),
            to:
                CGPoint(
                    x: 0.595,
                    y: 0.765
                ),
            startWidth: 0.122,
            endWidth: 0.087,
            curve: 0.006,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )
        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.405,
                    y: 0.748
                ),
            to:
                CGPoint(
                    x: 0.395,
                    y: 0.962
                ),
            startWidth: 0.084,
            endWidth: 0.054,
            curve: 0.004,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )
        drawTaperedSegment(
            from:
                CGPoint(
                    x: 0.595,
                    y: 0.748
                ),
            to:
                CGPoint(
                    x: 0.605,
                    y: 0.962
                ),
            startWidth: 0.084,
            endWidth: 0.054,
            curve: -0.004,
            fill: base,
            outline: outline,
            context: &context,
            size: size
        )

        var torso = Path()
        torso.move(
            to:
                point(
                    x: 0.455,
                    y: 0.155,
                    size: size
                )
        )
        torso.addCurve(
            to:
                point(
                    x: 0.5 - shoulder,
                    y: 0.225,
                    size: size
                ),
            control1:
                point(
                    x: 0.405,
                    y: 0.164,
                    size: size
                ),
            control2:
                point(
                    x:
                        0.5 -
                        shoulder * 0.82,
                    y: 0.178,
                    size: size
                )
        )
        torso.addCurve(
            to:
                point(
                    x: 0.5 - waist,
                    y: 0.485,
                    size: size
                ),
            control1:
                point(
                    x:
                        0.5 -
                        shoulder * 0.98,
                    y: 0.315,
                    size: size
                ),
            control2:
                point(
                    x:
                        0.5 -
                        waist * 1.18,
                    y: 0.425,
                    size: size
                )
        )
        torso.addCurve(
            to:
                point(
                    x: 0.5 - hip,
                    y: 0.555,
                    size: size
                ),
            control1:
                point(
                    x:
                        0.5 -
                        waist * 0.98,
                    y: 0.520,
                    size: size
                ),
            control2:
                point(
                    x:
                        0.5 -
                        hip * 0.84,
                    y: 0.548,
                    size: size
                )
        )
        torso.addCurve(
            to:
                point(
                    x: 0.5 + hip,
                    y: 0.555,
                    size: size
                ),
            control1:
                point(
                    x:
                        0.5 -
                        hip * 0.78,
                    y: 0.595,
                    size: size
                ),
            control2:
                point(
                    x:
                        0.5 +
                        hip * 0.78,
                    y: 0.595,
                    size: size
                )
        )
        torso.addCurve(
            to:
                point(
                    x: 0.5 + waist,
                    y: 0.485,
                    size: size
                ),
            control1:
                point(
                    x:
                        0.5 +
                        hip * 0.84,
                    y: 0.548,
                    size: size
                ),
            control2:
                point(
                    x:
                        0.5 +
                        waist * 0.98,
                    y: 0.520,
                    size: size
                )
        )
        torso.addCurve(
            to:
                point(
                    x: 0.5 + shoulder,
                    y: 0.225,
                    size: size
                ),
            control1:
                point(
                    x:
                        0.5 +
                        waist * 1.18,
                    y: 0.425,
                    size: size
                ),
            control2:
                point(
                    x:
                        0.5 +
                        shoulder * 0.98,
                    y: 0.315,
                    size: size
                )
        )
        torso.addCurve(
            to:
                point(
                    x: 0.545,
                    y: 0.155,
                    size: size
                ),
            control1:
                point(
                    x:
                        0.5 +
                        shoulder * 0.82,
                    y: 0.178,
                    size: size
                ),
            control2:
                point(
                    x: 0.595,
                    y: 0.164,
                    size: size
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
            lineWidth: 0.75
        )

        // Subtle sculpted highlight gives the neutral material depth without
        // making the figure glossy or medically realistic.
        var torsoLight = Path()
        torsoLight.move(
            to:
                point(
                    x: 0.475,
                    y: 0.185,
                    size: size
                )
        )
        torsoLight.addCurve(
            to:
                point(
                    x: 0.455,
                    y: 0.515,
                    size: size
                ),
            control1:
                point(
                    x: 0.440,
                    y: 0.275,
                    size: size
                ),
            control2:
                point(
                    x: 0.445,
                    y: 0.430,
                    size: size
                )
        )
        context.stroke(
            torsoLight,
            with: .color(highlight),
            lineWidth: 0.8
        )

        let neck =
            CGRect(
                x:
                    size.width *
                    0.462,
                y:
                    size.height *
                    0.112,
                width:
                    size.width *
                    0.076,
                height:
                    size.height *
                    0.070
            )
        context.fill(
            Path(
                roundedRect: neck,
                cornerRadius:
                    neck.width * 0.40
            ),
            with: .color(base)
        )

        let head =
            CGRect(
                x:
                    size.width *
                    0.405,
                y:
                    size.height *
                    0.012,
                width:
                    size.width *
                    0.190,
                height:
                    size.height *
                    0.112
            )
        context.fill(
            Path(ellipseIn: head),
            with: .color(base)
        )
        context.stroke(
            Path(ellipseIn: head),
            with: .color(outline),
            lineWidth: 0.65
        )

        // A barely visible centre reference keeps front/back orientation clear
        // at detail size while disappearing naturally in compact cards.
        var centreLine = Path()
        centreLine.move(
            to:
                point(
                    x: 0.5,
                    y:
                        side == .back
                            ? 0.185
                            : 0.255,
                    size: size
                )
        )
        centreLine.addLine(
            to:
                point(
                    x: 0.5,
                    y: 0.535,
                    size: size
                )
        )
        context.stroke(
            centreLine,
            with:
                .color(
                    Color.black
                        .opacity(
                            side == .back
                                ? 0.075
                                : 0.040
                        )
                ),
            lineWidth: 0.55
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
                activationTint
                    .opacity(
                        0.22 +
                        intensity * 0.74
                    )

        case .recoveryLoad:
            fill =
                recoveryLoadColor(
                    score: intensity
                )
        }

        let emphasis =
            min(
                max(
                    CGFloat(intensity),
                    0
                ),
                1
            )

        switch (side, region) {
        case (.front, .chest):
            organicPair(
                centerY: 0.300,
                width: 0.178,
                height: 0.094,
                spacing: 0.175,
                lean: 0.18,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .frontDelts),
             (.front, .sideDelts):
            organicPair(
                centerY: 0.250,
                width: 0.120,
                height: 0.092,
                spacing: 0.385,
                lean: 0.42,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .rearDelts),
             (.back, .sideDelts):
            organicPair(
                centerY: 0.252,
                width: 0.122,
                height: 0.094,
                spacing: 0.385,
                lean: 0.34,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .biceps):
            organicPair(
                centerY: 0.365,
                width: 0.064,
                height: 0.135,
                spacing: 0.505,
                lean: 0.18,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .triceps):
            organicPair(
                centerY: 0.365,
                width: 0.066,
                height: 0.145,
                spacing: 0.505,
                lean: 0.16,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (_, .forearms):
            organicPair(
                centerY: 0.495,
                width: 0.050,
                height: 0.135,
                spacing: 0.570,
                lean: 0.10,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .traps):
            organicSingle(
                centerX: 0.5,
                centerY: 0.225,
                width: 0.205,
                height: 0.120,
                lean: 0,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .upperBack):
            organicPair(
                centerY: 0.320,
                width: 0.160,
                height: 0.118,
                spacing: 0.185,
                lean: 0.22,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .lats):
            organicPair(
                centerY: 0.405,
                width: 0.106,
                height: 0.205,
                spacing: 0.225,
                lean: 0.34,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .lowerBack):
            organicSingle(
                centerX: 0.5,
                centerY: 0.480,
                width: 0.170,
                height: 0.115,
                lean: 0,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .abs):
            drawAbdominalStack(
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .obliques):
            organicPair(
                centerY: 0.455,
                width: 0.062,
                height: 0.155,
                spacing: 0.205,
                lean: 0.30,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .serratus):
            organicPair(
                centerY: 0.365,
                width: 0.050,
                height: 0.105,
                spacing: 0.247,
                lean: 0.44,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .glutes):
            organicPair(
                centerY: 0.565,
                width: 0.138,
                height: 0.090,
                spacing: 0.135,
                lean: 0.10,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .outerHip),
             (.back, .outerHip):
            organicPair(
                centerY: 0.570,
                width: 0.057,
                height: 0.105,
                spacing: 0.255,
                lean: 0.34,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .innerThigh):
            organicPair(
                centerY: 0.675,
                width: 0.052,
                height: 0.180,
                spacing: 0.078,
                lean: 0.12,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .hipFlexors):
            organicPair(
                centerY: 0.585,
                width: 0.050,
                height: 0.095,
                spacing: 0.118,
                lean: 0.30,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .quads):
            organicPair(
                centerY: 0.675,
                width: 0.092,
                height: 0.205,
                spacing: 0.170,
                lean: 0.10,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.back, .hamstrings):
            organicPair(
                centerY: 0.682,
                width: 0.090,
                height: 0.205,
                spacing: 0.170,
                lean: 0.10,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .calves),
             (.back, .calves):
            organicPair(
                centerY: 0.845,
                width: 0.064,
                height: 0.145,
                spacing: 0.172,
                lean: 0.08,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        case (.front, .shins):
            organicPair(
                centerY: 0.842,
                width: 0.038,
                height: 0.150,
                spacing: 0.172,
                lean: 0.04,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )

        default:
            break
        }
    }

    private func point(
        x: CGFloat,
        y: CGFloat,
        size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: size.width * x,
            y: size.height * y
        )
    }

    private func drawTaperedSegment(
        from start: CGPoint,
        to end: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        curve: CGFloat,
        fill: Color,
        outline: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let startPoint =
            point(
                x: start.x,
                y: start.y,
                size: size
            )
        let endPoint =
            point(
                x: end.x,
                y: end.y,
                size: size
            )
        let dx =
            endPoint.x -
            startPoint.x
        let dy =
            endPoint.y -
            startPoint.y
        let length =
            max(
                sqrt(
                    dx * dx +
                    dy * dy
                ),
                0.001
            )
        let nx =
            -dy / length
        let ny =
            dx / length
        let startRadius =
            size.width *
            startWidth / 2
        let endRadius =
            size.width *
            endWidth / 2
        let bend =
            size.width *
            curve

        let s1 =
            CGPoint(
                x:
                    startPoint.x +
                    nx *
                    startRadius,
                y:
                    startPoint.y +
                    ny *
                    startRadius
            )
        let s2 =
            CGPoint(
                x:
                    startPoint.x -
                    nx *
                    startRadius,
                y:
                    startPoint.y -
                    ny *
                    startRadius
            )
        let e1 =
            CGPoint(
                x:
                    endPoint.x +
                    nx *
                    endRadius,
                y:
                    endPoint.y +
                    ny *
                    endRadius
            )
        let e2 =
            CGPoint(
                x:
                    endPoint.x -
                    nx *
                    endRadius,
                y:
                    endPoint.y -
                    ny *
                    endRadius
            )
        let mid =
            CGPoint(
                x:
                    (
                        startPoint.x +
                        endPoint.x
                    ) / 2 +
                    nx * bend,
                y:
                    (
                        startPoint.y +
                        endPoint.y
                    ) / 2 +
                    ny * bend
            )

        var path = Path()
        path.move(to: s1)
        path.addQuadCurve(
            to: e1,
            control:
                CGPoint(
                    x:
                        mid.x +
                        nx *
                        (
                            startRadius +
                            endRadius
                        ) * 0.45,
                    y:
                        mid.y +
                        ny *
                        (
                            startRadius +
                            endRadius
                        ) * 0.45
                )
        )
        path.addQuadCurve(
            to: e2,
            control:
                CGPoint(
                    x:
                        endPoint.x -
                        dx / length *
                        endRadius * 0.55,
                    y:
                        endPoint.y -
                        dy / length *
                        endRadius * 0.55
                )
        )
        path.addQuadCurve(
            to: s2,
            control:
                CGPoint(
                    x:
                        mid.x -
                        nx *
                        (
                            startRadius +
                            endRadius
                        ) * 0.45,
                    y:
                        mid.y -
                        ny *
                        (
                            startRadius +
                            endRadius
                        ) * 0.45
                )
        )
        path.addQuadCurve(
            to: s1,
            control:
                CGPoint(
                    x:
                        startPoint.x -
                        dx / length *
                        startRadius * 0.45,
                    y:
                        startPoint.y -
                        dy / length *
                        startRadius * 0.45
                )
        )
        path.closeSubpath()

        context.fill(
            path,
            with: .color(fill)
        )
        context.stroke(
            path,
            with: .color(outline),
            lineWidth: 0.65
        )
    }

    private func organicPair(
        centerY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        lean: CGFloat,
        fill: Color,
        emphasis: CGFloat,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for sign in [-1.0, 1.0] {
            let direction =
                CGFloat(sign)
            organicSingle(
                centerX:
                    0.5 +
                    direction *
                    spacing / 2,
                centerY:
                    centerY,
                width: width,
                height: height,
                lean:
                    lean *
                    direction,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )
        }
    }

    private func organicSingle(
        centerX: CGFloat,
        centerY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        lean: CGFloat,
        fill: Color,
        emphasis: CGFloat,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let rect =
            CGRect(
                x:
                    size.width *
                    (
                        centerX -
                        width / 2
                    ),
                y:
                    size.height *
                    (
                        centerY -
                        height / 2
                    ),
                width:
                    size.width *
                    width,
                height:
                    size.height *
                    height
            )
        let leanOffset =
            rect.width *
            lean * 0.18
        let top =
            CGPoint(
                x:
                    rect.midX +
                    leanOffset,
                y: rect.minY
            )
        let bottom =
            CGPoint(
                x:
                    rect.midX -
                    leanOffset,
                y: rect.maxY
            )

        var path = Path()
        path.move(to: top)
        path.addCurve(
            to: bottom,
            control1:
                CGPoint(
                    x:
                        rect.maxX +
                        leanOffset * 0.35,
                    y:
                        rect.minY +
                        rect.height * 0.28
                ),
            control2:
                CGPoint(
                    x:
                        rect.maxX -
                        leanOffset * 0.30,
                    y:
                        rect.minY +
                        rect.height * 0.76
                )
        )
        path.addCurve(
            to: top,
            control1:
                CGPoint(
                    x:
                        rect.minX -
                        leanOffset * 0.30,
                    y:
                        rect.minY +
                        rect.height * 0.76
                ),
            control2:
                CGPoint(
                    x:
                        rect.minX +
                        leanOffset * 0.35,
                    y:
                        rect.minY +
                        rect.height * 0.28
                )
        )
        path.closeSubpath()

        context.fill(
            path,
            with: .color(fill)
        )
        context.stroke(
            path,
            with:
                .color(
                    Color.white
                        .opacity(
                            0.10 +
                            emphasis *
                            0.14
                        )
                ),
            lineWidth:
                emphasis > 0.72
                    ? 0.85
                    : 0.55
        )

        if emphasis > 0.56 {
            var highlightPath =
                Path()
            highlightPath.move(
                to:
                    CGPoint(
                        x:
                            rect.midX +
                            leanOffset * 0.55,
                        y:
                            rect.minY +
                            rect.height * 0.15
                    )
            )
            highlightPath.addCurve(
                to:
                    CGPoint(
                        x:
                            rect.midX -
                            leanOffset * 0.45,
                        y:
                            rect.minY +
                            rect.height * 0.72
                    ),
                control1:
                    CGPoint(
                        x:
                            rect.midX +
                            rect.width * 0.13,
                        y:
                            rect.minY +
                            rect.height * 0.32
                    ),
                control2:
                    CGPoint(
                        x:
                            rect.midX +
                            rect.width * 0.07,
                        y:
                            rect.minY +
                            rect.height * 0.56
                    )
            )
            context.stroke(
                highlightPath,
                with:
                    .color(
                        Color.white
                            .opacity(
                                0.10 +
                                emphasis *
                                0.10
                            )
                    ),
                lineWidth: 0.65
            )
        }
    }

    private func drawAbdominalStack(
        fill: Color,
        emphasis: CGFloat,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let rows: [
            (
                y: CGFloat,
                width: CGFloat,
                height: CGFloat
            )
        ] = [
            (0.385, 0.066, 0.050),
            (0.438, 0.064, 0.052),
            (0.492, 0.058, 0.054)
        ]

        for row in rows {
            organicPair(
                centerY: row.y,
                width: row.width,
                height: row.height,
                spacing: 0.072,
                lean: 0.04,
                fill: fill,
                emphasis: emphasis,
                context: &context,
                size: size
            )
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
