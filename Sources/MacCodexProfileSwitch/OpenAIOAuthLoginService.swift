import AppKit
import CryptoKit
import Foundation

struct OpenAIOAuthLoginResult {
    let profile: CodexProfile
    let email: String
}

enum OpenAIOAuthLoginError: LocalizedError {
    case invalidURL
    case invalidCallback
    case callbackServerUnavailable(String)
    case tokenExchangeFailed(String)
    case missingToken
    case missingEmail
    case missingAccountID

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build OpenAI OAuth URL."
        case .invalidCallback:
            return "Failed to parse OAuth callback."
        case .callbackServerUnavailable(let message):
            return "OAuth callback server is unavailable: \(message)"
        case .tokenExchangeFailed(let message):
            return "OAuth token exchange failed: \(message)"
        case .missingToken:
            return "OAuth response did not include the required tokens."
        case .missingEmail:
            return "OAuth token did not include an email address."
        case .missingAccountID:
            return "OAuth token did not include an account id."
        }
    }
}

@MainActor
final class OpenAIOAuthLoginService {
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let authURL = "https://auth.openai.com/oauth/authorize"
    private let tokenURL = "https://auth.openai.com/oauth/token"
    private let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"

    private var callbackServer: OAuthCallbackServer?
    private var pendingVerifier: String?
    private var pendingState: String?
    private var pendingRedirectURI: String?
    private var completion: ((Result<OpenAIOAuthLoginResult, Error>) -> Void)?

    func start(completion: @escaping (Result<OpenAIOAuthLoginResult, Error>) -> Void) {
        self.cancel()
        self.completion = completion

        do {
            let verifier = Self.generateCodeVerifier()
            let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let server = try self.startAvailableCallbackServer()
            let redirectURI = "http://localhost:\(server.port)/auth/callback"
            let url = try self.makeAuthorizationURL(verifier: verifier, state: state, redirectURI: redirectURI)

            self.pendingVerifier = verifier
            self.pendingState = state
            self.pendingRedirectURI = redirectURI
            self.callbackServer = server
            NSWorkspace.shared.open(url)
        } catch {
            self.finish(.failure(error))
        }
    }

    func cancel() {
        self.callbackServer?.stop()
        self.callbackServer = nil
        self.pendingVerifier = nil
        self.pendingState = nil
        self.pendingRedirectURI = nil
        self.completion = nil
    }

    private func complete(callbackURL: String) async {
        do {
            guard let verifier = self.pendingVerifier,
                  let redirectURI = self.pendingRedirectURI else {
                throw OpenAIOAuthLoginError.invalidCallback
            }

            let parsed = Self.parseCallback(callbackURL)
            guard let code = parsed.code, code.isEmpty == false else {
                throw OpenAIOAuthLoginError.invalidCallback
            }

            let tokens = try await self.exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
            let result = try self.createProfile(tokens: tokens)
            self.finish(.success(result))
        } catch {
            self.finish(.failure(error))
        }
    }

    private func finish(_ result: Result<OpenAIOAuthLoginResult, Error>) {
        let completion = self.completion
        self.callbackServer?.stop()
        self.callbackServer = nil
        self.pendingVerifier = nil
        self.pendingState = nil
        self.pendingRedirectURI = nil
        self.completion = nil
        completion?(result)
    }

    private func startAvailableCallbackServer() throws -> OAuthCallbackServer {
        var lastError: Error?
        for port in 1455...1465 {
            let server = OAuthCallbackServer(port: UInt16(port)) { [weak self] callbackURL in
                Task { @MainActor in
                    await self?.complete(callbackURL: callbackURL)
                }
            }
            do {
                try server.start()
                return server
            } catch {
                lastError = error
            }
        }
        throw OpenAIOAuthLoginError.callbackServerUnavailable(
            lastError?.localizedDescription ?? "all callback ports are in use"
        )
    }

