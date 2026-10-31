import Foundation

/// A local routing shortcut for explicit Coach route requests. A chat prompt
/// never becomes geometry: route generation still requires user approval and
/// Apple Maps pedestrian directions.
enum ATHLTHCoachRouteIntent {
    static func isRequest(_ message: String) -> Bool {
        let lower = message.lowercased()
        let routeWord = ["rute", "løype", "løperute", "running route", "route"]
            .contains { lower.contains($0) }
        let action = ["lag ", "finn ", "planlegg ", "generer ", "foreslå ",
                      "kan du lage ", "can you create ", "create ", "find ", "suggest "]
            .contains { lower.contains($0) }
        let excluded = ["sykkelrute", "bike route", "driving route", "bilrute"]
            .contains { lower.contains($0) }
        return routeWord && action && !excluded
    }

    static func initialBrief(from message: String) -> ATHLTHCoachRouteBrief {
        var brief = ATHLTHCoachRouteBrief()
        let lower = message.lowercased()
        let distance = number(in: lower, pattern: #"\d+(?:[,.]\d+)?\s*km"#)
        let time = number(in: lower, pattern: #"\d+\s*(?:minutter|min|minutes)"#)
        if let distance, (0.8...30).contains(distance) {
            brief.useDistance = true
            brief.distanceKilometers = distance
        } else if time != nil {
            brief.useDistance = false
        }
        if let time, (15...180).contains(time) {
            brief.useDuration = true
            brief.durationMinutes = Int(time.rounded())
        }

        if lower.contains("fjell") || lower.contains("mountain") {
            brief.surface = .mountain
        } else if lower.contains("grus") || lower.contains("gravel") {
            brief.surface = .gravel
        } else if lower.contains("asfalt") || lower.contains("asphalt") {
            brief.surface = .asphalt
        } else if lower.contains("sti") || lower.contains("trail") {
            brief.surface = .path
        }
        if lower.contains("sentrum") || lower.contains("city centre") {
            brief.setting = .central
        } else if lower.contains("natur") || lower.contains("nature") {
            brief.setting = .quietNature
        } else if lower.contains("nær vei") || lower.contains("near roads") {
            brief.setting = .streets
        }
        if lower.contains("i nærheten") || lower.contains("nærområde") ||
            lower.contains("nearby") {
            brief.startMode = .nearby
        }
        if lower.contains("tur-retur") || lower.contains("samme vei tilbake") ||
            lower.contains("out and back") {
            brief.isLoop = false
        }
        return brief
    }

    private static func number(in value: String, pattern: String) -> Double? {
        guard let match = value.range(of: pattern, options: .regularExpression)
        else { return nil }
        let captured = value[match].prefix {
            $0.isNumber || $0 == "." || $0 == ","
        }
        return Double(captured.replacingOccurrences(of: ",", with: "."))
    }
}
