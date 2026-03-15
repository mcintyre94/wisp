import Testing
import Foundation
import SwiftData
@testable import Wisp

@MainActor
@Suite("ChatSessionManager")
struct ChatSessionManagerTests {

    private func makeModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SpriteChat.self, SpriteSession.self, configurations: config)
        return ModelContext(container)
    }

    private func makeChat(number: Int = 1, modelContext: ModelContext) -> SpriteChat {
        let chat = SpriteChat(spriteName: "test", chatNumber: number)
        modelContext.insert(chat)
        try? modelContext.save()
        return chat
    }

    // MARK: - viewModel(for:)

    @Test func viewModel_returnsSameInstanceOnSecondCall() throws {
        let ctx = try makeModelContext()
        let manager = ChatSessionManager()
        let chat = makeChat(modelContext: ctx)
        let apiClient = SpritesAPIClient()

        let vm1 = manager.viewModel(for: chat, spriteName: "test", apiClient: apiClient, modelContext: ctx)
        let vm2 = manager.viewModel(for: chat, spriteName: "test", apiClient: apiClient, modelContext: ctx)

        #expect(vm1 === vm2)
    }

    @Test func viewModel_createsDistinctInstancesForDifferentChats() throws {
        let ctx = try makeModelContext()
        let manager = ChatSessionManager()
        let chat1 = makeChat(number: 1, modelContext: ctx)
        let chat2 = makeChat(number: 2, modelContext: ctx)
        let apiClient = SpritesAPIClient()

        let vm1 = manager.viewModel(for: chat1, spriteName: "test", apiClient: apiClient, modelContext: ctx)
        let vm2 = manager.viewModel(for: chat2, spriteName: "test", apiClient: apiClient, modelContext: ctx)

        #expect(vm1 !== vm2)
    }

    // MARK: - isStreaming

    @Test func isStreaming_returnsFalseForUncachedId() {
        let manager = ChatSessionManager()
        #expect(manager.isStreaming(chatId: UUID()) == false)
    }

    @Test func isStreaming_returnsFalseForCachedIdleVM() throws {
        let ctx = try makeModelContext()
        let manager = ChatSessionManager()
        let chat = makeChat(modelContext: ctx)

        let vm = manager.viewModel(for: chat, spriteName: "test", apiClient: SpritesAPIClient(), modelContext: ctx)
        vm.status = .idle

        #expect(manager.isStreaming(chatId: chat.id) == false)
    }

    // MARK: - remove(chatId:)

    @Test func remove_evictsFromCacheSoNextCallCreatesNewVM() throws {
        let ctx = try makeModelContext()
        let manager = ChatSessionManager()
        let chat = makeChat(modelContext: ctx)
        let apiClient = SpritesAPIClient()

        let vm1 = manager.viewModel(for: chat, spriteName: "test", apiClient: apiClient, modelContext: ctx)
        manager.remove(chatId: chat.id, modelContext: ctx)
        let vm2 = manager.viewModel(for: chat, spriteName: "test", apiClient: apiClient, modelContext: ctx)

        #expect(vm1 !== vm2)
    }

    @Test func remove_isNoopForUncachedId() throws {
        let ctx = try makeModelContext()
        let manager = ChatSessionManager()
        // Should not crash when removing an ID that was never cached
        manager.remove(chatId: UUID(), modelContext: ctx)
    }

    // MARK: - detachAll()

    @Test func detachAll_clearsAllCachedVMs() throws {
        let ctx = try makeModelContext()
        let manager = ChatSessionManager()
        let chat1 = makeChat(number: 1, modelContext: ctx)
        let chat2 = makeChat(number: 2, modelContext: ctx)
        let apiClient = SpritesAPIClient()

        let vm1 = manager.viewModel(for: chat1, spriteName: "test", apiClient: apiClient, modelContext: ctx)
        let vm2 = manager.viewModel(for: chat2, spriteName: "test", apiClient: apiClient, modelContext: ctx)

        manager.detachAll(modelContext: ctx)

        let vm1After = manager.viewModel(for: chat1, spriteName: "test", apiClient: apiClient, modelContext: ctx)
        let vm2After = manager.viewModel(for: chat2, spriteName: "test", apiClient: apiClient, modelContext: ctx)

        #expect(vm1 !== vm1After)
        #expect(vm2 !== vm2After)
    }
}
