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
    private var receivedSystemEvent = false
    private var usedResume = false
    private var queuedPrompt: String?
    private var retriedAfterTimeout = false

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

            if messages.isEmpty {
                let persisted = session.loadMessages()
                messages = persisted.map { ChatMessage(from: $0) }
                rebuildToolUseIndex()
            }
        }
    }

    func persistMessages(modelContext: ModelContext) {
        let persisted = messages.map { $0.toPersisted() }
        let session = fetchOrCreateSession(modelContext: modelContext)
        session.saveMessages(persisted)
        try? modelContext.save()
    }

    func startNewChat(modelContext: ModelContext) {
        interrupt()
        messages = []
        sessionId = nil
        toolUseIndex = [:]
        persistMessages(modelContext: modelContext)

        let session = fetchOrCreateSession(modelContext: modelContext)
        session.claudeSessionId = nil
        try? modelContext.save()
    }

    private func rebuildToolUseIndex() {
        toolUseIndex = [:]
        for (messageIndex, message) in messages.enumerated() {
            for item in message.content {
                if case .toolUse(let card) = item {
                    toolUseIndex[card.toolUseId] = (
                        messageIndex: messageIndex,
                        toolName: card.toolName
                    )
                }
            }
        }
    }

    func sendMessage(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        retriedAfterTimeout = false
        let userMessage = ChatMessage(role: .user, content: [.text(text)])
        messages.append(userMessage)

        if isStreaming {
            queuedPrompt = text
            return
        }

        streamTask = Task {
            await executeClaudeCommand(prompt: text, apiClient: apiClient, modelContext: modelContext)
        }
    }

    func interrupt(modelContext: ModelContext? = nil) {
        streamTask?.cancel()
        streamTask = nil
        execSession?.disconnect()
        execSession = nil

        if let msg = currentAssistantMessage {
            msg.isStreaming = false
        }
        currentAssistantMessage = nil
        status = .idle

        if let modelContext {
            persistMessages(modelContext: modelContext)
        }
    }

    // MARK: - Private

    private func executeClaudeCommand(
        prompt: String,
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .connecting

        // Wake sprite with a lightweight exec before running Claude
        await wakeSprite(apiClient: apiClient)

        let escapedPrompt = prompt
            .replacingOccurrences(of: "'", with: "'\\''")

        var command = "mkdir -p \(workingDirectory) && cd \(workingDirectory) && claude -p --verbose --output-format stream-json --dangerously-skip-permissions"
        usedResume = sessionId != nil
        if let sessionId {
            command += " --resume \(sessionId)"
        }
        command += " '\(escapedPrompt)'"
        receivedSystemEvent = false

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

        // Timeout if no data arrives within 30 seconds
        var receivedData = false
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if !receivedData {
                logger.warning("Timeout: no data received in 30s")
                session.disconnect()
            }
        }

        do {
            for try await data in session.stdout() {
                guard !Task.isCancelled else { break }
                receivedData = true
                timeoutTask.cancel()

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
            logger.error("Stream error: \(Self.sanitize(error.localizedDescription))")
            if !Task.isCancelled {
                status = .error(receivedData ? "Connection lost" : "No response from Claude — try again")
            }
        }
        timeoutTask.cancel()

        assistantMessage.isStreaming = false
        currentAssistantMessage = nil
        execSession = nil

        // If timed out with no data, clear Claude lock files and retry once
        if !receivedData && !retriedAfterTimeout && !Task.isCancelled {
            logger.info("Timeout — clearing Claude lock files and retrying")
            retriedAfterTimeout = true
            status = .connecting
            if let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                messages.remove(at: idx)
            }
            let notice = ChatMessage(role: .system, content: [.text("Slow to respond — retrying...")])
            messages.append(notice)
            await runExecWithTimeout(apiClient: apiClient, command: "rm -rf /home/sprite/.local/state/claude/locks", timeout: 15)
            await executeClaudeCommand(prompt: prompt, apiClient: apiClient, modelContext: modelContext)
            return
        }

        // If --resume failed (no system event received), retry without it
        if usedResume && !receivedSystemEvent && !Task.isCancelled {
            logger.info("Stale session detected, retrying without --resume")
            // Replace the failed assistant message with a notice
            if let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                messages.remove(at: idx)
            }
            let notice = ChatMessage(role: .system, content: [.text("Session expired — starting fresh")])
            messages.append(notice)
            sessionId = nil
            saveSession(modelContext: modelContext)
            await executeClaudeCommand(prompt: prompt, apiClient: apiClient, modelContext: modelContext)
            return
        }

        if case .streaming = status {
            status = .idle
        }

        persistMessages(modelContext: modelContext)

        if let queued = queuedPrompt, !Task.isCancelled {
            queuedPrompt = nil
            await executeClaudeCommand(prompt: queued, apiClient: apiClient, modelContext: modelContext)
        }
    }

    private func handleEvent(_ event: ClaudeStreamEvent, modelContext: ModelContext) {
        switch event {
        case .system(let systemEvent):
            receivedSystemEvent = true
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
            if resultEvent.isError == true {
                logger.error("Claude result error: \(resultEvent.result ?? "unknown")")
            }
            sessionId = resultEvent.sessionId
            saveSession(modelContext: modelContext)

        case .unknown:
            break
        }
    }

    private func fetchOrCreateSession(modelContext: ModelContext) -> SpriteSession {
        let name = spriteName
        let descriptor = FetchDescriptor<SpriteSession>(
            predicate: #Predicate { $0.spriteName == name }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let session = SpriteSession(spriteName: spriteName, workingDirectory: workingDirectory)
        modelContext.insert(session)
        return session
    }

    private func saveSession(modelContext: ModelContext) {
        let session = fetchOrCreateSession(modelContext: modelContext)
        session.claudeSessionId = sessionId
        session.lastUsed = Date()
        try? modelContext.save()
    }

    private func wakeSprite(apiClient: SpritesAPIClient) async {
        // Kill any stale Claude process from a previous interrupted session
        logger.info("Killing stale Claude processes")
        await runExecWithTimeout(apiClient: apiClient, command: "pkill claude", timeout: 15)
        logger.info("Waking sprite")
        await runExecWithTimeout(apiClient: apiClient, command: "echo ready", timeout: 15)
        logger.info("Sprite awake")
    }

    private static func sanitize(_ string: String) -> String {
        string.replacingOccurrences(
            of: "CLAUDE_CODE_OAUTH_TOKEN[=%][^&\\s,}]*",
            with: "CLAUDE_CODE_OAUTH_TOKEN=<redacted>",
            options: .regularExpression
        )
    }

    private func runExecWithTimeout(apiClient: SpritesAPIClient, command: String, timeout: Int) async {
        let session = apiClient.createExecSession(spriteName: spriteName, command: command)
        session.connect()
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            session.disconnect()
        }
        do {
            for try await _ in session.stdout() {}
        } catch {
            // Expected — either command failed or timeout disconnected
        }
        timeoutTask.cancel()
    }
}
