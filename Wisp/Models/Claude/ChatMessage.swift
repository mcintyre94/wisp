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
    var checkpointId: String?
    var checkpointComment: String?

    init(id: UUID = UUID(), timestamp: Date = Date(), role: ChatRole, content: [ChatContent] = [], checkpointId: String? = nil, checkpointComment: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.content = content
        self.checkpointId = checkpointId
        self.checkpointComment = checkpointComment
    }

    var textContent: String {
        content.compactMap {
            if case .text(let text) = $0 { return text }
            return nil
        }.joined(separator: "\n\n")
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
    let startedAt: Date
    var result: ToolResultCard?

    init(toolUseId: String, toolName: String, input: JSONValue, isExpanded: Bool = false, startedAt: Date = Date()) {
        self.id = toolUseId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.input = input
        self.isExpanded = isExpanded
        self.startedAt = startedAt
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
        case "mcp__askUser__WispAsk":
            return input["question"]?.stringValue ?? "asking user"
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
        case "mcp__askUser__WispAsk": return "questionmark.bubble"
        default: return "wrench"
        }
    }

    var activityLabel: String {
        switch toolName {
        case "Bash":
            let cmd = input["command"]?.stringValue ?? "command"
            let truncated = cmd.prefix(60)
            return "Running \(truncated)..."
        case "Read":
            return "Reading \(Self.fileName(from: input["file_path"]?.stringValue))..."
        case "Write":
            return "Writing \(Self.fileName(from: input["file_path"]?.stringValue))..."
        case "Edit":
            return "Editing \(Self.fileName(from: input["file_path"]?.stringValue))..."
        case "Glob":
            let pattern = input["pattern"]?.stringValue ?? "files"
            return "Searching \(pattern)..."
        case "Grep":
            let pattern = input["pattern"]?.stringValue ?? "code"
            return "Searching \(pattern)..."
        case "mcp__askUser__WispAsk":
            let question = input["question"]?.stringValue ?? "user"
            return "Asking: \(question.prefix(60))..."
        default:
            return "Running \(toolName)..."
        }
    }

    var elapsedString: String? {
        guard let completedAt = result?.completedAt else { return nil }
        let elapsed = completedAt.timeIntervalSince(startedAt)
        if elapsed < 1 {
            return "<1s"
        } else if elapsed < 60 {
            return "\(Int(elapsed))s"
        } else {
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    private static func fileName(from path: String?) -> String {
        guard let path, !path.isEmpty else { return "file" }
        return (path as NSString).lastPathComponent
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
    let completedAt: Date

    init(toolUseId: String, toolName: String, content: JSONValue, isExpanded: Bool = false, completedAt: Date = Date()) {
        self.id = toolUseId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.content = content
        self.isExpanded = isExpanded
        self.completedAt = completedAt
    }

    var displayContent: String {
        switch content {
        case .string(let text):
            return text
        case .array(let items):
            // Built-in tool results: array of strings
            let strings = items.compactMap(\.stringValue)
            if !strings.isEmpty { return strings.joined(separator: "\n") }
            // MCP tool results: array of content blocks [{type, text}]
            let texts = items.compactMap { $0["text"]?.stringValue }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
            return content.prettyString
        default:
            return content.prettyString
        }
    }

    var previewContent: String? {
        let text = displayContent
        guard !text.isEmpty, text.count <= 500 else { return nil }
        let lines = text.components(separatedBy: "\n").prefix(2)
        let preview = lines.joined(separator: "\n")
        if preview.count > 120 {
            return String(preview.prefix(120)) + "..."
        }
        return preview
    }
}
