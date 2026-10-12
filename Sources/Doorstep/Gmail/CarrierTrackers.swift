import Foundation

/// Official, free carrier tracking APIs. Each carrier is optional: packages from a
/// carrier with saved credentials get live tracking, the rest fall back to 17TRACK
/// (if set up) or to email.
///
/// Every client turns its carrier's response into a `LiveTracking`, using the same
/// status vocabulary as 17TRACK (InTransit, OutForDelivery, Delivered, Exception…).
protocol CarrierTracker {
    func track(_ number: String) async throws -> LiveTracking?
    /// Confirms the credentials work (fetches a token, or makes a harmless request).
    func verify() async throws
}

// MARK: - Credentials

struct CarrierCredentials {
    var id: String
    var secret: String?

    enum Kind: String, CaseIterable, Identifiable {
        case ups, usps, fedex, dhl
        var id: String { rawValue }

        var carrier: Carrier {
            switch self {
            case .ups: .ups
            case .usps: .usps
            case .fedex: .fedex
            case .dhl: .dhl
            }
        }

        var name: String { carrier.displayName }
        var needsSecret: Bool { self != .dhl }

        var idLabel: String {
            switch self {
            case .ups: "Client ID"
            case .usps: "Consumer key"
            case .fedex: "API key"
            case .dhl: "API key"
            }
        }

        var secretLabel: String {
            switch self {
            case .ups: "Client secret"
            case .usps: "Consumer secret"
            case .fedex: "Secret key"
            case .dhl: ""
            }
        }

        var signupURL: URL {
            switch self {
            case .ups: URL(string: "https://developer.ups.com")!
            case .usps: URL(string: "https://developers.usps.com")!
            case .fedex: URL(string: "https://developer.fedex.com")!
            case .dhl: URL(string: "https://developer.dhl.com/api-reference/shipment-tracking")!
            }
        }

        func tracker(_ c: CarrierCredentials) -> CarrierTracker {
            switch self {
            case .ups: UPSTracker(clientId: c.id, clientSecret: c.secret ?? "")
            case .usps: USPSTracker(clientId: c.id, clientSecret: c.secret ?? "")
            case .fedex: FedExTracker(clientId: c.id, clientSecret: c.secret ?? "")
            case .dhl: DHLTracker(apiKey: c.id)
            }
        }
    }

    static func load(_ kind: Kind) -> CarrierCredentials? {
        guard let id = Keychain.get("\(kind.rawValue)-id") else { return nil }
        let secret = Keychain.get("\(kind.rawValue)-secret")
        if kind.needsSecret && secret == nil { return nil }
        return CarrierCredentials(id: id, secret: secret)
    }

    static func save(_ kind: Kind, _ c: CarrierCredentials) {
        Keychain.set(c.id, for: "\(kind.rawValue)-id")
        if let secret = c.secret { Keychain.set(secret, for: "\(kind.rawValue)-secret") }
    }

    static func delete(_ kind: Kind) {
        Keychain.delete("\(kind.rawValue)-id")
        Keychain.delete("\(kind.rawValue)-secret")
        TokenCache.shared.clear(kind.rawValue)
    }

    static func kind(for carrier: Carrier) -> Kind? {
        Kind.allCases.first { $0.carrier == carrier }
    }
}

/// OAuth access tokens, reused until shortly before they expire.
final class TokenCache: @unchecked Sendable {
    static let shared = TokenCache()
    private var tokens: [String: (token: String, expiry: Date)] = [:]
    private let lock = NSLock()

    func token(_ key: String, fetch: () async throws -> (String, Int)) async throws -> String {
        if let cached = lock.withLock({ tokens[key] }), cached.expiry > Date() { return cached.token }
        let (token, expiresIn) = try await fetch()
        lock.withLock { tokens[key] = (token, Date().addingTimeInterval(TimeInterval(max(expiresIn - 120, 60)))) }
        return token
    }

    func clear(_ key: String) { lock.withLock { _ = tokens.removeValue(forKey: key) } }
}

