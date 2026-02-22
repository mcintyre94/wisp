import Testing
import Foundation
import SwiftData
@testable import Wisp

@MainActor
@Suite("SpriteChatListViewModel")
struct SpriteChatListViewModelTests {

    private func makeModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SpriteChat.self, SpriteSession.self, configurations: config)
        return ModelContext(container)
    }

    // MARK: - createChat

    @Test func createChat_incrementsChatNumber() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")

        let chat1 = vm.createChat(modelContext: ctx)
        let chat2 = vm.createChat(modelContext: ctx)
        let chat3 = vm.createChat(modelContext: ctx)

        #expect(chat1.chatNumber == 1)
        #expect(chat2.chatNumber == 2)
        #expect(chat3.chatNumber == 3)
    }

    @Test func createChat_setsActive() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")

        let chat = vm.createChat(modelContext: ctx)

        #expect(vm.activeChatId == chat.id)
        #expect(vm.chats.count == 1)
    }

    // MARK: - loadChats

    @Test func loadChats_setsActiveToMostRecentNonClosed() throws {
        let ctx = try makeModelContext()

        let chat1 = SpriteChat(spriteName: "test-sprite", chatNumber: 1)
        chat1.lastUsed = Date(timeIntervalSinceNow: -100)
        chat1.isClosed = true
        let chat2 = SpriteChat(spriteName: "test-sprite", chatNumber: 2)
        chat2.lastUsed = Date(timeIntervalSinceNow: -50)
        let chat3 = SpriteChat(spriteName: "test-sprite", chatNumber: 3)
        chat3.lastUsed = Date()

        ctx.insert(chat1)
        ctx.insert(chat2)
        ctx.insert(chat3)
        try ctx.save()

        let vm = SpriteChatListViewModel(spriteName: "test-sprite")
        vm.loadChats(modelContext: ctx)

        #expect(vm.chats.count == 3)
        // Most recent non-closed is chat3
        #expect(vm.activeChatId == chat3.id)
    }

    // MARK: - closeChat

    @Test func closeChat_setsIsClosed() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")
        let apiClient = SpritesAPIClient()

        let chat = vm.createChat(modelContext: ctx)
        #expect(chat.isClosed == false)

        vm.closeChat(chat, apiClient: apiClient, modelContext: ctx)
        #expect(chat.isClosed == true)
    }

    @Test func closeChat_selectsNextOpenChat() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")
        let apiClient = SpritesAPIClient()

        let chat1 = vm.createChat(modelContext: ctx)
        let chat2 = vm.createChat(modelContext: ctx)

        #expect(vm.activeChatId == chat2.id)

        vm.closeChat(chat2, apiClient: apiClient, modelContext: ctx)

        #expect(vm.activeChatId == chat1.id)
    }

    // MARK: - deleteChat

    @Test func deleteChat_removesFromList() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")
        let apiClient = SpritesAPIClient()

        let chat1 = vm.createChat(modelContext: ctx)
        _ = vm.createChat(modelContext: ctx)

        #expect(vm.chats.count == 2)

        vm.deleteChat(chat1, apiClient: apiClient, modelContext: ctx)
        #expect(vm.chats.count == 1)
    }

    // MARK: - selectChat

    @Test func selectChat_updatesActiveChatId() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")

        let chat1 = vm.createChat(modelContext: ctx)
        let chat2 = vm.createChat(modelContext: ctx)

        #expect(vm.activeChatId == chat2.id)

        vm.selectChat(chat1)
        #expect(vm.activeChatId == chat1.id)
    }

    // MARK: - clearAllChats

    @Test func clearAllChats_removesAllChatsAndResetsState() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")
        let apiClient = SpritesAPIClient()

        _ = vm.createChat(modelContext: ctx)
        _ = vm.createChat(modelContext: ctx)
        _ = vm.createChat(modelContext: ctx)
        #expect(vm.chats.count == 3)

        vm.clearAllChats(apiClient: apiClient, modelContext: ctx)

        #expect(vm.chats.isEmpty)
        #expect(vm.activeChatId == nil)

        // Verify SwiftData records are deleted
        let descriptor = FetchDescriptor<SpriteChat>()
        let remaining = try ctx.fetch(descriptor)
        #expect(remaining.isEmpty)
    }

    // MARK: - spriteCreatedAt

    @Test func createChat_storesSpriteCreatedAt() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")
        let date = Date(timeIntervalSince1970: 1700000000)
        vm.spriteCreatedAt = date

        let chat = vm.createChat(modelContext: ctx)

        #expect(chat.spriteCreatedAt == date)
    }

    @Test func createChat_spriteCreatedAtNilByDefault() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")

        let chat = vm.createChat(modelContext: ctx)

        #expect(chat.spriteCreatedAt == nil)
    }

    @Test func updateSpriteCreatedAt_updatesAllChats() throws {
        let ctx = try makeModelContext()
        let vm = SpriteChatListViewModel(spriteName: "test-sprite")

        _ = vm.createChat(modelContext: ctx)
        _ = vm.createChat(modelContext: ctx)

        let newDate = Date(timeIntervalSince1970: 1800000000)
        vm.updateSpriteCreatedAt(newDate, modelContext: ctx)

        #expect(vm.spriteCreatedAt == newDate)
        for chat in vm.chats {
            #expect(chat.spriteCreatedAt == newDate)
        }
    }
}
