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

struct NetworkRequestEntry: Identifiable {
    let id = UUID()
    let method: String
    let urlString: String
    let status: Int?       // nil means network error before response
    let durationMs: Double
    let error: String?
    let requestBody: String?
    let responseBody: String?
    let timestamp: Date = .now

    init(method: String, urlString: String, status: Int?, durationMs: Double, error: String?, requestBody: String? = nil, responseBody: String? = nil) {
        self.method = method
        self.urlString = urlString
        self.status = status
        self.durationMs = durationMs
        self.error = error
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    var statusColor: Color {
        guard let status else { return .red }
        switch status {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        default: return .red
        }
    }

    var displayPath: String {
        guard let url = URL(string: urlString) else { return urlString }
        let path = url.path()
        return path.isEmpty ? "/" : path
    }

    var formattedDuration: String {
        durationMs < 1000 ? "\(Int(durationMs))ms" : String(format: "%.1fs", durationMs / 1000)
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
    var networkRequests: [NetworkRequestEntry] = []
    fileprivate(set) weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
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
        ucc.addUserScript(WKUserScript(
            source: Self.networkScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        // WeakScriptMessageHandler avoids a retain cycle:
        // WKUserContentController strongly retains its handlers.
        let messageHandler = WeakScriptMessageHandler(context.coordinator)
        ucc.add(messageHandler, name: "consoleLog")
        ucc.add(messageHandler, name: "networkRequest")
        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

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

    private static let networkScript = """
        (function() {
            const h = window.webkit?.messageHandlers?.networkRequest;
            if (!h) return;

            const MAX = 50000;
            function truncate(s) {
                if (!s || s.length <= MAX) return s;
                return s.slice(0, MAX) + '\\n...[truncated]';
            }
            function bodyStr(b) {
                if (b == null) return null;
                if (typeof b === 'string') return truncate(b) || null;
                if (b instanceof URLSearchParams) return truncate(b.toString()) || null;
                return null;
            }

            // Intercept fetch
            const origFetch = window.fetch;
            if (origFetch) {
                window.fetch = function(input, init) {
                    const url = input instanceof Request ? input.url : String(input);
                    const method = (init?.method || (input instanceof Request ? input.method : null) || 'GET').toUpperCase();
                    const reqBody = bodyStr(init?.body);
                    const start = Date.now();
                    return Promise.resolve(origFetch.call(window, input, init)).then(
                        function(r) {
                            const status = r.status;
                            const dur = Date.now() - start;
                            r.clone().text().then(
                                function(text) {
                                    try { h.postMessage({method: method, url: url, status: status, duration: dur, requestBody: reqBody, responseBody: truncate(text) || null}); } catch(e) {}
                                },
                                function() {
                                    try { h.postMessage({method: method, url: url, status: status, duration: dur, requestBody: reqBody}); } catch(e) {}
                                }
                            );
                            return r;
                        },
                        function(err) {
                            try { h.postMessage({method: method, url: url, status: null, duration: Date.now() - start, error: String(err), requestBody: reqBody}); } catch(e) {}
                            throw err;
                        }
                    );
                };
            }

            // Intercept XMLHttpRequest via prototype patching
            const origOpen = XMLHttpRequest.prototype.open;
            const origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
                this._nm = String(method).toUpperCase();
                this._nu = String(url);
                return origOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function(body) {
                const start = Date.now();
                const self = this;
                const reqBody = bodyStr(body);
                this.addEventListener('loadend', function() {
                    try {
                        h.postMessage({
                            method: self._nm || 'GET',
                            url: self._nu || '',
                            status: self.status || null,
                            duration: Date.now() - start,
                            error: self.status === 0 ? 'Network error' : null,
                            requestBody: reqBody,
                            responseBody: truncate(self.responseText) || null
                        });
                    } catch(e) {}
                });
                return origSend.apply(this, arguments);
            };
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
            switch message.name {
            case "consoleLog":
                guard let body = message.body as? [String: String],
                      let levelRaw = body["level"],
                      let text = body["message"]
                else { return }
                Task { @MainActor [weak self] in
                    guard let level = ConsoleLogEntry.Level(rawValue: levelRaw) else { return }
                    self?.coordinator?.state.consoleLogs.append(ConsoleLogEntry(level: level, message: text))
                }
            case "networkRequest":
                guard let body = message.body as? [String: Any],
                      let method = body["method"] as? String,
                      let urlString = body["url"] as? String
                else { return }
                let status = body["status"] as? Int
                let durationMs = body["duration"] as? Double ?? 0
                let error = body["error"] as? String
                let requestBody = body["requestBody"] as? String
                let responseBody = body["responseBody"] as? String
                Task { @MainActor [weak self] in
                    let entry = NetworkRequestEntry(
                        method: method,
                        urlString: urlString,
                        status: status,
                        durationMs: durationMs,
                        error: error,
                        requestBody: requestBody,
                        responseBody: responseBody
                    )
                    self?.coordinator?.state.networkRequests.append(entry)
                }
            default:
                break
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

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            state.reload()
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
                    Task { @MainActor in
                        self?.state.isLoading = webView.isLoading
                        if !webView.isLoading {
                            webView.scrollView.refreshControl?.endRefreshing()
                        }
                    }
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
