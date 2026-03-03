import SwiftUI
import WebKit

struct ConsoleLogEntry: Identifiable {
    let id = UUID()
    let level: Level
    let message: String
    let timestamp: Date = .now

    enum Level: String {
        case log, info, warn, error, debug

        var color: Color {
            switch self {
            case .log: return .primary
            case .info: return .blue
            case .warn: return .orange
            case .error: return .red
            case .debug: return .secondary
            }
        }
    }
}

@Observable
@MainActor
final class WebViewState {
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var currentURL: URL?
    var consoleLogs: [ConsoleLogEntry] = []
    fileprivate(set) weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
}

struct WebViewPage: UIViewRepresentable {
    let initialURL: URL
    var authToken: String?
    let state: WebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, authToken: authToken)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(
            source: Self.consoleScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        // WeakScriptMessageHandler avoids a retain cycle:
        // WKUserContentController strongly retains its handlers.
        ucc.add(WeakScriptMessageHandler(context.coordinator), name: "consoleLog")
        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
        state.webView = webView
        webView.load(context.coordinator.authorizedRequest(for: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private static let consoleScript = """
        (function() {
            const h = window.webkit?.messageHandlers?.consoleLog;
            if (!h) return;
            ['log','info','warn','error','debug'].forEach(function(lvl) {
                const orig = console[lvl].bind(console);
                console[lvl] = function() {
                    const msg = Array.prototype.slice.call(arguments).map(function(a) {
                        try { return typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a); }
                        catch(e) { return String(a); }
                    }).join(' ');
                    try { h.postMessage({level: lvl, message: msg}); } catch(e) {}
                    orig.apply(console, arguments);
                };
            });
        })();
        """

    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler, @unchecked Sendable {
        weak var coordinator: Coordinator?

        init(_ coordinator: Coordinator) {
            self.coordinator = coordinator
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: String],
                  let levelRaw = body["level"],
                  let text = body["message"]
            else { return }
            Task { @MainActor [weak self] in
                guard let level = ConsoleLogEntry.Level(rawValue: levelRaw) else { return }
                self?.coordinator?.state.consoleLogs.append(ConsoleLogEntry(level: level, message: text))
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: WebViewState
        let authToken: String?
        private var observations: [NSKeyValueObservation] = []

        init(state: WebViewState, authToken: String?) {
            self.state = state
            self.authToken = authToken
        }

        func authorizedRequest(for url: URL) -> URLRequest {
            var request = URLRequest(url: url)
            if let token = authToken, url.host()?.hasSuffix(".sprites.app") == true {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.canGoBack) { [weak self] webView, _ in
                    Task { @MainActor in self?.state.canGoBack = webView.canGoBack }
                },
                webView.observe(\.canGoForward) { [weak self] webView, _ in
                    Task { @MainActor in self?.state.canGoForward = webView.canGoForward }
                },
                webView.observe(\.isLoading) { [weak self] webView, _ in
                    Task { @MainActor in self?.state.isLoading = webView.isLoading }
                },
                webView.observe(\.url) { [weak self] webView, _ in
                    Task { @MainActor in self?.state.currentURL = webView.url }
                },
            ]
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let request = navigationAction.request
            guard let url = request.url,
                  url.host()?.hasSuffix(".sprites.app") == true,
                  request.value(forHTTPHeaderField: "Authorization") == nil
            else {
                return .allow
            }

            // Cancel and reload with auth header
            webView.load(authorizedRequest(for: url))
            return .cancel
        }
    }
}
