import Foundation
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "Exec")

/// Events yielded by an exec session stream
enum ExecEvent: Sendable {
    /// Stdout/stderr data from the process
    case data(Data)
    /// Exec session ID from the session_info control frame
    case sessionInfo(id: String)
}

final class ExecSession: Sendable {
    private let url: URL
    private let token: String
    private let task: URLSessionWebSocketTask

    init(url: URL, token: String) {
        self.url = url
        self.token = token

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        self.task = URLSession.shared.webSocketTask(with: request)
    }

    func connect() {
        task.resume()
    }

    func disconnect() {
        task.cancel(with: .goingAway, reason: nil)
    }

    /// Send raw bytes to stdin (stream ID 0)
    func sendStdin(_ data: Data) async throws {
        var frame = Data([0]) // stream ID 0 = stdin
        frame.append(data)
        try await task.send(.data(frame))
    }

    /// Send stdin EOF (stream ID 4)
    func sendStdinEOF() async throws {
        try await task.send(.data(Data([4])))
    }

    /// Parse session_info JSON from a WebSocket text frame, returning the session ID if found
    private static func parseSessionInfo(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "session_info",
              let sessionId = obj["session_id"] as? String
        else { return nil }
        return sessionId
    }

    /// Stream events from the WebSocket exec session
    func events() -> AsyncThrowingStream<ExecEvent, Error> {
        AsyncThrowingStream { continuation in
            let receiveTask = Task { [task] in
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        switch message {
                        case .data(let data):
                            guard !data.isEmpty else { continue }
                            let streamId = data[0]
                            let payload = data.dropFirst()
                            let preview = String(data: Data(payload), encoding: .utf8)?.prefix(500) ?? "<binary>"
                            logger.info("Binary frame: streamId=\(streamId) size=\(payload.count) preview=\(preview)")

                            switch streamId {
                            case 1: // stdout
                                continuation.yield(.data(Data(payload)))
                            case 2: // stderr — also yield for visibility
                                logger.warning("stderr: \(preview)")
                                continuation.yield(.data(Data(payload)))
                            case 3: // exit
                                let exitCode = payload.first.map { Int($0) } ?? -1
                                logger.info("Exit frame received, code=\(exitCode)")
                                continuation.finish()
                                return
                            default:
                                logger.info("Unknown streamId: \(streamId)")
                                break
                            }
                        case .string(let text):
                            logger.info("Control frame: \(text.prefix(200))")
                            if let sid = Self.parseSessionInfo(text) {
                                continuation.yield(.sessionInfo(id: sid))
                            }
                        @unknown default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                receiveTask.cancel()
            }
        }
    }
}
