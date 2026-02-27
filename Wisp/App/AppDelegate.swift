import UIKit
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "Notifications")

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by RootView once the model container is available.
    var notificationHandler: NotificationHandler?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("APNs device token: \(token)")
        // TODO: send token to Sprites backend for push notification targeting
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let handler = notificationHandler else {
            completionHandler(.noData)
            return
        }
        handler.handleBackgroundPush(userInfo: userInfo, fetchCompletionHandler: completionHandler)
    }
}
