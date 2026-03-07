import Foundation
import UserNotifications

enum NotificationService {
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func buildContent(title: String, body: String, loopId: String, iterationId: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["loopId": loopId, "iterationId": iterationId]
        return content
    }

    static func postNotification(title: String, body: String, loopId: String, iterationId: String) async {
        let content = buildContent(title: title, body: body, loopId: loopId, iterationId: iterationId)
        let request = UNNotificationRequest(identifier: iterationId, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func truncatedSummary(_ text: String, maxLength: Int = 120) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}
