import Foundation
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "Exec")

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

    /// Stream stdout data from the WebSocket exec session
    func stdout() -> AsyncThrowingStream<Data, Error> {
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
                            logger.info("Binary frame: streamId=\(streamId) size=\(payload.count)")

                            switch streamId {
                            case 1: // stdout
                                continuation.yield(Data(payload))
                            case 2: // stderr — also yield for visibility
                                continuation.yield(Data(payload))
                            case 3: // exit
                                logger.info("Exit frame received")
                                continuation.finish()
                                return
                            default:
                                logger.info("Unknown streamId: \(streamId)")
                                break
                            }
                        case .string(let text):
                            // Text frames are exec control messages (session_info, etc.)
                            // Not Claude NDJSON — skip them
                            logger.info("Control frame: \(text.prefix(200))")
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
