import Foundation

struct ProviderProfileInput {
    let name: String
    let baseURL: String
    let apiKey: String
}

@MainActor
struct ProviderProfileService {
    func create(input: ProviderProfileInput) throws -> CodexProfile {
        let profileName = try normalizeProfileName(input.name)
        let baseURL = input.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = input.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try validate(baseURL: baseURL, apiKey: apiKey)

        try CodexPaths.ensureDirectories()
        let directory = CodexPaths.profilesRoot.appendingPathComponent(profileName, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            throw ProfileSwitchError.message(AppText.s(
                "Profile already exists: \(profileName)",
                "Profile 已存在：\(profileName)"
            ))
        }

        try writeProviderFiles(name: profileName, baseURL: baseURL, apiKey: apiKey, to: directory)

        var profile = CodexProfile(name: profileName, directoryURL: directory)
        profile.kind = .openAICompatibleProvider(URL(string: baseURL)?.host)
        return profile
    }

    func update(profile: CodexProfile, input: ProviderProfileInput) throws -> CodexProfile {
        let profileName = try normalizeProfileName(input.name)
        let baseURL = input.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = input.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try validate(baseURL: baseURL, apiKey: apiKey)

        try CodexPaths.ensureDirectories()
        var directory = profile.directoryURL
        if profileName.caseInsensitiveCompare(profile.name) != .orderedSame {
            let destination = CodexPaths.profilesRoot.appendingPathComponent(profileName, isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                throw ProfileSwitchError.message(AppText.s(
                    "Profile already exists: \(profileName)",
                    "Profile 已存在：\(profileName)"
                ))
            }
            try FileManager.default.moveItem(at: profile.directoryURL, to: destination)
            directory = destination
        }

        try writeProviderFiles(name: profileName, baseURL: baseURL, apiKey: apiKey, to: directory)

        var updated = CodexProfile(name: profileName, directoryURL: directory)
        updated.kind = .openAICompatibleProvider(URL(string: baseURL)?.host)
        updated.isCurrent = profile.isCurrent
        return updated
    }

    func input(for profile: CodexProfile) -> ProviderProfileInput {
        ProviderProfileInput(
            name: profile.name,
            baseURL: Self.baseURL(from: profile.configTOML) ?? "",
            apiKey: Self.apiKey(from: profile.authJSON) ?? ""
        )
    }

    private func validate(baseURL: String, apiKey: String) throws {
        guard URL(string: baseURL)?.host != nil else {
            throw ProfileSwitchError.message(AppText.s("Provider Base URL is invalid.", "Provider Base URL 无效。"))
        }
        guard apiKey.isEmpty == false else {
            throw ProfileSwitchError.message(AppText.s("API key cannot be empty.", "API key 不能为空。"))
        }
    }

    private func writeProviderFiles(name: String, baseURL: String, apiKey: String, to directory: URL) throws {
        let model = "gpt-5.5"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authObject: [String: Any] = ["OPENAI_API_KEY": apiKey]
        let authData = try JSONSerialization.data(withJSONObject: authObject, options: [.prettyPrinted, .sortedKeys])
        try authData.write(to: directory.appendingPathComponent("auth.json"), options: .atomic)

        let config = """
        model_provider = "openai"
        model = "\(Self.tomlEscaped(model))"
        review_model = "\(Self.tomlEscaped(model))"
        model_reasoning_effort = "medium"
        openai_base_url = "\(Self.tomlEscaped(baseURL))"
        """
        try config.write(to: directory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    }

    private func normalizeProfileName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ProfileSwitchError.message(AppText.s("Profile name cannot be empty.", "Profile 名称不能为空。"))
        }

        let invalid = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        return String(trimmed.unicodeScalars.map { invalid.contains($0) ? "-" : Character($0) })
    }

    private static func apiKey(from authJSON: URL) -> String? {
        guard let data = try? Data(contentsOf: authJSON),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["OPENAI_API_KEY"] as? String
    }

    private static func baseURL(from configTOML: URL) -> String? {
        guard let text = try? String(contentsOf: configTOML, encoding: .utf8) else {
            return nil
        }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("openai_base_url") || trimmed.hasPrefix("base_url") else {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            return parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