enum CarrierAPIError: LocalizedError {
    case auth(String), http(String, Int)
    var errorDescription: String? {
        switch self {
        case .auth(let carrier): "\(carrier) didn't accept these credentials."
        case .http(let carrier, let code): "\(carrier) tracking returned an error (\(code))."
        }
    }
}

// MARK: - Shared helpers

private enum HTTP {
    static func json(_ req: URLRequest, carrier: String) async throws -> (Int, [String: Any]) {
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (code, object)
    }

    static func form(_ fields: [String: String]) -> Data? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
    }

    static func expiresIn(_ any: Any?) -> Int {
        (any as? Int) ?? Int(any as? String ?? "") ?? 3600
    }
}

private func iso(_ s: String?) -> Date? { TrackingService.parseDate(s) }

/// "20261012" + "074100" → Date (local time, as UPS reports it).
private func compactDate(_ date: String?, _ time: String? = nil) -> Date? {
    guard let date, date.count == 8 else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    if let time, time.count >= 4 {
        f.dateFormat = time.count >= 6 ? "yyyyMMddHHmmss" : "yyyyMMddHHmm"
        return f.date(from: date + time)
    }
    f.dateFormat = "yyyyMMdd"
    return f.date(from: date)
}

private func place(_ parts: String?...) -> String? {
    let joined = parts.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        .map { $0.count > 3 && $0 == $0.uppercased() ? $0.capitalized : $0 }
        .joined(separator: ", ")
    return joined.isEmpty ? nil : joined
}

// MARK: - UPS (developer.ups.com · Track API v1)

struct UPSTracker: CarrierTracker {
    let clientId: String
    let clientSecret: String

