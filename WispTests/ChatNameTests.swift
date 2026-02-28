import Testing
import Foundation
import SwiftData
@testable import Wisp

@MainActor
@Suite("ChatName")
struct ChatNameTests {

    private func makeModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SpriteChat.self, SpriteSession.self, configurations: config)
        return ModelContext(container)
    }

    private func makeChatViewModel(modelContext: ModelContext) -> (ChatViewModel, SpriteChat) {
        let chat = SpriteChat(spriteName: "test", chatNumber: 1)
        modelContext.insert(chat)
        try? modelContext.save()
        let vm = ChatViewModel(
            spriteName: "test",
            chatId: chat.id,
            currentServiceName: nil,
            workingDirectory: chat.workingDirectory
        )
        return (vm, chat)
    }

    // MARK: - generateChatName (static)

    @Test("Name is non-nil and non-empty for normal prompt")
    func chatNameFromPrompt() async {
        let name = await ChatViewModel.generateChatName(from: "How do I add dark mode to my iOS app?")
        #expect(name.isEmpty == false)
        #expect(name.count <= 80)
    }

    @Test("Name is capped at 80 chars")
    func chatNameMaxLength() async {
        let longPrompt = String(repeating: "a", count: 1000)
        let name = await ChatViewModel.generateChatName(from: longPrompt)
        #expect(name.count <= 80)
    }

    @Test("Empty prompt returns 'New Chat'")
    func chatNameFromEmptyPrompt() async {
        let name = await ChatViewModel.generateChatName(from: "")
        #expect(name == "New Chat")
    }

    @Test("Whitespace-only prompt returns 'New Chat'")
    func chatNameFromWhitespace() async {
        let name = await ChatViewModel.generateChatName(from: "   \n\t  ")
        #expect(name == "New Chat")
    }

    @Test("Multiline prompt uses first line as fallback base")
    func chatNameMultilinePrompt() async {
        let prompt = "Fix the login bug\nIt crashes when the user taps submit"
        let name = await ChatViewModel.generateChatName(from: prompt)
        #expect(name.isEmpty == false)
        #expect(name.count <= 80)
    }

    // MARK: - sendMessage auto-naming behaviour

    @Test("First message auto-names the chat")
    func sendMessage_firstMessage_autoNamesChat() async throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        vm.inputText = "Help me debug this crash"
        vm.sendMessage(apiClient: SpritesAPIClient(), modelContext: ctx)
        await vm.namingTask?.value

        #expect(chat.customName != nil)
        #expect(chat.customName?.isEmpty == false)
    }

    @Test("Second message does not overwrite auto-generated name")
    func sendMessage_secondMessage_doesNotRename() async throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        vm.inputText = "First message"
        vm.sendMessage(apiClient: SpritesAPIClient(), modelContext: ctx)
        await vm.namingTask?.value
        let autoName = chat.customName
        #expect(autoName != nil)

        vm.inputText = "Second message"
        vm.sendMessage(apiClient: SpritesAPIClient(), modelContext: ctx)
        await vm.namingTask?.value

        #expect(chat.customName == autoName)
    }

    @Test("Existing customName is not overwritten by sendMessage")
    func sendMessage_existingCustomName_notOverwritten() async throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)
        chat.customName = "My Custom Name"
        try ctx.save()

        vm.inputText = "Some first message"
        vm.sendMessage(apiClient: SpritesAPIClient(), modelContext: ctx)
        await vm.namingTask?.value

        #expect(chat.customName == "My Custom Name")
    }
}
