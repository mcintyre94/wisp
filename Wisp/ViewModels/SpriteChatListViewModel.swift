import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "ChatList")

@Observable
@MainActor
final class SpriteChatListViewModel {
    let spriteName: String
    private(set) var chats: [SpriteChat] = []
    var activeChatId: UUID?

    var activeChat: SpriteChat? {
        guard let id = activeChatId else { return nil }
        return chats.first { $0.id == id }
    }

    init(spriteName: String) {
        self.spriteName = spriteName
    }

    func loadChats(modelContext: ModelContext) {
        let name = spriteName
        let descriptor = FetchDescriptor<SpriteChat>(
            predicate: #Predicate { $0.spriteName == name },
            sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]
        )
        chats = (try? modelContext.fetch(descriptor)) ?? []

        // Set active to most recent non-closed chat, or most recent overall
        if activeChatId == nil || !chats.contains(where: { $0.id == activeChatId }) {
            activeChatId = chats.first(where: { !$0.isClosed })?.id ?? chats.first?.id
        }
    }

    func createChat(modelContext: ModelContext) -> SpriteChat {
        let maxNumber = chats.map(\.chatNumber).max() ?? 0
        let chat = SpriteChat(
            spriteName: spriteName,
            chatNumber: maxNumber + 1
        )
        modelContext.insert(chat)
        try? modelContext.save()

        chats.insert(chat, at: 0)
        activeChatId = chat.id
        logger.info("Created chat \(chat.chatNumber) for \(self.spriteName)")
        return chat
    }

    func closeChat(_ chat: SpriteChat, apiClient: SpritesAPIClient, modelContext: ModelContext) {
        chat.isClosed = true
        try? modelContext.save()

        // Delete the service if one exists
        if let serviceName = chat.currentServiceName {
            let sName = spriteName
            Task {
                try? await apiClient.deleteService(spriteName: sName, serviceName: serviceName)
            }
        }

        // If closing the active chat, select next open chat
        if activeChatId == chat.id {
            selectNextOpenChat()
        }
    }

    func deleteChat(_ chat: SpriteChat, apiClient: SpritesAPIClient, modelContext: ModelContext) {
        let wasActive = activeChatId == chat.id

        // Delete the service if one exists
        if let serviceName = chat.currentServiceName {
            let sName = spriteName
            Task {
                try? await apiClient.deleteService(spriteName: sName, serviceName: serviceName)
            }
        }

        chats.removeAll { $0.id == chat.id }
        modelContext.delete(chat)
        try? modelContext.save()

        if wasActive {
            selectNextOpenChat()
        }
    }

    func selectChat(_ chat: SpriteChat) {
        activeChatId = chat.id
    }

    func renameChat(_ chat: SpriteChat, name: String, modelContext: ModelContext) {
        chat.customName = name.isEmpty ? nil : name
        try? modelContext.save()
    }

    private func selectNextOpenChat() {
        activeChatId = chats.first(where: { !$0.isClosed })?.id ?? chats.first?.id
    }
}
