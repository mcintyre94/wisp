import Foundation
import UserNotifications
import SwiftData
import UIKit
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "Notifications")

/// Handles incoming push notifications containing a Claude `session_id`.
///
/// - Foreground: shows the notification only when `session_id` belongs to a chat in Wisp;
///   suppresses it otherwise.
/// - Tap: resolves the session to a sprite + chat and tells `NotificationRouter` to navigate there.
@MainActor
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private let modelContainer: ModelContainer
    private let router: NotificationRouter

    init(modelContainer: ModelContainer, router: NotificationRouter) {
        self.modelContainer = modelContainer
        self.router = router
    }

    func requestPermission() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                logger.info("Notification permission granted: \(granted)")
            } catch {
                logger.error("Notification permission request failed: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification arrives while the app is in the foreground.
    /// Show it only if the session belongs to a Wisp chat; suppress otherwise.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let sessionId = notification.request.content.userInfo["session_id"] as? String
        if let sessionId, findChat(forSessionId: sessionId) != nil {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([])
        }
    }

    /// Called when the user taps a notification. Navigate to the linked chat if found.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionId = response.notification.request.content.userInfo["session_id"] as? String
        if let sessionId, let (spriteName, chatId) = findChat(forSessionId: sessionId) {
            router.navigate(to: NotificationDeepLink(spriteName: spriteName, chatId: chatId))
        }
        completionHandler()
    }

    // MARK: - Background push

    /// Called by AppDelegate when a silent push (`content-available: 1`) arrives.
    /// Posts a local notification if the session belongs to a Wisp chat; otherwise suppresses.
    ///
    /// Expected payload keys alongside `aps`:
    ///   - `session_id`: the Claude session ID
    ///   - `title`: notification title (optional, falls back to "Claude finished")
    ///   - `body`: notification body (optional, falls back to "Tap to view your session")
    func handleBackgroundPush(
        userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let sessionId = userInfo["session_id"] as? String,
              findChat(forSessionId: sessionId) != nil
        else {
            completionHandler(.noData)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = userInfo["title"] as? String ?? "Claude finished"
        content.body = userInfo["body"] as? String ?? "Tap to view your session"
        content.sound = .default
        content.userInfo = ["session_id": sessionId]

        let request = UNNotificationRequest(
            identifier: sessionId,
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                completionHandler(.newData)
            } catch {
                logger.error("Failed to post local notification: \(error)")
                completionHandler(.failed)
            }
        }
    }

    // MARK: - Private

    private func findChat(forSessionId sessionId: String) -> (spriteName: String, chatId: UUID)? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SpriteChat>(
            predicate: #Predicate { $0.claudeSessionId == sessionId }
        )
        guard let chat = try? context.fetch(descriptor).first else { return nil }
        return (chat.spriteName, chat.id)
    }
}
