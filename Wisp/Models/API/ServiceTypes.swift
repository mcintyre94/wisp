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

/// Response from GET /v1/sprites/{name}/services and GET /v1/sprites/{name}/services/{serviceName}
struct ServiceInfo: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let cmd: String
    let args: [String]?
    let httpPort: Int?
    let needs: [String]
    let state: ServiceState

    var id: String { name }

    struct ServiceState: Codable, Sendable, Hashable {
        let name: String
        let pid: Int?
        let startedAt: Date?
        let status: String  // "running", "stopped", etc.

        enum CodingKeys: String, CodingKey {
            case name, pid, status
            case startedAt = "started_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, cmd, args, needs, state
        case httpPort = "http_port"
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
