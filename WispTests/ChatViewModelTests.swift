import Testing
import Foundation
import SwiftData
@testable import Wisp

@MainActor
@Suite("ChatViewModel")
struct ChatViewModelTests {

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

    // MARK: - handleEvent: system

    @Test func handleEvent_systemSetsModelName() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant, isStreaming: true)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        let event = ClaudeStreamEvent.system(ClaudeSystemEvent(
            type: "system", sessionId: "sess-1", model: "claude-sonnet-4-20250514", tools: nil, cwd: nil
        ))
        vm.handleEvent(event, modelContext: ctx)

        #expect(vm.modelName == "claude-sonnet-4-20250514")
    }

    // MARK: - handleEvent: assistant text

    @Test func handleEvent_assistantTextAppended() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant, isStreaming: true)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        let event = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [.text("Hello")])
        ))
        vm.handleEvent(event, modelContext: ctx)

        #expect(msg.content.count == 1)
        if case .text(let text) = msg.content.first {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func handleEvent_consecutiveTextMerged() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant, isStreaming: true)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        let event1 = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [.text("Hello ")])
        ))
        let event2 = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [.text("world")])
        ))
        vm.handleEvent(event1, modelContext: ctx)
        vm.handleEvent(event2, modelContext: ctx)

        #expect(msg.content.count == 1)
        if case .text(let text) = msg.content.first {
            #expect(text == "Hello world")
        } else {
            Issue.record("Expected merged text")
        }
    }

    // MARK: - handleEvent: tool use

    @Test func handleEvent_toolUseAppended() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant, isStreaming: true)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        let event = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [
                .toolUse(ClaudeToolUse(id: "tu-1", name: "Bash", input: .object(["command": .string("ls")])))
            ])
        ))
        vm.handleEvent(event, modelContext: ctx)

        #expect(msg.content.count == 1)
        if case .toolUse(let card) = msg.content.first {
            #expect(card.toolName == "Bash")
            #expect(card.toolUseId == "tu-1")
        } else {
            Issue.record("Expected tool use content")
        }
    }

    // MARK: - handleEvent: tool result

    @Test func handleEvent_toolResultMatchedById() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant, isStreaming: true)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        // First send tool use
        let toolUseEvent = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [
                .toolUse(ClaudeToolUse(id: "tu-2", name: "Read", input: .object(["file_path": .string("/tmp/f")])))
            ])
        ))
        vm.handleEvent(toolUseEvent, modelContext: ctx)

        // Then send tool result
        let resultEvent = ClaudeStreamEvent.user(ClaudeToolResultEvent(
            type: "user",
            message: ClaudeToolResultMessage(role: "user", content: [
                ClaudeToolResult(type: "tool_result", toolUseId: "tu-2", content: .string("file contents"))
            ])
        ))
        vm.handleEvent(resultEvent, modelContext: ctx)

        #expect(msg.content.count == 2)
        if case .toolResult(let card) = msg.content.last {
            #expect(card.toolUseId == "tu-2")
            #expect(card.toolName == "Read")
        } else {
            Issue.record("Expected tool result content")
        }
    }

    // MARK: - handleEvent: result

    @Test func handleEvent_resultClearsStreaming() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant, isStreaming: true)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        let event = ClaudeStreamEvent.result(ClaudeResultEvent(
            type: "result", subtype: "success", sessionId: "sess-1",
            isError: nil, durationMs: 1000, numTurns: 1, result: nil
        ))
        vm.handleEvent(event, modelContext: ctx)

        #expect(msg.isStreaming == false)
    }
}
