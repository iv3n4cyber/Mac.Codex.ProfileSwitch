import Foundation

enum CodexPaths {
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var codexRoot: URL {
        homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    static var authJSON: URL {
        codexRoot.appendingPathComponent("auth.json")
    }

    static var configTOML: URL {
        codexRoot.appendingPathComponent("config.toml")
    }

    static var appRoot: URL {
        codexRoot.appendingPathComponent("mac-codex-profile-switch", isDirectory: true)
    }

    static var appConfig: URL {
        appRoot.appendingPathComponent("config.json")
    }

    static var appState: URL {
        appRoot.appendingPathComponent("state.json")
    }

    static var tokenUsageSessionCache: URL {
        appRoot.appendingPathComponent("token-usage-session-cache.json")
    }

    static var backupsRoot: URL {
        appRoot.appendingPathComponent("backups", isDirectory: true)
    }

    static var profilesRoot: URL {
        codexRoot.appendingPathComponent("profiles", isDirectory: true)
    }

    static func ensureDirectories() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try manager.createDirectory(at: appRoot, withIntermediateDirectories: true)
        try manager.createDirectory(at: backupsRoot, withIntermediateDirectories: true)
        try manager.createDirectory(at: profilesRoot, withIntermediateDirectories: true)
    }
}
