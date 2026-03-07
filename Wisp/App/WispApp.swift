import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct WispApp: App {
    @State private var apiClient = SpritesAPIClient()
    @State private var browserCoordinator = InAppBrowserCoordinator()
    @State private var loopManager = LoopManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme") private var theme: String = "system"

    init() {
        UserDefaults.standard.register(defaults: [
            "claudeQuestionTool": true,
            "worktreePerChat": true,
        ])

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: LoopManager.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            refreshTask.setTaskCompleted(success: true)
        }
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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                if !loopManager.activeLoopIds.isEmpty {
                    loopManager.scheduleBackgroundRefresh()
                }
            case .active:
                BGTaskScheduler.shared.cancelAllTaskRequests()
            default:
                break
            }
        }
    }
}
