import Foundation
import Network

/// One-shot HTTP listener on 127.0.0.1 that catches Google's OAuth redirect.
final class LoopbackServer {
    private let queue = DispatchQueue(label: "doorstep.loopback")
    private var listener: NWListener?
    private var callback: CheckedContinuation<URLComponents, Error>?
    private var finished = false

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }

        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    cont.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    cont.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback(timeout: Duration = .seconds(300)) async throws -> URLComponents {
        try await withThrowingTaskGroup(of: URLComponents.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    self.queue.async { self.callback = cont }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AuthError.timedOut
            }
            defer { group.cancelAll(); stop() }
            return try await group.next()!
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            if !self.finished, let cb = self.callback {
                self.finished = true
                cb.resume(throwing: AuthError.cancelled)
            }
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let firstLine = request.split(separator: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            let comps = URLComponents(string: "http://127.0.0.1\(path)")
            let isCallback = comps?.queryItems?.contains { $0.name == "code" || $0.name == "error" } ?? false

            let body = isCallback
                ? "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:80px\"><h2>Doorstep is connected</h2><p>You can close this tab.</p></body></html>"
                : ""
            let status = isCallback ? "200 OK" : "404 Not Found"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })

            if isCallback, let comps, !self.finished, let cb = self.callback {
                self.finished = true
                cb.resume(returning: comps)
            }
        }
    }
}

enum AuthError: LocalizedError {
    case missingClientFile, timedOut, cancelled, denied(String), stateMismatch, tokenExchange(String), notSignedIn

    var errorDescription: String? {
        switch self {
        case .missingClientFile: "Google client file not found."
        case .timedOut: "Sign-in timed out."
        case .cancelled: "Sign-in was cancelled."
        case .denied(let reason): "Google declined access (\(reason))."
        case .stateMismatch: "Sign-in response didn't match. Try again."
        case .tokenExchange(let msg): "Couldn't finish sign-in: \(msg)"
        case .notSignedIn: "Not connected to Gmail."
        }
    }
}
