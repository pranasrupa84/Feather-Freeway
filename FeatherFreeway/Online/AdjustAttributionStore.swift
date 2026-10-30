import AdjustSdk
import Foundation
import OSLog

/// Keeps Adjust naming and a deep link. A later organic attribution must not replace naming that already has a campaign.
final class AdjustAttributionStore: NSObject, AdjustDelegate, @unchecked Sendable {
    static let SETTINGS = (appToken: "13sodc7o4rxc", environment: ADJEnvironmentProduction, firstParameterTimeoutMilliseconds: 20_000)
    static let shared = AdjustAttributionStore()

    private let lock = NSLock()
    private var initialized = false
    private var namingJSON = ""
    private var oneLink = ""
    private var firstParameterReceived = false
    private var pendingLaunchURL: String?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func initialize() {
        lock.lock()
        let shouldInitialize = !initialized
        let queuedURL = pendingLaunchURL
        if shouldInitialize { pendingLaunchURL = nil }
        initialized = true
        lock.unlock()
        guard shouldInitialize else { return }

        guard let config = ADJConfig(appToken: Self.SETTINGS.appToken, environment: Self.SETTINGS.environment) else {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "FeatherFreeway", category: "Adjust")
                .error("Adjust configuration could not be created")
            return
        }
        config.delegate = self
        config.enableCostDataInAttribution()
        Adjust.initSdk(config)
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "FeatherFreeway", category: "Adjust")
            .notice("Adjust SDK init requested")
        if let queuedURL { deliverDeepLink(queuedURL) }
        Adjust.attribution { [weak self] attribution in
            self?.onAttributionChanged(attribution)
        }
    }

    /// Naming JSON for Banda, plus the deep link if one arrived. Returns after the first parameter or the timeout.
    func currentPayload(timeoutMilliseconds: Int) async -> (namingJSON: String, deeplink: String) {
        await waitForFirstParameter(timeoutMilliseconds: timeoutMilliseconds)
        return snapshot()
    }

    func processDeepLink(_ urlString: String) {
        guard !urlString.isEmpty else { return }
        lock.lock()
        let ready = initialized
        if !ready { pendingLaunchURL = urlString }
        lock.unlock()
        guard ready else { return }
        deliverDeepLink(urlString)
    }

    func adjustAttributionChanged(_ attribution: ADJAttribution?) {
        onAttributionChanged(attribution)
    }

    func adjustDeferredDeeplinkReceived(_ deeplink: URL?) -> Bool {
        guard let url = deeplink?.absoluteString, !url.isEmpty else { return false }
        acceptDeepLink(url, finishWait: true)
        return false
    }

    private func deliverDeepLink(_ urlString: String) {
        acceptDeepLink(urlString, finishWait: false)
        guard let url = URL(string: urlString), let deeplink = ADJDeeplink(deeplink: url) else {
            finishWaiters()
            return
        }
        Adjust.processAndResolve(deeplink, withCompletionHandler: { [weak self] resolved in
            let value = (resolved?.isEmpty == false) ? resolved! : urlString
            self?.acceptDeepLink(value, finishWait: true)
        })
    }

    private func onAttributionChanged(_ attribution: ADJAttribution?) {
        guard let attribution else { return }
        let json = Self.attributionJSON(attribution)
        guard !json.isEmpty else { return }
        lock.lock()
        if firstParameterReceived {
            if namingJSON.isEmpty || Self.hasCampaignFields(attribution) {
                namingJSON = json
            }
            lock.unlock()
            return
        }
        firstParameterReceived = true
        namingJSON = json
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    private func acceptDeepLink(_ value: String, finishWait: Bool) {
        guard !value.isEmpty else { return }
        lock.lock()
        firstParameterReceived = true
        oneLink = value
        if let naming = Self.namingJSON(fromDeepLink: value), !naming.isEmpty {
            namingJSON = naming
        }
        let pending = finishWait ? waiters : []
        if finishWait { waiters.removeAll() }
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    private func waitForFirstParameter(timeoutMilliseconds: Int) async {
        let already: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return firstParameterReceived
        }()
        if already { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if firstParameterReceived {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                self?.finishWaiters()
            }
        }
    }

    private func finishWaiters() {
        lock.lock()
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    private func snapshot() -> (namingJSON: String, deeplink: String) {
        lock.lock()
        defer { lock.unlock() }
        return (namingJSON.isEmpty ? "{}" : namingJSON, oneLink)
    }

    private static func hasCampaignFields(_ attribution: ADJAttribution) -> Bool {
        attribution.campaign?.isEmpty == false
            || attribution.adgroup?.isEmpty == false
            || attribution.creative?.isEmpty == false
            || attribution.clickLabel?.isEmpty == false
    }

    private static func attributionJSON(_ attribution: ADJAttribution) -> String {
        var dict: [String: Any] = [:]
        if let value = attribution.trackerToken { dict["trackerToken"] = value }
        if let value = attribution.trackerName { dict["trackerName"] = value }
        if let value = attribution.network { dict["network"] = value }
        if let value = attribution.campaign { dict["campaign"] = value }
        if let value = attribution.adgroup { dict["adgroup"] = value }
        if let value = attribution.creative { dict["creative"] = value }
        if let value = attribution.clickLabel { dict["clickLabel"] = value }
        if let value = attribution.costType { dict["costType"] = value }
        if let value = attribution.costAmount { dict["costAmount"] = String(describing: value) }
        if let value = attribution.costCurrency { dict["costCurrency"] = value }
        // Keep the complete response Adjust exposes. The individual fields above
        // remain convenient for Banda dashboards, while this preserves any new
        // attribution fields added by Adjust without shipping IDFA.
        if let response = attribution.jsonResponse, !response.isEmpty {
            dict["jsonResponse"] = response
        }
        return jsonString(dict)
    }

    private static func namingJSON(fromDeepLink value: String) -> String? {
        guard let url = URL(string: value),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }
        func first(_ names: String...) -> String? {
            for name in names {
                if let found = queryItems.first(where: { $0.name == name })?.value, !found.isEmpty { return found }
            }
            return nil
        }
        var dict: [String: Any] = [:]
        if let value = first("adj_t", "trackerToken") { dict["trackerToken"] = value }
        if let value = first("adj_campaign", "campaign") { dict["campaign"] = value }
        if let value = first("adj_adgroup", "adgroup") { dict["adgroup"] = value }
        if let value = first("adj_creative", "creative") { dict["creative"] = value }
        if let value = first("adj_label", "clickLabel", "label") { dict["clickLabel"] = value }
        guard !dict.isEmpty else { return nil }
        let json = jsonString(dict)
        return json == "{}" ? nil : json
    }

    private static func jsonString(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
