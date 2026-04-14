import Testing
import Foundation
import SwiftData
@testable import Wisp

@MainActor
@Suite("Worktree")
struct WorktreeTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SpriteChat.self, SpriteSession.self, configurations: config)
        return ModelContext(container)
    }

    private func makeVM(worktreePath: String? = nil, workingDirectory: String = "/home/sprite/project") throws -> ChatViewModel {
        let ctx = try makeContext()
        let chat = SpriteChat(spriteName: "test", chatNumber: 1)
        ctx.insert(chat)
        try ctx.save()
        return ChatViewModel(
            spriteName: "test",
            chatId: chat.id,
            workingDirectory: workingDirectory,
            worktreePath: worktreePath
        )
    }

    // MARK: - shellEscapePath

    @Test func shellEscapePath_plainPath() {
        #expect(ChatViewModel.shellEscapePath("/home/sprite/project/file.txt") == "'/home/sprite/project/file.txt'")
    }

    @Test func shellEscapePath_pathWithSingleQuote() {
        // "it's.txt" → 'it'\''s.txt'
        #expect(ChatViewModel.shellEscapePath("/home/sprite/it's.txt") == "'/home/sprite/it'\\''s.txt'")
    }

    @Test func shellEscapePath_pathWithSpaces() {
        #expect(ChatViewModel.shellEscapePath("/home/sprite/my file.txt") == "'/home/sprite/my file.txt'")
    }

    @Test func shellEscapePath_empty() {
        #expect(ChatViewModel.shellEscapePath("") == "''")
    }

    // MARK: - copyAttachmentsToWorktree

    @Test func copyAttachments_noWorktree_returnsOriginal() async throws {
        let vm = try makeVM()  // worktreePath is nil
        let attachments = [AttachedFile(name: "file.txt", path: "/home/sprite/project/file.txt")]
        let result = await vm.copyAttachmentsToWorktree(attachments, apiClient: SpritesAPIClient())
        #expect(result.map(\.path) == attachments.map(\.path))
    }

    @Test func copyAttachments_empty_returnsEmpty() async throws {
        let vm = try makeVM(worktreePath: "/home/sprite/.wisp/worktrees/project/my-branch")
        let result = await vm.copyAttachmentsToWorktree([], apiClient: SpritesAPIClient())
        #expect(result.isEmpty)
    }

    @Test func copyAttachments_alreadyInWorktree_noExecNeeded() async throws {
        let worktree = "/home/sprite/.wisp/worktrees/project/my-branch"
        let vm = try makeVM(worktreePath: worktree)
        // Attachment path is already inside the worktree — same source and destination, so it's skipped
        let path = worktree + "/file.txt"
        let attachments = [AttachedFile(name: "file.txt", path: path)]
        let result = await vm.copyAttachmentsToWorktree(attachments, apiClient: SpritesAPIClient())
        #expect(result.map(\.path) == [path])
    }

    @Test func copyAttachments_failedCopy_keepsOriginalPath() async throws {
        // SpritesAPIClient() has no token so runExec returns empty output — simulates copy failure
        let worktree = "/home/sprite/.wisp/worktrees/project/my-branch"
        let vm = try makeVM(worktreePath: worktree)
        let originalPath = "/home/sprite/project/file.txt"
        let attachments = [AttachedFile(name: "file.txt", path: originalPath)]
        let result = await vm.copyAttachmentsToWorktree(attachments, apiClient: SpritesAPIClient())
        #expect(result.map(\.path) == [originalPath])
    }

    @Test func copyAttachments_mixedFiles_failedKeepsOriginal() async throws {
        // Two files: one already in worktree (unchanged), one that needs copying (fails → original kept)
        let worktree = "/home/sprite/.wisp/worktrees/project/my-branch"
        let vm = try makeVM(worktreePath: worktree)
        let alreadyInWorktree = AttachedFile(name: "existing.txt", path: worktree + "/existing.txt")
        let needsCopying = AttachedFile(name: "new.txt", path: "/home/sprite/project/new.txt")
        let attachments = [alreadyInWorktree, needsCopying]
        let result = await vm.copyAttachmentsToWorktree(attachments, apiClient: SpritesAPIClient())
        // First file: unchanged (already in worktree). Second: failed copy → original path.
        #expect(result[0].path == alreadyInWorktree.path)
        #expect(result[1].path == needsCopying.path)
    }

    // MARK: - buildWorktreeSetupCommand

    private func makeSetupCommand(
        workDir: String = "/home/sprite/project",
        parent: String = "/home/sprite/.wisp/worktrees/project",
        dir: String = "/home/sprite/.wisp/worktrees/project/add-dark-mode-abc12345",
        branch: String = "add-dark-mode-abc12345"
    ) -> String {
        ChatViewModel.buildWorktreeSetupCommand(
            currentWorkDir: workDir,
            worktreeParent: parent,
            worktreeDir: dir,
            uniqueBranchName: branch
        )
    }

    @Test func setupCommand_fetchesOriginNonFatally() {
        let cmd = makeSetupCommand()
        #expect(cmd.contains("fetch origin 2>/dev/null || true"))
    }

    @Test func setupCommand_resolvesDefaultBranchViaOriginHEAD() {
        // Regression guard: previously hardcoded `origin/main`, which broke repos with
        // default branch master/develop/etc. Must now resolve via origin/HEAD.
        let cmd = makeSetupCommand()
        #expect(cmd.contains("remote set-head origin --auto"))
        #expect(cmd.contains("symbolic-ref --short refs/remotes/origin/HEAD"))
        #expect(cmd.contains("|| echo HEAD"))
        #expect(cmd.contains("\"$BASE_REF\""))
        // Must NOT hardcode origin/main as the worktree start point
        #expect(!cmd.contains("-b 'add-dark-mode-abc12345' origin/main"))
    }

    @Test func setupCommand_usesShellEscapeForAllPaths() {
        let cmd = makeSetupCommand(
            workDir: "/home/sprite/my project",
            parent: "/home/sprite/.wisp/worktrees/my project",
            dir: "/home/sprite/.wisp/worktrees/my project/feature-abc12345",
            branch: "feature-abc12345"
        )
        // Single-quoted paths with embedded spaces survive intact
        #expect(cmd.contains("'/home/sprite/my project'"))
        #expect(cmd.contains("'/home/sprite/.wisp/worktrees/my project/feature-abc12345'"))
        #expect(cmd.contains("'feature-abc12345'"))
    }

    @Test func setupCommand_escapesSingleQuotesInPaths() {
        // A path containing a single quote must be escaped via the '\'' idiom or it would
        // break out of the surrounding shell quoting.
        let cmd = makeSetupCommand(workDir: "/home/sprite/it's-a-repo")
        #expect(cmd.contains("'/home/sprite/it'\\''s-a-repo'"))
        // And the raw unescaped form must not appear
        #expect(!cmd.contains("'/home/sprite/it's-a-repo'"))
    }

    @Test func setupCommand_echoesWorktreeDirOnSuccess() {
        let cmd = makeSetupCommand(dir: "/home/sprite/.wisp/worktrees/project/feature-abc12345")
        #expect(cmd.contains("echo '/home/sprite/.wisp/worktrees/project/feature-abc12345'"))
    }
}