    private func accessToken() async throws -> String {
        try await TokenCache.shared.token("ups") {
            var req = URLRequest(url: URL(string: "https://onlinetools.ups.com/security/v1/oauth/token")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue("Basic " + Data("\(clientId):\(clientSecret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            req.httpBody = HTTP.form(["grant_type": "client_credentials"])
            let (code, json) = try await HTTP.json(req, carrier: "UPS")
            guard code == 200, let token = json["access_token"] as? String else { throw CarrierAPIError.auth("UPS") }
            return (token, HTTP.expiresIn(json["expires_in"]))
        }
    }

    func verify() async throws { _ = try await accessToken() }

    func track(_ number: String) async throws -> LiveTracking? {
        var comps = URLComponents(string: "https://onlinetools.ups.com/api/track/v1/details/\(number)")!
        comps.queryItems = [.init(name: "locale", value: "en_US"), .init(name: "returnSignature", value: "false")]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "transId")
        req.setValue("Doorstep", forHTTPHeaderField: "transactionSrc")
        let (code, json) = try await HTTP.json(req, carrier: "UPS")
        if code == 404 { return nil }
        guard code == 200 else { throw CarrierAPIError.http("UPS", code) }
        return Self.parse(json, now: Date())
    }

    static func parse(_ json: [String: Any], now: Date) -> LiveTracking? {
        let shipment = ((json["trackResponse"] as? [String: Any])?["shipment"] as? [[String: Any]])?.first
        guard let pkg = (shipment?["package"] as? [[String: Any]])?.first else { return nil }

        let events: [LiveEvent] = (pkg["activity"] as? [[String: Any]] ?? []).compactMap { a in
            guard let date = compactDate(a["date"] as? String, a["time"] as? String) else { return nil }
            let status = a["status"] as? [String: Any]
            let address = (a["location"] as? [String: Any])?["address"] as? [String: Any]
            return LiveEvent(date: date,
                             description: (status?["description"] as? String ?? "Update").trimmingCharacters(in: .whitespaces).capitalizedSentence,
                             location: place(address?["city"] as? String, address?["stateProvince"] as? String))
        }.sorted { $0.date > $1.date }

        // Status type: D delivered, I in transit, X exception, P pickup, M manifest; "out for delivery" is an I with that text.
        let current = pkg["currentStatus"] as? [String: Any]
        let latestStatus = ((pkg["activity"] as? [[String: Any]])?.first?["status"] as? [String: Any])
        let type = (latestStatus?["type"] as? String) ?? (current?["type"] as? String) ?? ""
        let text = ((current?["description"] as? String) ?? (latestStatus?["description"] as? String) ?? "").lowercased()
        let status: String
        if type == "D" || text.contains("delivered") { status = "Delivered" }
        else if text.contains("out for delivery") { status = "OutForDelivery" }
        else if type == "X" { status = "Exception" }
        else if text.contains("ready for") && text.contains("pickup") { status = "AvailableForPickup" }
        else if type == "M" || type == "P" { status = "InfoReceived" }
        else if type == "I" { status = "InTransit" }
        else { status = events.isEmpty ? "NotFound" : "InTransit" }

        // Expected date + optional window (EDW/CDW/IDW carry start and end).
        let dates = pkg["deliveryDate"] as? [[String: Any]] ?? []
        let day = dates.first { ($0["type"] as? String) == "RDD" }?["date"] as? String
            ?? dates.first { ($0["type"] as? String) == "SDD" }?["date"] as? String
        let time = pkg["deliveryTime"] as? [String: Any]
        let timeType = time?["type"] as? String ?? ""
        var from = compactDate(day)
        var to: Date?
        if ["EDW", "CDW", "IDW"].contains(timeType) {
            from = compactDate(day, time?["startTime"] as? String) ?? from
            to = compactDate(day, time?["endTime"] as? String)
        } else if timeType == "CMT" || timeType == "EOD" {
            to = compactDate(day, time?["endTime"] as? String)
        }

        return LiveTracking(status: status, events: events, estimatedFrom: from, estimatedTo: to, carrierName: "UPS", lastChecked: now)
    }
}

// MARK: - USPS (developers.usps.com · Tracking v3)

struct USPSTracker: CarrierTracker {
    let clientId: String
    let clientSecret: String

    private func accessToken() async throws -> String {
        try await TokenCache.shared.token("usps") {
            var req = URLRequest(url: URL(string: "https://apis.usps.com/oauth2/v3/token")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "client_id": clientId, "client_secret": clientSecret, "grant_type": "client_credentials",
            ])
            let (code, json) = try await HTTP.json(req, carrier: "USPS")
            guard code == 200, let token = json["access_token"] as? String else { throw CarrierAPIError.auth("USPS") }
            return (token, HTTP.expiresIn(json["expires_in"]))
        }
    }

    func verify() async throws { _ = try await accessToken() }

    func track(_ number: String) async throws -> LiveTracking? {
        var comps = URLComponents(string: "https://apis.usps.com/tracking/v3/tracking/\(number)")!
        comps.queryItems = [.init(name: "expand", value: "DETAIL")]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (code, json) = try await HTTP.json(req, carrier: "USPS")
        if code == 404 { return nil }
        guard code == 200 else { throw CarrierAPIError.http("USPS", code) }
        return Self.parse(json, now: Date())
    }

    static func parse(_ json: [String: Any], now: Date) -> LiveTracking? {
        let events: [LiveEvent] = (json["trackingEvents"] as? [[String: Any]] ?? []).compactMap { e in
            guard let date = iso(e["GMTTimestamp"] as? String) ?? iso(e["eventTimestamp"] as? String) else { return nil }
            return LiveEvent(date: date, description: (e["eventType"] as? String ?? "Update").capitalizedSentence,
                             location: place(e["eventCity"] as? String, e["eventState"] as? String))
        }.sorted { $0.date > $1.date }

        let category = ((json["statusCategory"] as? String) ?? (json["status"] as? String) ?? "").lowercased()
        let status: String
        if category.contains("delivered") && !category.contains("attempt") { status = "Delivered" }
        else if category.contains("out for delivery") { status = "OutForDelivery" }
        else if category.contains("pickup") || category.contains("available") { status = "AvailableForPickup" }
        else if category.contains("alert") || category.contains("attempt") || category.contains("return to sender") { status = "Exception" }
        else if category.contains("pre-shipment") || category.contains("label") { status = "InfoReceived" }
        else if category.isEmpty { status = events.isEmpty ? "NotFound" : "InTransit" }
        else { status = "InTransit" }

        let dayString = (json["predictedDeliveryDate"] as? String) ?? (json["expectedDeliveryDate"] as? String)
        let day = iso(dayString)
        let from = clockTime(json["predictedDeliveryWindowStartTime"] as? String ?? json["expectedDeliveryTimeStart"] as? String, on: day) ?? day
        let to = clockTime(json["predictedDeliveryWindowEndTime"] as? String ?? json["expectedDeliveryTimeEnd"] as? String, on: day)
        return LiveTracking(status: status, events: events, estimatedFrom: from, estimatedTo: to, carrierName: "USPS", lastChecked: now)
    }

    /// "10:30", "10:30:00", "10:30 AM" on a given day.
    private static func clockTime(_ s: String?, on day: Date?) -> Date? {
        guard let s, let day else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["HH:mm:ss", "HH:mm", "h:mm a", "h:mma", "ha"] {
            f.dateFormat = format
            if let t = f.date(from: s.trimmingCharacters(in: .whitespaces)) {
                let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                return Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day)
            }
        }
        return nil
    }
}

