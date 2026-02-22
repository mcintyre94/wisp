import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "Migration")

/// One-time migration from SpriteSession to SpriteChat.
/// Converts each SpriteSession into a SpriteChat with chatNumber=1, then deletes the old record.
@MainActor
func migrateSpriteSessionsIfNeeded(modelContext: ModelContext) {
    let descriptor = FetchDescriptor<SpriteSession>()
    guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else {
        return
    }

    logger.info("Migrating \(sessions.count) SpriteSession(s) to SpriteChat")

    for session in sessions {
        let chat = SpriteChat(
            spriteName: session.spriteName,
            chatNumber: 1,
            workingDirectory: session.workingDirectory
        )
        chat.claudeSessionId = session.claudeSessionId
        chat.lastUsed = session.lastUsed
        chat.messagesData = session.messagesData
        chat.draftInputText = session.draftInputText
        chat.isClosed = false

        modelContext.insert(chat)
        modelContext.delete(session)
    }

    try? modelContext.save()
    logger.info("Migration complete")
}
