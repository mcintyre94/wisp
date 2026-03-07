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
}
