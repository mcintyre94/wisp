import Testing
import Foundation
import SwiftData
@testable import Wisp

@MainActor
@Suite("SpriteChatMigration")
struct SpriteChatMigrationTests {

    private func makeModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SpriteChat.self, SpriteSession.self, configurations: config)
        return ModelContext(container)
    }

    @Test func migratesSpriteSessionToSpriteChat() throws {
        let ctx = try makeModelContext()

        let session = SpriteSession(spriteName: "my-sprite", workingDirectory: "/home/sprite/myproject")
        session.claudeSessionId = "sess-123"
        session.draftInputText = "hello"
        session.lastUsed = Date(timeIntervalSinceNow: -60)
        ctx.insert(session)
        try ctx.save()

        migrateSpriteSessionsIfNeeded(modelContext: ctx)

        let sessionDescriptor = FetchDescriptor<SpriteSession>()
        let remainingSessions = try ctx.fetch(sessionDescriptor)
        #expect(remainingSessions.isEmpty)

        let chatDescriptor = FetchDescriptor<SpriteChat>()
        let chats = try ctx.fetch(chatDescriptor)
        #expect(chats.count == 1)

        let chat = chats[0]
        #expect(chat.spriteName == "my-sprite")
        #expect(chat.chatNumber == 1)
        #expect(chat.claudeSessionId == "sess-123")
        #expect(chat.workingDirectory == "/home/sprite/myproject")
        #expect(chat.draftInputText == "hello")
        #expect(chat.isClosed == false)
    }

    @Test func migrationIsIdempotent() throws {
        let ctx = try makeModelContext()

        migrateSpriteSessionsIfNeeded(modelContext: ctx)

        let chatDescriptor = FetchDescriptor<SpriteChat>()
        let chats = try ctx.fetch(chatDescriptor)
        #expect(chats.isEmpty)
    }

    @Test func migratedChatsHaveNilSpriteCreatedAt() throws {
        let ctx = try makeModelContext()

        let session = SpriteSession(spriteName: "migrated-sprite")
        ctx.insert(session)
        try ctx.save()

        migrateSpriteSessionsIfNeeded(modelContext: ctx)

        let chatDescriptor = FetchDescriptor<SpriteChat>()
        let chats = try ctx.fetch(chatDescriptor)
        #expect(chats.count == 1)
        #expect(chats[0].spriteCreatedAt == nil)
    }
}
