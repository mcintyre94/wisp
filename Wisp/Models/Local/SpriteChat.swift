import Foundation
import SwiftData

@Model
final class SpriteChat {
    var id: UUID
    var spriteName: String
    var chatNumber: Int
    var customName: String?
    var currentServiceName: String?
    var execSessionId: String?
    var claudeSessionId: String?
    var workingDirectory: String
    var createdAt: Date
    var lastUsed: Date
    var draftInputText: String?
    var draftAttachmentPaths: [String]?
    var isClosed: Bool
    var spriteCreatedAt: Date?
    var firstMessagePreview: String?
    var forkContext: String?
    var worktreePath: String?
    var worktreeBranch: String?
    var isUnread: Bool = false

    var displayName: String {
        customName ?? "Chat \(chatNumber)"
    }

    init(
        spriteName: String,
        chatNumber: Int,
        workingDirectory: String = "/home/sprite/project",
        customName: String? = nil,
        spriteCreatedAt: Date? = nil
    ) {
        self.id = UUID()
        self.spriteName = spriteName
        self.chatNumber = chatNumber
        self.customName = customName
        self.workingDirectory = workingDirectory
        self.createdAt = Date()
        self.lastUsed = Date()
        self.isClosed = false
        self.spriteCreatedAt = spriteCreatedAt
    }
}
