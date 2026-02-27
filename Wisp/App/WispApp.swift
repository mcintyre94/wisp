import SwiftData
import SwiftUI

@main
struct WispApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var apiClient = SpritesAPIClient()
    @State private var browserCoordinator = InAppBrowserCoordinator()
    @State private var notificationRouter = NotificationRouter()
    @AppStorage("theme") private var theme: String = "system"

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
                .environment(notificationRouter)
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: apiClient.isAuthenticated, initial: true) {
                    browserCoordinator.authToken = apiClient.spritesToken
                }
        }
        .modelContainer(for: [SpriteChat.self, SpriteSession.self])
    }
}
