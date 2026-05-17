import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case english = "English"
    case chinese = "Chinese"
}

enum QuotaResetDisplayMode: String, Codable, CaseIterable {
    case primary
    case secondary

    var next: QuotaResetDisplayMode {
        switch self {
        case .primary:
            return .secondary
        case .secondary:
            return .primary
        }
    }
}

@MainActor
enum AppText {
    private struct AppConfig: Codable {
        var language: String?
        var quotaResetDisplayMode: String?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static var currentLanguage: AppLanguage = .english
    static var quotaResetDisplayMode: QuotaResetDisplayMode = .primary

    static func load() {
        do {
            try CodexPaths.ensureDirectories()
            guard FileManager.default.fileExists(atPath: CodexPaths.appConfig.path) else {
                currentLanguage = .english
                quotaResetDisplayMode = .primary
                return
            }

            let data = try Data(contentsOf: CodexPaths.appConfig)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            currentLanguage = AppLanguage(rawValue: config.language ?? "") ?? .english
            quotaResetDisplayMode = QuotaResetDisplayMode(rawValue: config.quotaResetDisplayMode ?? "") ?? .primary
        } catch {
            currentLanguage = .english
            quotaResetDisplayMode = .primary
        }
    }

    static func setLanguage(_ language: AppLanguage) throws {
        currentLanguage = language
        try saveConfig()
    }

    static func setQuotaResetDisplayMode(_ mode: QuotaResetDisplayMode) throws {
        quotaResetDisplayMode = mode
        try saveConfig()
    }

    private static func saveConfig() throws {
        try CodexPaths.ensureDirectories()
        let config = AppConfig(
            language: currentLanguage.rawValue,
            quotaResetDisplayMode: quotaResetDisplayMode.rawValue
        )
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
