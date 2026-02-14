import Foundation
import SwiftData

@Model
final class SpriteSession {
    @Attribute(.unique) var spriteName: String
    var claudeSessionId: String?
    var workingDirectory: String
    var lastUsed: Date

    init(spriteName: String, workingDirectory: String = "/home/sprite/project") {
        self.spriteName = spriteName
        self.workingDirectory = workingDirectory
        self.lastUsed = Date()
    }
}
