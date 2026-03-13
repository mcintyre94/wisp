import Testing
import Foundation
@testable import Wisp

@MainActor
@Suite("SideChatViewModel")
struct SideChatViewModelTests {

    private func makeViewModel() -> SideChatViewModel {
        SideChatViewModel(
            spriteName: "test-sprite",
            sessionId: "sess-abc",
            workingDirectory: "/home/sprite/project"
        )
    }

    private func assistantEvent(_ text: String) -> ClaudeStreamEvent {
        .assistant(ClaudeAssistantEvent(
            type: "assistant",
            message: ClaudeAssistantMessage(role: "assistant", content: [.text(text)])
        ))
    }

    private func resultEvent(isError: Bool) -> ClaudeStreamEvent {
        .result(ClaudeResultEvent(
            type: "result", subtype: isError ? "error" : "success",
            sessionId: "sess-abc", isError: isError,
            durationMs: 100, numTurns: 1, result: nil
        ))
    }

    // MARK: - send() guard conditions

    @Test func send_withEmptyQuestion_doesNotStream() {
        let vm = makeViewModel()
        vm.question = ""
        vm.send(apiClient: SpritesAPIClient())
        #expect(!vm.isStreaming)
    }

    @Test func send_withWhitespaceOnlyQuestion_doesNotStream() {
        let vm = makeViewModel()
        vm.question = "   \n  "
        vm.send(apiClient: SpritesAPIClient())
        #expect(!vm.isStreaming)
    }

    @Test func send_withValidQuestion_setsIsStreamingTrue() {
        let vm = makeViewModel()
        vm.question = "What does this code do?"
        vm.send(apiClient: SpritesAPIClient())
        #expect(vm.isStreaming)
        vm.cancel(apiClient: SpritesAPIClient())
    }

    @Test func send_whenAlreadyStreaming_doesNotResetResponse() {
        let vm = makeViewModel()
        vm.question = "First question"
        vm.send(apiClient: SpritesAPIClient())
        // Inject a partial response via handle()
        vm.handle(assistantEvent("Partial answer"))
        // Try to send again while streaming — should be a no-op
        vm.question = "Second question"
        vm.send(apiClient: SpritesAPIClient())
        #expect(vm.response == "Partial answer")
        vm.cancel(apiClient: SpritesAPIClient())
    }

    // MARK: - cancel()

    @Test func cancel_setsIsStreamingFalse() {
        let vm = makeViewModel()
        vm.question = "Hello"
        vm.send(apiClient: SpritesAPIClient())
        #expect(vm.isStreaming)
        vm.cancel(apiClient: SpritesAPIClient())
        #expect(!vm.isStreaming)
    }

    // MARK: - handle()

    @Test func handle_assistantTextBlock_appendsToResponse() {
        let vm = makeViewModel()
        vm.handle(assistantEvent("Hello, "))
        vm.handle(assistantEvent("world!"))
        #expect(vm.response == "Hello, world!")
    }

    @Test func handle_resultWithError_setsErrorWhenResponseEmpty() {
        let vm = makeViewModel()
        vm.handle(resultEvent(isError: true))
        #expect(vm.error == "Claude returned an error")
    }

    @Test func handle_resultWithError_doesNotSetErrorWhenResponseNonEmpty() {
        let vm = makeViewModel()
        vm.handle(assistantEvent("Some answer"))
        vm.handle(resultEvent(isError: true))
        #expect(vm.error == nil)
        #expect(vm.response == "Some answer")
    }

    @Test func handle_successResult_doesNotSetError() {
        let vm = makeViewModel()
        vm.handle(resultEvent(isError: false))
        #expect(vm.error == nil)
    }
}
