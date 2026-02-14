import Foundation

struct Sprite: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let status: SpriteStatus
    let url: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, status, url
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(SpriteStatus.self, forKey: .status)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

enum SpriteStatus: String, Codable, Sendable {
    case running
    case warm
    case cold
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = SpriteStatus(rawValue: value) ?? .unknown
    }

    var displayName: String {
        rawValue.capitalized
    }
}

struct CreateSpriteRequest: Codable, Sendable {
    let name: String
}

struct SpritesListResponse: Codable, Sendable {
    let sprites: [Sprite]
}
