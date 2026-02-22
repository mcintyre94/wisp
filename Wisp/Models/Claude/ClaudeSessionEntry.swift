import Foundation

/// Decoded output from jq extraction of session .jsonl files.
struct SessionSummary: Codable, Sendable {
    let sessionId: String?
    let timestamp: String?
    let prompt: String?
    let mtime: Int?        // Unix epoch seconds (file last-modified)
}

struct ClaudeSessionEntry: Codable, Sendable, Identifiable {
    let sessionId: String
    let firstPrompt: String?
    let messageCount: Int?
    let modifiedDate: Date?
    let gitBranch: String?

    var id: String { sessionId }

    var displayPrompt: String? {
        guard let firstPrompt, !firstPrompt.isEmpty else { return nil }
        let firstLine = firstPrompt.prefix(while: { $0 != "\n" && $0 != "\r" })
        if firstLine.count > 100 {
            return String(firstLine.prefix(100)) + "..."
        }
        return String(firstLine)
    }
}

// MARK: - JSONL Line Parsing (for restoring chat history from session files)

/// A single line from a Claude session .jsonl file.
/// All fields optional for resilient parsing — unknown lines are silently skipped.
struct SessionJSONLLine: Codable, Sendable {
    let type: String?
    let sessionId: String?
    let message: SessionJSONLMessage?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case message
    }
}

struct SessionJSONLMessage: Codable, Sendable {
    let role: String?
    let content: SessionMessageContent?
}

/// Content can be a plain string (user prompt) or an array of content blocks.
enum SessionMessageContent: Codable, Sendable {
    case string(String)
    case blocks([SessionContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let blocks = try? container.decode([SessionContentBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .blocks([])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

/// A content block within a JSONL message. Handles text, tool_use, and tool_result.
struct SessionContentBlock: Codable, Sendable {
    let type: String?
    // text block
    let text: String?
    // tool_use block
    let id: String?
    let name: String?
    let input: JSONValue?
    // tool_result block
    let toolUseId: String?
    let content: SessionToolResultContent?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, content
        case toolUseId = "tool_use_id"
    }
}

/// Tool result content can be a string or an array of text objects.
enum SessionToolResultContent: Codable, Sendable {
    case string(String)
    case blocks([SessionToolResultTextBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let blocks = try? container.decode([SessionToolResultTextBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }

    var textValue: String {
        switch self {
        case .string(let str):
            return str
        case .blocks(let blocks):
            return blocks.compactMap { $0.text }.joined(separator: "\n")
        }
    }
}

struct SessionToolResultTextBlock: Codable, Sendable {
    let type: String?
    let text: String?
}
