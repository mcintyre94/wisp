import BackgroundTasks
import SwiftUI

struct RootView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(InAppBrowserCoordinator.self) private var browserCoordinator
    @Environment(LoopManager.self) private var loopManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

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
        .task {
            migrateSpriteSessionsIfNeeded(modelContext: modelContext)
            syncLoopScheduling()
        }
        .onChange(of: apiClient.isAuthenticated, initial: true) {
            syncLoopScheduling()
        }
        .onChange(of: apiClient.hasClaudeToken, initial: true) {
            syncLoopScheduling()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: LoopManager.bgTaskIdentifier)
                syncLoopScheduling()
            case .background:
                loopManager.scheduleBackgroundRefresh(modelContext: modelContext)
            default:
                break
            }
        }
    }

    private func syncLoopScheduling() {
        loopManager.apiClient = apiClient

        guard apiClient.isAuthenticated && apiClient.hasClaudeToken else {
            loopManager.stopAll()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: LoopManager.bgTaskIdentifier)
            return
        }

        loopManager.restoreLoops(modelContext: modelContext)
    }
}
