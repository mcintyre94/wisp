import Testing
import Foundation
@testable import Wisp

@Suite("ChatViewModel Helpers")
struct ChatViewModelHelpersTests {

    // MARK: - stripLogTimestamps

    @Test func stripLogTimestamps_stdoutPrefix() {
        let input = "2026-02-19T09:13:24.665Z [stdout] {\"type\":\"system\"}\n"
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == "{\"type\":\"system\"}\n")
    }

    @Test func stripLogTimestamps_stderrPrefix() {
        let input = "2026-02-19T09:13:24.665Z [stderr] some error\n"
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == "some error\n")
    }

    @Test func stripLogTimestamps_noPrefix() {
        let input = "{\"type\":\"system\"}\n"
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == "{\"type\":\"system\"}\n")
    }

    @Test func stripLogTimestamps_multiLine() {
        let input = """
        2026-02-19T09:13:24.665Z [stdout] line1
        2026-02-19T09:13:25.000Z [stdout] line2
        """
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == "line1\nline2")
    }

    @Test func stripLogTimestamps_mixed() {
        let input = "2026-02-19T09:13:24.665Z [stdout] json\nplain line\n"
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == "json\nplain line\n")
    }

    @Test func stripLogTimestamps_empty() {
        #expect(ChatViewModel.stripLogTimestamps("") == "")
    }

    @Test func stripLogTimestamps_trailingNewline() {
        let input = "2026-02-19T09:13:24.665Z [stdout] data\n"
        let result = ChatViewModel.stripLogTimestamps(input)
        #expect(result == "data\n")
    }

    // MARK: - sanitize

    @Test func sanitize_equalsSignToken() {
        let input = "CLAUDE_CODE_OAUTH_TOKEN=sk-ant-secret123"
        let result = ChatViewModel.sanitize(input)
        #expect(result == "CLAUDE_CODE_OAUTH_TOKEN=<redacted>")
    }

    @Test func sanitize_percentEncodedToken() {
        let input = "CLAUDE_CODE_OAUTH_TOKEN%3Dsk-ant-secret123"
        let result = ChatViewModel.sanitize(input)
        #expect(result == "CLAUDE_CODE_OAUTH_TOKEN=<redacted>")
    }

    @Test func sanitize_noToken() {
        let input = "some normal command string"
        let result = ChatViewModel.sanitize(input)
        #expect(result == "some normal command string")
    }

    @Test func sanitize_tokenInLongerCommand() {
        let input = "export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-secret123 && claude -p 'hello'"
        let result = ChatViewModel.sanitize(input)
        #expect(result == "export CLAUDE_CODE_OAUTH_TOKEN=<redacted> && claude -p 'hello'")
    }
}
