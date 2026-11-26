import Foundation
import SwiftUI

/// Local, descriptive profile, not a fitness ranking or a medical assessment.
/// Equal 28-day windows; relative indices have a personal baseline of 50.
/// Never infer a zero capability from unavailable measurements.
enum ATHLTHDigitalTrainingProfile {
    enum Axis: String, CaseIterable, Identifiable {
        case endurance, speed, strength, recovery, continuity, balance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .endurance: return tr("Endurance", "Utholdenhet")
            case .speed: return tr("Speed", "Hurtighet")
            case .strength: return tr("Strength", "Styrke")
            case .recovery: return tr("Recovery", "Restitusjon")
            case .continuity: return tr("Consistency", "Kontinuitet")
            case .balance: return tr("Training variety", "Treningsbalanse")
            }
        }
        var compactTitle: String {
            switch self {
            case .endurance: return tr("Endurance", "Uthold.")
            case .speed: return tr("Speed", "Fart")
            case .strength: return tr("Strength", "Styrke")
            case .recovery: return tr("Recovery", "Restit.")
            case .continuity: return tr("Consistency", "Kontin.")
            case .balance: return tr("Variety", "Balanse")
            }
        }
        var methodology: String {
            switch self {
            case .endurance: return tr("Recorded aerobic training minutes, last 28 days versus the preceding 28 days. A volume index, not measured aerobic capacity.", "Registrerte kondisjonsminutter siste 28 dager mot foregående 28 dager. Måler treningsmengde, ikke kondisjonskapasitet.")
            case .speed: return tr("Median average running speed in comparable distance and indoor/outdoor groups; at least three runs per period in each group. Terrain and effort can differ.", "Median av gjennomsnittsfart for sammenlignbare distansegrupper og inne/ute. Minst tre løp per periode i hver gruppe. Terreng og innsats kan variere.")
            case .strength: return tr("Median change in estimated 1RM from completed weighted sets of the same exercise name, with 1–10 reps and at least two distinct sessions per period.", "Median endring i estimert 1RM fra fullførte sett med vekt, samme øvelsesnavn og 1–10 repetisjoner. Minst to ulike økter per periode.")
            case .recovery: return tr("Existing Daily Form assessment, combining available recovery data and daily check-in.", "Eksisterende Dagens form, med tilgjengelige restitusjonsdata og egenrapportert dagsform.")
            case .continuity: return tr("Percentage of the last four seven-day periods with at least one recorded workout. This is a regularity indicator, not a training target.", "Andel av de siste fire sjudagersperiodene med minst én registrert økt. Dette er et mål på regelmessighet, ikke et treningsmål.")
            case .balance: return tr("Diversity of recorded endurance, strength and other sport sessions. A higher value means more even distribution, not necessarily better training.", "Variasjon mellom registrert kondisjon, styrke og annen idrett. Høyere verdi betyr jevnere fordeling, ikke nødvendigvis bedre trening.")
            }
        }
    }

    struct Metric: Identifiable, Equatable {
        var axis: Axis
        var score: Int?
        var evidence: String
        var id: String { axis.rawValue }
    }

    struct Snapshot: Equatable {
        var metrics: [Metric]
        var availableCount: Int { metrics.compactMap(\.score).count }
        static var empty: Self {
            .init(metrics: Axis.allCases.map { .init(axis: $0, score: nil, evidence: tr("Not enough data", "For lite data")) })
        }
    }

    static func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    static func relativeIndex(current: Double, baseline: Double) -> Int? {
        guard current.isFinite, current >= 0, baseline.isFinite, baseline > 0 else { return nil }
        return Int(min(100, max(0, current / baseline * 50)).rounded())
    }

    static func median(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !valid.isEmpty else { return nil }
        let m = valid.count / 2
        return valid.count.isMultiple(of: 2) ? (valid[m - 1] + valid[m]) / 2 : valid[m]
    }

    static func build(workouts: [WorkoutSummary], strength: [StrengthWorkoutLog],
                      recoveryScore: Int?, now: Date = Date(), calendar: Calendar = .current) -> Snapshot {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        guard let middle = calendar.date(byAdding: .day, value: -28, to: end),
              let beginning = calendar.date(byAdding: .day, value: -28, to: middle) else { return .empty }
        var seen = Set<UUID>()
        let recorded = workouts.filter {
            $0.endDate <= now && $0.endDate >= beginning &&
            $0.duration.isFinite && $0.duration > 0 && seen.insert($0.id).inserted
        }
        let recent = recorded.filter { $0.endDate >= middle }
        let prior = recorded.filter { $0.endDate < middle }
        func aerobic(_ workout: WorkoutSummary) -> Bool {
            !workout.isSports && [.running, .walking, .cycling, .swimming, .hiking, .rowing, .elliptical, .stairClimbing].contains(workout.activity)
        }
        func minutes(_ workouts: [WorkoutSummary]) -> Double {
            workouts.filter(aerobic).reduce(0) { $0 + $1.duration } / 60
        }
        let unavailable = tr("Not enough data", "For lite data")
        let recentMinutes = minutes(recent), priorMinutes = minutes(prior)
        let endurance = recent.filter(aerobic).count >= 2 && prior.filter(aerobic).count >= 2
            ? relativeIndex(current: recentMinutes, baseline: priorMinutes) : nil

        func speedGroups(_ workouts: [WorkoutSummary]) -> [String: [Double]] {
            var result: [String: [Double]] = [:]
            for workout in workouts where workout.activity == .running && !workout.isSports {
                guard let distance = workout.distanceMeters, distance.isFinite,
                      distance >= 1000, distance <= 100000,
                      let indoor = workout.isIndoor, workout.duration >= 180 else { continue }
                // Narrow logarithmic bands: distances in a group differ by less than 25%.
                let band = Int(log(distance / 1000) / log(1.25))
                let speed = distance / workout.duration
                guard (0.5...12).contains(speed) else { continue }
                result["\(indoor)|\(band)", default: []].append(speed)
            }
            return result
        }
        let recentSpeeds = speedGroups(recent), priorSpeeds = speedGroups(prior)
        let speedRatios = recentSpeeds.compactMap { key, values -> Double? in
            guard values.count >= 3, let old = priorSpeeds[key], old.count >= 3,
                  let current = median(values), let baseline = median(old) else { return nil }
            return current / baseline
        }
        let speedRatio = median(speedRatios)

        // Aggregate the best actual estimated 1RM once per exercise per session.
        // Never count planned values, warm-ups or skipped sets as evidence.
        var strengthSeen = Set<UUID>()
        var recentStrength: [String: [Double]] = [:], priorStrength: [String: [Double]] = [:]
        for log in strength {
            guard let date = log.endedAt, date >= beginning, date <= now,
                  strengthSeen.insert(log.id).inserted else { continue }
            var best: [String: Double] = [:]
            for item in log.exercises {
                guard item.isEmbeddedRunningInterval != true,
                      !StrengthCardioExercisePolicy.isCardio(item.exercise.name) else { continue }
                let key = item.exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                guard !key.isEmpty else { continue }
                for set in item.sets where set.isCompleted && set.skippedAt == nil && set.isWarmUp != true {
                    guard set.recordsWeight != false, set.hybridPhaseKind == nil,
                          let weight = set.completedWeightKilograms, weight.isFinite, weight > 0,
                          let reps = set.completedReps, (1...10).contains(reps) else { continue }
                    let estimate = reps == 1 ? weight : weight * (1 + Double(reps) / 30)
                    best[key] = max(best[key] ?? 0, estimate)
                }
            }
            for (key, estimate) in best {
                if date >= middle { recentStrength[key, default: []].append(estimate) }
                else { priorStrength[key, default: []].append(estimate) }
            }
        }
        let strengthRatios = recentStrength.compactMap { key, values -> Double? in
            guard values.count >= 2, let old = priorStrength[key], old.count >= 2,
                  let current = median(values), let baseline = median(old) else { return nil }
            return current / baseline
        }
        let strengthRatio = median(strengthRatios)
        var weeks = Set<Int>()
        for date in recent.map(\.endDate) {
            let days = calendar.dateComponents([.day], from: middle, to: calendar.startOfDay(for: date)).day ?? 0
            if (0..<28).contains(days) { weeks.insert(days / 7) }
        }
        // Without any recorded history, lack of visibility is not a zero.
        let continuity = recorded.isEmpty ? nil : weeks.count * 25

        let cardioCount = recent.filter(aerobic).count
        let strengthCount = recent.filter { !$0.isSports && ($0.activity == .strength || $0.activity == .coreTraining) }.count
        let sportCount = recent.filter { $0.isSports || $0.activity == .hiit }.count
        let counts = [cardioCount, strengthCount, sportCount]
        let total = counts.reduce(0, +)
        let diversity: Int? = total >= 4 ? Int((counts.filter { $0 > 0 }.reduce(0.0) { value, count in
            let p = Double(count) / Double(total)
            return value - p * log(p)
        } / log(3) * 100).rounded()) : nil

        let validRecovery = recoveryScore.flatMap { (0...100).contains($0) ? $0 : nil }
        return Snapshot(metrics: [
            .init(axis: .endurance, score: endurance,
                  evidence: endurance == nil ? unavailable : "\(Int(recentMinutes.rounded())) / \(Int(priorMinutes.rounded())) min"),
            .init(axis: .speed, score: speedRatio.flatMap { relativeIndex(current: $0, baseline: 1) },
                  evidence: speedRatio.map { String(format: "%+.0f %% · %d", ($0 - 1) * 100, speedRatios.count) + tr(" groups", " grupper") } ?? unavailable),
            .init(axis: .strength, score: strengthRatio.flatMap { relativeIndex(current: $0, baseline: 1) },
                  evidence: strengthRatio.map { String(format: "%+.0f %% · %d", ($0 - 1) * 100, strengthRatios.count) + tr(" exercises", " øvelser") } ?? unavailable),
            .init(axis: .recovery, score: validRecovery, evidence: validRecovery.map { "\($0)/100" } ?? unavailable),
            .init(axis: .continuity, score: continuity, evidence: continuity == nil ? unavailable : "\(weeks.count)/4" + tr(" active weeks", " aktive uker")),
            .init(axis: .balance, score: diversity, evidence: diversity == nil ? unavailable : "\(cardioCount) / \(strengthCount) / \(sportCount) " + tr("sessions", "økter"))
        ])
    }
}

