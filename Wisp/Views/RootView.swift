import SwiftUI

struct RootView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(InAppBrowserCoordinator.self) private var browserCoordinator

    var body: some View {
        @Bindable var browser = browserCoordinator

        Group {
            if apiClient.isAuthenticated && apiClient.hasClaudeToken {
                DashboardView()
            } else {
                AuthView()
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            browserCoordinator.open(url)
            return .handled
        })
        .sheet(isPresented: Binding(
            get: { browser.presentedURL != nil },
            set: { if !$0 { browser.presentedURL = nil } }
        )) {
            if let url = browserCoordinator.presentedURL {
                InAppBrowserSheet(initialURL: url, authToken: browserCoordinator.authToken)
            }
        }
    }
}
