import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case english = "English"
    case chinese = "Chinese"
}

@MainActor
enum AppText {
    private struct AppConfig: Codable {
        var language: String?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static var currentLanguage: AppLanguage = .english

    static func load() {
        do {
            try CodexPaths.ensureDirectories()
            guard FileManager.default.fileExists(atPath: CodexPaths.appConfig.path) else {
                currentLanguage = .english
                return
            }

            let data = try Data(contentsOf: CodexPaths.appConfig)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            currentLanguage = AppLanguage(rawValue: config.language ?? "") ?? .english
        } catch {
            currentLanguage = .english
        }
    }

    static func setLanguage(_ language: AppLanguage) throws {
        currentLanguage = language
        try CodexPaths.ensureDirectories()
        let config = AppConfig(language: language.rawValue)
        try encoder.encode(config).write(to: CodexPaths.appConfig, options: .atomic)
    }

    static func s(_ english: String, _ chinese: String) -> String {
        currentLanguage == .chinese ? chinese : english
    }
}

struct LanguageOption: Equatable {
    let language: AppLanguage
    let displayName: String
}
