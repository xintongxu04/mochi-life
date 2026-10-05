import UIKit
import WebKit

/// A page after its scripts ran: the HTML (for embedded data) and the text a reader would see,
/// with tabs, accordions and details opened.
struct RenderedPage: Sendable {
    var url: URL
    var html: String
    var text: String
    var clicks: Int
}

/// Loads a page like a browser. Replaceable for tests.
protocol PageRenderer: Sendable {
    /// Nil when the page can't be rendered within the time limit.
    func render(_ url: URL) async -> RenderedPage?
}

/// Renders in an invisible WKWebView: non-persistent storage (no cookies kept), JavaScript on,
/// desktop Safari User-Agent, a 12-second ceiling. Waits for the load plus a quiet network,
/// opens `<details>` and clicks tabs/buttons named nutrition, calorie, guaranteed analysis,
/// feeding, size or ingredients, then reads `body.innerText`, hidden panel text and the HTML.
/// Navigation to other hosts, pop-ups and downloads are blocked; the view is torn down after.
struct WebKitPageRenderer: PageRenderer {
    static let ceiling: Duration = .seconds(12)

    func render(_ url: URL) async -> RenderedPage? {
        guard url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
        let session = await RenderSession(url: url, deadline: .now + Self.ceiling)
        return await session.run()
    }
}

