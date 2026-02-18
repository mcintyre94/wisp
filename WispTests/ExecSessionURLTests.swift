import Testing
import Foundation
@testable import Wisp

@Suite("Exec Session URL Encoding")
struct ExecSessionURLTests {

    // MARK: - Semicolon encoding

    @Test func semicolonsInCommandArePercentEncoded() throws {
        // Semicolons must be percent-encoded because Go's net/url (1.17+)
        // silently drops query parameters containing literal semicolons.
        let command = "echo 'CREATE TABLE t (id INT); SELECT 1;'"

        let url = buildExecURL(command: command)
        let query = try #require(url.query)

        // The raw query string must not contain literal semicolons
        #expect(!query.contains(";"))
        // But should contain the encoded form
        #expect(url.absoluteString.contains("%3B"))
    }

    @Test func commandWithSQLiteDefaultDatetime() throws {
        // Reproduces the exact user-reported bug: SQLite CREATE TABLE
        // with datetime('now') DEFAULT and trailing semicolons.
        let command = """
            mkdir -p /home/sprite/project && cd /home/sprite/project && claude -p \
            'CREATE TABLE emails (received_at TEXT NOT NULL DEFAULT (datetime('\\''now'\\''))); \
            CREATE TABLE docs (created_at TEXT NOT NULL DEFAULT (datetime('\\''now'\\'')));'
            """

        let url = buildExecURL(command: command)

        // Verify no literal semicolons in the URL
        #expect(!url.absoluteString.contains(";"))
        #expect(url.absoluteString.contains("%3B"))
    }

    @Test func commandWithoutSemicolonsIsUnchanged() throws {
        let command = "echo hello world"

        let url = buildExecURL(command: command)
        let query = try #require(url.query)

        // Should still have the command in the query
        #expect(query.contains("cmd=echo"))
    }

    @Test func allCmdParametersPreserved() throws {
        let command = "echo 'a;b'"

        let url = buildExecURL(command: command)
        let absoluteString = url.absoluteString

        // All three cmd params should be present
        let cmdCount = absoluteString.components(separatedBy: "cmd=").count - 1
        #expect(cmdCount == 3) // bash, -c, and the command
    }

    // MARK: - Helpers

    /// Build an exec WebSocket URL the same way SpritesAPIClient does.
    private func buildExecURL(command: String, env: [String: String] = [:]) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.sprites.dev"
        components.path = "/v1/sprites/test-sprite/exec"

        var queryItems = [
            URLQueryItem(name: "cmd", value: "bash"),
            URLQueryItem(name: "cmd", value: "-c"),
            URLQueryItem(name: "cmd", value: command),
        ]

        for (key, value) in env {
            queryItems.append(URLQueryItem(name: "env", value: "\(key)=\(value)"))
        }

        components.queryItems = queryItems

        if let encoded = components.percentEncodedQuery {
            components.percentEncodedQuery = encoded.replacingOccurrences(of: ";", with: "%3B")
        }

        return components.url!
    }
}
