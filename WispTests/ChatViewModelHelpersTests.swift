import Testing
import Foundation
@testable import Wisp

@Suite("ChatViewModel Helpers")
struct ChatViewModelHelpersTests {

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

    @Test func sanitize_noDNANotRedacted() {
        let input = "export NO_DNA=1 && claude -p 'hello'"
        let result = ChatViewModel.sanitize(input)
        #expect(result == "export NO_DNA=1 && claude -p 'hello'")
    }

    // MARK: - claudeProjectPathEncoding

    @Test func claudeProjectPathEncoding_standardPath() {
        // Plain path with no dots — only slashes replaced
        let result = ChatViewModel.claudeProjectPathEncoding("/home/sprite/project")
        #expect(result == "-home-sprite-project")
    }

    @Test func claudeProjectPathEncoding_worktreePath() {
        // Worktree paths contain a hidden directory (.wisp) — the dot must also be
        // replaced so the encoded name matches what Claude Code writes on disk.
        let result = ChatViewModel.claudeProjectPathEncoding(
            "/home/sprite/.wisp/worktrees/wisp/start-chat-from-directory-e216cd70"
        )
        #expect(result == "-home-sprite--wisp-worktrees-wisp-start-chat-from-directory-e216cd70")
    }

    @Test func claudeProjectPathEncoding_repoPath() {
        let result = ChatViewModel.claudeProjectPathEncoding("/home/sprite/my-repo")
        #expect(result == "-home-sprite-my-repo")
    }
}
