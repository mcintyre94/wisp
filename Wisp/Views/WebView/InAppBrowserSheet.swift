import SwiftUI

struct InAppBrowserSheet: View {
    let initialURL: URL
    var authToken: String?
    @Environment(\.dismiss) private var dismiss
    @State private var state = WebViewState()

    private var displayTitle: String {
        let host = (state.currentURL ?? initialURL).host() ?? ""
        if host.hasSuffix(".sprites.app"), let name = host.split(separator: ".").first {
            return String(name)
        }
        return host.isEmpty ? initialURL.absoluteString : host
    }

    var body: some View {
        NavigationStack {
            WebViewPage(initialURL: initialURL, authToken: authToken, state: state)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }

                    ToolbarItem(placement: .status) {
                        if state.isLoading {
                            ProgressView()
                        }
                    }

                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            state.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!state.canGoBack)

                        Button {
                            state.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!state.canGoForward)

                        Spacer()

                        ShareLink(item: state.currentURL ?? initialURL)

                        Button {
                            UIApplication.shared.open(state.currentURL ?? initialURL)
                        } label: {
                            Image(systemName: "safari")
                        }
                    }
                }
        }
    }
}
