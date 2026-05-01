import Testing
import Foundation
import SwiftData
@testable import Wisp

@MainActor
@Suite("AutoCheckpoints")
struct AutoCheckpointTests {

    private func makeModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SpriteChat.self, SpriteSession.self, configurations: config)
        return ModelContext(container)
    }

    // MARK: - Checkpoint comment generation

    @Test("Comment is non-nil and non-empty for text content")
    func checkpointCommentFromText() async {
        let msg = ChatMessage(role: .assistant, content: [
            .text("Updated the configuration file\nAlso fixed a typo in the README")
        ])
        let comment = await ChatViewModel.generateCheckpointComment(from: msg)
        #expect(comment != nil)
        #expect(comment!.isEmpty == false)
        #expect(comment!.count <= 120)
    }

    @Test("Comment is capped at 120 chars")
    func checkpointCommentMaxLength() async {
        let longText = String(repeating: "a", count: 200)
        let msg = ChatMessage(role: .assistant, content: [.text(longText)])
        let comment = await ChatViewModel.generateCheckpointComment(from: msg)
        #expect(comment != nil)
        #expect(comment!.count <= 120)
    }

    @Test("Comment is nil for empty content")
    func checkpointCommentEmpty() async {
        let msg = ChatMessage(role: .assistant, content: [])
        let comment = await ChatViewModel.generateCheckpointComment(from: msg)
        #expect(comment == nil)
    }

    @Test("Comment is nil for nil message")
    func checkpointCommentNilMessage() async {
        let comment = await ChatViewModel.generateCheckpointComment(from: nil)
        #expect(comment == nil)
    }

    @Test("Comment is non-nil for tool-use-only message")
    func checkpointCommentToolUseOnly() async {
        let card = ToolUseCard(toolUseId: "tu-1", toolName: "Bash", input: .string("ls"))
        let msg = ChatMessage(role: .assistant, content: [.toolUse(card)])
        let comment = await ChatViewModel.generateCheckpointComment(from: msg)
        #expect(comment != nil)
        #expect(comment!.isEmpty == false)
    }

    // MARK: - Checkpoint fields on ChatMessage

    @Test("Checkpoint fields default to nil")
    func checkpointFieldsDefaultNil() {
        let msg = ChatMessage(role: .assistant, content: [.text("Hello")])
        #expect(msg.checkpointId == nil)
        #expect(msg.checkpointComment == nil)
    }

    @Test("Checkpoint fields can be set in-memory")
    func checkpointFieldsSetInMemory() {
        let msg = ChatMessage(
            role: .assistant,
            content: [.text("I updated the file")],
            checkpointId: "cp-abc123",
            checkpointComment: "Updated the config"
        )
        #expect(msg.checkpointId == "cp-abc123")
        #expect(msg.checkpointComment == "Updated the config")
    }

    // MARK: - SpriteChat forkContext

    @Test("ForkContext field persists on SpriteChat")
    func forkContextPersists() throws {
        let ctx = try makeModelContext()
        let chat = SpriteChat(spriteName: "test", chatNumber: 1)
        chat.forkContext = "Previous context here"
        ctx.insert(chat)
        try ctx.save()

        let id = chat.id
        let descriptor = FetchDescriptor<SpriteChat>(
            predicate: #Predicate { $0.id == id }
        )
        let fetched = try ctx.fetch(descriptor).first
        #expect(fetched?.forkContext == "Previous context here")
    }

    @Test("ForkContext defaults to nil")
    func forkContextDefaultsToNil() {
        let chat = SpriteChat(spriteName: "test", chatNumber: 1)
        #expect(chat.forkContext == nil)
    }
}
