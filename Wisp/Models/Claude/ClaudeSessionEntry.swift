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
