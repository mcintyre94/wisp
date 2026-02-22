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

        // Create a SpriteSession with data
        let session = SpriteSession(spriteName: "my-sprite", workingDirectory: "/home/sprite/myproject")
        session.claudeSessionId = "sess-123"
        session.draftInputText = "hello"
        session.lastUsed = Date(timeIntervalSinceNow: -60)
        let messages = [PersistedChatMessage(
            id: UUID(),
            timestamp: Date(),
            role: .user,
            content: [.text("test message")]
        )]
        session.saveMessages(messages)
        ctx.insert(session)
        try ctx.save()

        // Run migration
        migrateSpriteSessionsIfNeeded(modelContext: ctx)

        // Verify SpriteSession is deleted
        let sessionDescriptor = FetchDescriptor<SpriteSession>()
        let remainingSessions = try ctx.fetch(sessionDescriptor)
        #expect(remainingSessions.isEmpty)

        // Verify SpriteChat was created
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

        // Verify messages were copied
        let loadedMessages = chat.loadMessages()
        #expect(loadedMessages.count == 1)
    }

    @Test func migrationIsIdempotent() throws {
        let ctx = try makeModelContext()

        // No sessions to migrate
        migrateSpriteSessionsIfNeeded(modelContext: ctx)

        let chatDescriptor = FetchDescriptor<SpriteChat>()
        let chats = try ctx.fetch(chatDescriptor)
        #expect(chats.isEmpty)
    }
}