struct ATHLTHDigitalTrainingProfileCard: View {
    let snapshot: ATHLTHDigitalTrainingProfile.Snapshot
    private let gold = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk

    private func tr(_ en: String, _ no: String) -> String { ATHLTHDigitalTrainingProfile.tr(en, no) }

    var body: some View {
        NavigationLink {
            detail
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.xyaxis.line").font(.caption).foregroundStyle(gold)
                    Text(tr("Training profile", "Treningsprofil"))
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(gold)
                }.frame(minHeight: 31)
                ATHLTHTrainingRadar(metrics: snapshot.metrics, compact: true)
                    .frame(height: 122)
                Text(snapshot.availableCount == 0 ? tr("Building your profile", "Bygger treningsprofilen") :
                    tr("\(snapshot.availableCount) of 6 dimensions", "\(snapshot.availableCount) av 6 dimensjoner"))
                    .font(.caption2).foregroundStyle(dim).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .athlthTrainPaper()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-profile-digital-training")
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ATHLTHUnifiedCard {
                    ATHLTHTrainingRadar(metrics: snapshot.metrics, compact: false)
                        .frame(height: 260)
                    Text(tr("Your own baseline, not a comparison with other athletes.", "Ditt eget utgangspunkt, ikke en sammenligning med andre utøvere."))
                        .font(.caption).foregroundStyle(dim)
                }
                Text(tr("Last 28 days · Personal indices", "Siste 28 dager · Personlige indekser"))
                    .font(.headline).foregroundStyle(ink)
                Text(tr("For endurance, speed and strength, 50 means the same level as the previous 28 days. Other axes use their own explained scale. Missing evidence is left blank.", "For utholdenhet, hurtighet og styrke betyr 50 samme nivå som foregående 28 dager. De andre aksene har egne forklarte skalaer. Manglende data vises ikke som null."))
                    .font(.subheadline).foregroundStyle(dim)
                ForEach(snapshot.metrics) { metric in
                    ATHLTHUnifiedCard(compact: true) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(metric.axis.title).font(.headline).foregroundStyle(ink)
                                Spacer()
                                Text(metric.score.map(String.init) ?? "–").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(gold)
                            }
                            Text(metric.evidence).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                            Text(metric.axis.methodology).font(.caption).foregroundStyle(dim)
                        }
                    }
                }
            }.padding(14).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .navigationTitle(tr("Digital training profile", "Digital treningsprofil"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ATHLTHTrainingRadar: View {
    let metrics: [ATHLTHDigitalTrainingProfile.Metric]
    let compact: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(1, min(size.width * (compact ? 0.29 : 0.31), size.height * 0.34))
            let gold = ATHLTHPlanDesign.accentInk
            let dim = ATHLTHPlanDesign.secondaryInk
            func point(_ index: Int, _ scale: CGFloat) -> CGPoint {
                let angle = Double(index) * .pi / 3 - .pi / 2
                return CGPoint(x: center.x + radius * scale * CGFloat(cos(angle)),
                               y: center.y + radius * scale * CGFloat(sin(angle)))
            }
            for level in [0.25, 0.5, 0.75, 1.0] {
                var line = Path()
                for index in 0..<6 {
                    let p = point(index, CGFloat(level))
                    if index == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                line.closeSubpath()
                context.stroke(line, with: .color(dim.opacity(level == 0.5 ? 0.36 : 0.18)), lineWidth: 0.6)
            }
            for index in 0..<6 {
                var axis = Path()
                axis.move(to: center); axis.addLine(to: point(index, 1))
                context.stroke(axis, with: .color(dim.opacity(0.22)), lineWidth: 0.6)
            }
            let values = ATHLTHDigitalTrainingProfile.Axis.allCases.map { axis in
                metrics.first(where: { $0.axis == axis })?.score
            }
            if values.allSatisfy({ $0 != nil }) {
                var polygon = Path()
                for index in 0..<6 {
                    let p = point(index, CGFloat(values[index] ?? 0) / 100)
                    if index == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) }
                }
                polygon.closeSubpath()
                context.fill(polygon, with: .color(gold.opacity(0.18)))
                context.stroke(polygon, with: .color(gold), lineWidth: 1.4)
            }
            for (index, axis) in ATHLTHDigitalTrainingProfile.Axis.allCases.enumerated() {
                if let value = values[index] {
                    let p = point(index, CGFloat(value) / 100)
                    let dot: CGFloat = compact ? 4 : 6
                    context.fill(Path(ellipseIn: CGRect(x: p.x-dot/2, y: p.y-dot/2, width: dot, height: dot)), with: .color(gold))
                }
                let labelPoint = point(index, 1.37)
                let label = compact ? axis.compactTitle : axis.title
                let font: Font = .system(size: compact ? 8 : 11, weight: .medium)
                context.draw(Text(label).font(font).foregroundColor(values[index] == nil ? dim.opacity(0.6) : dim),
                             at: labelPoint, anchor: .center)
            }
        }
        .accessibilityLabel(ATHLTHDigitalTrainingProfile.tr("Training profile radar", "Radardiagram for treningsprofil"))
        .accessibilityValue(metrics.map { $0.axis.title + ": " + ($0.score.map(String.init) ?? "–") }.joined(separator: ", "))
    }
}
