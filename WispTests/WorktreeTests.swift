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
            currentServiceName: nil,
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
}
