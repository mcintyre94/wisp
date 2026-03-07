import Testing
import Foundation
@testable import Wisp

@Suite("NotificationService")
struct NotificationServiceTests {

    @Test func buildNotificationContent_setsFields() {
        let content = NotificationService.buildContent(
            title: "Loop Complete",
            body: "Iteration finished successfully",
            loopId: "loop-123",
            iterationId: "iter-456"
        )
        #expect(content.title == "Loop Complete")
        #expect(content.body == "Iteration finished successfully")
        #expect(content.sound == .default)
        #expect(content.userInfo["loopId"] as? String == "loop-123")
        #expect(content.userInfo["iterationId"] as? String == "iter-456")
    }

    @Test func truncatedSummary_shortText() {
        let short = "This is a short message"
        #expect(NotificationService.truncatedSummary(short) == short)
    }

    @Test func truncatedSummary_longText() {
        let long = String(repeating: "a", count: 200)
        let result = NotificationService.truncatedSummary(long)
        #expect(result.count == 123) // 120 chars + "..."
        #expect(result.hasSuffix("..."))
        #expect(result.hasPrefix(String(repeating: "a", count: 120)))
    }
}
