import Foundation
import OSLog
import Security

/// Serializes authentication and stores the refresh credential in the device keychain.
actor PlayerAPI {
    let config: OnlineConfiguration
    private var session: AuthSession?
    private var authentication: Task<AuthSession, Error>?
    private let network = URLSession(configuration: .ephemeral)
    private let keychainAccount: String

    nonisolated struct AuthSession: Codable, Sendable {
        let access_token: String
        let refresh_token: String
        let expires_at: Double
        enum CodingKeys: String, CodingKey { case access_token, refresh_token, expires_at, expires_in }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            access_token = try values.decode(String.self, forKey: .access_token)
            refresh_token = try values.decode(String.self, forKey: .refresh_token)
            if let expiry = try values.decodeIfPresent(Double.self, forKey: .expires_at) { expires_at = expiry }
            else { expires_at = Date().timeIntervalSince1970 + (try values.decode(Double.self, forKey: .expires_in)) }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(access_token, forKey: .access_token)
            try values.encode(refresh_token, forKey: .refresh_token)
            try values.encode(expires_at, forKey: .expires_at)
        }
    }
    private struct ServerErrorBody: Decodable {
        let code: String?
        let error: String?
        let message: String?
    }
    init(config: OnlineConfiguration) {
        self.config = config
        keychainAccount = "\(Bundle.main.bundleIdentifier ?? "FeatherFreeway").\(config.supabaseURL)"
    }
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "FeatherFreeway.Supabase", kSecAttrAccount as String: keychainAccount]
    }
    private func credential(forceRefresh: Bool = false) async throws -> AuthSession {
        if !forceRefresh, let session, session.expires_at > Date().timeIntervalSince1970 + 60 { return session }
        if let authentication { return try await authentication.value }
        let task = Task<AuthSession, Error> {
            var old = self.session
            if old == nil {
                var query = self.keychainQuery
                query[kSecReturnData as String] = true
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess {
                    guard let data = result as? Data else { throw OnlineError.invalidResponse }
                    old = try JSONDecoder().decode(AuthSession.self, from: data)
                } else if status != errSecItemNotFound && status != errSecMissingEntitlement {
                    throw OnlineError.keychain(status)
                } else if status == errSecMissingEntitlement {
                    // Some simulator and restricted signing environments do not grant Keychain
                    // access. Do not let that prevent the anonymous Supabase session or the
                    // launch-resolution request; the session remains available in memory.
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "FeatherFreeway", category: "Online")
                        .error("Keychain unavailable; continuing with an in-memory session")
                }
            }
            if !forceRefresh, let old, old.expires_at > Date().timeIntervalSince1970 + 60 { return old }
            let path = old == nil ? "auth/v1/signup" : "auth/v1/token?grant_type=refresh_token"
            let body = old.map { ["refresh_token": $0.refresh_token] } ?? [:]
            let data = try await self.raw(path: path, method: "POST", body: JSONEncoder().encode(body), token: nil)
            let fresh = try JSONDecoder().decode(AuthSession.self, from: data)
            // A keychain write failure must not discard a session the server already issued:
            // keep it in memory for this launch and log, otherwise the player row is never created.
            do { try self.store(fresh) } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "FeatherFreeway", category: "Online")
                    .error("Session not persisted: \(error.localizedDescription, privacy: .public)")
            }
            return fresh
        }
        authentication = task
        defer { authentication = nil }
        let value = try await task.value
        session = value
        return value
    }
    private func store(_ session: AuthSession) throws {
        let encoded = try JSONEncoder().encode(session)
        let update = [kSecValueData as String: encoded]
        let status = SecItemUpdate(keychainQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = keychainQuery
            insert[kSecValueData as String] = encoded
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw OnlineError.keychain(added) }
        } else if status != errSecSuccess { throw OnlineError.keychain(status) }
    }
    private func raw(path: String, method: String, body: Data?, token: String?) async throws -> Data {
        guard let base = config.baseURL,
              let url = URL(string: path, relativeTo: base.appendingPathComponent("/")) else { throw OnlineError.unavailable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let diagnostic = (try? JSONDecoder().decode(ServerErrorBody.self, from: data))
                .map { [$0.code, $0.error, $0.message].compactMap { $0 }.joined(separator: " | ") }
                .map { String($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(180)) }
            throw OnlineError.response(http.statusCode, diagnostic?.isEmpty == false ? diagnostic : nil)
        }
        return data
    }
    func call<Body: Encodable & Sendable, Value: Decodable & Sendable>(_ function: String, body: Body, as: Value.Type) async throws -> Value {
        let auth = try await credential()
        do {
            return try JSONDecoder().decode(Value.self, from: await raw(path: "functions/v1/\(function)", method: "POST", body: JSONEncoder().encode(body), token: auth.access_token))
        } catch OnlineError.response(401, _) {
            let refreshed = try await credential(forceRefresh: true)
            return try JSONDecoder().decode(Value.self, from: await raw(path: "functions/v1/\(function)", method: "POST", body: JSONEncoder().encode(body), token: refreshed.access_token))
        }
    }
    func leaderboard(appid: String) async throws -> [TopPlayer] {
        let auth = try await credential()
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "appid", value: "eq.\(appid)"),
                            URLQueryItem(name: "select", value: "id,name,avatar,best_score"),
                            URLQueryItem(name: "order", value: "best_score.desc,id.asc"), URLQueryItem(name: "limit", value: "50")]
        return try JSONDecoder().decode([TopPlayer].self, from: await raw(path: "rest/v1/leaderboard\(parts.string ?? "")", method: "GET", body: nil, token: auth.access_token))
    }
    func realtimeCredential() async throws -> String { try await credential().access_token }
}
