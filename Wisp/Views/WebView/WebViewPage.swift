import SwiftUI
import WebKit

@Observable
@MainActor
final class WebViewState {
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var currentURL: URL?
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
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
        state.webView = webView
        webView.load(context.coordinator.authorizedRequest(for: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

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