@MainActor
private final class RenderSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let url: URL
    private let deadline: ContinuousClock.Instant
    private let allowedHost: String
    private var webView: WKWebView?
    private var loadWaiter: Once<Bool>?

    init(url: URL, deadline: ContinuousClock.Instant) {
        self.url = url
        self.deadline = deadline
        allowedHost = Self.baseHost(url.host() ?? "")
        super.init()
    }

    func run() async -> RenderedPage? {
        let start = ContinuousClock.now
        defer { tearDown() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsInlineMediaPlayback = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 2400), configuration: configuration)
        webView.customUserAgent = URLSessionWebFetcher.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        // In a window (off screen) so WebKit doesn't treat the page as hidden and throttle it.
        if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            webView.frame.origin = CGPoint(x: -4000, y: 0)
            window.insertSubview(webView, at: 0)
        }
        self.webView = webView

        let loaded = await wait(false) { once in
            self.loadWaiter = once
            webView.load(URLRequest(url: self.url, timeoutInterval: 10))
        }
        AILog.logger.info("render load_finished=\(loaded)")
        guard loaded, !Task.isCancelled else { return nil }
        await waitForQuietNetwork()

        let expanded = await evaluate(Self.expandScript)
        let clicks = Int(expanded ?? "") ?? 0
        try? await Task.sleep(for: .milliseconds(clicks > 0 ? 900 : 300))
        guard !Task.isCancelled,
              let json = await evaluate(Self.readScript),
              let data = json.data(using: .utf8),
              let read = try? JSONDecoder().decode(ReadResult.self, from: data)
        else { return nil }
        let elapsed = ContinuousClock.now - start
        AILog.logger.info("render ok duration_ms=\(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000) clicks=\(clicks) text_chars=\(read.text.count) hidden_chars=\(read.hidden.count) html_bytes=\(read.html.utf8.count)")
        return RenderedPage(url: webView.url ?? url, html: read.html,
                            text: read.text + (read.hidden.isEmpty ? "" : "\n" + read.hidden), clicks: clicks)
    }

    private struct ReadResult: Decodable {
        var text: String
        var hidden: String
        var html: String
    }

    /// Waits until no new network requests have started for 800 ms (at most 3 s).
    private func waitForQuietNetwork() async {
        let limit = min(deadline, .now + .seconds(3))
        var lastCount = -1
        var quietSince = ContinuousClock.now
        while ContinuousClock.now < limit, !Task.isCancelled {
            let count = Int(await evaluate("return String(performance.getEntriesByType('resource').length);") ?? "") ?? 0
            if count != lastCount {
                lastCount = count
                quietSince = .now
            } else if ContinuousClock.now - quietSince >= .milliseconds(800) {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Runs a JavaScript function body in an isolated world and returns its string result.
    private func evaluate(_ script: String) async -> String? {
        guard let webView else { return nil }
        return await wait(nil) { once in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .defaultClient) { result in
                switch result {
                case let .success(value): once.finish(value as? String)
                case .failure: once.finish(nil)
                }
            }
        }
    }

    /// Starts work that calls `finish` once; returns `fallback` at the deadline or on cancellation.
    private func wait<T: Sendable>(_ fallback: T, _ start: (Once<T>) -> Void) async -> T {
        let deadline = self.deadline
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                let once = Once(continuation)
                start(once)
                Task { @MainActor in
                    try? await Task.sleep(until: deadline)
                    once.finish(fallback)
                }
                self.pendingCancel = { once.finish(fallback) }
            }
        } onCancel: {
            Task { @MainActor in self.pendingCancel?() }
        }
    }

    private var pendingCancel: (() -> Void)?

    private func tearDown() {
        loadWaiter?.finish(false)
        pendingCancel = nil
        guard let webView else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        self.webView = nil
    }

    // MARK: - Navigation policy

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload || navigationAction.targetFrame == nil { return .cancel }
        guard let target = navigationAction.request.url else { return .cancel }
        if target.scheme == "about" || target.scheme == "blob" || target.scheme == "data" { return .allow }
        guard ["https", "http"].contains(target.scheme?.lowercased() ?? ""),
              Self.baseHost(target.host() ?? "") == allowedHost
        else {
            AILog.logger.info("render blocked_navigation main_frame=\(navigationAction.targetFrame?.isMainFrame ?? false)")
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadWaiter?.finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadWaiter?.finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadWaiter?.finish(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadWaiter?.finish(false)
    }

    /// No pop-up windows.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    /// "shop.example.com" and "www.example.com" → "example.com".
    static func baseHost(_ host: String) -> String {
        let parts = host.lowercased().split(separator: ".")
        guard parts.count > 2 else { return parts.joined(separator: ".") }
        let twoLevel = ["co", "com", "org", "net", "ac", "gov"].contains(String(parts[parts.count - 2])) && parts.last!.count == 2
        return parts.suffix(twoLevel ? 3 : 2).joined(separator: ".")
    }

    // MARK: - Scripts

    /// Opens details and clicks controls about nutrition; returns how many were clicked.
    static let expandScript = #"""
    const words = /nutrition|calori|guaranteed analysis|feeding|size|ingredient/i;
    document.querySelectorAll('details').forEach(d => { d.open = true; });
    let clicks = 0;
    const controls = document.querySelectorAll('button, summary, [role="tab"], [role="button"], [aria-expanded], [aria-controls], a[href^="#"], [data-toggle], [data-bs-toggle]');
    for (const el of controls) {
      if (clicks >= 25) break;
      const label = ((el.innerText || el.textContent || '') + ' ' + (el.getAttribute('aria-label') || '')).trim();
      if (!label || label.length > 80 || !words.test(label)) continue;
      if (el.tagName === 'A' && !(el.getAttribute('href') || '').startsWith('#')) continue;
      if (el.getAttribute('type') === 'submit' || el.getAttribute('aria-expanded') === 'true') continue;
      try { el.click(); clicks++; } catch (e) {}
    }
    return String(clicks);
    """#

    /// Reads the visible text, text in still-hidden panels that mentions nutrition, and the HTML.
    static let readScript = #"""
    const hiddenWords = /kcal|calori|metaboli|guaranteed analysis|ingredient|net w/i;
    const extra = [];
    let extraLength = 0;
    document.querySelectorAll('[role="tabpanel"], [hidden], [aria-hidden="true"], details, [class*="accordion"], [class*="tab-content"], [class*="tab-pane"], [class*="collapse"], [class*="panel"]').forEach(el => {
      if (extraLength > 30000) return;
      const visible = el.checkVisibility ? el.checkVisibility() : (el.offsetParent !== null);
      if (visible) return;
      const t = (el.textContent || '').replace(/\s+/g, ' ').trim();
      if (t.length < 20 || t.length > 20000 || !hiddenWords.test(t)) return;
      extra.push(t); extraLength += t.length;
    });
    const html = document.documentElement.outerHTML;
    return JSON.stringify({
      text: document.body ? document.body.innerText : '',
      hidden: extra.join('\n'),
      html: html.length > 3000000 ? html.slice(0, 3000000) : html
    });
    """#
}

/// Resumes a continuation exactly once.
@MainActor
private final class Once<T: Sendable> {
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: T) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
