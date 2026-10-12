import AppKit
import CryptoKit
import Foundation
import Observation

struct OAuthClient {
    let clientId: String
    let clientSecret: String

    /// Reads the JSON Google Cloud Console gives you for a "Desktop app" OAuth client.
    static func load() -> OAuthClient? {
        let candidates = [AppPaths.clientSecretFile, Bundle.main.url(forResource: "client_secret", withExtension: "json")]
        for url in candidates.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let body = (json["installed"] ?? json["web"]) as? [String: Any] ?? json
            if let id = body["client_id"] as? String, let secret = body["client_secret"] as? String {
                return OAuthClient(clientId: id, clientSecret: secret)
            }
        }
        return nil
    }

    /// Checks a file before using it, with a message a person can act on.
    static func validate(_ url: URL) -> Result<OAuthClient, ClientFileError> {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.notAClientFile) }
        if json["web"] != nil { return .failure(.webClient) }
        guard let body = json["installed"] as? [String: Any] else { return .failure(.notAClientFile) }
        guard let id = body["client_id"] as? String, let secret = body["client_secret"] as? String else { return .failure(.incomplete) }
        return .success(OAuthClient(clientId: id, clientSecret: secret))
    }

    /// Validates and copies a downloaded client file into place.
    static func importFile(_ url: URL) throws {
        if case .failure(let error) = validate(url) { throw error }
        let destination = AppPaths.clientSecretFile
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
    }

    /// The newest client_secret*.json in Downloads from the last day.
    static func newestDownload() -> URL? {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dayAgo = Date().addingTimeInterval(-86_400)
        return files
            .filter { $0.lastPathComponent.hasPrefix("client_secret") && $0.pathExtension == "json" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > dayAgo else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?.0
    }
}

enum ClientFileError: LocalizedError {
    case notAClientFile, webClient, incomplete
    var errorDescription: String? {
        switch self {
        case .notAClientFile: "This isn't a Google client file. Download the JSON from your Desktop app client."
        case .webClient: "This is a Web application client. Create a Desktop app client instead (step 5)."
        case .incomplete: "This client file is missing its ID or secret. Download it again."
        }
    }
}

@MainActor
@Observable
final class GoogleAuth {
    private static let refreshKey = "google-refresh-token"
    private static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    private(set) var isSignedIn: Bool
    private var accessToken: String?
    private var expiry = Date.distantPast

    private(set) var hasClientFile = OAuthClient.load() != nil
    /// Google revoked the sign-in (usually the weekly expiry while the app is in Testing).
    private(set) var signedOutByGoogle = UserDefaults.standard.bool(forKey: "signedOutByGoogle")

    init() {
        // Snapshot mode renders sample data and must never trigger a Keychain prompt.
        isSignedIn = Snapshot.isActive ? false : Keychain.get(Self.refreshKey) != nil
    }

    func importClientFile(_ url: URL) throws {
        try OAuthClient.importFile(url)
        hasClientFile = OAuthClient.load() != nil
    }

    func signIn() async throws {
        guard let client = OAuthClient.load() else { throw AuthError.missingClientFile }

        let server = LoopbackServer()
        let port = try await server.start()
        let redirect = "http://127.0.0.1:\(port)"
        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = Self.randomURLSafe(24)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: client.clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        NSWorkspace.shared.open(comps.url!)

        let result = try await server.waitForCallback()
        let query = Dictionary(uniqueKeysWithValues: (result.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = query["error"] { throw AuthError.denied(error) }
        guard query["state"] == state else { throw AuthError.stateMismatch }
        guard let code = query["code"] else { throw AuthError.cancelled }

        let tokens = try await Self.tokenRequest([
            "code": code,
            "client_id": client.clientId,
            "client_secret": client.clientSecret,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refresh = tokens.refresh_token else { throw AuthError.tokenExchange("no refresh token returned") }
        Keychain.set(refresh, for: Self.refreshKey)
        accessToken = tokens.access_token
        expiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in - 60))
        isSignedIn = true
        signedOutByGoogle = false
        UserDefaults.standard.set(false, forKey: "signedOutByGoogle")
        NSApp.activate()
    }

    func validAccessToken() async throws -> String {
        if let accessToken, Date() < expiry { return accessToken }
        guard let refresh = Keychain.get(Self.refreshKey) else { throw AuthError.notSignedIn }
        guard let client = OAuthClient.load() else { throw AuthError.missingClientFile }
        do {
            let tokens = try await Self.tokenRequest([
                "refresh_token": refresh,
                "client_id": client.clientId,
                "client_secret": client.clientSecret,
                "grant_type": "refresh_token",
            ])
            accessToken = tokens.access_token
            expiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in - 60))
            return tokens.access_token
        } catch AuthError.tokenExchange(let msg) where msg.contains("invalid_grant") {
            // Refresh token revoked or expired (e.g. app still in Google's "Testing" mode).
            signOut()
            signedOutByGoogle = true
            UserDefaults.standard.set(true, forKey: "signedOutByGoogle")
            throw AuthError.notSignedIn
        }
    }

    func signOut() {
        Keychain.delete(Self.refreshKey)
        accessToken = nil
        expiry = .distantPast
        isSignedIn = false
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    private static func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.tokenExchange(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
