import CoreFoundation
import Foundation

/// Stable, privacy-safe descriptions of every proposed change. The complete
/// snapshots are retained separately so reviewers never approve hidden edits.
enum ChallengeChangeDiff {
    struct Row: Identifiable {
        let id: String
        let title: String
        let oldValue: String
        let newValue: String
    }

    static func rows(_ proposal: ChallengeChangeProposal) -> [Row] {
        let old = proposal.original
        let new = proposal.proposed
        var rows: [Row] = []

        func append(_ id: String, _ title: String, _ before: String, _ after: String) {
            guard before != after else { return }
            rows.append(Row(id: id, title: title, oldValue: before, newValue: after))
        }

        append("title", "Øktnavn", old.title, new.title)
        append("sport", "Treningstype", old.sport.title, new.sport.title)

        let before = properties(old.rules)
        let after = properties(new.rules)
        let keys = Set(before.keys).union(after.keys).sorted()
        for key in keys {
            let a = before[key]
            let b = after[key]
            guard fingerprint(a) != fingerprint(b) else { continue }
            let title = labels[key] ?? readable(key)
            append(key, title, value(a, key: key), value(b, key: key))
        }

        let oldPeople = old.participants
            .filter { $0.state != .creator }
            .map { "\($0.displayName) (\($0.state.rawValue))" }
            .sorted().joined(separator: ", ")
        let newPeople = new.participants
            .filter { $0.state != .creator }
            .map { "\($0.displayName) (\($0.state.rawValue))" }
            .sorted().joined(separator: ", ")
        append("participants", "Deltakere", oldPeople, newPeople)
        return rows
    }

    private static let labels: [String: String] = [
        "scoring": "Konkurransetype",
        "verificationPolicy": "Resultatkontroll",
        "targetDistanceMeters": "Måldistanse",
        "targetDurationSeconds": "Måltid",
        "timeBasis": "Tidsberegning",
        "route": "Rute",
        "gpsRequired": "GPS-krav",
        "minimumRouteMatchPercent": "Rutematch",
        "distanceTolerancePercent": "Distanseavvik",
        "startFinishToleranceMeters": "Start- og sluttoleranse",
        "routeDirection": "Ruteretning",
        "attemptPolicy": "Forsøksregler",
        "maximumAttempts": "Maks antall forsøk",
        "allowTreadmill": "Tredemølle",
        "allowTargetGhost": "Ghost-mål",
        "allowLiveGhost": "Live Ghost",
        "exerciseName": "Øvelse",
        "fixedWeightKilograms": "Vekt",
        "heartRateZone": "Pulssone",
        "heartRateAggregation": "Pulsmåling",
        "summary": "Beskrivelse",
        "coverArtworkName": "Forsidebilde",
        "coverImageURL": "Eget bilde",
        "headToHeadMetricRaw": "Duellmål",
        "startsAt": "Starttid",
        "endsAt": "Sluttid",
        "allowMultipleAttempts": "Flere forsøk",
        "lockRulesAtStart": "Regellås",
        "meetup": "Møtepunkt"
    ]

    private static func properties(_ rules: ATHLTHChallengeRules) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(rules),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    private static func fingerprint(_ value: Any?) -> String {
        guard let value else { return "<nil>" }
        guard let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]
        ) else { return String(describing: value) }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func value(_ raw: Any?, key: String) -> String {
        guard let raw else { return "–" }
        if let value = raw as? String {
            if (key == "startsAt" || key == "endsAt"),
               let date = ISO8601DateFormatter().date(from: value) {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
            return String(value.prefix(80))
        }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "Ja" : "Nei"
            }
            return number.stringValue
        }
        if let object = raw as? [String: Any] {
            if key == "route" { return (object["title"] as? String) ?? "Rute valgt" }
            if key == "meetup" {
                return (object["placeName"] as? String) ?? "Møtepunkt valgt"
            }
            return "Endret"
        }
        return "Endret"
    }

    private static func readable(_ key: String) -> String {
        key.replacingOccurrences(of: "([a-z])([A-Z])",
                                 with: "$1 $2",
                                 options: .regularExpression)
            .capitalized
    }
}
