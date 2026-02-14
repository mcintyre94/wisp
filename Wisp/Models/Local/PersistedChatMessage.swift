import Foundation

// MARK: - Persisted DTOs

struct PersistedChatMessage: Codable {
    let id: UUID
    let timestamp: Date
    let role: ChatRole
    let content: [PersistedChatContent]
}

enum PersistedChatContent: Codable {
    case text(String)
    case toolUse(PersistedToolUse)
    case toolResult(PersistedToolResult)
    case error(String)
}

struct PersistedToolUse: Codable {
    let toolUseId: String
    let toolName: String
    let input: JSONValue
}

struct PersistedToolResult: Codable {
    let toolUseId: String
    let toolName: String
    let content: JSONValue
}

// MARK: - ChatMessage -> Persisted

extension ChatMessage {
    @MainActor
    func toPersisted() -> PersistedChatMessage {
        PersistedChatMessage(
            id: id,
            timestamp: timestamp,
            role: role,
            content: content.map { $0.toPersisted() }
        )
    }
}

extension ChatContent {
    @MainActor
    func toPersisted() -> PersistedChatContent {
        switch self {
        case .text(let text):
            return .text(text)
        case .toolUse(let card):
            return .toolUse(PersistedToolUse(
                toolUseId: card.toolUseId,
                toolName: card.toolName,
                input: card.input
            ))
        case .toolResult(let card):
            return .toolResult(PersistedToolResult(
                toolUseId: card.toolUseId,
                toolName: card.toolName,
                content: card.content
            ))
        case .error(let msg):
            return .error(msg)
        }
    }
}

// MARK: - Persisted -> ChatMessage

extension ChatMessage {
    @MainActor
    convenience init(from persisted: PersistedChatMessage) {
        self.init(
            id: persisted.id,
            timestamp: persisted.timestamp,
            role: persisted.role,
            content: persisted.content.map { ChatContent(from: $0) }
        )
    }
}

extension ChatContent {
    @MainActor
    init(from persisted: PersistedChatContent) {
        switch persisted {
        case .text(let text):
            self = .text(text)
        case .toolUse(let dto):
            self = .toolUse(ToolUseCard(
                toolUseId: dto.toolUseId,
                toolName: dto.toolName,
                input: dto.input
            ))
        case .toolResult(let dto):
            self = .toolResult(ToolResultCard(
                toolUseId: dto.toolUseId,
                toolName: dto.toolName,
                content: dto.content
            ))
        case .error(let msg):
            self = .error(msg)
        }
    }
}
