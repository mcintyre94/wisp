import Foundation

struct ExecControlMessage: Codable, Sendable {
    let type: String
    let sessionInfo: ExecSessionInfo?
    let exit: ExecExit?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionInfo = "session_info"
        case exit
    }
}

struct ExecSessionInfo: Codable, Sendable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

struct ExecExit: Codable, Sendable {
    let exitCode: Int

    enum CodingKeys: String, CodingKey {
        case exitCode = "exit_code"
    }
}
