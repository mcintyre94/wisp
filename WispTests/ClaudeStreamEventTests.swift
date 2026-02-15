import Testing
import Foundation
@testable import Wisp

@Suite("ClaudeStreamEvent")
struct ClaudeStreamEventTests {

    private let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> ClaudeStreamEvent {
        try decoder.decode(ClaudeStreamEvent.self, from: Data(json.utf8))
    }

    // MARK: - System event

    @Test func decodeSystemEvent() throws {
        let json = """
        {
            "type": "system",
            "session_id": "sess-abc",
            "model": "claude-sonnet-4-20250514",
            "tools": ["Bash", "Read", "Write"],
            "cwd": "/home/sprite/project"
        }
        """
        let event = try decode(json)
        guard case .system(let e) = event else {
            Issue.record("Expected system event")
            return
        }
        #expect(e.sessionId == "sess-abc")
        #expect(e.model == "claude-sonnet-4-20250514")
        #expect(e.tools == ["Bash", "Read", "Write"])
        #expect(e.cwd == "/home/sprite/project")
    }

    // MARK: - Assistant event with text

    @Test func decodeAssistantTextEvent() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "text", "text": "Hello world"}
                ]
            }
        }
        """
        let event = try decode(json)
        guard case .assistant(let e) = event else {
            Issue.record("Expected assistant event")
            return
        }
        #expect(e.message.role == "assistant")
        #expect(e.message.content.count == 1)
        if case .text(let text) = e.message.content[0] {
            #expect(text == "Hello world")
        } else {
            Issue.record("Expected text content block")
        }
    }

    // MARK: - Assistant event with tool_use

    @Test func decodeAssistantToolUseEvent() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": "tool-123",
                        "name": "Bash",
                        "input": {"command": "ls -la"}
                    }
                ]
            }
        }
        """
        let event = try decode(json)
        guard case .assistant(let e) = event else {
            Issue.record("Expected assistant event")
            return
        }
        if case .toolUse(let tool) = e.message.content[0] {
            #expect(tool.id == "tool-123")
            #expect(tool.name == "Bash")
            #expect(tool.input["command"]?.stringValue == "ls -la")
        } else {
            Issue.record("Expected tool_use content block")
        }
    }

    // MARK: - Unknown content block type

    @Test func decodeUnknownContentBlock() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "server_tool_use", "id": "x", "name": "y"}
                ]
            }
        }
        """
        let event = try decode(json)
        guard case .assistant(let e) = event else {
            Issue.record("Expected assistant event")
            return
        }
        if case .unknown = e.message.content[0] {
            // pass
        } else {
            Issue.record("Expected unknown content block")
        }
    }

    // MARK: - User / tool result event

    @Test func decodeUserToolResultEvent() throws {
        let json = """
        {
            "type": "user",
            "message": {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "tool-123",
                        "content": "file contents here"
                    }
                ]
            }
        }
        """
        let event = try decode(json)
        guard case .user(let e) = event else {
            Issue.record("Expected user event")
            return
        }
        #expect(e.message.role == "user")
        #expect(e.message.content.count == 1)
        #expect(e.message.content[0].toolUseId == "tool-123")
        #expect(e.message.content[0].content?.stringValue == "file contents here")
    }

    // MARK: - Result event

    @Test func decodeResultEvent() throws {
        let json = """
        {
            "type": "result",
            "subtype": "success",
            "session_id": "sess-xyz",
            "is_error": false,
            "duration_ms": 12500.0,
            "num_turns": 3,
            "result": "Task completed"
        }
        """
        let event = try decode(json)
        guard case .result(let e) = event else {
            Issue.record("Expected result event")
            return
        }
        #expect(e.sessionId == "sess-xyz")
        #expect(e.isError == false)
        #expect(e.durationMs == 12500.0)
        #expect(e.numTurns == 3)
        #expect(e.result == "Task completed")
    }

    // MARK: - Unknown top-level type

    @Test func decodeUnknownTopLevelType() throws {
        let json = #"{"type":"future_event","data":"something"}"#
        let event = try decode(json)
        if case .unknown(let type) = event {
            #expect(type == "future_event")
        } else {
            Issue.record("Expected unknown event")
        }
    }
}