    private func makeAuthorizationURL(verifier: String, state: String, redirectURI: String) throws -> URL {
        var components = URLComponents(string: self.authURL)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: self.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: self.scope),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(from: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "Codex Desktop")
        ]
        guard let url = components?.url else {
            throw OpenAIOAuthLoginError.invalidURL
        }
        return url
    }

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> OAuthTokens {
        guard let url = URL(string: self.tokenURL) else {
            throw OpenAIOAuthLoginError.invalidURL
        }

        let body = [
            "grant_type": "authorization_code",
            "client_id": self.clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        request.httpBody = body
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIOAuthLoginError.missingToken
        }
        if let error = json["error"] as? String {
            let description = json["error_description"] as? String ?? ""
            throw OpenAIOAuthLoginError.tokenExchangeFailed("\(error): \(description)")
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let idToken = json["id_token"] as? String else {
            throw OpenAIOAuthLoginError.missingToken
        }

        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken
        )
    }

    private func createProfile(tokens: OAuthTokens) throws -> OpenAIOAuthLoginResult {
        guard let email = Self.jwtPayload(tokens.idToken)?["email"] as? String,
              email.isEmpty == false else {
            throw OpenAIOAuthLoginError.missingEmail
        }
        let authClaims = Self.jwtPayload(tokens.accessToken)?["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        guard let accountID = (authClaims["chatgpt_account_id"] as? String) ??
                (authClaims["chatgpt_account_user_id"] as? String),
              accountID.isEmpty == false else {
            throw OpenAIOAuthLoginError.missingAccountID
        }

        let preferredProfileName = Self.profileName(from: email)
        let profileName = try self.existingOAuthProfileName(accountID: accountID) ?? preferredProfileName
        let directory = CodexPaths.profilesRoot.appendingPathComponent(profileName, isDirectory: true)
        try CodexPaths.ensureDirectories()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let authObject: [String: Any] = [
            "auth_mode": "chatgpt",
            "client_id": self.clientID,
            "last_refresh": now,
            "OPENAI_API_KEY": NSNull(),
            "tokens": [
                "access_token": tokens.accessToken,
                "refresh_token": tokens.refreshToken,
                "id_token": tokens.idToken,
                "account_id": accountID
            ]
        ]
        let authData = try JSONSerialization.data(
            withJSONObject: authObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try authData.write(to: directory.appendingPathComponent("auth.json"), options: .atomic)

        let configURL = directory.appendingPathComponent("config.toml")
        if FileManager.default.fileExists(atPath: configURL.path) == false {
            try Self.defaultConfigTOML.write(to: configURL, atomically: true, encoding: .utf8)
        }

        var profile = CodexProfile(name: profileName, directoryURL: directory)
        profile.kind = .openAIOAuth
        return OpenAIOAuthLoginResult(profile: profile, email: email)
    }

    private static func parseCallback(_ input: String) -> (code: String?, state: String?) {
        guard let url = URL(string: input),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (nil, nil)
        }
        return (
            components.queryItems?.first(where: { $0.name == "code" })?.value,
            components.queryItems?.first(where: { $0.name == "state" })?.value
        )
    }

    private static func profileName(from email: String) -> String {
        let prefix = email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? email
        let invalid = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        let cleaned = String(prefix.unicodeScalars.map { invalid.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "openai" : cleaned
    }

    private func existingOAuthProfileName(accountID: String) throws -> String? {
        try CodexPaths.ensureDirectories()
        let urls = try FileManager.default.contentsOfDirectory(
            at: CodexPaths.profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls.sorted(by: { Self.profileSortKey($0.lastPathComponent) < Self.profileSortKey($1.lastPathComponent) }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let authURL = url.appendingPathComponent("auth.json")
            guard let data = try? Data(contentsOf: authURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = object["tokens"] as? [String: Any],
                  let existingAccountID = tokens["account_id"] as? String,
                  existingAccountID == accountID else {
                continue
            }
            return url.lastPathComponent
        }
        return nil
    }

    private static func profileSortKey(_ name: String) -> String {
        name == "default" ? "zzzz-\(name)" : name.localizedLowercase
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(from verifier: String) -> String {
        let data = verifier.data(using: .ascii) ?? Data()
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let defaultConfigTOML = """
    model_provider = "openai"
    model = "gpt-5.5"
    review_model = "gpt-5.5"
    model_reasoning_effort = "medium"
    """
}

private struct OAuthTokens {
    let accessToken: String
    let refreshToken: String
    let idToken: String
}

private final class OAuthCallbackServer: @unchecked Sendable {
    let port: UInt16
    private let callbackPath: String
    private let onCallback: @MainActor (String) -> Void
    private let queue = DispatchQueue(label: "mac.codex.profile-switch.oauth-callback")
    private var serverFd: Int32 = -1
    private var isRunning = false

    init(
        port: UInt16 = 1455,
        callbackPath: String = "/auth/callback",
        onCallback: @escaping @MainActor (String) -> Void
    ) {
        self.port = port
        self.callbackPath = callbackPath
        self.onCallback = onCallback
    }

    func start() throws {
        self.stop()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw OpenAIOAuthLoginError.callbackServerUnavailable("socket failed")
        }

        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = self.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        memset(&address.sin_zero, 0, MemoryLayout.size(ofValue: address.sin_zero))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw OpenAIOAuthLoginError.callbackServerUnavailable(message)
        }

        guard Darwin.listen(fd, 5) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw OpenAIOAuthLoginError.callbackServerUnavailable(message)
        }

        self.serverFd = fd
        self.isRunning = true
        self.queue.async { [weak self] in
            self?.acceptLoop(serverFd: fd)
        }
    }

    func stop() {
        self.isRunning = false
        if self.serverFd >= 0 {
            shutdown(self.serverFd, SHUT_RDWR)
            close(self.serverFd)
            self.serverFd = -1
        }
    }

    private func acceptLoop(serverFd: Int32) {
        defer {
            if self.serverFd == serverFd {
                self.serverFd = -1
            }
            close(serverFd)
        }

        while self.isRunning {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else {
                if self.isRunning == false { break }
                continue
            }
            self.handle(clientFd: clientFd)
        }
    }

    private func handle(clientFd: Int32) {
        defer { close(clientFd) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let readCount = recv(clientFd, &buffer, buffer.count - 1, 0)
        guard readCount > 0,
              let request = String(bytes: buffer.prefix(readCount), encoding: .utf8),
              let callbackURL = Self.callbackURL(from: request, port: self.port, callbackPath: self.callbackPath) else {
            self.write(Self.response(status: "400 Bad Request", body: "Invalid OAuth callback."), to: clientFd)
            return
        }

        self.write(Self.response(status: "200 OK", body: "Login received. You can return to Mac.Codex.ProfileSwitch."), to: clientFd)
        self.stop()
        Task { @MainActor [callbackURL, onCallback] in
            onCallback(callbackURL)
        }
    }

    private func write(_ data: Data, to clientFd: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            _ = send(clientFd, base, rawBuffer.count, 0)
        }
    }

    private static func callbackURL(from request: String, port: UInt16, callbackPath: String) -> String? {
        guard let line = request.components(separatedBy: "\r\n").first,
              line.hasPrefix("GET ") else {
            return nil
        }
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 2, parts[1].hasPrefix(callbackPath) else {
            return nil
        }
        return "http://localhost:\(port)\(parts[1])"
    }

    private static func response(status: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var data = Data(header.utf8)
        data.append(bodyData)
        return data
    }
}
