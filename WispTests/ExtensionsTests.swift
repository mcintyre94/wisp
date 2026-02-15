import Testing
import Foundation
@testable import Wisp

@Suite("Extensions")
struct ExtensionsTests {

    // MARK: - apiDecoder date handling

    @Test func decodesISO8601WithFractionalSeconds() throws {
        let json = #"{"date": "2025-01-15T10:30:00.123Z"}"#
        let wrapper = try JSONDecoder.apiDecoder().decode(DateWrapper.self, from: Data(json.utf8))
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: wrapper.date
        )
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 15)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
    }

    @Test func decodesISO8601WithoutFractionalSeconds() throws {
        let json = #"{"date": "2025-06-01T12:00:00Z"}"#
        let wrapper = try JSONDecoder.apiDecoder().decode(DateWrapper.self, from: Data(json.utf8))
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: wrapper.date
        )
        #expect(components.year == 2025)
        #expect(components.month == 6)
        #expect(components.day == 1)
        #expect(components.hour == 12)
    }

    @Test func throwsOnInvalidDateString() throws {
        let json = #"{"date": "not-a-date"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder.apiDecoder().decode(DateWrapper.self, from: Data(json.utf8))
        }
    }
}

// Helper type for testing date decoding
private struct DateWrapper: Decodable {
    let date: Date
}
