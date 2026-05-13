import AppKit
import Foundation

enum CodexProfileKind: Equatable {
    case openAIOAuth
    case openAICompatibleProvider(String?)
    case apiKey
    case incomplete
    case unknown

    @MainActor
    var title: String {
        switch self {
        case .openAIOAuth:
            return "OAuth"
        case .openAICompatibleProvider:
            return AppText.s("Provider", "Provider")
        case .apiKey:
            return "API Key"
        case .incomplete:
            return AppText.s("Incomplete", "不完整")
        case .unknown:
            return AppText.s("Unknown", "未知")
        }
    }

    @MainActor
    var detail: String {
        switch self {
        case .openAIOAuth:
            return AppText.s("OpenAI OAuth account", "OpenAI OAuth 账号")
        case .openAICompatibleProvider(let host):
            return host.map {
                AppText.s("OpenAI-compatible provider: \($0)", "OpenAI 兼容 Provider：\($0)")
            } ?? AppText.s("OpenAI-compatible provider", "OpenAI 兼容 Provider")
        case .apiKey:
            return AppText.s("API key based profile", "基于 API key 的 profile")
        case .incomplete:
            return AppText.s("Missing auth.json or config.toml", "缺少 auth.json 或 config.toml")
        case .unknown:
            return AppText.s("Could not identify auth type", "无法识别认证类型")
        }
    }
}

struct CodexProfile: Equatable {
    let name: String
    let directoryURL: URL
    var isCurrent: Bool = false
    var kind: CodexProfileKind = .unknown

    var summary: CodexProfileSummary {
        CodexProfileSummary.make(profile: self)
    }

    var authJSON: URL {
        directoryURL.appendingPathComponent("auth.json")
    }

    var configTOML: URL {
        directoryURL.appendingPathComponent("config.toml")
    }

    var isComplete: Bool {
        FileManager.default.fileExists(atPath: authJSON.path) &&
            FileManager.default.fileExists(atPath: configTOML.path)
    }

    @MainActor
    var displayName: String {
        if !isComplete {
            return AppText.s("\(name) (missing files)", "\(name) (缺少文件)")
        }

        return isCurrent ? AppText.s("\(name) (current)", "\(name) (当前)") : name
    }
}

struct CodexProfileSummary: Equatable {
    var email: String?
    var accountIdentifier: String?
    var model: String?
    var providerHost: String?
    var lastRefreshText: String?
    var nextRefreshCountdownText: String?

    @MainActor
    var title: String {
        email.map { "OpenAI · \($0)" } ??
            accountIdentifier.map { "OpenAI · \($0)" } ??
            AppText.s("Identity not available", "未识别账号身份")
    }

    static func make(profile: CodexProfile) -> CodexProfileSummary {
        let auth = Self.authSnapshot(from: profile.authJSON)
        let config = Self.configSnapshot(from: profile.configTOML)
        return CodexProfileSummary(
            email: auth.email,
            accountIdentifier: auth.accountIdentifier,
            model: config.model,
            providerHost: config.providerHost,
            lastRefreshText: auth.lastRefreshText,
            nextRefreshCountdownText: auth.nextRefreshCountdownText
        )
    }

    private static func authSnapshot(from url: URL) -> (
        email: String?,
        accountIdentifier: String?,
        lastRefreshText: String?,
        nextRefreshCountdownText: String?
    ) {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil, nil)
        }

        let tokens = object["tokens"] as? [String: Any]
        let accountID = tokens?["account_id"] as? String
        let email = (tokens?["id_token"] as? String).flatMap(emailFromIDToken)
        let accessExpiresAt = (tokens?["access_token"] as? String).flatMap(expiresAtFromJWT)
        let lastRefresh = object["last_refresh"] as? String
        return (email, accountID, formattedDate(lastRefresh), refreshCountdown(until: accessExpiresAt))
    }

    private static func emailFromIDToken(_ idToken: String) -> String? {
        jwtPayload(idToken)?["email"] as? String
    }

    private static func expiresAtFromJWT(_ token: String) -> Date? {
        guard let exp = jwtPayload(token)?["exp"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func configSnapshot(from url: URL) -> (model: String?, providerHost: String?) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil)
        }

        var model: String?
        var providerHost: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("model") && !trimmed.hasPrefix("model_provider") && model == nil {
                model = tomlStringValue(from: trimmed)
            }
            if (trimmed.hasPrefix("openai_base_url") || trimmed.hasPrefix("base_url")) && providerHost == nil,
               let rawValue = tomlStringValue(from: trimmed),
               let host = URL(string: rawValue)?.host {
                providerHost = host
            }
        }

        return (model, providerHost)
    }

    private static func tomlStringValue(from line: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else {
            return nil
        }

        return parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func formattedDate(_ value: String?) -> String? {
        guard let value,
              let date = ISO8601DateFormatter().date(from: value) else {
            return nil
        }

        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .numeric, time: .shortened)
    }

    private static func refreshCountdown(until date: Date?) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else {
            return "<1m"
        }

        let minutes = Int(ceil(remaining / 60))
        if minutes >= 24 * 60 {
            let days = minutes / (24 * 60)
            let restHours = (minutes % (24 * 60)) / 60
            return restHours == 0 ? "\(days)d" : "\(days)d \(restHours)h"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(minutes)m"
    }
}