// MARK: - FedEx (developer.fedex.com · Track API v1)

struct FedExTracker: CarrierTracker {
    let clientId: String
    let clientSecret: String

    private func accessToken() async throws -> String {
        try await TokenCache.shared.token("fedex") {
            var req = URLRequest(url: URL(string: "https://apis.fedex.com/oauth/token")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = HTTP.form(["grant_type": "client_credentials", "client_id": clientId, "client_secret": clientSecret])
            let (code, json) = try await HTTP.json(req, carrier: "FedEx")
            guard code == 200, let token = json["access_token"] as? String else { throw CarrierAPIError.auth("FedEx") }
            return (token, HTTP.expiresIn(json["expires_in"]))
        }
    }

    func verify() async throws { _ = try await accessToken() }

    func track(_ number: String) async throws -> LiveTracking? {
        var req = URLRequest(url: URL(string: "https://apis.fedex.com/track/v1/trackingnumbers")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("en_US", forHTTPHeaderField: "X-locale")
        req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "includeDetailedScans": true,
            "trackingInfo": [["trackingNumberInfo": ["trackingNumber": number]]],
        ])
        let (code, json) = try await HTTP.json(req, carrier: "FedEx")
        guard code == 200 else { throw CarrierAPIError.http("FedEx", code) }
        return Self.parse(json, now: Date())
    }

    static func parse(_ json: [String: Any], now: Date) -> LiveTracking? {
        let complete = ((json["output"] as? [String: Any])?["completeTrackResults"] as? [[String: Any]])?.first
        guard let result = (complete?["trackResults"] as? [[String: Any]])?.first, result["error"] == nil else { return nil }

        let events: [LiveEvent] = (result["scanEvents"] as? [[String: Any]] ?? []).compactMap { e in
            guard let date = iso(e["date"] as? String) else { return nil }
            let loc = e["scanLocation"] as? [String: Any]
            return LiveEvent(date: date, description: (e["eventDescription"] as? String ?? "Update").capitalizedSentence,
                             location: place(loc?["city"] as? String, loc?["stateOrProvinceCode"] as? String))
        }.sorted { $0.date > $1.date }

        let latest = result["latestStatusDetail"] as? [String: Any]
        let statusCode = ((latest?["derivedCode"] as? String) ?? (latest?["code"] as? String) ?? "").uppercased()
        let status: String
        switch statusCode {
        case "DL": status = "Delivered"
        case "OD": status = "OutForDelivery"
        case "HL", "HP": status = "AvailableForPickup"
        case "DE", "SE", "CA", "DY", "RS": status = "Exception"
        case "OC", "LP": status = "InfoReceived"
        case "": status = events.isEmpty ? "NotFound" : "InTransit"
        default: status = "InTransit"
        }

        let window = (result["estimatedDeliveryTimeWindow"] as? [String: Any])?["window"] as? [String: Any]
        var from = iso(window?["begins"] as? String)
        var to = iso(window?["ends"] as? String)
        if from == nil, to == nil {
            let dates = result["dateAndTimes"] as? [[String: Any]] ?? []
            from = iso(dates.first { ($0["type"] as? String) == "ESTIMATED_DELIVERY" }?["dateTime"] as? String)
            to = nil
        }
        return LiveTracking(status: status, events: events, estimatedFrom: from, estimatedTo: to, carrierName: "FedEx", lastChecked: now)
    }
}

