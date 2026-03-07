import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct WispApp: App {
    private let sharedModelContainer: ModelContainer
    @State private var apiClient = SpritesAPIClient()
    @State private var browserCoordinator = InAppBrowserCoordinator()
    @State private var chatSessionManager = ChatSessionManager()
    @State private var loopManager = LoopManager()
    @AppStorage("theme") private var theme: String = "system"

    init() {
        do {
            sharedModelContainer = try ModelContainer(for: SpriteChat.self, SpriteSession.self, SpriteLoop.self)
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }

        UserDefaults.standard.register(defaults: [
            "claudeQuestionTool": true,
            "worktreePerChat": true,
        ])

        let modelContainer = sharedModelContainer
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: LoopManager.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            let workTask = Task { @MainActor in
                let backgroundLoopManager = LoopManager()
                backgroundLoopManager.apiClient = SpritesAPIClient()
                let modelContext = ModelContext(modelContainer)
                return await backgroundLoopManager.handleBackgroundRefresh(modelContext: modelContext)
            }

            refreshTask.expirationHandler = {
                workTask.cancel()
            }

            Task {
                let success = await workTask.value
                refreshTask.setTaskCompleted(success: success)
            }
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
                .environment(chatSessionManager)
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
        .modelContainer(sharedModelContainer)
    }
}
