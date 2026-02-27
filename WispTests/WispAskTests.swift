import Testing
import Foundation
@testable import Wisp

@Suite("WispAsk")
struct WispAskTests {

    // MARK: - ClaudeQuestionTool paths

    @Test func mcpConfigFilePath_containsSessionId() {
        let id = "abc-123"
        #expect(ClaudeQuestionTool.mcpConfigFilePath(for: id) == "/tmp/.wisp_mcp_abc-123.json")
    }

    @Test func responseFilePath_containsSessionId() {
        let id = "abc-123"
        #expect(ClaudeQuestionTool.responseFilePath(for: id) == "/tmp/.wisp_ask_response_abc-123.json")
    }

    @Test func mcpConfigJSON_containsSessionId() {
        let id = "test-session-id"
        let json = ClaudeQuestionTool.mcpConfigJSON(for: id)
        #expect(json.contains("test-session-id"))
    }

    @Test func mcpConfigJSON_isValidJSON() throws {
        let json = ClaudeQuestionTool.mcpConfigJSON(for: "sess-1")
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(parsed["mcpServers"] as? [String: Any])
        let askUser = try #require(servers["askUser"] as? [String: Any])
        let env = try #require(askUser["env"] as? [String: Any])
        #expect(env["WISP_SESSION_ID"] as? String == "sess-1")
    }

    @Test func mcpConfigJSON_pointsToServerPy() throws {
        let json = ClaudeQuestionTool.mcpConfigJSON(for: "x")
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(parsed["mcpServers"] as? [String: Any])
        let askUser = try #require(servers["askUser"] as? [String: Any])
        let args = try #require(askUser["args"] as? [String])
        #expect(args.contains(ClaudeQuestionTool.serverPyPath))
    }

    @Test func differentSessionIds_produceDifferentPaths() {
        #expect(
            ClaudeQuestionTool.responseFilePath(for: "a") !=
            ClaudeQuestionTool.responseFilePath(for: "b")
        )
    }

    // MARK: - ToolUseCard properties for WispAsk

    @MainActor
    @Test func toolUseCard_wispAsk_iconName() {
        let card = ToolUseCard(
            toolUseId: "1",
            toolName: "mcp__askUser__WispAsk",
            input: .object(["question": .string("Test?")])
        )
        #expect(card.iconName == "questionmark.bubble")
    }

    @MainActor
    @Test func toolUseCard_wispAsk_summary_returnsQuestion() {
        let card = ToolUseCard(
            toolUseId: "1",
            toolName: "mcp__askUser__WispAsk",
            input: .object(["question": .string("What should I do?")])
        )
        #expect(card.summary == "What should I do?")
    }

    @MainActor
    @Test func toolUseCard_wispAsk_activityLabel_truncates() {
        let longQuestion = String(repeating: "a", count: 80)
        let card = ToolUseCard(
            toolUseId: "1",
            toolName: "mcp__askUser__WispAsk",
            input: .object(["question": .string(longQuestion)])
        )
        let label = card.activityLabel
        #expect(label.hasPrefix("Asking: "))
        #expect(label.hasSuffix("..."))
        // question is truncated to 60 chars + "Asking: " prefix + "..." suffix
        #expect(label.count == "Asking: ".count + 60 + "...".count)
    }

    @MainActor
    @Test func toolUseCard_wispAsk_summary_fallback() {
        let card = ToolUseCard(
            toolUseId: "1",
            toolName: "mcp__askUser__WispAsk",
            input: .object([:])
        )
        #expect(card.summary == "asking user")
    }

    // MARK: - pendingWispAskCard

    @MainActor
    @Test func pendingWispAskCard_returnsNilWhenNoMessages() {
        let vm = ChatViewModel(
            spriteName: "test",
            chatId: UUID(),
            currentServiceName: nil,
            workingDirectory: "/tmp"
        )
        #expect(vm.pendingWispAskCard == nil)
    }

    @MainActor
    @Test func pendingWispAskCard_returnsNilWhenToolHasResult() {
        let vm = ChatViewModel(
            spriteName: "test",
            chatId: UUID(),
            currentServiceName: nil,
            workingDirectory: "/tmp"
        )
        let card = ToolUseCard(
            toolUseId: "t1",
            toolName: "mcp__askUser__WispAsk",
            input: .object(["question": .string("Done?")])
        )
        card.result = ToolResultCard(toolUseId: "t1", toolName: "mcp__askUser__WispAsk", content: .string("yes"))
        let message = ChatMessage(role: .assistant, content: [.toolUse(card)])
        vm.messages = [message]
        #expect(vm.pendingWispAskCard == nil)
    }

    @MainActor
    @Test func pendingWispAskCard_returnsPendingCard() {
        let vm = ChatViewModel(
            spriteName: "test",
            chatId: UUID(),
            currentServiceName: nil,
            workingDirectory: "/tmp"
        )
        let card = ToolUseCard(
            toolUseId: "t1",
            toolName: "mcp__askUser__WispAsk",
            input: .object(["question": .string("Which approach?")])
        )
        let message = ChatMessage(role: .assistant, content: [.toolUse(card)])
        vm.messages = [message]
        #expect(vm.pendingWispAskCard?.toolUseId == "t1")
    }

    @MainActor
    @Test func pendingWispAskCard_ignoresNonWispAskTools() {
        let vm = ChatViewModel(
            spriteName: "test",
            chatId: UUID(),
            currentServiceName: nil,
            workingDirectory: "/tmp"
        )
        let card = ToolUseCard(
            toolUseId: "t1",
            toolName: "Bash",
            input: .object(["command": .string("ls")])
        )
        let message = ChatMessage(role: .assistant, content: [.toolUse(card)])
        vm.messages = [message]
        #expect(vm.pendingWispAskCard == nil)
    }
}
