import Foundation
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "BashQuick")

@Observable
@MainActor
final class BashQuickViewModel {
    let spriteName: String
    let workingDirectory: String

    var command = ""
    private(set) var output = ""
    private(set) var isRunning = false
    private(set) var error: String?
    private(set) var lastCommand = ""

    private var streamTask: Task<Void, Never>?

    init(spriteName: String, workingDirectory: String) {
        self.spriteName = spriteName
        self.workingDirectory = workingDirectory
    }

    func send(apiClient: SpritesAPIClient) {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty, !isRunning else { return }

        lastCommand = cmd
        command = ""
        output = ""
        error = nil
        isRunning = true

        streamTask = Task {
            await executeCommand(cmd, apiClient: apiClient)
        }
    }

    func cancel(apiClient: SpritesAPIClient) {
        streamTask?.cancel()
        streamTask = nil
        isRunning = false
    }

    func insertFormatted() -> String {
        BashQuickViewModel.formatInsert(command: lastCommand, output: output)
    }

    static func formatInsert(command: String, output: String) -> String {
        "```\n$ \(command)\n\(output.trimmingCharacters(in: .newlines))\n```"
    }

    // MARK: - Private

    private func executeCommand(_ cmd: String, apiClient: SpritesAPIClient) async {
        let fullCommand = "cd \(workingDirectory) 2>/dev/null || true; \(cmd)"
        let session = apiClient.createExecSession(spriteName: spriteName, command: fullCommand)
        session.connect()

        do {
            streamLoop: for try await event in session.events() {
                guard !Task.isCancelled else { break streamLoop }
                switch event {
                case .stdout(let data), .stderr(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        output += text
                    }
                case .exit:
                    break streamLoop
                case .sessionInfo:
                    break
                }
            }
        } catch {
            if !Task.isCancelled {
                self.error = "Connection error"
                logger.error("Bash quick stream error: \(error.localizedDescription)")
            }
        }

        session.disconnect()

        if !Task.isCancelled {
            isRunning = false
        }
    }
}
