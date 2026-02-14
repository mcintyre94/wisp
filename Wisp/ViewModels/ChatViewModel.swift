import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.wisp.app", category: "Chat")

enum ChatStatus: Sendable {
    case idle
    case connecting
    case streaming
    case error(String)
}

@Observable
@MainActor
final class ChatViewModel {
    let spriteName: String
    var messages: [ChatMessage] = []
    var inputText = ""
    var status: ChatStatus = .idle
    var modelName: String?

    private var sessionId: String?
    private var workingDirectory: String
    private var execSession: ExecSession?
    private var streamTask: Task<Void, Never>?
    private let parser = ClaudeStreamParser()
    private var currentAssistantMessage: ChatMessage?
    private var toolUseIndex: [String: (messageIndex: Int, toolName: String)] = [:]

    init(spriteName: String) {
        self.spriteName = spriteName
        self.workingDirectory = "/home/sprite/project"
    }

    var isStreaming: Bool {
        if case .streaming = status { return true }
        if case .connecting = status { return true }
        return false
    }

    func loadSession(modelContext: ModelContext) {
        let name = spriteName
        let descriptor = FetchDescriptor<SpriteSession>(
            predicate: #Predicate { $0.spriteName == name }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            sessionId = session.claudeSessionId
            workingDirectory = session.workingDirectory
        }
    }

    func sendMessage(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        let userMessage = ChatMessage(role: .user, content: [.text(text)])
        messages.append(userMessage)

        streamTask = Task {
            await executeClaudeCommand(prompt: text, apiClient: apiClient, modelContext: modelContext)
        }
    }

    func interrupt() {
        streamTask?.cancel()
        streamTask = nil
        execSession?.disconnect()
        execSession = nil

        if let msg = currentAssistantMessage {
            msg.isStreaming = false
        }
        currentAssistantMessage = nil
        status = .idle
    }

    // MARK: - Private

    private func executeClaudeCommand(
        prompt: String,
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .connecting

        let escapedPrompt = prompt
            .replacingOccurrences(of: "'", with: "'\\''")

        var command = "mkdir -p \(workingDirectory) && cd \(workingDirectory) && claude -p --verbose --output-format stream-json --dangerously-skip-permissions"
        if let sessionId {
            command += " --resume \(sessionId)"
        }
        command += " '\(escapedPrompt)'"

        guard let claudeToken = apiClient.claudeToken else {
            status = .error("No Claude token configured")
            return
        }

        let env = ["CLAUDE_CODE_OAUTH_TOKEN": claudeToken]
        logger.info("Exec command: \(command)")

        let session = apiClient.createExecSession(
            spriteName: spriteName,
            command: command,
            env: env
        )

        execSession = session
        session.connect()
        logger.info("WebSocket connected")
        status = .streaming

        let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(assistantMessage)
        currentAssistantMessage = assistantMessage

        do {
            for try await data in session.stdout() {
                guard !Task.isCancelled else { break }

                let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count)b>"
                logger.info("Received \(data.count) bytes: \(raw.prefix(500))")
                let events = await parser.parse(data: data)
                logger.info("Parsed \(events.count) events")
                for event in events {
                    handleEvent(event, modelContext: modelContext)
                }
            }

            // Process any remaining buffered data
            let remaining = await parser.flush()
            for event in remaining {
                handleEvent(event, modelContext: modelContext)
            }
            logger.info("Stream ended normally")
        } catch {
            logger.error("Stream error: \(error)")
            if !Task.isCancelled {
                status = .error(error.localizedDescription)
            }
        }

        assistantMessage.isStreaming = false
        currentAssistantMessage = nil
        execSession = nil

        if case .streaming = status {
            status = .idle
        }
    }

    private func handleEvent(_ event: ClaudeStreamEvent, modelContext: ModelContext) {
        switch event {
        case .system(let systemEvent):
            sessionId = systemEvent.sessionId
            modelName = systemEvent.model
            saveSession(modelContext: modelContext)

        case .assistant(let assistantEvent):
            guard let message = currentAssistantMessage else { return }

            for block in assistantEvent.message.content {
                switch block {
                case .text(let text):
                    // Merge consecutive text blocks
                    if case .text(let existing) = message.content.last {
                        message.content[message.content.count - 1] = .text(existing + text)
                    } else {
                        message.content.append(.text(text))
                    }
                case .toolUse(let toolUse):
                    let card = ToolUseCard(
                        toolUseId: toolUse.id,
                        toolName: toolUse.name,
                        input: toolUse.input
                    )
                    message.content.append(.toolUse(card))
                    toolUseIndex[toolUse.id] = (
                        messageIndex: messages.count - 1,
                        toolName: toolUse.name
                    )
                case .unknown:
                    break
                }
            }

        case .user(let toolResultEvent):
            guard let message = currentAssistantMessage else { return }

            for result in toolResultEvent.message.content {
                let toolName = toolUseIndex[result.toolUseId]?.toolName ?? "Unknown"
                let card = ToolResultCard(
                    toolUseId: result.toolUseId,
                    toolName: toolName,
                    content: result.content ?? .null
                )
                message.content.append(.toolResult(card))
            }

        case .result(let resultEvent):
            sessionId = resultEvent.sessionId
            saveSession(modelContext: modelContext)

        case .unknown:
            break
        }
    }

    private func saveSession(modelContext: ModelContext) {
        let name = spriteName
        let descriptor = FetchDescriptor<SpriteSession>(
            predicate: #Predicate { $0.spriteName == name }
        )

        let session: SpriteSession
        if let existing = try? modelContext.fetch(descriptor).first {
            session = existing
        } else {
            session = SpriteSession(spriteName: spriteName, workingDirectory: workingDirectory)
            modelContext.insert(session)
        }

        session.claudeSessionId = sessionId
        session.lastUsed = Date()
        try? modelContext.save()
    }
}
