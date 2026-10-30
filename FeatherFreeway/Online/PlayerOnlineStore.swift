import Foundation
import OSLog
import Observation
import Network
import UIKit
import WebKit

private enum LaunchRequestPolicy {
    static let maximumAttempts = 3 // Initial request plus two retries.
    static let retryDelay = Duration.seconds(1)
}

nonisolated struct PendingScore: Codable, Sendable, Identifiable {
    let gameId: UUID
    let appid: String
    let ad_id: String
    let score: Int
    var completedAt: String
    let duration: Double
    let meters: Int
    let corn: Int
    let mode: String
    let avatar: String
    var rejectedStatus: Int? = nil
    var id: UUID { gameId }
}

@MainActor
@Observable
final class PlayerOnlineStore {
    private(set) var launch: LaunchDecision?
    private(set) var players: [TopPlayer] = []
    private(set) var leaderboardMessage: String?
    private(set) var syncMessage: String?
    private(set) var isLoading = false
    var playerName: String {
        didSet { defaults.set(playerName, forKey: "online.playerName"); Task { await updateProfile() } }
    }
    let config: OnlineConfiguration?
    private let api: PlayerAPI?
    private let defaults: UserDefaults
    private let disabled: Bool
    private var identity: String? { UIDevice.current.identifierForVendor?.uuidString }
    private var appid: String { Bundle.main.bundleIdentifier ?? "" }
    @ObservationIgnored private var pending: [PendingScore] = []
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var resolving = false
    @ObservationIgnored private var launchResolutionCompleted = false
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var watching = false
    @ObservationIgnored private var watchGeneration = UUID()
    @ObservationIgnored private var uaView: WKWebView?
    @ObservationIgnored private var queueURL: URL?
    private static let scoreTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(defaults: UserDefaults = .standard, disabled: Bool = false) {
        self.defaults = defaults
        self.disabled = disabled
        config = disabled ? nil : OnlineConfiguration.bundled
        api = config.map(PlayerAPI.init)
        playerName = defaults.string(forKey: "online.playerName") ?? "Driver \(String(UUID().uuidString.prefix(4)))"
        if !disabled {
            defaults.set(playerName, forKey: "online.playerName")
            do {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("FeatherFreewayOnline", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("scores.json")
                queueURL = file
                if FileManager.default.fileExists(atPath: file.path) {
                    pending = try JSONDecoder().decode([PendingScore].self, from: Data(contentsOf: file))
                    // A prior server-side validation bug may have permanently rejected a valid run.
                    // Recheck HTTP 400 items once after each app launch so a server fix can recover them.
                    for index in pending.indices {
                        if pending[index].rejectedStatus == 400 { pending[index].rejectedStatus = nil }
                        pending[index].completedAt = Self.normalizedScoreTimestamp(pending[index].completedAt)
                    }
                }
            } catch { syncMessage = "Saved uploads could not be opened. \(error.localizedDescription)"; queueURL = nil }
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.launchResolutionCompleted else { return }
                    await self.updateProfile()
                    await self.syncScores()
                    if self.watching { await self.refreshLeaderboard() }
                }
            }
            monitor.start(queue: DispatchQueue(label: "FeatherFreeway.connectivity"))
        }
    }

    func resolveLaunch() async {
        guard !resolving else { return }
        resolving = true
        defer { resolving = false }
        guard !disabled, let config, let api, let identity, !appid.isEmpty else {
            launch = .temporaryGame
            launchResolutionCompleted = true
            return
        }
        // Require a fresh server decision for each app launch; never open a cached destination.
        guard var url = URLComponents(string: config.checkURL), url.scheme == "https", url.host != nil else {
            launch = .temporaryGame
            await updateProfile()
            await syncScores()
            launchResolutionCompleted = true
            return
        }
        async let token = PushRegistration.shared.tokenWithinThreeSeconds()
        async let attributionPayload = AdjustAttributionStore.shared.currentPayload(timeoutMilliseconds: AdjustAttributionStore.SETTINGS.firstParameterTimeoutMilliseconds)
        let userAgent = await userAgent()
        let attribution = await attributionPayload
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "FeatherFreeway", category: "Adjust")
            .notice("Adjust naming bytes=\(attribution.namingJSON.utf8.count, privacy: .public) deeplink=\(attribution.deeplink.isEmpty ? "absent" : "present", privacy: .public) json=\(attribution.namingJSON, privacy: .public)")
        url.queryItems = [URLQueryItem(name: "appid", value: appid), URLQueryItem(name: "idfv", value: identity),
                          URLQueryItem(name: "deviceName", value: Self.hardwareModel),
                          URLQueryItem(name: "pushToken", value: await token), URLQueryItem(name: "userAgent", value: userAgent),
                          URLQueryItem(name: "appVersion", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")]
        guard let requestURL = url.url?.absoluteString else {
            launch = .temporaryGame
            await updateProfile()
            await syncScores()
            launchResolutionCompleted = true
            return
        }
        nonisolated struct Request: Encodable, Sendable { let appid: String; let ad_id: String; let request_url: String; let name: String; let avatar: String; let adjust_json: String; let deeplink: String }

        var decision: LaunchDecision?
        var lastError: Error = OnlineError.invalidResponse
        for attempt in 1...LaunchRequestPolicy.maximumAttempts {
            do {
                let response = try await api.call("resolve-player", body: Request(appid: appid, ad_id: identity, request_url: requestURL, name: playerName, avatar: Breed.starter.rawValue, adjust_json: attribution.namingJSON, deeplink: attribution.deeplink), as: LaunchDecision.self)
                guard response.isValid(using: config) else { throw OnlineError.invalidResponse }
                decision = response
                break
            } catch {
                lastError = error
                if attempt < LaunchRequestPolicy.maximumAttempts {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "FeatherFreeway", category: "Online")
                        .error("Launch request attempt \(attempt) failed; retrying: \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(for: LaunchRequestPolicy.retryDelay)
                }
            }
        }

        if let decision {
            launch = decision
        } else {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "FeatherFreeway", category: "Online")
                .error("Launch request failed after retries: \(lastError.localizedDescription, privacy: .public)")
            // Only use the game fallback after the initial request and both retries fail.
            launch = .temporaryGame
        }
        await updateProfile()
        await syncScores()
        launchResolutionCompleted = true
    }

    func appDidBecomeActive() async {
        guard launchResolutionCompleted else { return }
        await updateProfile()
        await syncScores()
    }

    private func userAgent() async -> String {
        let web = WKWebView(frame: .zero)
        uaView = web
        defer { uaView = nil }
        // The fallback timer also covers WebKit process startup failure.
        return await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ value: String) { guard !resumed else { return }; resumed = true; continuation.resume(returning: value) }
            web.evaluateJavaScript("navigator.userAgent") { value, _ in finish(value as? String ?? "") }
            Task { @MainActor in try? await Task.sleep(for: .seconds(3)); finish("") }
        }
    }
    private static var hardwareModel: String {
        var info = utsname(); uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }
    func enqueue(_ summary: RunSummary) {
        guard !disabled, let identity, !appid.isEmpty else { return }
        let item = PendingScore(gameId: UUID(), appid: appid, ad_id: identity, score: summary.score,
                                completedAt: Self.scoreTimestampFormatter.string(from: .now), duration: summary.duration,
                                meters: summary.meters, corn: summary.corn, mode: summary.mode.storageKey, avatar: summary.breed.rawValue)
        pending.append(item)
        do { try persistQueue(); syncMessage = nil } catch { syncMessage = OnlineError.storage.localizedDescription }
        Task { await syncScores() }
    }
    private static func normalizedScoreTimestamp(_ value: String) -> String {
        let timestampWithoutZone = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$"#
        return value.range(of: timestampWithoutZone, options: .regularExpression) == nil ? value : value + "Z"
    }
    private func persistQueue() throws {
        guard let queueURL else { throw OnlineError.storage }
        try JSONEncoder().encode(pending).write(to: queueURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func syncScores() async {
        guard !syncing, let api, !pending.isEmpty else { return }
        syncing = true
        defer { syncing = false }
        // Persist before attempting delivery; a network acknowledgment never replaces local durability.
        do { try persistQueue() } catch { syncMessage = OnlineError.storage.localizedDescription; return }
        nonisolated struct Ack: Decodable, Sendable { let accepted: Bool }
        for item in pending where item.appid == appid && item.ad_id == identity && item.rejectedStatus == nil {
            do {
                let ack = try await api.call("submit-score", body: item, as: Ack.self)
                guard ack.accepted else { throw OnlineError.invalidResponse }
                let previous = pending
                pending.removeAll { $0.id == item.id }
                do { try persistQueue() } catch { pending = previous; throw error }
                syncMessage = nil
            } catch OnlineError.response(let status, let diagnostic) where [400, 403, 409, 422].contains(status) {
                // Keep permanent rejections locally and show the server diagnostic. HTTP 400 is
                // reconsidered once on the next app launch to recover from validation fixes.
                if let index = pending.firstIndex(where: { $0.id == item.id }) { pending[index].rejectedStatus = status }
                syncMessage = diagnostic.map { "Server rejected a result (HTTP \(status)): \($0)" }
                    ?? "Server rejected a result (HTTP \(status)). It remains saved on this device."
                do { try persistQueue() } catch { syncMessage = OnlineError.storage.localizedDescription; break }
            } catch {
                syncMessage = "Your result is saved on this device. Upload will retry."
                break
            }
        }
        if syncMessage == nil && pending.contains(where: { $0.rejectedStatus != nil }) {
            syncMessage = "Some results were rejected by the server. They remain saved on this device."
        }
        if pending.contains(where: { $0.rejectedStatus == nil && $0.appid == appid && $0.ad_id == identity }) && retryTask == nil {
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.retryTask = nil
                await self?.syncScores()
            }
        }
    }
    func updateProfile() async {
        guard let api, let identity else { return }
        nonisolated struct Body: Encodable, Sendable { let appid: String; let ad_id: String; let name: String }
        nonisolated struct Ack: Decodable, Sendable { let updated: Bool }
        _ = try? await api.call("player-profile", body: Body(appid: appid, ad_id: identity, name: playerName), as: Ack.self)
    }
    func refreshLeaderboard() async {
        guard !isLoading else { return }
        let key = "online.leaderboard.\(appid)"
        if players.isEmpty, let data = defaults.data(forKey: key), let cached = try? JSONDecoder().decode([TopPlayer].self, from: data) { players = cached }
        guard let api else { leaderboardMessage = "Online leaderboard is not configured yet."; return }
        isLoading = true
        defer { isLoading = false }
        do {
            players = try await api.leaderboard(appid: appid)
            defaults.set(try JSONEncoder().encode(players), forKey: key)
            leaderboardMessage = nil
        } catch { leaderboardMessage = "Offline — showing the last saved leaderboard." }
    }
    func watchLeaderboard() async {
        watching = true
        let generation = UUID()
        watchGeneration = generation
        while watching && watchGeneration == generation && !Task.isCancelled {
            await refreshLeaderboard()
            var ownedConnection: URLSessionWebSocketTask?
            var ownedHeartbeat: Task<Void, Never>?
            do {
                guard let api, let config, var parts = URLComponents(string: config.supabaseURL) else { return }
                let token = try await api.realtimeCredential()
                parts.scheme = "wss"; parts.path = "/realtime/v1/websocket"
                parts.queryItems = [URLQueryItem(name: "apikey", value: config.publishableKey), URLQueryItem(name: "vsn", value: "1.0.0")]
                guard let url = parts.url else { return }
                let connection = URLSession.shared.webSocketTask(with: url)
                ownedConnection = connection
                guard watching && watchGeneration == generation && !Task.isCancelled else { return }
                socket = connection; connection.resume()
                let join: [String: Any] = ["topic": "realtime:public:leaderboard", "event": "phx_join", "ref": "1", "payload": ["access_token": token, "config": ["postgres_changes": [["event": "*", "schema": "public", "table": "leaderboard", "filter": "appid=eq.\(appid)"]]]]]
                try await connection.send(.string(String(decoding: JSONSerialization.data(withJSONObject: join), as: UTF8.self)))
                heartbeat = Task {
                    for tick in 1...100 { // Reconnect periodically to renew the auth token.
                        try? await Task.sleep(for: .seconds(20))
                        guard !Task.isCancelled else { return }
                        let ping: [String: Any] = ["topic": "phoenix", "event": "heartbeat", "payload": [:], "ref": "h\(tick)"]
                        do { try await connection.send(.string(String(decoding: JSONSerialization.data(withJSONObject: ping), as: UTF8.self))) } catch { connection.cancel(); return }
                    }
                    connection.cancel()
                }
                ownedHeartbeat = heartbeat
                while watching && !Task.isCancelled && watchGeneration == generation {
                    let message = try await connection.receive()
                    let data: Data
                    switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if event["event"] as? String == "postgres_changes" { await refreshLeaderboard() }
                    if event["event"] as? String == "phx_error" || event["event"] as? String == "phx_close" { break }
                    if event["event"] as? String == "phx_reply", let payload = event["payload"] as? [String: Any], payload["status"] as? String == "error" { break }
                }
            } catch { /* Reconnect while this screen remains visible. */ }
            ownedHeartbeat?.cancel(); ownedConnection?.cancel(with: .goingAway, reason: nil)
            guard watching && watchGeneration == generation else { break }
            try? await Task.sleep(for: .seconds(5))
        }
    }
    func stopWatchingLeaderboard() {
        watching = false; watchGeneration = UUID()
        heartbeat?.cancel(); socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }
}
