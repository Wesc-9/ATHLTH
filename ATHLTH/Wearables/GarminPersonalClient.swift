#if ATHLTH_GARMIN_PERSONAL && DEBUG
import Foundation
import Security

/// This file is excluded from every ordinary Debug/Release/TestFlight build.
/// Opt in explicitly only for a private, owner-installed development build.
enum GarminPersonalClientError: Error {
    case invalidKey, invalidToken, invalidResponse, unauthorized, throttled, server, keychain
}

enum GarminPersonalKeychain {
    private static func query(_ account: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wesc9.athlth.garmin.personal.private",
            kSecAttrAccount as String: account.uuidString,
            kSecAttrSynchronizable as String: false
        ]
    }

    static func read(_ account: UUID) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw GarminPersonalClientError.keychain
        }
        return key
    }

    static func save(_ key: String, account: UUID) throws {
        let q = query(account)
        let values: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updated = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw GarminPersonalClientError.keychain }
        let added = SecItemAdd(q.merging(values) { _, new in new } as CFDictionary, nil)
        guard added == errSecSuccess else { throw GarminPersonalClientError.keychain }
    }

    static func remove(_ account: UUID) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GarminPersonalClientError.keychain
        }
    }
}

private final class GarminNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct GarminPersonalPreview {
    let workouts: [GarminImportedActivity]
    let steps: Int?
    let sleepSeconds: Double?
    let restingHeartRate: Double?
    let overnightHRV: Double?
    let averageStress: Double?
    let bodyBatteryHigh: Double?
    let bodyBatteryLow: Double?
    let unavailableSections: Int
    let measurementDay: Date
    let historyPossiblyTruncated: Bool
    let sleepStages: GarminPersonalSleep.Day?
    let stepsHistory: [String: Double]
    let hrvHistory: [String: Double]
    let restingHeartHistory: [String: Double]
    let activeEnergy: Double?
    let basalEnergy: Double?
}