@MainActor
final class ProfileSwitcherService {
    private struct AppState: Codable {
        var activeProfileName: String?
    }

    private let stateEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func listProfiles() throws -> [CodexProfile] {
        try CodexPaths.ensureDirectories()
        try bootstrapCurrentProfileIfNeeded()
        let activeProfileName = self.loadActiveProfileName()
        let urls = try FileManager.default.contentsOfDirectory(
            at: CodexPaths.profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map { url in
                CodexProfile(name: url.lastPathComponent, directoryURL: url)
            }
            .map { profile in
                var profile = profile
                profile.isCurrent = isCurrentProfile(profile, activeProfileName: activeProfileName)
                profile.kind = detectProfileKind(profile)
                return profile
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func switchTo(_ profile: CodexProfile) throws {
        guard profile.isComplete else {
            throw ProfileSwitchError.message(AppText.s(
                "This profile must contain both auth.json and config.toml.",
                "这个 profile 必须同时包含 auth.json 和 config.toml"
            ))
        }

        try CodexPaths.ensureDirectories()
        try backupIfPresent(CodexPaths.authJSON)
        try backupIfPresent(CodexPaths.configTOML)
        try replaceFile(at: CodexPaths.authJSON, with: profile.authJSON)
        try replaceFile(at: CodexPaths.configTOML, with: profile.configTOML)
        try saveActiveProfileName(profile.name)
    }

    func openProfilesFolder() throws {
        try CodexPaths.ensureDirectories()
        NSWorkspace.shared.open(CodexPaths.profilesRoot)
    }

    func openProfileFile(_ profile: CodexProfile, fileName: String) throws {
        let url: URL
        switch fileName {
        case "auth.json":
            url = profile.authJSON
        case "config.toml":
            url = profile.configTOML
        default:
            throw ProfileSwitchError.message(AppText.s("Unsupported file.", "不支持的文件"))
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileSwitchError.message(AppText.s(
                "The profile does not contain \(fileName).",
                "Profile 中不存在 \(fileName)"
            ))
        }

        NSWorkspace.shared.open(url)
    }

    func openProfileFolder(_ profile: CodexProfile) {
        NSWorkspace.shared.open(profile.directoryURL)
    }

    func deleteProfile(_ profile: CodexProfile) throws {
        try FileManager.default.removeItem(at: profile.directoryURL)
        if loadActiveProfileName()?.caseInsensitiveCompare(profile.name) == .orderedSame {
            try saveActiveProfileName("")
        }
    }

    private func bootstrapCurrentProfileIfNeeded() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: CodexPaths.authJSON.path),
              manager.fileExists(atPath: CodexPaths.configTOML.path) else {
            return
        }

        let existingProfiles = try manager.contentsOfDirectory(
            at: CodexPaths.profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        guard existingProfiles.isEmpty else {
            return
        }

        let rawName = suggestedBootstrapProfileName()
        let profileName = try availableProfileName(normalizeProfileName(rawName))
        let profileDirectory = CodexPaths.profilesRoot.appendingPathComponent(profileName, isDirectory: true)
        try manager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try manager.copyItem(at: CodexPaths.authJSON, to: profileDirectory.appendingPathComponent("auth.json"))
        try manager.copyItem(at: CodexPaths.configTOML, to: profileDirectory.appendingPathComponent("config.toml"))
        try saveActiveProfileName(profileName)
    }

    private func suggestedBootstrapProfileName() -> String {
        if let email = oauthEmail(from: CodexPaths.authJSON), let prefix = email.split(separator: "@").first {
            return String(prefix)
        }

        if let host = compatibleProviderHost(from: CodexPaths.configTOML) {
            let firstLabel = host.split(separator: ".").first.map(String.init) ?? host
            return firstLabel.uppercased()
        }

        return "current"
    }

    private func isCurrentProfile(_ profile: CodexProfile, activeProfileName: String?) -> Bool {
        guard profile.isComplete else { return false }
        if filesHaveSameContent(profile.authJSON, CodexPaths.authJSON) &&
            filesHaveSameContent(profile.configTOML, CodexPaths.configTOML) {
            return true
        }
        return activeProfileName?.caseInsensitiveCompare(profile.name) == .orderedSame
    }

    private func loadActiveProfileName() -> String? {
        guard let data = try? Data(contentsOf: CodexPaths.appState),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return nil
        }
        return state.activeProfileName
    }

    private func saveActiveProfileName(_ name: String) throws {
        try CodexPaths.ensureDirectories()
        let data = try stateEncoder.encode(AppState(activeProfileName: name))
        try data.write(to: CodexPaths.appState, options: .atomic)
    }

    private func detectProfileKind(_ profile: CodexProfile) -> CodexProfileKind {
        guard profile.isComplete else {
            return .incomplete
        }

        let authKeys = topLevelJSONKeys(at: profile.authJSON)
        if authKeys.contains("tokens") ||
            authKeys.contains("client_id") ||
            authKeys.contains("last_refresh") ||
            authKeys.contains("auth_mode") {
            return .openAIOAuth
        }

        if let host = compatibleProviderHost(from: profile.configTOML) {
            return .openAICompatibleProvider(host)
        }

        if authKeys.contains("OPENAI_API_KEY") {
            return .apiKey
        }

        return .unknown
    }

    private func topLevelJSONKeys(at url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        return Set(object.keys)
    }

    private func oauthEmail(from authURL: URL) -> String? {
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String else {
            return nil
        }
        return jwtPayload(idToken)?["email"] as? String
    }

    private func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func compatibleProviderHost(from configURL: URL) -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("openai_base_url") || trimmed.hasPrefix("base_url") else {
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }

            let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard let url = URL(string: rawValue),
                  let host = url.host,
                  host != "api.openai.com" else {
                continue
            }

            return host
        }

