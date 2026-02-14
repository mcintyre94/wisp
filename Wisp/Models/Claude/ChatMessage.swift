import Foundation

enum ChatRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

@Observable
@MainActor
final class ChatMessage: Identifiable {
    nonisolated let id: UUID
    let timestamp: Date
    let role: ChatRole
    var content: [ChatContent]
    var isStreaming: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), role: ChatRole, content: [ChatContent] = [], isStreaming: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}

enum ChatContent: Identifiable {
    case text(String)
    case toolUse(ToolUseCard)
    case toolResult(ToolResultCard)
    case error(String)

    var id: String {
        switch self {
        case .text(let text): return "text-\(text.prefix(50).hashValue)"
        case .toolUse(let card): return "tool-\(card.toolUseId)"
        case .toolResult(let card): return "result-\(card.toolUseId)"
        case .error(let msg): return "error-\(msg.hashValue)"
        }
    }
}

@Observable
@MainActor
final class ToolUseCard: Identifiable {
    let id: String
    let toolUseId: String
    let toolName: String
    let input: JSONValue
    var isExpanded: Bool

    init(toolUseId: String, toolName: String, input: JSONValue, isExpanded: Bool = false) {
        self.id = toolUseId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.input = input
        self.isExpanded = isExpanded
    }

    var summary: String {
        switch toolName {
        case "Bash":
            return input["command"]?.stringValue ?? "bash command"
        case "Read":
            return input["file_path"]?.stringValue ?? "read file"
        case "Write":
            return input["file_path"]?.stringValue ?? "write file"
        case "Edit":
            return input["file_path"]?.stringValue ?? "edit file"
        case "Glob":
            return input["pattern"]?.stringValue ?? "glob search"
        case "Grep":
            return input["pattern"]?.stringValue ?? "grep search"
        default:
            return toolName
        }
    }

    var iconName: String {
        switch toolName {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil.line"
        case "Glob": return "magnifyingglass"
        case "Grep": return "text.magnifyingglass"
        default: return "wrench"
        }
    }
}

@Observable
@MainActor
final class ToolResultCard: Identifiable {
    let id: String
    let toolUseId: String
    let toolName: String
    let content: JSONValue
    var isExpanded: Bool

    init(toolUseId: String, toolName: String, content: JSONValue, isExpanded: Bool = false) {
        self.id = toolUseId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.content = content
        self.isExpanded = isExpanded
    }

    var displayContent: String {
        switch content {
        case .string(let text):
            return text
        case .array(let items):
            return items.compactMap(\.stringValue).joined(separator: "\n")
        default:
            return content.prettyString
        }
    }
}
