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

    // MARK: - parseSessionJSONL

    @Test func parseSessionJSONL_userTextMessage() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"Hello world"}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 1)
        #expect(messages[0].role == .user)
        #expect(messages[0].textContent == "Hello world")
    }

    @Test func parseSessionJSONL_assistantTextMessage() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi there"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 1)
        #expect(messages[0].role == .assistant)
        #expect(messages[0].textContent == "Hi there")
    }

    @Test func parseSessionJSONL_toolUseAndResult() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"List files"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":"Bash","input":{"command":"ls"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu-1","content":"file1.txt"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Found 2 files."}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        // user, assistant (with tool_use + tool_result + text)
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[1].role == .assistant)
        // Assistant should have tool_use, tool_result, and text
        #expect(messages[1].content.count == 3)
        if case .toolUse(let card) = messages[1].content[0] {
            #expect(card.toolName == "Bash")
        } else {
            Issue.record("Expected tool use")
        }
        if case .toolResult(let card) = messages[1].content[1] {
            #expect(card.toolName == "Bash")
        } else {
            Issue.record("Expected tool result")
        }
        if case .text(let text) = messages[1].content[2] {
            #expect(text == "Found 2 files.")
        } else {
            Issue.record("Expected text")
        }
    }

    @Test func parseSessionJSONL_skipsUnknownTypes() {
        let jsonl = """
        {"type":"system","session_id":"s-1","model":"claude-sonnet-4-20250514"}
        {"type":"user","message":{"role":"user","content":"Hello"}}
        {"type":"progress","data":{}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}
        {"type":"result","session_id":"s-1","is_error":false}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 2)
    }

    @Test func parseSessionJSONL_skipsThinkingBlocks() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"let me think..."},{"type":"text","text":"Answer"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 1)
        #expect(messages[0].content.count == 1)
        #expect(messages[0].textContent == "Answer")
    }

    @Test func parseSessionJSONL_emptyInput() {
        let messages = ChatViewModel.parseSessionJSONL("")
        #expect(messages.isEmpty)
    }

    @Test func parseSessionJSONL_corruptLinesSkipped() {
        let jsonl = """
        not json at all
        {"type":"user","message":{"role":"user","content":"Hello"}}
        {invalid json}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 2)
    }

    @Test func parseSessionJSONL_toolResultArrayContent() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":"Read","input":{"file_path":"/tmp/f"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu-1","content":[{"type":"text","text":"line1"},{"type":"text","text":"line2"}]}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 1)
        if case .toolResult(let card) = messages[0].content[1] {
            #expect(card.displayContent.contains("line1"))
            #expect(card.displayContent.contains("line2"))
        } else {
            Issue.record("Expected tool result")
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