        return nil
    }

    private func filesHaveSameContent(_ firstURL: URL, _ secondURL: URL) -> Bool {
        guard
            FileManager.default.fileExists(atPath: firstURL.path),
            FileManager.default.fileExists(atPath: secondURL.path),
            let firstAttributes = try? FileManager.default.attributesOfItem(atPath: firstURL.path),
            let secondAttributes = try? FileManager.default.attributesOfItem(atPath: secondURL.path),
            firstAttributes[.size] as? UInt64 == secondAttributes[.size] as? UInt64,
            let firstData = try? Data(contentsOf: firstURL),
            let secondData = try? Data(contentsOf: secondURL)
        else {
            return false
        }

        return firstData == secondData
    }

    private func backupIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backupURL = CodexPaths.backupsRoot.appendingPathComponent("\(url.lastPathComponent).\(stamp).bak")
        try replaceFile(at: backupURL, with: url)
    }

    private func replaceFile(at destination: URL, with source: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func normalizeProfileName(_ name: String) throws -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileSwitchError.message(AppText.s(
                "Profile name cannot be empty.",
                "Profile 名称不能为空"
            ))
        }

        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
            .union(.controlCharacters)
            .union(.newlines)
        trimmed = String(trimmed.unicodeScalars.map {
            invalidCharacters.contains($0) ? "-" : Character($0)
        })
        return trimmed
    }

    private func availableProfileName(_ preferredName: String) throws -> String {
        var candidate = preferredName
        var suffix = 2
        while FileManager.default.fileExists(
            atPath: CodexPaths.profilesRoot.appendingPathComponent(candidate, isDirectory: true).path
        ) {
            candidate = "\(preferredName)-\(suffix)"
            suffix += 1
        }
        return candidate
    }
}

enum ProfileSwitchError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
