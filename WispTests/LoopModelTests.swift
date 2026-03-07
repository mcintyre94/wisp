import Testing
import Foundation
@testable import Wisp

@Suite("Loop Models")
struct LoopModelTests {

    // MARK: - SpriteLoop Defaults

    @Test func loopDefaultsAreCorrect() {
        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check status",
            interval: .tenMinutes
        )

        #expect(loop.state == .active)
        #expect(loop.stateRaw == "active")
        #expect(loop.iterations.isEmpty)
        #expect(loop.lastRunAt == nil)
        #expect(loop.spriteName == "test-sprite")
        #expect(loop.workingDirectory == "/home/sprite/project")
        #expect(loop.prompt == "Check status")
        #expect(loop.interval == .tenMinutes)
    }

    @Test func defaultDurationIsOneWeek() {
        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check status",
            interval: .fiveMinutes
        )

        let expectedExpiry = loop.createdAt.addingTimeInterval(LoopDuration.oneWeek.timeInterval)
        let difference = abs(loop.expiresAt.timeIntervalSince(expectedExpiry))
        #expect(difference < 1.0)
    }

    // MARK: - Duration Presets

    @Test func durationPresetValues() {
        #expect(LoopDuration.oneDay.timeInterval == 86400)
        #expect(LoopDuration.threeDays.timeInterval == 259200)
        #expect(LoopDuration.oneWeek.timeInterval == 604800)
        #expect(LoopDuration.oneMonth.timeInterval == 2592000)
    }

    @Test func durationDisplayNames() {
        #expect(LoopDuration.oneDay.displayName == "1 Day")
        #expect(LoopDuration.threeDays.displayName == "3 Days")
        #expect(LoopDuration.oneWeek.displayName == "1 Week")
        #expect(LoopDuration.oneMonth.displayName == "1 Month")
    }

    // MARK: - Interval Presets

    @Test func intervalPresetValues() {
        #expect(LoopInterval.fiveMinutes.seconds == 300)
        #expect(LoopInterval.tenMinutes.seconds == 600)
        #expect(LoopInterval.fifteenMinutes.seconds == 900)
        #expect(LoopInterval.thirtyMinutes.seconds == 1800)
        #expect(LoopInterval.oneHour.seconds == 3600)
    }

    @Test func intervalDisplayNames() {
        #expect(LoopInterval.fiveMinutes.displayName == "5m")
        #expect(LoopInterval.tenMinutes.displayName == "10m")
        #expect(LoopInterval.fifteenMinutes.displayName == "15m")
        #expect(LoopInterval.thirtyMinutes.displayName == "30m")
        #expect(LoopInterval.oneHour.displayName == "1h")
    }

    // MARK: - Expiration Logic

    @Test func loopNotExpiredWhenFuture() {
        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check status",
            interval: .tenMinutes,
            duration: .oneWeek
        )

        #expect(!loop.isExpired)
    }

    @Test func loopExpiredWhenBackdated() {
        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check status",
            interval: .tenMinutes
        )
        // Manually backdate expiresAt to the past
        loop.expiresAt = Date().addingTimeInterval(-3600)

        #expect(loop.isExpired)
    }

    // MARK: - Time Remaining Display

    @Test func timeRemainingDisplayShowsSensibleStrings() {
        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check status",
            interval: .tenMinutes,
            duration: .oneWeek
        )

        let display = loop.timeRemainingDisplay
        #expect(display.contains("remaining"))

        // Expired loop
        loop.expiresAt = Date().addingTimeInterval(-100)
        #expect(loop.timeRemainingDisplay == "Expired")
    }

    // MARK: - IterationStatus

    @Test func iterationStatusDefaultIsRunning() {
        let iteration = LoopIteration(prompt: "Do something")
        #expect(iteration.status == .running)
    }

    @Test func iterationInitSetsFields() {
        let iteration = LoopIteration(prompt: "Run tests")
        #expect(iteration.prompt == "Run tests")
        #expect(iteration.responseText == nil)
        #expect(iteration.completedAt == nil)
        #expect(iteration.notificationSummary == nil)
    }
}
