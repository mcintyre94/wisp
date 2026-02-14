import SwiftUI

struct RootView: View {
    @Environment(SpritesAPIClient.self) private var apiClient

    var body: some View {
        if apiClient.isAuthenticated && apiClient.hasClaudeToken {
            DashboardView()
        } else {
            AuthView()
        }
    }
}
