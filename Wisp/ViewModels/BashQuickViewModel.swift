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
        let serviceName = "wisp-quick-\(UUID().uuidString.prefix(8).lowercased())"
        let config = ServiceRequest(cmd: "bash", args: ["-c", fullCommand], needs: nil, httpPort: nil)
        let stream = apiClient.streamService(spriteName: spriteName, serviceName: serviceName, config: config)

        do {
            streamLoop: for try await event in stream {
                guard !Task.isCancelled else { break streamLoop }
                switch event.type {
                case .stdout, .stderr:
                    if let text = event.data {
                        output += text
                    }
                case .error:
                    if output.isEmpty {
                        error = event.data ?? "Service error"
                    }
                case .complete:
                    break streamLoop
                default:
                    break
                }
            }
        } catch {
            if !Task.isCancelled {
                self.error = "Connection error"
                logger.error("Bash quick stream error: \(error.localizedDescription)")
            }
        }

        Task {
            try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)
        }

        if !Task.isCancelled {
            isRunning = false
        }
    }
}
