import Foundation

struct GmailMessage {
    let id: String
    let threadId: String
    let date: Date
    let fromName: String
    let fromAddress: String
    let subject: String
    let html: String?
    let plainText: String?
}

struct GmailClient {
    let token: String
    private let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    /// Shipping and order emails from the last few weeks. Promotions are excluded so
    /// "20% off your next order" mail never becomes a package.
    static let searchQuery = """
    newer_than:60d -category:promotions -category:social -from:informeddelivery.usps.com \
    (category:purchases OR subject:(order OR ordered OR shipped OR "out for delivery" OR delivered OR \
    arriving OR shipment OR tracking OR package OR delivery OR delayed OR return OR refund))
    """

    func profileEmail() async throws -> String {
        struct Profile: Decodable { let emailAddress: String }
        let data = try await get("\(base)/profile")
        return try JSONDecoder().decode(Profile.self, from: data).emailAddress
    }

    func listMessageIDs(query: String = searchQuery, limit: Int = 400) async throws -> [String] {
        struct Page: Decodable {
            struct Ref: Decodable { let id: String }
            let messages: [Ref]?
            let nextPageToken: String?
        }
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var comps = URLComponents(string: "\(base)/messages")!
            comps.queryItems = [
                .init(name: "q", value: query),
                .init(name: "maxResults", value: "100"),
            ] + (pageToken.map { [.init(name: "pageToken", value: $0)] } ?? [])
            let page = try JSONDecoder().decode(Page.self, from: try await get(comps.url!.absoluteString))
            ids += page.messages?.map(\.id) ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil && ids.count < limit
        return Array(ids.prefix(limit))
    }

    func message(id: String) async throws -> GmailMessage {
        let data = try await get("\(base)/messages/\(id)?format=full")
        let raw = try JSONDecoder().decode(RawMessage.self, from: data)

        let headers = raw.payload.headers ?? []
        func header(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }
        let (fromName, fromAddress) = Self.parseFrom(header("From"))

        var html: String?
        var text: String?
        func walk(_ part: RawPart) {
            if let body = part.body?.data, let decoded = Data(base64URLEncoded: body),
               let string = String(data: decoded, encoding: .utf8) ?? String(data: decoded, encoding: .isoLatin1) {
                if part.mimeType == "text/html", html == nil { html = string }
                if part.mimeType == "text/plain", text == nil { text = string }
            }
            part.parts?.forEach(walk)
        }
        walk(raw.payload)

        let millis = Double(raw.internalDate ?? "") ?? Date().timeIntervalSince1970 * 1000
        return GmailMessage(
            id: raw.id,
            threadId: raw.threadId,
            date: Date(timeIntervalSince1970: millis / 1000),
            fromName: fromName,
            fromAddress: fromAddress,
            subject: header("Subject"),
            html: html,
            plainText: text
        )
    }

    private func get(_ url: String) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GmailError.http(code) }
        return data
    }

    static func parseFrom(_ value: String) -> (String, String) {
        // "Amazon.com <shipment-tracking@amazon.com>"
        if let lt = value.lastIndex(of: "<"), let gt = value.lastIndex(of: ">"), lt < gt {
            let name = value[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            let address = String(value[value.index(after: lt)..<gt])
            return (name.isEmpty ? address : name, address)
        }
        return (value, value)
    }

    private struct RawMessage: Decodable {
        let id: String
        let threadId: String
        let internalDate: String?
        let payload: RawPart
    }

    private struct RawPart: Decodable {
        struct Header: Decodable { let name: String; let value: String }
        struct Body: Decodable { let data: String? }
        let mimeType: String?
        let headers: [Header]?
        let body: Body?
        let parts: [RawPart]?
    }
}

enum GmailError: LocalizedError {
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .http(401): "Gmail session expired."
        case .http(403): "Gmail access was denied. Check the Gmail API is enabled."
        case .http(let code): "Gmail returned an error (\(code))."
        }
    }
}
