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
}

@MainActor
@Observable
final class GoogleAuth {
    private static let refreshKey = "google-refresh-token"
    private static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    private(set) var isSignedIn: Bool
    private var accessToken: String?
    private var expiry = Date.distantPast

    var hasClientFile: Bool { OAuthClient.load() != nil }

    init() {
        isSignedIn = Keychain.get(Self.refreshKey) != nil
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
