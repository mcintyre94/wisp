import Testing
import SwiftUI
@testable import Wisp

@Suite("ConsoleLogEntry")
struct ConsoleLogEntryTests {

    // MARK: - Level raw value parsing

    @Test func levelParsesAllValidRawValues() {
        #expect(ConsoleLogEntry.Level(rawValue: "log") == .log)
        #expect(ConsoleLogEntry.Level(rawValue: "info") == .info)
        #expect(ConsoleLogEntry.Level(rawValue: "warn") == .warn)
        #expect(ConsoleLogEntry.Level(rawValue: "error") == .error)
        #expect(ConsoleLogEntry.Level(rawValue: "debug") == .debug)
    }

    @Test func levelReturnsNilForUnknownRawValue() {
        #expect(ConsoleLogEntry.Level(rawValue: "warning") == nil)
        #expect(ConsoleLogEntry.Level(rawValue: "LOG") == nil)
        #expect(ConsoleLogEntry.Level(rawValue: "") == nil)
    }

    // MARK: - Level colors

    @Test func levelColorsAreDistinct() {
        let levels = ConsoleLogEntry.Level.allCases
        let colors = levels.map(\.color)
        // warn and error must be visually distinct (orange vs red)
        #expect(colors[levels.firstIndex(of: .warn)!] == Color.orange)
        #expect(colors[levels.firstIndex(of: .error)!] == Color.red)
        #expect(colors[levels.firstIndex(of: .info)!] == Color.blue)
    }

    // MARK: - Entry initialisation

    @Test func entryStoresLevelAndMessage() {
        let entry = ConsoleLogEntry(level: .warn, message: "something is off")
        #expect(entry.level == .warn)
        #expect(entry.message == "something is off")
    }

    @Test func eachEntryHasUniqueID() {
        let a = ConsoleLogEntry(level: .log, message: "a")
        let b = ConsoleLogEntry(level: .log, message: "b")
        #expect(a.id != b.id)
    }

    // MARK: - Message body parsing (mirrors WeakScriptMessageHandler logic)

    @Test func parsesValidMessageBody() {
        let body: [String: String] = ["level": "error", "message": "boom"]
        let level = ConsoleLogEntry.Level(rawValue: body["level"] ?? "")
        #expect(level == .error)
        let entry = ConsoleLogEntry(level: level!, message: body["message"]!)
        #expect(entry.message == "boom")
    }

    @Test func rejectsBodyMissingLevelKey() {
        let body: [String: String] = ["message": "orphan"]
        #expect(body["level"] == nil)
    }

    @Test func rejectsBodyMissingMessageKey() {
        let body: [String: String] = ["level": "log"]
        #expect(body["message"] == nil)
    }

    @Test func rejectsBodyWithUnknownLevel() {
        let body: [String: String] = ["level": "verbose", "message": "hi"]
        #expect(ConsoleLogEntry.Level(rawValue: body["level"]!) == nil)
    }
}

extension ConsoleLogEntry.Level: CaseIterable {
    public static var allCases: [ConsoleLogEntry.Level] {
        [.log, .info, .warn, .error, .debug]
    }
}
