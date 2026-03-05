import SwiftData
import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.removeObject(forKey: "apnsDeviceToken")
    }
}

@main
struct WispApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var apiClient = SpritesAPIClient()
    @State private var browserCoordinator = InAppBrowserCoordinator()
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
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: apiClient.isAuthenticated, initial: true) {
                    browserCoordinator.authToken = apiClient.spritesToken
                }
        }
        .modelContainer(for: [SpriteChat.self, SpriteSession.self])
    }
}
