import Foundation
import SwiftData

@Model
final class SpriteSession {
    @Attribute(.unique) var spriteName: String
    var claudeSessionId: String?
    var execSessionId: String?
    var workingDirectory: String
    var lastUsed: Date
    var messagesData: Data?
    var draftInputText: String?

    init(spriteName: String, workingDirectory: String = "/home/sprite/project") {
        self.spriteName = spriteName
        self.workingDirectory = workingDirectory
        self.lastUsed = Date()
    }
}
