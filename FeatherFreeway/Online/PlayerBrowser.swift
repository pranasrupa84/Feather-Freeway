import SwiftUI
import WebKit

struct PlayerBrowser: UIViewControllerRepresentable {
    let url: URL
    let configuration: OnlineConfiguration
    func makeUIViewController(context: Context) -> PlayerBrowserController {
        PlayerBrowserController(url: url, configuration: configuration)
    }
    func updateUIViewController(_ controller: PlayerBrowserController, context: Context) {}
}

@MainActor
final class PlayerBrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let initialURL: URL
    private let configuration: OnlineConfiguration
    private var web: WKWebView!
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let back = UIButton(type: .system)
    private let forward = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let errorPanel = UIStackView()
    private let errorLabel = UILabel()
    private var observations: [NSKeyValueObservation] = []
    private var downloads: [ObjectIdentifier: URL] = [:]
    private var downloadDirectories: [URL] = []
    private var failedURL: URL?

    init(url: URL, configuration: OnlineConfiguration) {
        initialURL = url; self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .default()
        settings.defaultWebpagePreferences.allowsContentJavaScript = true
        settings.allowsInlineMediaPlayback = true
        settings.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: .zero, configuration: settings)
        web.navigationDelegate = self; web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.allowsLinkPreview = true
        web.isOpaque = false; web.backgroundColor = .black; web.scrollView.backgroundColor = .black
        let bar = UIStackView(arrangedSubviews: [back, forward, reloadButton])
        bar.axis = .horizontal; bar.distribution = .fillEqually; bar.backgroundColor = .black
        for (button, symbol, title, action) in [
            (back, "chevron.left", "Back", #selector(goBack)),
            (forward, "chevron.right", "Forward", #selector(goForward)),
            (reloadButton, "arrow.clockwise", "Reload", #selector(reloadPage))
        ] {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityLabel = title; button.tintColor = .white
            button.addTarget(self, action: action, for: .touchUpInside)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        for child in [web!, bar, progress] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            progress.topAnchor.constraint(equalTo: web.topAnchor),
            progress.leadingAnchor.constraint(equalTo: web.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: web.trailingAnchor)
        ])
        errorLabel.textAlignment = .center; errorLabel.numberOfLines = 0; errorLabel.textColor = .white
        let retry = UIButton(type: .system)
        retry.setTitle("Try Again", for: .normal); retry.tintColor = .white
        retry.addTarget(self, action: #selector(retryPage), for: .touchUpInside)
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        errorPanel.axis = .vertical; errorPanel.spacing = 12
        errorPanel.addArrangedSubview(errorLabel); errorPanel.addArrangedSubview(retry)
        errorPanel.translatesAutoresizingMaskIntoConstraints = false; errorPanel.backgroundColor = .black
        errorPanel.isHidden = true; view.addSubview(errorPanel)
        NSLayoutConstraint.activate([
            errorPanel.centerXAnchor.constraint(equalTo: web.centerXAnchor), errorPanel.centerYAnchor.constraint(equalTo: web.centerYAnchor),
            errorPanel.widthAnchor.constraint(lessThanOrEqualTo: web.widthAnchor, constant: -40)
        ])
        observations = [
            web.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshControls() }
            },
            web.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in Task { @MainActor [weak self] in self?.refreshControls() } },
            web.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in Task { @MainActor [weak self] in self?.refreshControls() } }
        ]
        refreshControls(); load(initialURL)
    }
    private func load(_ url: URL) {
        guard configuration.allows(url) else { showError("This destination is unavailable."); return }
        errorPanel.isHidden = true
        web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }
    private func refreshControls() {
        back.isEnabled = web.canGoBack; forward.isEnabled = web.canGoForward
        back.alpha = back.isEnabled ? 1 : 0.35; forward.alpha = forward.isEnabled ? 1 : 0.35
        progress.progress = Float(web.estimatedProgress); progress.isHidden = web.estimatedProgress >= 1
    }
    @objc private func goBack() { if web.canGoBack { web.goBack() } }
    @objc private func goForward() { if web.canGoForward { web.goForward() } }
    @objc private func reloadPage() { load(web.url ?? initialURL) }
    @objc private func retryPage() { load(failedURL ?? web.url ?? initialURL) }
    private func showError(_ message: String) { errorLabel.text = message; errorPanel.isHidden = false; progress.isHidden = true }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { errorPanel.isHidden = true; progress.isHidden = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { failedURL = nil; errorPanel.isHidden = true; refreshControls() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showError("The page stopped responding.") }
    private func handle(_ error: Error) {
        let value = error as NSError
        guard value.code != NSURLErrorCancelled, value.code != 102 else { return }
        if let url = value.userInfo[NSURLErrorFailingURLErrorKey] as? URL, configuration.allows(url) { failedURL = url }
        showError("The page could not be loaded. Check your connection and try again.")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if configuration.allows(url) {
            if navigationAction.shouldPerformDownload { decisionHandler(.download) }
            else { decisionHandler(.allow) }
        } else if url.absoluteString == "about:blank" || (url.scheme == "blob" && navigationAction.shouldPerformDownload) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated { openExternal(url) }
        }
    }
    private func openExternal(_ url: URL) {
        let allowedSchemes = ["tel", "mailto", "sms", "facetime", "facetime-audio", "maps", "itms-apps"]
        if allowedSchemes.contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url); return
        }
        if url.scheme == "intent", let range = url.absoluteString.range(of: "S.browser_fallback_url=") {
            let tail = url.absoluteString[range.upperBound...]
            let encoded = String(tail.prefix { $0 != ";" })
            if let decoded = encoded.removingPercentEncoding, let fallback = URL(string: decoded), configuration.allows(fallback) { load(fallback) }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let url = navigationResponse.response.url, url.scheme != "blob" && !configuration.allows(url) { decisionHandler(.cancel); return }
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        decisionHandler(!navigationResponse.canShowMIMEType || disposition.lowercased().contains("attachment") ? .download : .allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, self.configuration.allows(url) { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        guard presentedViewController == nil else { completionHandler(); return }; present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        guard presentedViewController == nil else { completionHandler(false); return }; present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in completionHandler(alert?.textFields?.first?.text) })
        guard presentedViewController == nil else { completionHandler(nil); return }; present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.protocol == "https" ? .prompt : .deny)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            downloadDirectories.append(directory)
            let safeName = URL(fileURLWithPath: suggestedFilename).lastPathComponent
            let destination = directory.appendingPathComponent(safeName.isEmpty || safeName == "." || safeName == ".." ? "download" : safeName)
            downloads[ObjectIdentifier(download)] = destination; completionHandler(destination)
        } catch { completionHandler(nil); showError("The file could not be saved.") }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = reloadButton
        share.popoverPresentationController?.sourceRect = reloadButton.bounds
        share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        guard presentedViewController == nil else { showError("Close the dialog, then download the file again."); return }
        present(share, animated: true)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let file = downloads.removeValue(forKey: ObjectIdentifier(download)) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        showError("The download failed. Please try again.")
    }
    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(request.url.map(configuration.allows) == true ? .allow : .cancel)
    }
    deinit {
        for directory in downloadDirectories { try? FileManager.default.removeItem(at: directory) }
    }
}
