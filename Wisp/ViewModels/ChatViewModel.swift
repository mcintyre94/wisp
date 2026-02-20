import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.wisp.app", category: "Chat")

enum ChatStatus: Sendable {
    case idle
    case connecting
    case streaming
    case reconnecting
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

    private let serviceName = "claude"
    private var sessionId: String?
    private var workingDirectory: String
    private var streamTask: Task<Void, Never>?
    private let parser = ClaudeStreamParser()
    private var currentAssistantMessage: ChatMessage?
    private var toolUseIndex: [String: (messageIndex: Int, toolName: String)] = [:]
    private var receivedSystemEvent = false
    private var receivedResultEvent = false
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
        if case .reconnecting = status { return true }
        return false
    }

    func loadSession(apiClient: SpritesAPIClient, modelContext: ModelContext) {
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

    func startNewChat(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        interrupt(apiClient: apiClient)
        messages = []
        sessionId = nil
        toolUseIndex = [:]
        persistMessages(modelContext: modelContext)

        let session = fetchOrCreateSession(modelContext: modelContext)
        session.claudeSessionId = nil
        session.execSessionId = nil
        workingDirectory = session.workingDirectory
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
        persistMessages(modelContext: modelContext)

        if isStreaming {
            queuedPrompt = text
            return
        }

        streamTask = Task {
            await executeClaudeCommand(prompt: text, apiClient: apiClient, modelContext: modelContext)
        }
    }

    func resumeAfterBackground(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        guard isStreaming else { return }
        // Cancel the stale stream and reconnect via service logs
        streamTask?.cancel()
        streamTask = Task {
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext)
        }
    }

    func interrupt(apiClient: SpritesAPIClient? = nil, modelContext: ModelContext? = nil) {
        streamTask?.cancel()
        streamTask = nil

        if let msg = currentAssistantMessage {
            msg.isStreaming = false
        }
        currentAssistantMessage = nil
        status = .idle

        // Delete the service to stop it
        if let apiClient {
            let sName = spriteName
            let svcName = serviceName
            Task {
                try? await apiClient.deleteService(spriteName: sName, serviceName: svcName)
            }
        }

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

        // Delete any existing service so the PUT creates a fresh one
        try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)

        guard let claudeToken = apiClient.claudeToken else {
            status = .error("No Claude token configured")
            return
        }

        let escapedPrompt = prompt
            .replacingOccurrences(of: "'", with: "'\\''")

        // Build the full bash -c command with env vars inlined
        var commandParts: [String] = [
            "export CLAUDE_CODE_OAUTH_TOKEN='\(claudeToken)'",
            "mkdir -p \(workingDirectory)",
            "cd \(workingDirectory)",
        ]

        var claudeCmd = "claude -p --verbose --output-format stream-json --dangerously-skip-permissions"

        let modelId = UserDefaults.standard.string(forKey: "claudeModel") ?? ClaudeModel.sonnet.rawValue
        claudeCmd += " --model \(modelId)"

        let maxTurns = UserDefaults.standard.integer(forKey: "maxTurns")
        if maxTurns > 0 {
            claudeCmd += " --max-turns \(maxTurns)"
        }

        let customInstructions = UserDefaults.standard.string(forKey: "customInstructions") ?? ""
        if !customInstructions.isEmpty {
            let escapedInstructions = customInstructions.replacingOccurrences(of: "'", with: "'\\''")
            claudeCmd += " --append-system-prompt '\(escapedInstructions)'"
        }

        usedResume = sessionId != nil
        if let sessionId {
            claudeCmd += " --resume \(sessionId)"
        }
        claudeCmd += " '\(escapedPrompt)'"

        commandParts.append(claudeCmd)
        let fullCommand = commandParts.joined(separator: " && ")

        receivedSystemEvent = false
        receivedResultEvent = false

        logger.info("Service command: \(Self.sanitize(fullCommand))")

        let config = ServiceRequest(
            cmd: "bash",
            args: ["-c", fullCommand],
            needs: nil,
            httpPort: nil
        )

        let stream = apiClient.streamService(
            spriteName: spriteName,
            serviceName: serviceName,
            config: config
        )

        let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(assistantMessage)
        currentAssistantMessage = assistantMessage

        let streamResult = await processServiceStream(stream: stream, modelContext: modelContext)
        logger.info("[Chat] Main stream ended: result=\(streamResult), cancelled=\(Task.isCancelled)")
        assistantMessage.isStreaming = false
        currentAssistantMessage = nil

        // Attempt reconnection on disconnect
        if case .disconnected = streamResult, !Task.isCancelled {
            logger.info("[Chat] Disconnected mid-stream, attempting reconnect via service logs")
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext)
            return
        }

        // If timed out with no data, clear Claude lock files and retry once
        if case .timedOut = streamResult, !retriedAfterTimeout, !Task.isCancelled {
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

        saveSession(modelContext: modelContext)

        if case .streaming = status {
            status = .idle
        }

        persistMessages(modelContext: modelContext)

        if let queued = queuedPrompt, !Task.isCancelled {
            queuedPrompt = nil
            await executeClaudeCommand(prompt: queued, apiClient: apiClient, modelContext: modelContext)
        }
    }

    /// Result of processing a service stream
    private enum StreamResult: CustomStringConvertible {
        case completed
        case timedOut
        case disconnected
        case cancelled

        var description: String {
            switch self {
            case .completed: "completed"
            case .timedOut: "timedOut"
            case .disconnected: "disconnected"
            case .cancelled: "cancelled"
            }
        }
    }

    /// Process events from a service log stream (two-level NDJSON parsing)
    private func processServiceStream(
        stream: AsyncThrowingStream<ServiceLogEvent, Error>,
        modelContext: ModelContext
    ) async -> StreamResult {
        var receivedData = false
        var lastPersistTime = Date.distantPast
        var eventCount = 0

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if !receivedData {
                logger.warning("No service data received in 30s")
            }
        }

        do {
            for try await event in stream {
                guard !Task.isCancelled else { break }
                eventCount += 1

                switch event.type {
                case .stdout:
                    guard let text = event.data else { continue }
                    receivedData = true
                    timeoutTask.cancel()
                    if case .connecting = status { status = .streaming }

                    // Two-level NDJSON: ServiceLogEvent.data contains Claude NDJSON.
                    // The logs endpoint prefixes each line with a timestamp
                    // (e.g. "2026-02-19T09:13:24.665Z [stdout] {...}"), so strip it.
                    var dataStr = Self.stripLogTimestamps(text)
                    if !dataStr.hasSuffix("\n") {
                        dataStr += "\n"
                    }
                    let data = Data(dataStr.utf8)
                    let events = await parser.parse(data: data)
                    for parsedEvent in events {
                        handleEvent(parsedEvent, modelContext: modelContext)
                    }

                    // Periodic persistence
                    let now = Date()
                    if now.timeIntervalSince(lastPersistTime) > 1 {
                        lastPersistTime = now
                        persistMessages(modelContext: modelContext)
                    }

                case .stderr:
                    receivedData = true
                    timeoutTask.cancel()
                    if case .connecting = status { status = .streaming }
                    if let text = event.data {
                        logger.warning("Service stderr: \(text.prefix(500), privacy: .public)")
                    }

                case .exit:
                    timeoutTask.cancel()
                    let code = event.exitCode ?? -1
                    logger.info("Service exit: code=\(code)")
                    // Flush any remaining buffered data
                    let remaining = await parser.flush()
                    for e in remaining {
                        handleEvent(e, modelContext: modelContext)
                    }

                case .error:
                    timeoutTask.cancel()
                    logger.error("Service error: \(event.data ?? "unknown", privacy: .public)")
                    if !receivedData {
                        status = .error(event.data ?? "Service error")
                    }

                case .complete:
                    timeoutTask.cancel()

                case .started:
                    if case .connecting = status { status = .streaming }

                case .stopping, .stopped:
                    break

                case .unknown:
                    break
                }
            }

            // Flush parser on stream end
            let remaining = await parser.flush()
            for e in remaining {
                handleEvent(e, modelContext: modelContext)
            }
            timeoutTask.cancel()

            logger.info("Stream ended: events=\(eventCount) receivedData=\(receivedData)")
            return Task.isCancelled ? .cancelled : (receivedData ? .completed : .timedOut)
        } catch {
            timeoutTask.cancel()
            logger.error("Stream error after \(eventCount) events: \(Self.sanitize(error.localizedDescription), privacy: .public)")
            if Task.isCancelled { return .cancelled }
            if receivedData { return .disconnected }
            status = .error("No response from Claude — try again")
            return .timedOut
        }
    }

    /// Reconnect to a running service via GET logs (provides full history)
    private func reconnectToServiceLogs(
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .reconnecting
        logger.info("[Chat] Reconnecting to service logs")

        persistMessages(modelContext: modelContext)

        // Mark old assistant message as no longer streaming
        if let currentMsg = currentAssistantMessage {
            currentMsg.isStreaming = false
            currentAssistantMessage = nil
        }

        let oldAssistantIndex = messages.lastIndex(where: { $0.role == .assistant })

        // Reset parser for fresh replay from logs
        await parser.reset()

        // Create new assistant message for replayed content
        let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(assistantMessage)
        currentAssistantMessage = assistantMessage

        toolUseIndex = [:]
        rebuildToolUseIndex()

        let stream = apiClient.streamServiceLogs(
            spriteName: spriteName,
            serviceName: serviceName
        )

        status = .streaming
        let streamResult = await processServiceStream(stream: stream, modelContext: modelContext)

        assistantMessage.isStreaming = false
        currentAssistantMessage = nil

        let reattachGotData = !assistantMessage.content.isEmpty
        logger.info("[Chat] Reconnect stream ended: result=\(streamResult), gotData=\(reattachGotData)")

        switch streamResult {
        case .completed where reattachGotData:
            // Scrollback arrived — remove the old partial assistant message
            if let oldIdx = oldAssistantIndex, oldIdx < messages.count,
               messages[oldIdx].role == .assistant, messages[oldIdx].id != assistantMessage.id {
                messages.remove(at: oldIdx)
            }
            saveSession(modelContext: modelContext)
            if case .streaming = status { status = .idle }
            persistMessages(modelContext: modelContext)

        case .disconnected:
            // Remove empty reconnect message, keep old one
            if !reattachGotData, let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                messages.remove(at: idx)
            }
            // If we already got the result event, treat as completed — don't reconnect
            if receivedResultEvent {
                logger.info("[Chat] Disconnected after result event, treating as completed")
                if let oldIdx = oldAssistantIndex, oldIdx < messages.count,
                   messages[oldIdx].role == .assistant, messages[oldIdx].id != assistantMessage.id {
                    messages.remove(at: oldIdx)
                }
                saveSession(modelContext: modelContext)
                status = .idle
                persistMessages(modelContext: modelContext)
                break
            }
            // Retry reconnection
            if !Task.isCancelled {
                logger.info("Disconnected again during reconnect, retrying")
                await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext)
                return
            }
            fallthrough

        default:
            // Reconnect failed — remove empty message, keep old partial
            if !reattachGotData, let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                messages.remove(at: idx)
            } else if reattachGotData, let oldIdx = oldAssistantIndex, oldIdx < messages.count,
                      messages[oldIdx].role == .assistant, messages[oldIdx].id != assistantMessage.id {
                messages.remove(at: oldIdx)
            }
            saveSession(modelContext: modelContext)
            if !Task.isCancelled {
                status = .idle
            }
            persistMessages(modelContext: modelContext)
        }

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
                logger.error("Claude result error: \(resultEvent.result ?? "unknown", privacy: .public)")
            }
            receivedResultEvent = true
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

    /// Strip timestamp prefixes from service log lines.
    /// The logs endpoint returns lines like "2026-02-19T09:13:24.665Z [stdout] {...}"
    /// but the PUT stream returns just "{...}". This normalizes both formats.
    private static func stripLogTimestamps(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                // Match "TIMESTAMP [stdout] " or "TIMESTAMP [stderr] " prefix
                if let range = line.range(of: #"^\d{4}-\d{2}-\d{2}T[\d:.]+Z \[(stdout|stderr)\] "#, options: .regularExpression) {
                    return String(line[range.upperBound...])
                }
                return String(line)
            }
            .joined(separator: "\n")
    }

    private static func sanitize(_ string: String) -> String {
        string.replacingOccurrences(
            of: "CLAUDE_CODE_OAUTH_TOKEN[=%][^&\\s,}]*",
            with: "CLAUDE_CODE_OAUTH_TOKEN=<redacted>",
            options: .regularExpression
        )
    }

    /// Returns true if the command completed, false if it timed out.
    @discardableResult
    private func runExecWithTimeout(apiClient: SpritesAPIClient, command: String, timeout: Int) async -> Bool {
        let session = apiClient.createExecSession(spriteName: spriteName, command: command)
        session.connect()
        var timedOut = false
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            timedOut = true
            session.disconnect()
        }
        do {
            for try await _ in session.events() {}
        } catch {
            // Expected — either command failed or timeout disconnected
        }
        timeoutTask.cancel()
        session.disconnect()
        return !timedOut
    }
}
