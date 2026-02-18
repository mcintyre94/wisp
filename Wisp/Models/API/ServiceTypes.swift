import Foundation

/// Request body for PUT /v1/sprites/{name}/services/{serviceName}
struct ServiceRequest: Codable, Sendable {
    let cmd: String
    let args: [String]?
    let needs: [String]?
    let httpPort: Int?

    enum CodingKeys: String, CodingKey {
        case cmd, args, needs
        case httpPort = "http_port"
    }
}

/// NDJSON event from service log stream
struct ServiceLogEvent: Sendable {
    let type: ServiceLogEventType
    let data: String?
    let exitCode: Int?
    let timestamp: Double?
    let logFiles: [String: String]?
}

extension ServiceLogEvent: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, data, timestamp
        case exitCode = "exit_code"
        case logFiles = "log_files"
    }
}

enum ServiceLogEventType: String, Codable, Sendable {
    case stdout
    case stderr
    case exit
    case error
    case complete
    case started
    case stopping
    case stopped
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ServiceLogEventType(rawValue: value) ?? .unknown
    }
}

/// Request body for POST /v1/sprites/{name}/services/signal
struct ServiceSignalRequest: Codable, Sendable {
    let name: String
    let signal: String
}
