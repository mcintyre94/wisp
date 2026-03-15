import Foundation
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "QuickChat")

@Observable
@MainActor
final class QuickChatViewModel {
    let spriteName: String
    let sessionId: String?
    let workingDirectory: String

    var question = ""
    private(set) var lastQuestion = ""
    private(set) var response = ""
    private(set) var isStreaming = false
    private(set) var error: String?

    private var streamTask: Task<Void, Never>?
    private let parser = ClaudeStreamParser()

    init(spriteName: String, sessionId: String?, workingDirectory: String) {
        self.spriteName = spriteName
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
    }

    func send(apiClient: SpritesAPIClient) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }

        lastQuestion = q
        question = ""
        response = ""
        error = nil
        isStreaming = true

        streamTask = Task {
            await executeQuestion(q, apiClient: apiClient)
        }
    }

    func cancel(apiClient: SpritesAPIClient) {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    // MARK: - Private

    private func executeQuestion(_ question: String, apiClient: SpritesAPIClient) async {
        guard let claudeToken = apiClient.claudeToken else {
            error = "No Claude token configured"
            isStreaming = false
            return
        }

        let escapedQuestion = question.replacingOccurrences(of: "'", with: "'\\''")
        let modelId = UserDefaults.standard.string(forKey: "claudeModel") ?? ClaudeModel.sonnet.rawValue

        var claudeCmd = "claude -p --verbose --output-format stream-json --dangerously-skip-permissions"
        claudeCmd += " --disallowedTools \"Bash,Write,Edit,MultiEdit,WebSearch,WebFetch\""
        claudeCmd += " --max-turns 3"
        claudeCmd += " --model \(modelId)"
        if let sid = sessionId {
            claudeCmd += " --resume \(sid)"
        }
        claudeCmd += " '\(escapedQuestion)'"

        let commandParts: [String] = [
            "export CLAUDE_CODE_OAUTH_TOKEN='\(claudeToken)'",
            "mkdir -p \(workingDirectory)",
            "cd \(workingDirectory)",
            claudeCmd
        ]
        let fullCommand = commandParts.joined(separator: " && ")

        let serviceName = "wisp-quick-\(UUID().uuidString.prefix(8).lowercased())"
        let config = ServiceRequest(cmd: "bash", args: ["-c", fullCommand], needs: nil, httpPort: nil)
        let stream = apiClient.streamService(spriteName: spriteName, serviceName: serviceName, config: config)

        await parser.reset()

        var receivedData = false
        var receivedResult = false

        do {
            streamLoop: for try await event in stream {
                guard !Task.isCancelled else { break streamLoop }

                switch event.type {
                case .stdout:
                    guard let text = event.data else { continue }
                    receivedData = true

                    var dataStr = ChatViewModel.stripLogTimestamps(text)
                    if !dataStr.hasSuffix("\n") { dataStr += "\n" }
                    let parsed = await parser.parse(data: Data(dataStr.utf8))
                    for e in parsed {
                        handle(e)
                        if case .result = e { receivedResult = true }
                    }
                    if receivedResult { break streamLoop }

                case .stderr:
                    if !receivedData, let text = event.data {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { error = trimmed }
                    }

                case .exit:
                    let remaining = await parser.flush()
                    for e in remaining { handle(e) }

                case .error:
                    if !receivedData {
                        error = event.data ?? "Service error"
                    }

                case .complete:
                    let flushed = await parser.flush()
                    for e in flushed { handle(e) }
                    break streamLoop

                default:
                    break
                }
            }

            let remaining = await parser.flush()
            for e in remaining { handle(e) }
        } catch {
            if !Task.isCancelled {
                self.error = "Connection error"
                logger.error("Quick chat stream error: \(error.localizedDescription)")
            }
        }

        // Clean up the service — it's ephemeral
        Task {
            try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)
        }

        if !Task.isCancelled {
            isStreaming = false
        }
    }

    func handle(_ event: ClaudeStreamEvent) {
        switch event {
        case .assistant(let assistantEvent):
            for block in assistantEvent.message.content {
                if case .text(let text) = block {
                    response += text
                }
            }
        case .result(let resultEvent):
            if resultEvent.isError == true, response.isEmpty {
                error = "Claude returned an error"
            }
        default:
            break
        }
    }
}
