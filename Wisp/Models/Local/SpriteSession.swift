import Foundation
import SwiftData

@Model
final class SpriteSession {
    @Attribute(.unique) var spriteName: String
    var claudeSessionId: String?
    var workingDirectory: String
    var lastUsed: Date
    var messagesData: Data?

    init(spriteName: String, workingDirectory: String = "/home/sprite/project") {
        self.spriteName = spriteName
        self.workingDirectory = workingDirectory
        self.lastUsed = Date()
    }

    func loadMessages() -> [PersistedChatMessage] {
        guard let data = messagesData else { return [] }
        return (try? JSONDecoder().decode([PersistedChatMessage].self, from: data)) ?? []
    }

    func saveMessages(_ messages: [PersistedChatMessage]) {
        messagesData = try? JSONEncoder().encode(messages)
    }
}
