import Testing
import Foundation
@testable import Wisp

@MainActor
@Suite("BashQuickViewModel")
struct BashQuickViewModelTests {

    private func makeViewModel() -> BashQuickViewModel {
        BashQuickViewModel(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project"
        )
    }

    // MARK: - send() guard conditions

    @Test func send_withEmptyCommand_doesNotRun() {
        let vm = makeViewModel()
        vm.command = ""
        vm.send(apiClient: SpritesAPIClient())
        #expect(!vm.isRunning)
    }

    @Test func send_withWhitespaceOnlyCommand_doesNotRun() {
        let vm = makeViewModel()
        vm.command = "   \n  "
        vm.send(apiClient: SpritesAPIClient())
        #expect(!vm.isRunning)
    }

    @Test func send_withValidCommand_setsIsRunningTrue() {
        let vm = makeViewModel()
        vm.command = "ls -la"
        vm.send(apiClient: SpritesAPIClient())
        #expect(vm.isRunning)
        vm.cancel(apiClient: SpritesAPIClient())
    }

    @Test func send_whenAlreadyRunning_isIdempotent() {
        let vm = makeViewModel()
        vm.command = "sleep 10"
        vm.send(apiClient: SpritesAPIClient())
        #expect(vm.isRunning)
        // Second send should be no-op
        vm.command = "ls"
        vm.send(apiClient: SpritesAPIClient())
        // Still running the first command
        #expect(vm.isRunning)
        vm.cancel(apiClient: SpritesAPIClient())
    }

    // MARK: - cancel()

    @Test func cancel_setsIsRunningFalse() {
        let vm = makeViewModel()
        vm.command = "sleep 10"
        vm.send(apiClient: SpritesAPIClient())
        #expect(vm.isRunning)
        vm.cancel(apiClient: SpritesAPIClient())
        #expect(!vm.isRunning)
    }

    // MARK: - formatInsert()

    @Test func formatInsert_wrapsCommandAndOutputInCodeFence() {
        let result = BashQuickViewModel.formatInsert(
            command: "ls -la",
            output: "total 4\ndrwxr-xr-x 2 user user"
        )
        #expect(result == "```\n$ ls -la\ntotal 4\ndrwxr-xr-x 2 user user\n```")
    }

    @Test func formatInsert_withEmptyOutput_producesMinimalFence() {
        let result = BashQuickViewModel.formatInsert(command: "pwd", output: "")
        #expect(result == "```\n$ pwd\n\n```")
    }

    @Test func formatInsert_preservesNewlinesInOutput() {
        let multiline = "line1\nline2\nline3"
        let result = BashQuickViewModel.formatInsert(command: "cat file.txt", output: multiline)
        #expect(result.contains("line1\nline2\nline3"))
        #expect(result.hasPrefix("```\n$ cat file.txt\n"))
        #expect(result.hasSuffix("\n```"))
    }
}
