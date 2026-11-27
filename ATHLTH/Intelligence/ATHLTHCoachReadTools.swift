import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A bounded local query, never an arbitrary database predicate or mutation.
struct ATHLTHCoachReadQuery: Equatable, Sendable {
    enum Activity: String, Sendable { case all, running, walking, strength }
    enum Kind: String, Sendable { case search, report }
    var kind: Kind = .search
    var activity: Activity = .all
    var days = 56
    var minimumKilometers: Double? = nil
    var maximumAveragePulse: Double? = nil

    var isValid: Bool {
        (1...366).contains(days) &&
        minimumKilometers.map { $0.isFinite && (0...500).contains($0) } != false &&
        maximumAveragePulse.map { $0.isFinite && (20...250).contains($0) } != false
    }

    static func isRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        return ["treningsrapport", "ukesrapport", "månedsrapport", "weekly report", "monthly report",
                "treningshistorikk", "workout history", "finn alle", "finn økt", "vis alle økt",
                "find workouts", "find all runs", "vis løpeøkter", "vis styrkeøkter"].contains { text.contains($0) }
    }

    static func parse(_ source: String) -> Self? {
        guard isRequest(source) else { return nil }
        let text = source.lowercased()
        var query = Self()
        if text.contains("rapport") || text.contains("report") { query.kind = .report }
        if text.contains("løp") || text.contains("run") { query.activity = .running }
        else if text.contains("styrke") || text.contains("strength") { query.activity = .strength }
        else if text.contains("gåtur") || text.contains("walking") { query.activity = .walking }
        if text.contains("uke") || text.contains("week") { query.days = 7 }
        if text.contains("måned") || text.contains("month") { query.days = 30 }

        func value(_ pattern: String) -> Double? {
            guard let range = text.range(of: pattern, options: .regularExpression),
                  let digits = text[range].range(of: #"[0-9]+(?:[.,][0-9]+)?"#, options: .regularExpression) else { return nil }
            return Double(text[digits].replacingOccurrences(of: ",", with: "."))
        }
        query.minimumKilometers = value(#"(?:over|mer enn|above)\s+[0-9]+(?:[.,][0-9]+)?\s*km"#)
        query.maximumAveragePulse = value(#"(?:snittpuls|gjennomsnittspuls|average heart rate)\s*(?:under|below)\s*[0-9]+"#)
        if (text.contains("km") && query.minimumKilometers == nil) ||
           ((text.contains("puls") || text.contains("heart rate")) && query.maximumAveragePulse == nil) { return nil }
        // Do not silently ignore unsupported numeric conditions or units.
        let numbers = text.matchesNumericTokens
        let recognized = [query.minimumKilometers, query.maximumAveragePulse].compactMap { $0 }
        guard numbers.count == recognized.count else { return nil }
        return query.isValid ? query : nil
    }
}

private extension String {
    var matchesNumericTokens: [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(?:[.,][0-9]+)?"#) else { return [] }
        return regex.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap {
            Range($0.range, in: self).map { String(self[$0]) }
        }
    }
}

struct ATHLTHCoachReadRecord: Sendable, Equatable {
    let id: UUID
    let activity: ATHLTHCoachReadQuery.Activity
    let date: Date
    let seconds: Double
    let meters: Double?
    let pulse: Double?
}

enum ATHLTHCoachReadExecutor {
    static func matches(_ query: ATHLTHCoachReadQuery, records: [ATHLTHCoachReadRecord],
                        now: Date = Date(), calendar: Calendar = .current) -> [ATHLTHCoachReadRecord] {
        guard query.isValid, let start = calendar.date(byAdding: .day, value: -query.days, to: now) else { return [] }
        var seen = Set<UUID>()
        return records.filter { item in
            guard item.date >= start, item.date <= now,
                  item.seconds.isFinite, item.seconds > 0,
                  query.activity == .all || item.activity == query.activity,
                  query.minimumKilometers.map({ limit in item.meters.map { $0.isFinite && $0 > limit * 1000 } == true }) != false,
                  query.maximumAveragePulse.map({ limit in item.pulse.map { $0.isFinite && $0 > 0 && $0 < limit } == true }) != false else { return false }
            return seen.insert(item.id).inserted
        }.sorted { $0.date > $1.date }
    }

    static func render(_ query: ATHLTHCoachReadQuery, records: [ATHLTHCoachReadRecord], norwegian: Bool,
                       now: Date = Date()) -> String {
        let rows = matches(query, records: records, now: now)
        func tr(_ en: String, _ no: String) -> String { norwegian ? no : en }
        func activityName(_ activity: ATHLTHCoachReadQuery.Activity) -> String {
            switch activity {
            case .all: return tr("All activities", "Alle treningsformer")
            case .running: return tr("Running", "Løping")
            case .walking: return tr("Walking", "Gåing")
            case .strength: return tr("Strength", "Styrke")
            }
        }
        var result = tr("Last \(query.days) days · \(rows.count) recorded workouts",
                        "Siste \(query.days) dager · \(rows.count) registrerte økter")
        result += "\n" + activityName(query.activity)
        if let limit = query.minimumKilometers { result += " · > \(limit.formatted()) km" }
        if let limit = query.maximumAveragePulse { result += " · " + tr("Average HR", "Snittpuls") + " < \(limit.formatted())" }
        result += "\n" + tr("Total time: ", "Samlet tid: ") +
            ATHLTHWorkoutSummaryEngine.durationText(rows.reduce(0.0) { $0 + $1.seconds })
        let distances = rows.compactMap { item -> Double? in
            guard let meters = item.meters, meters.isFinite, meters > 0 else { return nil }
            return meters
        }
        if !distances.isEmpty {
            result += "\n" + tr("Recorded distance: ", "Registrert distanse: ") +
                ATHLTHWorkoutSummaryEngine.distanceText(distances.reduce(0, +))
        }
        if query.kind == .search {
            for item in rows.prefix(8) {
                var parts = [item.date.formatted(date: .abbreviated, time: .omitted), activityName(item.activity),
                             ATHLTHWorkoutSummaryEngine.durationText(item.seconds)]
                if let m = item.meters, m.isFinite, m > 0 { parts.append(ATHLTHWorkoutSummaryEngine.distanceText(m)) }
                if let p = item.pulse, p.isFinite, p > 0 { parts.append(ATHLTHWorkoutSummaryEngine.pulseText(p)) }
                result += "\n" + parts.joined(separator: " · ")
            }
            if rows.count > 8 { result += "\n" + tr("Showing the 8 most recent matches.", "Viser de 8 siste treffene.") }
        }
        return result + "\n" + tr("Only available recorded data is included. Missing measurements are not estimated.",
                                 "Kun tilgjengelige registreringer er med. Manglende målinger estimeres ikke.")
    }
}

// Apple Tool Calling only selects a read query. No personal records or store
// references are passed to the model. The app checks consent independently.
#if canImport(FoundationModels)
@available(iOS 26.0, *)
private actor ATHLTHCoachReadQueryCapture {
    private var query: ATHLTHCoachReadQuery?
    func store(_ value: ATHLTHCoachReadQuery) { if query == nil { query = value } }
    func result() -> ATHLTHCoachReadQuery? { query }
}

@available(iOS 26.0, *)
private struct ATHLTHCoachReadQueryTool: Tool {
    let name = "selectWorkoutReadQuery"
    let description = "Select a read-only workout search or report. No user records are accessible."
    let capture: ATHLTHCoachReadQueryCapture

    @Generable
    struct Arguments {
        @Guide(description: "search or report") var kind: String
        @Guide(description: "all, running, walking, or strength") var activity: String
        @Guide(description: "Preceding days, 1 to 366") var days: Int
        @Guide(description: "Strict minimum distance in kilometers, or nil") var minimumKilometers: Double?
        @Guide(description: "Strict maximum measured average heart rate, or nil") var maximumAveragePulse: Double?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let kind = ATHLTHCoachReadQuery.Kind(rawValue: arguments.kind),
              let activity = ATHLTHCoachReadQuery.Activity(rawValue: arguments.activity) else { return "Unsupported query." }
        let query = ATHLTHCoachReadQuery(kind: kind, activity: activity, days: arguments.days,
            minimumKilometers: arguments.minimumKilometers, maximumAveragePulse: arguments.maximumAveragePulse)
        guard query.isValid else { return "Invalid query." }
        await capture.store(query)
        return "Read query selected. The app will execute after consent."
    }
}
#endif

@MainActor
enum ATHLTHCoachReadRouter {
    static func query(_ question: String) async throws -> ATHLTHCoachReadQuery? {
        guard let parsed = ATHLTHCoachReadQuery.parse(question) else { return nil }
        // The deterministic query is authoritative. Apple may select exactly
        // that query; it cannot broaden it or substitute unverified filters.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), ATHLTHIntelligenceEngine.isLocalAvailable {
            let capture = ATHLTHCoachReadQueryCapture()
            let session = LanguageModelSession(tools: [ATHLTHCoachReadQueryTool(capture: capture)],
                instructions: "Select the requested read-only query exactly once. Default period: 56 days. Weekly: 7 days; monthly: 30 days. Never widen filters.")
            do {
                _ = try await session.respond(to: String(question.prefix(1000)))
                try Task.checkCancellation()
                if let selected = await capture.result(), selected == parsed { return selected }
            } catch is CancellationError { throw CancellationError() }
            catch { /* local deterministic fallback */ }
        }
        #endif
        return parsed
    }
}
