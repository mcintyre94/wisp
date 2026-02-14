import Foundation

extension JSONDecoder {
    static func apiDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Models use explicit CodingKeys — no automatic key conversion needed
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            // Try ISO 8601 with fractional seconds first (most common)
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractional.date(from: string) {
                return date
            }

            // Fall back to standard ISO 8601
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode date from: \(string)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static func apiEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Models use explicit CodingKeys — no automatic key conversion needed
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
