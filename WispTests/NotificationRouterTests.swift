import Testing
import Foundation
@testable import Wisp

@MainActor
@Suite("NotificationRouter")
struct NotificationRouterTests {

    @Test func navigate_setsPendingNavigation() {
        let router = NotificationRouter()
        let link = NotificationDeepLink(spriteName: "my-sprite", chatId: UUID())

        router.navigate(to: link)

        #expect(router.pendingNavigation?.spriteName == "my-sprite")
        #expect(router.pendingNavigation?.chatId == link.chatId)
    }

    @Test func consume_returnsPendingAndClears() {
        let router = NotificationRouter()
        let chatId = UUID()
        router.navigate(to: NotificationDeepLink(spriteName: "my-sprite", chatId: chatId))

        let consumed = router.consume()

        #expect(consumed?.spriteName == "my-sprite")
        #expect(consumed?.chatId == chatId)
        #expect(router.pendingNavigation == nil)
    }

    @Test func consume_returnsNilWhenNoPending() {
        let router = NotificationRouter()

        let consumed = router.consume()

        #expect(consumed == nil)
    }

    @Test func navigate_overwritesPreviousPending() {
        let router = NotificationRouter()
        let first = NotificationDeepLink(spriteName: "sprite-a", chatId: UUID())
        let second = NotificationDeepLink(spriteName: "sprite-b", chatId: UUID())

        router.navigate(to: first)
        router.navigate(to: second)

        #expect(router.pendingNavigation?.spriteName == "sprite-b")
    }
}