// MARK: - DHL (developer.dhl.com · Shipment Tracking – Unified)

struct DHLTracker: CarrierTracker {
    let apiKey: String

    private func request(_ number: String) async throws -> (Int, [String: Any]) {
        var comps = URLComponents(string: "https://api-eu.dhl.com/track/shipments")!
        comps.queryItems = [.init(name: "trackingNumber", value: number)]
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey, forHTTPHeaderField: "DHL-API-Key")
        return try await HTTP.json(req, carrier: "DHL")
    }

    /// An unknown number returns 404 with a good key and 401 with a bad one.
    func verify() async throws {
        let (code, _) = try await request("0000000000")
        if code == 401 || code == 403 { throw CarrierAPIError.auth("DHL") }
    }

    func track(_ number: String) async throws -> LiveTracking? {
        let (code, json) = try await request(number)
        if code == 404 { return nil }
        if code == 401 || code == 403 { throw CarrierAPIError.auth("DHL") }
        guard code == 200 else { throw CarrierAPIError.http("DHL", code) }
        return Self.parse(json, now: Date())
    }

    static func parse(_ json: [String: Any], now: Date) -> LiveTracking? {
        guard let shipment = (json["shipments"] as? [[String: Any]])?.first else { return nil }
        func locality(_ e: [String: Any]?) -> String? {
            ((e?["location"] as? [String: Any])?["address"] as? [String: Any])?["addressLocality"] as? String
        }
        let events: [LiveEvent] = (shipment["events"] as? [[String: Any]] ?? []).compactMap { e in
            guard let date = iso(e["timestamp"] as? String) else { return nil }
            let text = (e["description"] as? String) ?? (e["status"] as? String) ?? "Update"
            return LiveEvent(date: date, description: text.capitalizedSentence, location: place(locality(e)))
        }.sorted { $0.date > $1.date }

        let current = shipment["status"] as? [String: Any]
        let code = (current?["statusCode"] as? String ?? "").lowercased()
        let text = ((current?["status"] as? String) ?? (current?["description"] as? String) ?? "").lowercased()
        let status: String
        if code == "delivered" { status = "Delivered" }
        else if text.contains("out for delivery") || text.contains("with delivery courier") { status = "OutForDelivery" }
        else if code == "failure" { status = "Exception" }
        else if code == "pre-transit" { status = "InfoReceived" }
        else if code == "transit" { status = "InTransit" }
        else { status = events.isEmpty ? "NotFound" : "InTransit" }

        let frame = shipment["estimatedDeliveryTimeFrame"] as? [String: Any]
        let from = iso(frame?["estimatedFrom"] as? String) ?? iso(shipment["estimatedTimeOfDelivery"] as? String)
        let to = iso(frame?["estimatedThrough"] as? String)
        return LiveTracking(status: status, events: events, estimatedFrom: from, estimatedTo: to, carrierName: "DHL", lastChecked: now)
    }
}

extension String {
    /// "OUT FOR DELIVERY TODAY" → "Out for delivery today"; mixed-case text is left alone.
    var capitalizedSentence: String {
        guard self == uppercased(), contains(where: \.isLetter) else { return self }
        let lower = lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
