import Foundation

struct OpenAIQuotaSnapshot: Equatable {
    let planType: String
    let primaryUsedPercent: Double
    let secondaryUsedPercent: Double
    let primaryResetAt: Date?
    let secondaryResetAt: Date?
    let primaryLimitWindowSeconds: Int?
    let secondaryLimitWindowSeconds: Int?
    let checkedAt: Date

    var primaryRemainingPercent: Double {
        max(0, 100 - primaryUsedPercent)
    }

    var secondaryRemainingPercent: Double {
        max(0, 100 - secondaryUsedPercent)
    }

    var menuBarSummary: String {
        "\(Int(primaryRemainingPercent.rounded()))%·\(Int(secondaryRemainingPercent.rounded()))%"
    }
}

enum OpenAIQuotaError: LocalizedError {
    case notOAuthProfile
    case missingToken
    case invalidResponse
    case unauthorized
    case forbidden
    case parseError
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notOAuthProfile:
            return "Usage refresh is only available for OAuth profiles."
        case .missingToken:
            return "OAuth token or account id is missing."
        case .invalidResponse:
            return "Invalid quota response."
        case .unauthorized:
            return "OAuth token may be expired. Switch or refresh the Codex account first."
        case .forbidden:
            return "The account is forbidden or suspended."
        case .parseError:
            return "Failed to parse quota response."
        case .httpError(let code):
            return "HTTP \(code)"
        }
    }
}

actor OpenAIQuotaService {
    static let shared = OpenAIQuotaService()

    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private init() {}

    func refresh(profile: CodexProfile) async throws -> OpenAIQuotaSnapshot {
        guard case .openAIOAuth = profile.kind else {
            throw OpenAIQuotaError.notOAuthProfile
        }
        let credentials = try credentials(from: profile.authJSON)

        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "oai-language")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIQuotaError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw OpenAIQuotaError.unauthorized
        case 402, 403:
            throw OpenAIQuotaError.forbidden
        default:
            throw OpenAIQuotaError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIQuotaError.parseError
        }
        return parseUsage(json)
    }

    private func credentials(from authURL: URL) throws -> (accessToken: String, accountID: String) {
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              accessToken.isEmpty == false,
              let accountID = tokens["account_id"] as? String,
              accountID.isEmpty == false else {
            throw OpenAIQuotaError.missingToken
        }

        return (accessToken, accountID)
    }

    private func parseUsage(_ json: [String: Any]) -> OpenAIQuotaSnapshot {
        let planType = json["plan_type"] as? String ?? "free"
        let rateLimit = json["rate_limit"] as? [String: Any]
        let primary = rateLimit?["primary_window"] as? [String: Any]
        let secondary = rateLimit?["secondary_window"] as? [String: Any]

        return OpenAIQuotaSnapshot(
            planType: planType,
            primaryUsedPercent: numeric(primary?["used_percent"]),
            secondaryUsedPercent: numeric(secondary?["used_percent"]),
            primaryResetAt: date(primary?["reset_at"]),
            secondaryResetAt: date(secondary?["reset_at"]),
            primaryLimitWindowSeconds: integer(primary?["limit_window_seconds"]),
            secondaryLimitWindowSeconds: integer(secondary?["limit_window_seconds"]),
            checkedAt: Date()
        )
    }

    private func numeric(_ value: Any?) -> Double {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as String:
            return Double(value) ?? 0
        default:
            return 0
        }
    }

    private func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private func date(_ value: Any?) -> Date? {
        switch value {
        case let value as TimeInterval:
            return Date(timeIntervalSince1970: value)
        case let value as Int:
            return Date(timeIntervalSince1970: TimeInterval(value))
        case let value as String:
            if let seconds = TimeInterval(value) {
                return Date(timeIntervalSince1970: seconds)
            }
            return ISO8601DateFormatter().date(from: value)
        default:
            return nil
        }
    }
}
