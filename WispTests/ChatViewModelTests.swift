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
            workingDirectory: chat.workingDirectory
        )
        return (vm, chat)
    }

    private func makeExecStream(_ events: [ExecEvent]) -> AsyncThrowingStream<ExecEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
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

    @Test func activeToolLabel_relativisesCwd() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let msg = ChatMessage(role: .assistant)
        vm.messages.append(msg)
        vm.setCurrentAssistantMessage(msg)

        let event = ClaudeStreamEvent.assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [
                .toolUse(ClaudeToolUse(id: "tu-cwd", name: "Bash", input: .object(["command": .string("find /home/sprite/project/src -name '*.swift'")])))
            ])
        ))
        vm.handleEvent(event, modelContext: ctx)

        #expect(vm.activeToolLabel?.contains("/home/sprite/project") == false)
        #expect(vm.activeToolLabel?.contains("./src") == true)
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

    @Test func parseSessionJSONL_skillInjectionSuppressed() {
        // isMeta:true text-block user messages are skill injections — should not appear as user bubbles
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"Hello"},"isMeta":false}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":"Bash","input":{"command":"ls"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu-1","content":"files"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /home/sprite/.claude/skills/sprite\\n\\nYou are the Sprite agent..."}]},"isMeta":true}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done."}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        // Should have user + assistant only; skill injection is suppressed
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].textContent == "Hello")
        #expect(messages[1].role == .assistant)
        // Skill content must not appear anywhere
        let allText = messages.flatMap { $0.content }.compactMap {
            if case .text(let t) = $0 { t } else { nil }
        }.joined()
        #expect(!allText.contains("Base directory for this skill"))
    }

    @Test func parseSessionJSONL_textBlockUserMessageShown() {
        // Non-meta text-block user messages should be shown as user bubbles
        let jsonl = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello from blocks"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi there"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].textContent == "Hello from blocks")
    }

    // MARK: - claudeProjectPathEncoding

    @Test func claudeProjectPathEncoding_simpleProject() {
        #expect(ChatViewModel.claudeProjectPathEncoding("/home/sprite/project") == "-home-sprite-project")
    }

    @Test func claudeProjectPathEncoding_dotInPath() {
        // The `.wisp` directory: Claude Code replaces `.` too, Wisp must match
        #expect(ChatViewModel.claudeProjectPathEncoding("/home/sprite/.wisp/worktrees/wisp/my-branch")
            == "-home-sprite--wisp-worktrees-wisp-my-branch")
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

    // MARK: - processExecStream

    @Test func processExecStream_cleanCloseWithResultEvent_returnsCompleted() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        let systemLine = #"{"type":"system","session_id":"s1","model":"claude-sonnet-4-20250514"}"# + "\n"
        let resultLine = #"{"type":"result","session_id":"s1","subtype":"success"}"# + "\n"

        let stream = makeExecStream([
            .stdout(Data((systemLine + resultLine).utf8))
        ])

        let result = await vm.processExecStream(events: stream, modelContext: ctx)

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
    }

    @Test func processExecStream_cleanCloseWithDataButNoResultEvent_returnsDisconnected() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        let systemLine = #"{"type":"system","session_id":"s1","model":"claude-sonnet-4-20250514"}"# + "\n"

        let stream = makeExecStream([.stdout(Data(systemLine.utf8))])
        let result = await vm.processExecStream(events: stream, modelContext: ctx)

        guard case .disconnected = result else {
            Issue.record("Expected .disconnected, got \(result)")
            return
        }
    }

    @Test func processExecStream_noDataReceived_returnsTimedOut() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let stream = makeExecStream([])
        let result = await vm.processExecStream(events: stream, modelContext: ctx)

        guard case .timedOut = result else {
            Issue.record("Expected .timedOut, got \(result)")
            return
        }
    }

    @Test func processExecStream_stderrCountsAsActivity_doesNotTimeout() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        // stderr (heartbeat) should count as receivedData so we get .completed not .timedOut
        let resultLine = #"{"type":"result","session_id":"s1","subtype":"success"}"# + "\n"
        let stream = makeExecStream([
            .stderr(Data(".".utf8)),
            .stdout(Data(resultLine.utf8))
        ])
        let result = await vm.processExecStream(events: stream, modelContext: ctx)

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
    }

    @Test func processExecStream_setsExecSessionIdFromSessionInfo() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        let resultLine = #"{"type":"result","session_id":"s1","subtype":"success"}"# + "\n"
        let stream = makeExecStream([
            .sessionInfo(id: "exec-abc-123"),
            .stdout(Data(resultLine.utf8))
        ])

        _ = await vm.processExecStream(events: stream, modelContext: ctx)

        #expect(vm.execSessionId == "exec-abc-123")
    }

    // MARK: - reattachToExec

    @Test func reattachToExec_setsLastSessionCompleteWhenResultReceived() async throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let assistantMsg = ChatMessage(role: .assistant)
        vm.messages.append(assistantMsg)
        vm.setCurrentAssistantMessage(assistantMsg)

        let systemLine = #"{"type":"system","session_id":"s1","model":"claude-sonnet-4-20250514"}"# + "\n"
        let textLine = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done"}]}}"# + "\n"
        let resultLine = #"{"type":"result","session_id":"s1","subtype":"success"}"# + "\n"

        let stream = makeExecStream([
            .stdout(Data((systemLine + textLine + resultLine).utf8))
        ])
        let result = await vm.processExecStream(events: stream, modelContext: ctx)

        #expect(result == .completed)
        #expect(vm.sessionId == "s1")
    }

    // MARK: - reconnectIfNeeded with execSessionId

    @Test func reconnectIfNeeded_nilExecSessionId_restoresDraftSynchronously() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.messages = [
            ChatMessage(role: .user, content: [.text("earlier message")]),
            ChatMessage(role: .user, content: [.text("draft message")]),
        ]

        vm.reconnectIfNeeded(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.messages.count == 1)
        #expect(vm.inputText == "draft message")
    }

    @Test func reconnectIfNeeded_withExecSessionId_startsReattachTask() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.messages = [ChatMessage(role: .user, content: [.text("hello")])]
        vm.setExecSessionId("exec-abc")

        vm.reconnectIfNeeded(apiClient: SpritesAPIClient(), modelContext: ctx)

        // A stream task should have been created for reattach
        #expect(vm.streamTask != nil)
    }

    // MARK: - UUID persistence

    @Test func persistMessages_savesUUIDsToChat() throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        vm.processedEventUUIDs = ["uuid-a", "uuid-b"]
        vm.persistMessages(modelContext: ctx)

        #expect(chat.loadStreamEventUUIDs() == ["uuid-a", "uuid-b"])
    }

    @Test func persistMessages_doesNotOverwriteWithEmptySet() throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        // Save a valid UUID set
        chat.saveStreamEventUUIDs(["uuid-prior"])

        // persistMessages with empty processedEventUUIDs should not overwrite
        vm.processedEventUUIDs = []
        vm.persistMessages(modelContext: ctx)

        #expect(chat.loadStreamEventUUIDs() == ["uuid-prior"])
    }

    @Test func loadSession_restoresProcessedEventUUIDs() throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        chat.saveStreamEventUUIDs(["uuid-x", "uuid-y"])

        vm.loadSession(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.processedEventUUIDs == ["uuid-x", "uuid-y"])
    }

    @Test func loadSession_setsEmptyUUIDsWhenNoneStored() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.loadSession(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.processedEventUUIDs.isEmpty)
    }

    // MARK: - fetchRemoteSessions

    @Test func fetchRemoteSessions_isNoOpWhenWorktreePathIsSet() throws {
        // Established worktrees (worktreePath already set) are always fresh — no sessions to resume.
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        chat.worktreePath = "/tmp/worktrees/my-branch"
        vm.loadSession(apiClient: SpritesAPIClient(), modelContext: ctx)

        vm.fetchRemoteSessions(apiClient: SpritesAPIClient(), existingSessionIds: [])

        #expect(vm.remoteSessions.isEmpty)
        #expect(vm.isLoadingRemoteSessions == false)
    }

    @Test func fetchRemoteSessions_isNoOpWhenSiblingChatHasWorktree() throws {
        // A fresh chat on a sprite that has previously created worktrees should also
        // suppress remote session fetching — the sprite has git, so resumes are irrelevant.
        let ctx = try makeModelContext()

        // Create an older chat for the same sprite with an established worktree
        let olderChat = SpriteChat(spriteName: "test", chatNumber: 1)
        olderChat.worktreePath = "/tmp/worktrees/main"
        ctx.insert(olderChat)
        try ctx.save()

        // New chat for the same sprite — worktreePath is nil (not yet created)
        let newChat = SpriteChat(spriteName: "test", chatNumber: 2)
        ctx.insert(newChat)
        try ctx.save()

        let vm = ChatViewModel(spriteName: "test", chatId: newChat.id, workingDirectory: newChat.workingDirectory)
        vm.loadSession(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.worktreePath == nil)
        #expect(vm.spriteUsesWorktrees == true)

        vm.fetchRemoteSessions(apiClient: SpritesAPIClient(), existingSessionIds: [])

        #expect(vm.remoteSessions.isEmpty)
        #expect(vm.isLoadingRemoteSessions == false)
    }

    // MARK: - ChatStatus computed properties

    @Test func chatStatus_isConnecting_onlyForConnecting() {
        #expect(ChatStatus.connecting.isConnecting == true)
        #expect(ChatStatus.streaming.isConnecting == false)
        #expect(ChatStatus.reconnecting.isConnecting == false)
        #expect(ChatStatus.idle.isConnecting == false)
        #expect(ChatStatus.error("x").isConnecting == false)
    }

    @Test func chatStatus_isReconnecting_onlyForReconnecting() {
        #expect(ChatStatus.reconnecting.isReconnecting == true)
        #expect(ChatStatus.connecting.isReconnecting == false)
        #expect(ChatStatus.streaming.isReconnecting == false)
        #expect(ChatStatus.idle.isReconnecting == false)
        #expect(ChatStatus.error("x").isReconnecting == false)
    }

    @Test func chatStatus_isStreaming_trueForActiveStates() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.status = .connecting
        #expect(vm.isStreaming == true)

        vm.status = .streaming
        #expect(vm.isStreaming == true)

        vm.status = .reconnecting
        #expect(vm.isStreaming == true)

        vm.status = .idle
        #expect(vm.isStreaming == false)

        vm.status = .error("oops")
        #expect(vm.isStreaming == false)
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

    // MARK: - addAttachedFile

    @Test func addAttachedFile_appendsWithLastPathComponent() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.addAttachedFile(remotePath: "/home/sprite/project/photo_20260312_120000.png")

        #expect(vm.attachedFiles.count == 1)
        #expect(vm.attachedFiles[0].name == "photo_20260312_120000.png")
        #expect(vm.attachedFiles[0].path == "/home/sprite/project/photo_20260312_120000.png")
    }

    @Test func addAttachedFile_appendsMultiple() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.addAttachedFile(remotePath: "/home/sprite/project/file1.txt")
        vm.addAttachedFile(remotePath: "/home/sprite/project/file2.py")

        #expect(vm.attachedFiles.count == 2)
        #expect(vm.attachedFiles[0].name == "file1.txt")
        #expect(vm.attachedFiles[1].name == "file2.py")
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

    // MARK: - Draft attachment persistence

    @Test func saveDraft_persistsAttachmentPaths() throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        vm.attachedFiles = [
            AttachedFile(name: "main.py", path: "/home/sprite/project/main.py"),
            AttachedFile(name: "README.md", path: "/home/sprite/project/README.md"),
        ]
        vm.saveDraft(modelContext: ctx)

        #expect(chat.draftAttachmentPaths == [
            "/home/sprite/project/main.py",
            "/home/sprite/project/README.md",
        ])
    }

    @Test func saveDraft_clearsAttachmentPathsWhenEmpty() throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        chat.draftAttachmentPaths = ["/home/sprite/project/old.py"]
        vm.attachedFiles = []
        vm.saveDraft(modelContext: ctx)

        #expect(chat.draftAttachmentPaths == nil)
    }

    @Test func loadSession_restoresDraftAttachments() throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        chat.draftAttachmentPaths = [
            "/home/sprite/project/main.py",
            "/home/sprite/project/photo.png",
        ]

        vm.loadSession(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.attachedFiles.count == 2)
        #expect(vm.attachedFiles[0].name == "main.py")
        #expect(vm.attachedFiles[0].path == "/home/sprite/project/main.py")
        #expect(vm.attachedFiles[1].name == "photo.png")
        #expect(vm.attachedFiles[1].path == "/home/sprite/project/photo.png")
    }

    @Test func loadSession_doesNotOverwriteExistingAttachments() throws {
        let ctx = try makeModelContext()
        let (vm, chat) = makeChatViewModel(modelContext: ctx)

        chat.draftAttachmentPaths = ["/home/sprite/project/persisted.py"]
        vm.attachedFiles = [AttachedFile(name: "live.py", path: "/home/sprite/project/live.py")]

        vm.loadSession(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.attachedFiles.count == 1)
        #expect(vm.attachedFiles[0].name == "live.py")
    }

    // MARK: - restoreUndeliveredDraft

    @Test func restoreUndeliveredDraft_removesTrailingUserMessageAndRestoresInputText() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.messages = [
            ChatMessage(role: .user, content: [.text("first message")]),
            ChatMessage(role: .assistant, content: [.text("response")]),
            ChatMessage(role: .user, content: [.text("unsent message")]),
        ]

        vm.restoreUndeliveredDraft(modelContext: ctx)

        #expect(vm.messages.count == 2)
        #expect(vm.inputText == "unsent message")
    }

    @Test func restoreUndeliveredDraft_isNoopWhenLastMessageIsAssistant() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.messages = [
            ChatMessage(role: .user, content: [.text("hello")]),
            ChatMessage(role: .assistant, content: [.text("hi there")]),
        ]

        vm.restoreUndeliveredDraft(modelContext: ctx)

        #expect(vm.messages.count == 2)
        #expect(vm.inputText == "")
    }

    @Test func restoreUndeliveredDraft_doesNotOverwriteExistingInputText() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.messages = [
            ChatMessage(role: .user, content: [.text("unsent message")]),
        ]
        vm.inputText = "already typing something"

        vm.restoreUndeliveredDraft(modelContext: ctx)

        // Message removed but inputText NOT overwritten
        #expect(vm.messages.count == 0)
        #expect(vm.inputText == "already typing something")
    }

    // MARK: - resumeAfterBackground / reconnectIfNeeded guards

    /// resumeAfterBackground must not interrupt a VM that is already reconnecting via
    /// GET logs — it should only cancel genuine PUT streams (.streaming / .connecting).
    @Test func resumeAfterBackground_doesNotInterruptReconnecting() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.status = .reconnecting
        vm.resumeAfterBackground(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.status == .reconnecting)
    }

    @Test func resumeAfterBackground_doesNotInterruptIdle() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.status = .idle
        vm.resumeAfterBackground(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.status == .idle)
        #expect(vm.streamTask == nil)
    }

    /// reconnectIfNeeded must be a no-op when the VM is already in a streaming/
    /// connecting/reconnecting state — prevents creating a second concurrent task.
    @Test func reconnectIfNeeded_isNoopWhenAlreadyStreaming() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.messages = [ChatMessage(role: .user, content: [.text("hello")])]
        vm.status = .reconnecting
        vm.reconnectIfNeeded(apiClient: SpritesAPIClient(), modelContext: ctx)

        #expect(vm.status == .reconnecting)
    }

    /// When reconnectIfNeeded is called with execSessionId set twice synchronously,
    /// the second call pre-cancels the first task and replaces streamTask.
    @Test func reconnectIfNeeded_concurrentCallPrecancelsFirst() throws {
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        vm.messages = [ChatMessage(role: .user, content: [.text("hello")])]
        vm.setExecSessionId("exec-abc")

        // First call creates a stream task
        vm.reconnectIfNeeded(apiClient: SpritesAPIClient(), modelContext: ctx)
        #expect(vm.streamTask != nil)

        // Second call should cancel the first task and create a new one
        vm.reconnectIfNeeded(apiClient: SpritesAPIClient(), modelContext: ctx)

        // A stream task should still be present (reattach attempt ongoing)
        #expect(vm.streamTask != nil)
        // Status should not be idle yet (task was created)
        #expect(vm.status != .idle || vm.streamTask != nil)
    }

    // MARK: - parseSessionJSONL: block-format user messages

    @Test func parseSessionJSONL_userMessageAsTextBlockArray() {
        // Some Claude Code versions write the user turn as an array of text blocks
        // instead of a plain string. Verify these are treated as user messages.
        let jsonl = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello from blocks"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi back"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].textContent == "Hello from blocks")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].textContent == "Hi back")
    }

    @Test func parseSessionJSONL_multiTurnWithBlockFormatUserMessages() {
        // Multi-turn conversation where both turns store the user prompt as block arrays.
        let jsonl = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"first prompt"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"first answer"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"second prompt"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"second answer"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 4)
        #expect(messages[0].role == .user)
        #expect(messages[0].textContent == "first prompt")
        #expect(messages[1].role == .assistant)
        #expect(messages[2].role == .user)
        #expect(messages[2].textContent == "second prompt")
        #expect(messages[3].role == .assistant)
    }

    @Test func parseSessionJSONL_blockFormatUserDoesNotConflictWithToolResults() {
        // A user event with only tool_result blocks (not text blocks) must still be
        // treated as tool results, not as a user message.
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":"Bash","input":{"command":"ls"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu-1","content":"file.txt"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        // Should be one assistant message with tool_use, tool_result, and text
        #expect(messages.count == 1)
        #expect(messages[0].role == .assistant)
        #expect(messages[0].content.count == 3)
    }

    // MARK: - loadSession: SwiftData round-trip preserves tool result linkage

    @Test func loadSession_linksToolResultsAfterSwiftDataRoundTrip() throws {
        // Regression: PersistedChatMessage stores toolUse and toolResult as flat separate
        // items and does not persist ToolUseCard.result. After loading from SwiftData,
        // all ToolUseCard.result were nil, causing tool calls to render as strikethrough.
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        // Simulate a completed session stored in SwiftData: assistant message with a
        // tool use and its result already linked (as they would be after live streaming).
        let toolCard = ToolUseCard(toolUseId: "tu-1", toolName: "Bash", input: .object(["command": .string("ls")]))
        let resultCard = ToolResultCard(toolUseId: "tu-1", toolName: "Bash", content: .string("file.txt"))
        toolCard.result = resultCard

        let assistantMsg = ChatMessage(role: .assistant, content: [
            .toolUse(toolCard),
            .toolResult(resultCard),
            .text("Done"),
        ])
        vm.messages = [assistantMsg]

        // Persist and reload
        vm.persistMessages(modelContext: ctx)

        // Create a second VM for the same chat to simulate a fresh load
        let vm2 = ChatViewModel(spriteName: "test", chatId: vm.chatId, workingDirectory: "")
        vm2.loadSession(apiClient: SpritesAPIClient(), modelContext: ctx)

        guard case .toolUse(let loadedCard) = vm2.messages.first?.content.first else {
            Issue.record("Expected toolUse as first content item")
            return
        }
        #expect(loadedCard.result != nil, "ToolUseCard.result must be re-linked after SwiftData round-trip")
        #expect(loadedCard.result?.toolUseId == "tu-1")
    }

    @Test func parseSessionJSONL_linksToolResultToToolUseCard() {
        // Regression: reloaded chats were not showing tool calls because parseSessionJSONL
        // never set ToolUseCard.result. The view only renders a ToolStepRow when result != nil.
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"do something"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":"Bash","input":{"command":"ls"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu-1","content":"file.txt"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done"}]}}
        """
        let messages = ChatViewModel.parseSessionJSONL(jsonl)
        #expect(messages.count == 2)
        let assistant = messages[1]
        guard case .toolUse(let card) = assistant.content.first(where: { if case .toolUse = $0 { true } else { false } }) else {
            Issue.record("Expected toolUse content item")
            return
        }
        #expect(card.result != nil, "ToolUseCard.result must be linked for the completed tool to render")
        #expect(card.result?.toolUseId == "tu-1")
    }

    // MARK: - mergedWithLocalMessages

    @Test func mergedWithLocalMessages_preservesSubAgentToolCalls() throws {
        // Local messages have sub-agent tool calls (streamed live); JSONL only has main-agent turns.
        // The merge should keep local tool cards and use JSONL text if it's more complete.
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        // Simulate locally-persisted assistant message with a sub-agent Bash call
        let userMsg = ChatMessage(role: .user, content: [.text("do the thing")])
        let subAgentCard = ToolUseCard(toolUseId: "tu-bash", toolName: "Bash", input: .object(["command": .string("ls")]))
        let assistantMsg = ChatMessage(role: .assistant, content: [
            .toolUse(subAgentCard),
            .text("Partial text..."),   // truncated — app disconnected before full response
        ])
        vm.messages = [userMsg, assistantMsg]

        // JSONL version: no Bash card, but complete final text
        let jsonlUser = ChatMessage(role: .user, content: [.text("do the thing")])
        let jsonlAssistant = ChatMessage(role: .assistant, content: [
            .text("Complete response from Claude with all details."),
        ])
        let jsonlMessages = [jsonlUser, jsonlAssistant]

        let result = vm.mergedWithLocalMessages(jsonlMessages)

        #expect(result.count == 2)
        let merged = result[1]
        #expect(merged.role == .assistant)
        // Sub-agent Bash tool call preserved
        let hasToolUse = merged.content.contains { if case .toolUse = $0 { true } else { false } }
        #expect(hasToolUse, "Sub-agent tool call should be preserved from local messages")
        // Text updated to the longer JSONL version
        #expect(merged.textContent == "Complete response from Claude with all details.")
    }

    @Test func mergedWithLocalMessages_fallsBackToJSONLWhenStructureDiffers() throws {
        // If the conversation structures differ (different user message counts), fall back
        // to the JSONL messages as-is. In practice this shouldn't happen — Claude can't
        // create new user turns on its own — but it's a safety net for unexpected states.
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let userMsg = ChatMessage(role: .user, content: [.text("first message")])
        vm.messages = [userMsg]

        // JSONL has an extra exchange
        let jsonlMessages = [
            ChatMessage(role: .user, content: [.text("first message")]),
            ChatMessage(role: .assistant, content: [.text("reply")]),
            ChatMessage(role: .user, content: [.text("follow-up")]),
            ChatMessage(role: .assistant, content: [.text("final reply")]),
        ]

        let result = vm.mergedWithLocalMessages(jsonlMessages)

        #expect(result.count == 4, "Should fall back to JSONL when structures differ")
    }

    @Test func mergedWithLocalMessages_preservesIntroTextBeforeToolCalls() throws {
        // "Let me check…" → tool call → "Final response" — intro text must stay in
        // position; only the last text block (which may be truncated) should be updated.
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let taskCard = ToolUseCard(toolUseId: "tu-task", toolName: "Task", input: .null)
        let userMsg = ChatMessage(role: .user, content: [.text("do the thing")])
        let assistantMsg = ChatMessage(role: .assistant, content: [
            .text("Let me check on that..."),
            .toolUse(taskCard),
            .text("Partial fi"),  // truncated
        ])
        vm.messages = [userMsg, assistantMsg]

        let jsonlMessages = [
            ChatMessage(role: .user, content: [.text("do the thing")]),
            ChatMessage(role: .assistant, content: [
                .text("Let me check on that..."),
                .toolUse(taskCard),
                .text("Final response complete."),
            ]),
        ]

        let result = vm.mergedWithLocalMessages(jsonlMessages)
        let merged = result[1]

        // Intro text stays first
        guard case .text(let intro) = merged.content.first else {
            Issue.record("Expected intro text as first content item"); return
        }
        #expect(intro == "Let me check on that...")
        // Tool call stays second
        guard case .toolUse = merged.content[1] else {
            Issue.record("Expected toolUse as second content item"); return
        }
        // Final text updated from JSONL
        guard case .text(let final) = merged.content[2] else {
            Issue.record("Expected text as third content item"); return
        }
        #expect(final == "Final response complete.")
    }

    @Test func mergedWithLocalMessages_keepsLocalTextIfAlreadyComplete() throws {
        // If local text is already as long as the JSONL text, keep the local version unchanged.
        let ctx = try makeModelContext()
        let (vm, _) = makeChatViewModel(modelContext: ctx)

        let subAgentCard = ToolUseCard(toolUseId: "tu-read", toolName: "Read", input: .object(["file_path": .string("/foo.txt")]))
        let userMsg = ChatMessage(role: .user, content: [.text("read a file")])
        let assistantMsg = ChatMessage(role: .assistant, content: [
            .toolUse(subAgentCard),
            .text("Here is the content of the file."),
        ])
        vm.messages = [userMsg, assistantMsg]

        let jsonlMessages = [
            ChatMessage(role: .user, content: [.text("read a file")]),
            ChatMessage(role: .assistant, content: [.text("Here is the content.")]),  // shorter
        ]

        let result = vm.mergedWithLocalMessages(jsonlMessages)

        #expect(result[1].textContent == "Here is the content of the file.", "Local text should be kept when it's already complete")
        let hasToolUse = result[1].content.contains { if case .toolUse = $0 { true } else { false } }
        #expect(hasToolUse)
    }
}
