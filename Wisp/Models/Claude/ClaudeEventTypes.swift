import Foundation

// MARK: - System Event

struct ClaudeSystemEvent: Codable, Sendable {
    let type: String
    let sessionId: String
    let model: String?
    let tools: [String]?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case model, tools, cwd
    }
}

// MARK: - Assistant Event

struct ClaudeAssistantEvent: Codable, Sendable {
    let type: String
    let message: ClaudeAssistantMessage
}

struct ClaudeAssistantMessage: Codable, Sendable {
    let role: String
    let content: [ClaudeContentBlock]
}

enum ClaudeContentBlock: Sendable {
    case text(String)
    case toolUse(ClaudeToolUse)
    case unknown
}

extension ClaudeContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(JSONValue.self, forKey: .input)
            self = .toolUse(ClaudeToolUse(id: id, name: name, input: input))
        default:
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let toolUse):
            try container.encode("tool_use", forKey: .type)
            try container.encode(toolUse.id, forKey: .id)
            try container.encode(toolUse.name, forKey: .name)
            try container.encode(toolUse.input, forKey: .input)
        case .unknown:
            try container.encode("unknown", forKey: .type)
        }
    }
}

struct ClaudeToolUse: Codable, Sendable {
    let id: String
    let name: String
    let input: JSONValue
}

// MARK: - User / Tool Result Event

struct ClaudeToolResultEvent: Codable, Sendable {
    let type: String
    let message: ClaudeToolResultMessage
}

struct ClaudeToolResultMessage: Codable, Sendable {
    let role: String
    let content: [ClaudeToolResult]
}

struct ClaudeToolResult: Codable, Sendable {
    let type: String
    let toolUseId: String
    let content: JSONValue?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
    }
}

// MARK: - Result Event

struct ClaudeResultEvent: Codable, Sendable {
    let type: String
    let sessionId: String
    let durationMs: Double?
    let numTurns: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case durationMs = "duration_ms"
        case numTurns = "num_turns"
    }
}
