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

        let msg = ChatMessage(role: .assistant)
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

        let msg = ChatMessage(role: .assistant)
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

        let msg = ChatMessage(role: .assistant)
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

        let msg = ChatMessage(role: .assistant)
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

        let msg = ChatMessage(role: .assistant)
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

    // MARK: - handleEvent: tool result linking

    @Test func handleEvent_toolResultLinkedToToolUse() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        // Send tool use
        let toolUseEvent = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [
                .toolUse(ClaudeToolUse(id: "tu-link", name: "Bash", input: .object(["command": .string("echo hi")])))
            ])
        ))
        vm.handleEvent(toolUseEvent, modelContext: ctx)

        // Verify tool use has no result yet
        if case .toolUse(let card) = msg.content[0] {
            #expect(card.result == nil)
        }

        // Send tool result
        let resultEvent = ClaudeStreamEvent.user(ClaudeToolResultEvent(
            type: "user",
            message: ClaudeToolResultMessage(role: "user", content: [
                ClaudeToolResult(type: "tool_result", toolUseId: "tu-link", content: .string("hi"))
            ])
        ))
        vm.handleEvent(resultEvent, modelContext: ctx)

        // Verify result is linked
        if case .toolUse(let card) = msg.content[0] {
            #expect(card.result != nil)
            #expect(card.result?.toolUseId == "tu-link")
        } else {
            Issue.record("Expected tool use content")
        }
    }

    // MARK: - activeToolLabel

    @Test func activeToolLabel_returnsLabelForPendingTool() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        let event = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [
                .toolUse(ClaudeToolUse(id: "tu-active", name: "Bash", input: .object(["command": .string("npm test")])))
            ])
        ))
        vm.handleEvent(event, modelContext: ctx)

        #expect(vm.activeToolLabel != nil)
        #expect(vm.activeToolLabel?.contains("npm test") == true)
    }

    @Test func activeToolLabel_returnsNilWhenAllToolsComplete() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        // Send tool use then result
        let toolEvent = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [
                .toolUse(ClaudeToolUse(id: "tu-done", name: "Bash", input: .object(["command": .string("ls")])))
            ])
        ))
        vm.handleEvent(toolEvent, modelContext: ctx)

        let resultEvent = ClaudeStreamEvent.user(ClaudeToolResultEvent(
            type: "user",
            message: ClaudeToolResultMessage(role: "user", content: [
                ClaudeToolResult(type: "tool_result", toolUseId: "tu-done", content: .string("output"))
            ])
        ))
        vm.handleEvent(resultEvent, modelContext: ctx)

        #expect(vm.activeToolLabel == nil)
    }

    // MARK: - ToolUseCard computed properties

    @Test func toolUseCard_activityLabel_bash() {
        let card = ToolUseCard(
            toolUseId: "t1", toolName: "Bash",
            input: .object(["command": .string("npm test")])
        )
        #expect(card.activityLabel == "Running npm test...")
    }

    @Test func toolUseCard_activityLabel_read() {
        let card = ToolUseCard(
            toolUseId: "t2", toolName: "Read",
            input: .object(["file_path": .string("/Users/me/project/config.ts")])
        )
        #expect(card.activityLabel == "Reading config.ts...")
    }

    @Test func toolUseCard_activityLabel_grep() {
        let card = ToolUseCard(
            toolUseId: "t3", toolName: "Grep",
            input: .object(["pattern": .string("TODO")])
        )
        #expect(card.activityLabel == "Searching TODO...")
    }

    @Test func toolUseCard_elapsedString_subSecond() {
        let start = Date()
        let card = ToolUseCard(toolUseId: "t4", toolName: "Bash", input: .null, startedAt: start)
        let result = ToolResultCard(toolUseId: "t4", toolName: "Bash", content: .null, completedAt: start.addingTimeInterval(0.5))
        card.result = result
        #expect(card.elapsedString == "<1s")
    }

    @Test func toolUseCard_elapsedString_seconds() {
        let start = Date()
        let card = ToolUseCard(toolUseId: "t5", toolName: "Bash", input: .null, startedAt: start)
        let result = ToolResultCard(toolUseId: "t5", toolName: "Bash", content: .null, completedAt: start.addingTimeInterval(3))
        card.result = result
        #expect(card.elapsedString == "3s")
    }

    @Test func toolUseCard_elapsedString_minutes() {
        let start = Date()
        let card = ToolUseCard(toolUseId: "t6", toolName: "Bash", input: .null, startedAt: start)
        let result = ToolResultCard(toolUseId: "t6", toolName: "Bash", content: .null, completedAt: start.addingTimeInterval(83))
        card.result = result
        #expect(card.elapsedString == "1m 23s")
    }

    @Test func toolUseCard_elapsedString_nilWithoutResult() {
        let card = ToolUseCard(toolUseId: "t7", toolName: "Bash", input: .null)
        #expect(card.elapsedString == nil)
    }

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

    // MARK: - Queued prompt

    @Test func sendMessage_whileStreaming_queuesPrompt() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)
        vm.status = .streaming

        vm.inputText = "make the tests pass"
        vm.sendMessage(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.queuedPrompt == "make the tests pass")
        #expect(vm.inputText == "")
    }

    @Test func sendMessage_whileStreaming_replacesExistingQueuedPrompt() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)
        vm.status = .streaming
        vm.queuedPrompt = "old message"

        vm.inputText = "new message"
        vm.sendMessage(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.queuedPrompt == "new message")
    }

    @Test func cancelQueuedPrompt_clearsQueuedPrompt() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)
        vm.queuedPrompt = "some queued message"

        vm.cancelQueuedPrompt()

        #expect(vm.queuedPrompt == nil)
    }

    @Test func detach_clearsQueuedPrompt() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)
        vm.status = .streaming
        vm.queuedPrompt = "queued while streaming"

        vm.detach(modelContext: ctx)

        #expect(vm.queuedPrompt == nil)
        guard case .idle = vm.status else {
            Issue.record("Expected idle status after detach"); return
        }
    }

    // MARK: - processServiceStream return value

    /// Builds a stream that yields a single stdout ServiceLogEvent then finishes cleanly.
    private func stdoutStream(_ text: String) -> AsyncThrowingStream<ServiceLogEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ServiceLogEvent(type: .stdout, data: text, exitCode: nil, timestamp: nil, logFiles: nil))
            continuation.finish()
        }
    }

    @Test func processServiceStream_cleanCloseWithDataButNoResultEvent_returnsDisconnected() async throws {
        // Core bug fix: a stream that closes cleanly after delivering data but without
        // a Claude `result` event should return .disconnected (triggering reconnect),
        // not .completed (which would incorrectly set status to .idle).
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        let systemLine = #"{"type":"system","session_id":"s1","model":"claude-sonnet-4-20250514"}"# + "\n"
        let result = await vm.processServiceStream(stream: stdoutStream(systemLine), modelContext: ctx)

        guard case .disconnected = result else {
            Issue.record("Expected .disconnected when stream closes cleanly without result event, got \(result)")
            return
        }
    }

    @Test func processServiceStream_cleanCloseWithResultEvent_returnsCompleted() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        let stream = AsyncThrowingStream<ServiceLogEvent, Error> { continuation in
            let systemLine = #"{"type":"system","session_id":"s1","model":"claude-sonnet-4-20250514"}"# + "\n"
            let resultLine = #"{"type":"result","session_id":"s1","subtype":"success"}"# + "\n"
            continuation.yield(ServiceLogEvent(type: .stdout, data: systemLine, exitCode: nil, timestamp: nil, logFiles: nil))
            continuation.yield(ServiceLogEvent(type: .stdout, data: resultLine, exitCode: nil, timestamp: nil, logFiles: nil))
            continuation.finish()
        }

        let result = await vm.processServiceStream(stream: stream, modelContext: ctx)

        guard case .completed = result else {
            Issue.record("Expected .completed when result event received, got \(result)")
            return
        }
    }

    @Test func processServiceStream_noDataReceived_returnsTimedOut() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let stream = AsyncThrowingStream<ServiceLogEvent, Error> { continuation in
            continuation.finish()
        }

        let result = await vm.processServiceStream(stream: stream, modelContext: ctx)

        guard case .timedOut = result else {
            Issue.record("Expected .timedOut when no data received, got \(result)")
            return
        }
    }

    @Test func processServiceStream_errorAfterData_returnsDisconnected() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        let stream = AsyncThrowingStream<ServiceLogEvent, Error> { continuation in
            let systemLine = #"{"type":"system","session_id":"s1","model":"claude-sonnet-4-20250514"}"# + "\n"
            continuation.yield(ServiceLogEvent(type: .stdout, data: systemLine, exitCode: nil, timestamp: nil, logFiles: nil))
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }

        let result = await vm.processServiceStream(stream: stream, modelContext: ctx)

        guard case .disconnected = result else {
            Issue.record("Expected .disconnected when stream errors after receiving data, got \(result)")
            return
        }
    }

    // MARK: - stripLogTimestamps

    @Test func stripLogTimestamps_removesStdoutPrefix() {
        let input = #"2026-02-19T09:13:24.665Z [stdout] {"type":"system"}"#
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == #"{"type":"system"}"#)
    }

    @Test func stripLogTimestamps_removesStderrPrefix() {
        let input = "2026-02-19T09:13:24.665Z [stderr] error output"
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == "error output")
    }

    @Test func stripLogTimestamps_preservesLinesWithoutPrefix() {
        let input = #"{"type":"system"}"#
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == #"{"type":"system"}"#)
    }

    @Test func stripLogTimestamps_handlesMultipleLines() {
        let input = "2026-02-19T09:13:24.665Z [stdout] {\"type\":\"system\"}\n2026-02-19T09:13:25.000Z [stderr] error message\n{\"type\":\"plain\"}"
        let result = ChatViewModel.stripLogTimestamps(input)
        let lines = result.components(separatedBy: "\n")
        #expect(lines[0] == "{\"type\":\"system\"}")
        #expect(lines[1] == "error message")
        #expect(lines[2] == "{\"type\":\"plain\"}")
    }

    // MARK: - Streaming state (single source of truth)

    @Test func currentAssistantMessageId_tracksCurrentMessage() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        #expect(vm.currentAssistantMessageId == nil)

        let msg = ChatMessage(role: .assistant)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        #expect(vm.currentAssistantMessageId == msg.id)

        vm.setCurrentAssistantMessage(nil)

        #expect(vm.currentAssistantMessageId == nil)
    }

    // MARK: - stashDraft

    @Test func stashDraft_movesInputTextToStash() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.inputText = "my long prompt"
        vm.stashDraft()

        #expect(vm.stashedDraft == "my long prompt")
        #expect(vm.inputText == "")
    }

    @Test func stashDraft_doesNothingWhenEmpty() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.inputText = "   "
        vm.stashDraft()

        #expect(vm.stashedDraft == nil)
        #expect(vm.inputText == "   ")
    }

    @Test func stashDraft_overwritesPreviousStash() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.inputText = "first draft"
        vm.stashDraft()
        vm.inputText = "second draft"
        vm.stashDraft()

        #expect(vm.stashedDraft == "second draft")
        #expect(vm.inputText == "")
    }

    @Test func stashDraft_leavesInputReadyForNextMessage() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.inputText = "long prompt I want to come back to"
        vm.stashDraft()

        // After stashing, the field is clear and stash holds the draft
        #expect(vm.inputText == "")
        #expect(vm.stashedDraft == "long prompt I want to come back to")

        // Manually simulate the restore (as sendMessage would do)
        vm.inputText = vm.stashedDraft!
        vm.stashedDraft = nil

        #expect(vm.inputText == "long prompt I want to come back to")
        #expect(vm.stashedDraft == nil)
    }
}
