import Foundation

/// 17TRACK API v2.4 (https://api.17track.net). One key covers UPS, USPS, FedEx, DHL and
/// most other carriers. Registering a number uses one unit of the account's quota;
/// reading its status afterwards is free.
struct TrackingService {
    let key: String
    private let base = "https://api.17track.net/track/v2.4"

    static let keychainAccount = "17track-key"

    /// Returns the numbers 17TRACK is now tracking (newly accepted or already registered).
    func register(_ numbers: [String]) async throws -> Set<String> {
        var tracked = Set<String>()
        for batch in numbers.chunked(40) {
            let data = try await post("/register", body: batch.map { ["number": $0] })
            for item in data["accepted"] as? [[String: Any]] ?? [] {
                if let n = item["number"] as? String { tracked.insert(n) }
            }
            for item in data["rejected"] as? [[String: Any]] ?? [] {
                let message = ((item["error"] as? [String: Any])?["message"] as? String ?? "").lowercased()
                if message.contains("already"), let n = item["number"] as? String { tracked.insert(n) }
            }
        }
        return tracked
    }

    func trackInfo(_ numbers: [String], now: Date = Date()) async throws -> [String: LiveTracking] {
        var result: [String: LiveTracking] = [:]
        for batch in numbers.chunked(40) {
            let data = try await post("/gettrackinfo", body: batch.map { ["number": $0] })
            for item in data["accepted"] as? [[String: Any]] ?? [] {
                guard let number = item["number"] as? String else { continue }
                result[number] = Self.parse(item, now: now)
            }
        }
        return result
    }

    /// (used, total) registrations, when the account reports them.
    func quota() async -> (used: Int, total: Int)? {
        guard let data = try? await post("/getquota", body: [[String: String]]()) else { return nil }
        let used = (data["quota_used"] as? Int) ?? (data["quota_used"] as? NSNumber)?.intValue
        let total = (data["quota_total"] as? Int) ?? (data["quota_total"] as? NSNumber)?.intValue
        guard let used, let total else { return nil }
        return (used, total)
    }

    // MARK: Parsing (defensive: fields are looked up under track_info first, then the item)

    static func parse(_ item: [String: Any], now: Date) -> LiveTracking {
        let info = item["track_info"] as? [String: Any] ?? [:]
        func field(_ key: String) -> Any? { info[key] ?? item[key] }

        let latest = field("latest_status") as? [String: Any]
        let status = latest?["status"] as? String ?? "NotFound"

        let tracking = field("tracking") as? [String: Any]
        let providers = tracking?["providers"] as? [[String: Any]] ?? []
        let provider = providers.first
        let carrierName = (provider?["provider"] as? [String: Any])?["name"] as? String

        let events: [LiveEvent] = (provider?["events"] as? [[String: Any]] ?? []).compactMap { e in
            guard let date = parseDate(e["time_iso"]) ?? parseDate(e["time_utc"]) else { return nil }
            let description = (e["description"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            var location = e["location"] as? String
            if location?.isEmpty ?? true, let address = e["address"] as? [String: Any] {
                location = [address["city"], address["state"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
            return LiveEvent(date: date, description: description.isEmpty ? "Update" : description,
                             location: (location?.isEmpty ?? true) ? nil : location)
        }.sorted { $0.date > $1.date }

        let metrics = field("time_metrics") as? [String: Any]
        let estimate = metrics?["estimated_delivery_date"] as? [String: Any]

        return LiveTracking(
            status: status,
            events: events,
            estimatedFrom: parseDate(estimate?["from"]),
            estimatedTo: parseDate(estimate?["to"]),
            carrierName: carrierName,
            lastChecked: now
        )
    }

    static func parseDate(_ value: Any?) -> Date? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    // MARK: HTTP

    private func post(_ path: String, body: Any) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: base + path)!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "17token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TrackingError.http(code)
        }
        if let apiCode = json["code"] as? Int, apiCode != 0 {
            let message = ((json["data"] as? [String: Any])?["errors"] as? [[String: Any]])?.first?["message"] as? String
            throw TrackingError.api(apiCode, message)
        }
        return json["data"] as? [String: Any] ?? [:]
    }
}

enum TrackingError: LocalizedError {
    case http(Int), api(Int, String?)
    var errorDescription: String? {
        switch self {
        case .http(401), .http(403): "17TRACK rejected the API key."
        case .http(let c): "17TRACK returned an error (\(c))."
        case .api(_, let m?): "17TRACK: \(m)"
        case .api(let c, nil): "17TRACK error \(c)."
        }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
