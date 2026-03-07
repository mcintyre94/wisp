import SwiftData
import SwiftUI

@main
struct WispApp: App {
    @State private var apiClient = SpritesAPIClient()
    @State private var browserCoordinator = InAppBrowserCoordinator()
    @State private var loopManager = LoopManager()
    @AppStorage("theme") private var theme: String = "system"

    init() {
        UserDefaults.standard.register(defaults: [
            "claudeQuestionTool": true,
            "worktreePerChat": true,
        ])
    }

    private var preferredColorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(apiClient)
                .environment(browserCoordinator)
                .environment(loopManager)
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: apiClient.isAuthenticated, initial: true) {
                    browserCoordinator.authToken = apiClient.spritesToken
                }
                .task {
                    loopManager.apiClient = apiClient
                    await NotificationService.requestPermission()
                }
        }
        .modelContainer(for: [SpriteChat.self, SpriteSession.self, SpriteLoop.self])
    }
}
