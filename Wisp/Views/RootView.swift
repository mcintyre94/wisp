import SwiftUI
import UIKit
import UserNotifications

struct RootView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(InAppBrowserCoordinator.self) private var browserCoordinator
    @Environment(NotificationRouter.self) private var notificationRouter
    @Environment(\.modelContext) private var modelContext
    @State private var notificationHandler: NotificationHandler?

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
            setupNotifications()
        }
    }

    private func setupNotifications() {
        guard notificationHandler == nil else { return }
        let handler = NotificationHandler(
            modelContainer: modelContext.container,
            router: notificationRouter
        )
        UNUserNotificationCenter.current().delegate = handler
        notificationHandler = handler
        // Give AppDelegate a reference so it can forward background pushes
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.notificationHandler = handler
        }
        handler.requestPermission()
    }
}
