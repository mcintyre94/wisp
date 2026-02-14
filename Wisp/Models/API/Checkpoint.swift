import Foundation

struct Checkpoint: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let createTime: Date?
    let isAuto: Bool?
    let comment: String?
    let sourceId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createTime = "create_time"
        case isAuto = "is_auto"
        case comment
        case sourceId = "source_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createTime = try container.decodeIfPresent(Date.self, forKey: .createTime)
        isAuto = try container.decodeIfPresent(Bool.self, forKey: .isAuto)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(createTime, forKey: .createTime)
        try container.encodeIfPresent(isAuto, forKey: .isAuto)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(sourceId, forKey: .sourceId)
    }
}

struct CreateCheckpointRequest: Codable, Sendable {
    let comment: String?
}

/// NDJSON event from streaming checkpoint create/restore
struct CheckpointStreamEvent: Codable, Sendable {
    let type: String
    let data: String?
    let time: String?
}
