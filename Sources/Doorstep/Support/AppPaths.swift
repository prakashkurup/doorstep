import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Doorstep", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var stateFile: URL { supportDirectory.appendingPathComponent("state.json") }

    /// Where the Google OAuth client file can be dropped without rebuilding.
    static var clientSecretFile: URL { supportDirectory.appendingPathComponent("client_secret.json") }
}