@MainActor
final class GarminPersonalClient {
    private let base = "https://personal.connectapi.garmin.com"
    private let session: URLSession
    private var token: String?
    private var tokenExpiry: Date = .distantPast

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: GarminNoRedirect(), delegateQueue: nil)
    }

    func close() {
        token = nil
        tokenExpiry = .distantPast
        session.invalidateAndCancel()
    }

    private func request(path: String, query: [URLQueryItem] = [],
                         method: String = "GET", authorization: String) async throws -> Data {
        guard var components = URLComponents(string: base + path) else {
            throw GarminPersonalClientError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url, url.scheme == "https",
              url.host == "personal.connectapi.garmin.com" else {
            throw GarminPersonalClientError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GarminPersonalClientError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw GarminPersonalClientError.unauthorized
        case 429: throw GarminPersonalClientError.throttled
        default: throw GarminPersonalClientError.server
        }
    }

    private func bearer(_ key: String) async throws -> String {
        if let token, tokenExpiry.timeIntervalSinceNow > 300 { return token }
        guard !key.isEmpty, key.count <= 4096,
              !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw GarminPersonalClientError.invalidKey
        }
        let data = try await request(
            path: "/personalapitoken-service/personal-api/personal-api-key/token",
            method: "POST", authorization: "ApiKey " + key
        )
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw GarminPersonalClientError.invalidToken
        }
        let parts = value.split(separator: ".")
        guard parts.count == 3 else { throw GarminPersonalClientError.invalidToken }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let decoded = Data(base64Encoded: payload),
              let claims = try JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let exp = claims["exp"] as? Double, exp.isFinite,
              exp > Date().timeIntervalSince1970 else { throw GarminPersonalClientError.invalidToken }
        // Expiry is a cache hint, not identity verification.
        token = value
        tokenExpiry = Date(timeIntervalSince1970: exp)
        return value
    }

    private func get<T: Decodable>(_ type: T.Type, path: String,
                                  query: [URLQueryItem] = [], key: String) async throws -> T {
        let data: Data
        do {
            let auth = try await bearer(key)
            data = try await request(path: path, query: query, authorization: "Bearer " + auth)
        } catch GarminPersonalClientError.unauthorized {
            token = nil
            let auth = try await bearer(key)
            data = try await request(path: path, query: query, authorization: "Bearer " + auth)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func preview(key: String) async throws -> GarminPersonalPreview {
        let today = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: today)
        let from = formatter.string(from: Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today)
        var workouts: [String: GarminImportedActivity] = [:]
        var possiblyTruncated = false
        // Bounded first import. No partial history is represented as complete.
        for offset in stride(from: 0, to: 500, by: 50) {
            try Task.checkCancellation()
            let rows = try await get([GarminPersonalActivityResponse].self,
                path: "/activitylist-service/activities/search/activities",
                query: [.init(name: "start", value: String(offset)), .init(name: "limit", value: "50"),
                        .init(name: "startDate", value: from), .init(name: "endDate", value: day)],
                key: key)
            for row in rows {
                let item = try row.normalized()
                workouts[item.workout.id] = item
            }
            if rows.count < 50 { break }
            if offset == 450 { possiblyTruncated = true }
        }
        var unavailable = 0
        func optional<T: Decodable>(_ type: T.Type, path: String,
                                    query: [URLQueryItem] = []) async throws -> T? {
            try Task.checkCancellation()
            do { return try await get(type, path: path, query: query, key: key) }
            catch GarminPersonalClientError.unauthorized { throw GarminPersonalClientError.unauthorized }
            catch GarminPersonalClientError.throttled { throw GarminPersonalClientError.throttled }
            catch {
                try Task.checkCancellation()
                unavailable += 1
                return nil
            }
        }
        let dateQuery = [URLQueryItem(name: "date", value: day)]
        let steps = try await optional([GarminPersonalSteps].self,
            path: "/usersummary-service/stats/steps/daily/" + from + "/" + day)
        let sleep = try await optional(GarminPersonalSleep.self,
            path: "/sleep-service/sleep/dailySleep", query: dateQuery)
        let heart = try await optional(GarminPersonalHeart.self,
            path: "/wellness-service/wellness/dailyHeartRate", query: dateQuery)
        let hrv = try await optional(GarminPersonalHRV.self, path: "/hrv-service/hrv/" + day)
        let summary = try await optional(GarminPersonalDailySummary.self,
            path: "/usersummary-service/v2/dailysummaries",
            query: [.init(name: "startDate", value: from), .init(name: "endDate", value: day)])
        let hrvHistory = try await optional(GarminPersonalHRVHistory.self,
            path: "/hrv-service/hrv/daily/" + from + "/" + day)
        let daily = summary?.data.first { $0.calendarDate == day }
        var stepsByDay: [String: Double] = [:]
        var hrvByDay: [String: Double] = [:]
        var restByDay: [String: Double] = [:]
        for entry in steps ?? [] {
            if let value = entry.totalSteps, value >= 0 { stepsByDay[entry.calendarDate] = Double(value) }
        }
        for entry in hrvHistory?.hrvSummaries ?? [] {
            if let value = entry.lastNightAvg, value.isFinite, value > 0 { hrvByDay[entry.calendarDate] = value }
        }
        for entry in summary?.data ?? [] {
            if let date = entry.calendarDate, let value = entry.restingHeartRate,
               value.isFinite, value > 0 { restByDay[date] = value }
        }
        let sleepDay = sleep?.day.calendarDate == day ? sleep?.day : nil
        return GarminPersonalPreview(
            workouts: workouts.values.sorted { $0.workout.startedAt > $1.workout.startedAt },
            steps: steps?.first { $0.calendarDate == day }?.totalSteps,
            sleepSeconds: sleepDay?.sleepTimeSeconds, restingHeartRate: heart?.restingHeartRate ?? restByDay[day],
            overnightHRV: hrv?.hrvSummary?.lastNightAvg ?? hrvByDay[day],
            averageStress: daily?.averageStressLevel, bodyBatteryHigh: daily?.bodyBatteryHighestValue,
            bodyBatteryLow: daily?.bodyBatteryLowestValue, unavailableSections: unavailable,
            measurementDay: Calendar.current.startOfDay(for: today),
            historyPossiblyTruncated: possiblyTruncated, sleepStages: sleepDay,
            stepsHistory: stepsByDay, hrvHistory: hrvByDay, restingHeartHistory: restByDay,
            activeEnergy: daily?.activeKilocalories, basalEnergy: daily?.bmrKilocalories)
    }
}
#endif
