import Foundation
import SwiftData

/// App-wide cache of ChatViewModels, keyed by chat UUID.
/// Keeps streams alive across chat switches and sprite navigation so connections
/// are only torn down on explicit actions (interrupt, chat deletion, app termination).
@Observable
@MainActor
final class ChatSessionManager {
    private var cache: [UUID: ChatViewModel] = [:]

    /// Returns the cached VM for a chat, or creates and loads a new one.
    func viewModel(
        for chat: SpriteChat,
        spriteName: String,
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) -> ChatViewModel {
        if let existing = cache[chat.id] {
            return existing
        }
        let vm = ChatViewModel(
            spriteName: spriteName,
            chatId: chat.id,
            workingDirectory: chat.workingDirectory
        )
        vm.loadSession(apiClient: apiClient, modelContext: modelContext)
        cache[chat.id] = vm
        return vm
    }

    func isStreaming(chatId: UUID) -> Bool {
        cache[chatId]?.isStreaming ?? false
    }

    /// Called when the app returns to the foreground — reconnects any VM that had a live stream.
    func resumeAllAfterBackground(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        for vm in cache.values {
            vm.resumeAfterBackground(apiClient: apiClient, modelContext: modelContext)
            vm.reconnectIfNeeded(apiClient: apiClient, modelContext: modelContext)
        }
    }

    /// Removes and detaches a VM when its chat is deleted.
    func remove(chatId: UUID, modelContext: ModelContext) {
        cache[chatId]?.detach(modelContext: modelContext)
        cache.removeValue(forKey: chatId)
    }

    /// Detaches and removes all cached VMs. Call when clearing all chats.
    func detachAll(modelContext: ModelContext) {
        for vm in cache.values {
            vm.detach(modelContext: modelContext)
        }
        cache.removeAll()
    }
}
