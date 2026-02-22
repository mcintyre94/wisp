import Foundation
import SwiftData

@Model
final class SpriteChat {
    var id: UUID
    var spriteName: String
    var chatNumber: Int
    var customName: String?
    var currentServiceName: String?
    var claudeSessionId: String?
    var workingDirectory: String
    var createdAt: Date
    var lastUsed: Date
    var messagesData: Data?
    var draftInputText: String?
    var isClosed: Bool

    var displayName: String {
        customName ?? "Chat \(chatNumber)"
    }

    init(
        spriteName: String,
        chatNumber: Int,
        workingDirectory: String = "/home/sprite/project",
        customName: String? = nil
    ) {
        self.id = UUID()
        self.spriteName = spriteName
        self.chatNumber = chatNumber
        self.customName = customName
        self.workingDirectory = workingDirectory
        self.createdAt = Date()
        self.lastUsed = Date()
        self.isClosed = false
    }

    func loadMessages() -> [PersistedChatMessage] {
        guard let data = messagesData else { return [] }
        return (try? JSONDecoder().decode([PersistedChatMessage].self, from: data)) ?? []
    }

    func saveMessages(_ messages: [PersistedChatMessage]) {
        messagesData = try? JSONEncoder().encode(messages)
    }
}
