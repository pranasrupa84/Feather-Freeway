import SwiftUI
import WebKit
import MessageUI

struct PlayerBrowser: UIViewControllerRepresentable {
    let url: URL
    let configuration: OnlineConfiguration
    func makeUIViewController(context: Context) -> PlayerBrowserController {
        PlayerBrowserController(url: url, configuration: configuration)
    }
    func updateUIViewController(_ controller: PlayerBrowserController, context: Context) {}
}

@MainActor
final class PlayerBrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, MFMailComposeViewControllerDelegate {
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
    private var returnHistory: [URL] = []
    private var lastCommittedPageURL: URL?
    private var primaryBlankNavigation = false
    private var hasLoadedInitialPage = false
    private var restoringReturnURL = false

    init(url: URL, configuration: OnlineConfiguration) {
        initialURL = url; self.configuration = configuration; lastCommittedPageURL = url
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
    private func load(_ url: URL, restoringFromBack: Bool = false) {
        guard allowsWebNavigation(to: url) else { showError("This destination is unavailable."); return }
        errorPanel.isHidden = true
        restoringReturnURL = restoringFromBack
        web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }
    private func allowsWebNavigation(to url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return false }
        return scheme == "http" || configuration.allows(url)
    }
    private func captureReturnPage() {
        // Provisional redirects can change web.url before a new page actually commits.
        let origin = lastCommittedPageURL ?? initialURL
        guard returnHistory.last != origin else { return }
        returnHistory.append(origin)
    }
    private func refreshControls() {
        back.isEnabled = canNavigateBack(); forward.isEnabled = web.canGoForward
        back.alpha = back.isEnabled ? 1 : 0.35; forward.alpha = forward.isEnabled ? 1 : 0.35
        progress.progress = Float(web.estimatedProgress); progress.isHidden = web.estimatedProgress >= 1
    }
    private func canNavigateBack() -> Bool {
        returnHistory.contains { $0 != web.url } || (primaryBlankNavigation && web.url != initialURL)
    }
    @objc private func goBack() {
        _ = navigateBack()
    }
    @discardableResult
    private func navigateBack() -> Bool {
        while let returnURL = returnHistory.popLast() {
            guard returnURL != web.url else { continue }
            primaryBlankNavigation = false
            if let item = web.backForwardList.backList.last(where: { $0.url == returnURL }),
               web.go(to: item) != nil { return true }
            web.stopLoading()
            load(returnURL, restoringFromBack: true)
            return true
        }
        if primaryBlankNavigation {
            primaryBlankNavigation = false
            web.stopLoading()
            load(initialURL, restoringFromBack: true)
            return true
        }
        return false
    }
    @objc private func goForward() {
        guard web.canGoForward else { return }
        captureReturnPage()
        web.goForward()
    }
    @objc private func reloadPage() { load(web.url ?? initialURL) }
    @objc private func retryPage() { load(failedURL ?? web.url ?? initialURL) }
    private func showError(_ message: String) { errorLabel.text = message; errorPanel.isHidden = false; progress.isHidden = true }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { errorPanel.isHidden = true; progress.isHidden = false }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url, allowsWebNavigation(to: url) { lastCommittedPageURL = url }
        refreshControls()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedInitialPage = true
        restoringReturnURL = false
        failedURL = nil
        errorPanel.isHidden = true
        refreshControls()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showError("The page stopped responding.") }
    private func handle(_ error: Error) {
        let value = error as NSError
        guard value.code != NSURLErrorCancelled, value.code != 102 else { return }
        restoringReturnURL = false
        if let url = value.userInfo[NSURLErrorFailingURLErrorKey] as? URL, allowsWebNavigation(to: url) { failedURL = url }
        showError("The page could not be loaded. Check your connection and try again.")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if hasLoadedInitialPage, !restoringReturnURL, !navigationAction.shouldPerformDownload,
           allowsWebNavigation(to: url) || url.absoluteString == "about:blank",
           navigationAction.navigationType != .backForward,
           navigationAction.navigationType != .reload,
           navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == true {
            // Save the current page before any top-level navigation. A script can redirect
            // from about:blank with replaceState/location.replace and erase WebKit's back item.
            captureReturnPage()
            refreshControls()
        }
        if allowsWebNavigation(to: url) {
            if navigationAction.shouldPerformDownload { decisionHandler(.download) }
            else { decisionHandler(.allow) }
        } else if url.absoluteString == "about:blank" {
            if navigationAction.targetFrame?.isMainFrame == true {
                captureReturnPage()
                primaryBlankNavigation = true
                refreshControls()
            }
            decisionHandler(.allow)
        } else if url.scheme == "blob" && navigationAction.shouldPerformDownload {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        } else {
            decisionHandler(.cancel)
            openExternal(url)
        }
    }
    private func openExternal(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "intent", let range = url.absoluteString.range(of: "S.browser_fallback_url=") {
            let tail = url.absoluteString[range.upperBound...]
            let encoded = String(tail.prefix { $0 != ";" })
            if let decoded = encoded.removingPercentEncoding, let fallback = URL(string: decoded), allowsWebNavigation(to: fallback) { load(fallback) }
            return
        }
        guard !["", "http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) else { return }
        if scheme == "mailto", presentMailComposer(for: url) { return }
        // Let WebKit finish cancelling the navigation before handing control to another app.
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:])
        }
    }
    private func presentMailComposer(for url: URL) -> Bool {
        guard MFMailComposeViewController.canSendMail(), presentedViewController == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = self
        let recipient = components.path.removingPercentEncoding ?? components.path
        let recipients = recipient.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        if !recipients.isEmpty { composer.setToRecipients(recipients) }
        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "subject": composer.setSubject(item.value ?? "")
            case "body": composer.setMessageBody(item.value ?? "", isHTML: false)
            case "cc": composer.setCcRecipients((item.value ?? "").split(separator: ",").map(String.init))
            case "bcc": composer.setBccRecipients((item.value ?? "").split(separator: ",").map(String.init))
            default: break
            }
        }
        present(composer, animated: true)
        return true
    }
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let url = navigationResponse.response.url,
           url.scheme != "blob", url.absoluteString != "about:blank", !allowsWebNavigation(to: url) {
            decisionHandler(.cancel); openExternal(url); return
        }
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        decisionHandler(!navigationResponse.canShowMIMEType || disposition.lowercased().contains("attachment") ? .download : .allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if allowsWebNavigation(to: url) || url.absoluteString == "about:blank" {
            captureReturnPage()
            refreshControls()
            webView.load(navigationAction.request)
        } else {
            openExternal(url)
        }
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
        decisionHandler(request.url.map(allowsWebNavigation) == true ? .allow : .cancel)
    }
    deinit {
        for directory in downloadDirectories { try? FileManager.default.removeItem(at: directory) }
    }
}
