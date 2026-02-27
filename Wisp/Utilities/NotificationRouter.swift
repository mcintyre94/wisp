import Foundation

struct NotificationDeepLink: Sendable, Equatable {
    let spriteName: String
    let chatId: UUID
}

/// Coordinates navigation to a specific chat when a push notification is tapped.
/// Injected into the environment so DashboardView and SpriteDetailView can react.
@Observable
@MainActor
final class NotificationRouter {
    var pendingNavigation: NotificationDeepLink?

    func navigate(to link: NotificationDeepLink) {
        pendingNavigation = link
    }

    func consume() -> NotificationDeepLink? {
        defer { pendingNavigation = nil }
        return pendingNavigation
    }
}
