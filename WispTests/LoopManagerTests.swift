import Testing
import Foundation
import SwiftData
@testable import Wisp

@Suite("LoopManager Tests")
@MainActor
struct LoopManagerTests {
    private func makeModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SpriteLoop.self, SpriteChat.self, SpriteSession.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test("register adds loop to activeLoopIds")
    func registerAddsToActive() throws {
        let context = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "check status",
            interval: .fiveMinutes
        )
        context.insert(loop)
        try context.save()

        manager.register(loop: loop, modelContext: context)

        #expect(manager.activeLoopIds.contains(loop.id))
    }

    @Test("stop removes loop from activeLoopIds")
    func stopRemovesFromActive() throws {
        let context = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "check status",
            interval: .fiveMinutes
        )
        context.insert(loop)
        try context.save()

        manager.register(loop: loop, modelContext: context)
        #expect(manager.activeLoopIds.contains(loop.id))

        manager.stop(loopId: loop.id, modelContext: context)
        #expect(!manager.activeLoopIds.contains(loop.id))
    }

    @Test("pause sets state to paused and removes from active; resume restores active")
    func pauseAndResume() throws {
        let context = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "check status",
            interval: .fiveMinutes
        )
        context.insert(loop)
        try context.save()

        manager.register(loop: loop, modelContext: context)
        #expect(manager.activeLoopIds.contains(loop.id))
        #expect(loop.state == .active)

        manager.pause(loopId: loop.id, modelContext: context)
        #expect(!manager.activeLoopIds.contains(loop.id))
        #expect(loop.state == .paused)

        manager.resume(loop: loop, modelContext: context)
        #expect(manager.activeLoopIds.contains(loop.id))
        #expect(loop.state == .active)
    }

    @Test("expired loop is set to stopped and not added to active")
    func expiredLoopStopped() throws {
        let context = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "check status",
            interval: .fiveMinutes
        )
        // Force expiry by setting expiresAt to the past
        loop.expiresAt = Date().addingTimeInterval(-100)
        context.insert(loop)
        try context.save()

        manager.register(loop: loop, modelContext: context)
        #expect(!manager.activeLoopIds.contains(loop.id))
        #expect(loop.state == .stopped)
    }

    @Test("restoreLoops re-registers persisted active loops only")
    func restoreLoopsRegistersPersistedActiveLoops() throws {
        let context = try makeModelContext()
        let manager = LoopManager()

        let activeLoop = SpriteLoop(
            spriteName: "active-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "check active",
            interval: .tenMinutes
        )
        let pausedLoop = SpriteLoop(
            spriteName: "paused-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "check paused",
            interval: .tenMinutes
        )
        pausedLoop.state = .paused

        context.insert(activeLoop)
        context.insert(pausedLoop)
        try context.save()

        manager.restoreLoops(modelContext: context)

        #expect(manager.activeLoopIds.contains(activeLoop.id))
        #expect(!manager.activeLoopIds.contains(pausedLoop.id))
    }

    @Test("register makes the loop due immediately")
    func registerMarksLoopDueNow() throws {
        let context = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "check status",
            interval: .tenMinutes
        )
        loop.scheduleNextRun(after: Date().addingTimeInterval(3600))
        context.insert(loop)
        try context.save()

        manager.register(loop: loop, modelContext: context)

        #expect(loop.nextRunAt <= Date())
        #expect(manager.activeLoopIds.contains(loop.id))
    }

    @Test("handleBackgroundRefresh succeeds on MainActor with no due loops")
    func handleBackgroundRefreshOnMainActor() async throws {
        // This test documents that handleBackgroundRefresh must be called from
        // MainActor context. The BGTaskScheduler handler must dispatch to main
        // queue (using: .main) to avoid @MainActor isolation crashes at runtime.
        let context = try makeModelContext()
        let manager = LoopManager()
        manager.apiClient = SpritesAPIClient()

        let success = await manager.handleBackgroundRefresh(modelContext: context)
        #expect(success)
    }
}
