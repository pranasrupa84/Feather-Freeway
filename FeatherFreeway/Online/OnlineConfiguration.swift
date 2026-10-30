import Foundation

nonisolated struct OnlineConfiguration: Codable, Sendable {
    let supabaseURL: String
    let publishableKey: String
    let checkURL: String

    static var bundled: OnlineConfiguration? {
        guard let url = Bundle.main.url(forResource: "OnlineConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Self.self, from: data),
              config.baseURL != nil, !config.publishableKey.isEmpty else { return nil }
        return config
    }
    var baseURL: URL? {
        guard let url = URL(string: supabaseURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    func allows(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil &&
        url.host != nil
    }
}

nonisolated struct LaunchDecision: Codable, Sendable {
    let action: String
    let targetUrl: String?
    let cacheable: Bool
    static let temporaryGame = Self(action: "game", targetUrl: nil, cacheable: false)
    func destination(using config: OnlineConfiguration) -> URL? {
        guard action == "webview", let value = targetUrl, let url = URL(string: value), config.allows(url) else { return nil }
        return url
    }
    func isValid(using config: OnlineConfiguration) -> Bool {
        (action == "game" && targetUrl == nil) || destination(using: config) != nil
    }
}

nonisolated struct TopPlayer: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let avatar: String?
    let best_score: Int
}

nonisolated enum OnlineError: LocalizedError {
    case unavailable, response(Int, String?), invalidResponse, storage, keychain(Int32)
    var errorDescription: String? {
        switch self {
        case .unavailable: "Online services are not configured."
        case .response(let status, let diagnostic):
            if let diagnostic, !diagnostic.isEmpty { "Online service returned \(status): \(diagnostic)" }
            else { "Online service returned \(status). Please try again." }
        case .invalidResponse: "The online service returned an invalid response."
        case .keychain(let status): "Secure session storage error (\(status))."
        case .storage: "Your result could not be saved for upload. Please free some device storage."
        }
    }
}
