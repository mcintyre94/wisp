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

    private var sessionId: String?
    private var execSessionId: String?
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

            // Attempt reattach if there's a pending exec session (app was killed mid-stream)
            if let execId = session.execSessionId, execSession == nil, !isStreaming {
                logger.info("[Chat] loadSession found pending execSessionId=\(execId), attempting reattach")
                execSessionId = execId
                streamTask = Task {
                    await reattachToExec(apiClient: apiClient, modelContext: modelContext)
                }
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
        execSessionId = nil
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
        execSessionId = nil
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

    func interrupt(modelContext: ModelContext? = nil) {
        streamTask?.cancel()
        streamTask = nil
        execSession?.disconnect()
        execSession = nil
        execSessionId = nil

        if let msg = currentAssistantMessage {
            msg.isStreaming = false
        }
        currentAssistantMessage = nil
        status = .idle

        if let modelContext {
            let session = fetchOrCreateSession(modelContext: modelContext)
            session.execSessionId = nil
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
        execSessionId = nil

        // Wake sprite with a lightweight exec before running Claude
        let spriteReady = await wakeSprite(apiClient: apiClient)
        guard spriteReady else {
            status = .error("Sprite not responding — try again")
            return
        }

        let escapedPrompt = prompt
            .replacingOccurrences(of: "'", with: "'\\''")

        var command = "mkdir -p \(workingDirectory) && cd \(workingDirectory) && claude -p --verbose --output-format stream-json --dangerously-skip-permissions"

        let modelId = UserDefaults.standard.string(forKey: "claudeModel") ?? ClaudeModel.sonnet.rawValue
        command += " --model \(modelId)"

        let maxTurns = UserDefaults.standard.integer(forKey: "maxTurns")
        if maxTurns > 0 {
            command += " --max-turns \(maxTurns)"
        }

        let customInstructions = UserDefaults.standard.string(forKey: "customInstructions") ?? ""
        if !customInstructions.isEmpty {
            let escapedInstructions = customInstructions.replacingOccurrences(of: "'", with: "'\\''")
            command += " --append-system-prompt '\(escapedInstructions)'"
        }

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
            env: env,
            maxRunAfterDisconnect: 600
        )

        execSession = session
        session.connect()
        logger.info("WebSocket connected")
        status = .streaming

        let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(assistantMessage)
        currentAssistantMessage = assistantMessage

        let streamResult = await processExecStream(session: session, modelContext: modelContext)
        let eid = execSessionId ?? "nil"
        logger.info("[Chat] Main stream ended: result=\(streamResult), execSessionId=\(eid), cancelled=\(Task.isCancelled)")
        assistantMessage.isStreaming = false
        currentAssistantMessage = nil
        execSession = nil

        // Attempt reattach on disconnect if we have an exec session ID
        if case .disconnected = streamResult, let execId = execSessionId, !Task.isCancelled {
            logger.info("[Chat] Disconnected mid-stream, attempting reattach to \(execId)")
            await reattachToExec(apiClient: apiClient, modelContext: modelContext)
            return
        }

        // If timed out with no data, clear Claude lock files and retry once
        if case .timedOut = streamResult, !retriedAfterTimeout, !Task.isCancelled {
            logger.info("Timeout — clearing Claude lock files and retrying")
            retriedAfterTimeout = true
            execSessionId = nil
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
            execSessionId = nil
            saveSession(modelContext: modelContext)
            await executeClaudeCommand(prompt: prompt, apiClient: apiClient, modelContext: modelContext)
            return
        }

        // Clean up exec session ID on normal completion
        execSessionId = nil
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

    /// Result of processing an exec stream
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

    /// Process events from an exec session, returns how the stream ended
    private func processExecStream(session: ExecSession, modelContext: ModelContext) async -> StreamResult {
        var receivedData = false
        var lastPersistTime = Date.distantPast
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if !receivedData {
                logger.warning("Timeout: no data received in 30s")
                session.disconnect()
            }
        }

        do {
            for try await event in session.events() {
                guard !Task.isCancelled else { break }

                switch event {
                case .data(let data):
                    receivedData = true
                    timeoutTask.cancel()

                    let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count)b>"
                    logger.info("Received \(data.count) bytes: \(raw.prefix(500))")
                    let events = await parser.parse(data: data)
                    logger.info("Parsed \(events.count) events")
                    for parsedEvent in events {
                        handleEvent(parsedEvent, modelContext: modelContext)
                    }

                    // Persist messages so they survive app death or navigation away.
                    // Persist immediately on first data, then every second.
                    let now = Date()
                    if now.timeIntervalSince(lastPersistTime) > 1 {
                        lastPersistTime = now
                        persistMessages(modelContext: modelContext)
                    }

                case .sessionInfo(let id):
                    logger.info("[Chat] Got exec session ID from stream: \(id)")
                    execSessionId = id
                    let spriteSession = fetchOrCreateSession(modelContext: modelContext)
                    spriteSession.execSessionId = id
                    try? modelContext.save()
                }
            }

            // Process any remaining buffered data
            let remaining = await parser.flush()
            for event in remaining {
                handleEvent(event, modelContext: modelContext)
            }
            timeoutTask.cancel()
            logger.info("Stream ended normally")
            return Task.isCancelled ? .cancelled : (receivedData ? .completed : .timedOut)
        } catch {
            timeoutTask.cancel()
            logger.error("Stream error: \(Self.sanitize(error.localizedDescription))")
            if Task.isCancelled {
                return .cancelled
            }
            if receivedData {
                // Had data flowing, then lost connection — this is a disconnect
                return .disconnected
            }
            status = .error("No response from Claude — try again")
            return .timedOut
        }
    }

    /// Attempt to reattach to a running exec session after disconnect
    private func reattachToExec(apiClient: SpritesAPIClient, modelContext: ModelContext) async {
        guard let execId = execSessionId else { return }

        status = .reconnecting
        logger.info("[Chat] === REATTACH STARTING for exec session \(execId) ===")

        // Save current messages before modifying anything — if reattach fails,
        // we keep the partial response rather than losing it
        persistMessages(modelContext: modelContext)

        // Mark the old assistant message as no longer streaming
        if let currentMsg = currentAssistantMessage {
            currentMsg.isStreaming = false
            currentAssistantMessage = nil
        }

        // Remember the old assistant message — we'll remove it only if scrollback arrives
        let oldAssistantIndex = messages.lastIndex(where: { $0.role == .assistant })

        // Reset parser state for fresh scrollback replay
        await parser.reset()

        let session = apiClient.attachExecSession(spriteName: spriteName, execSessionId: execId)
        execSession = session
        session.connect()

        // Create a new assistant message for scrollback replay
        let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(assistantMessage)
        currentAssistantMessage = assistantMessage

        // Rebuild tool use index from messages before the new assistant message
        toolUseIndex = [:]
        rebuildToolUseIndex()

        status = .streaming
        let streamResult = await processExecStream(session: session, modelContext: modelContext)

        assistantMessage.isStreaming = false
        currentAssistantMessage = nil
        execSession = nil

        let reattachGotData = !assistantMessage.content.isEmpty
        logger.info("[Chat] Reattach stream ended: result=\(streamResult), gotData=\(reattachGotData)")

        switch streamResult {
        case .completed where reattachGotData:
            // Scrollback arrived — remove the old partial assistant message
            if let oldIdx = oldAssistantIndex, oldIdx < messages.count,
               messages[oldIdx].role == .assistant, messages[oldIdx].id != assistantMessage.id {
                messages.remove(at: oldIdx)
            }
            execSessionId = nil
            saveSession(modelContext: modelContext)
            if case .streaming = status { status = .idle }
            persistMessages(modelContext: modelContext)
        case .disconnected:
            // Remove the empty reattach message, keep the old one
            if !reattachGotData, let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                messages.remove(at: idx)
            }
            // Try again if still have the exec session ID
            if execSessionId != nil && !Task.isCancelled {
                logger.info("Disconnected again during reattach, retrying")
                await reattachToExec(apiClient: apiClient, modelContext: modelContext)
                return
            }
            fallthrough
        default:
            // Reattach failed — remove the empty reattach message, keep old partial response
            if !reattachGotData, let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                messages.remove(at: idx)
            } else if reattachGotData, let oldIdx = oldAssistantIndex, oldIdx < messages.count,
                      messages[oldIdx].role == .assistant, messages[oldIdx].id != assistantMessage.id {
                // Reattach got some data but failed — keep the better one (reattach), remove old
                messages.remove(at: oldIdx)
            }
            execSessionId = nil
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
        session.execSessionId = execSessionId
        session.lastUsed = Date()
        try? modelContext.save()
    }

    /// Wake the sprite and kill any stale Claude processes.
    /// Returns false if the sprite is unresponsive (wake command timed out).
    private func wakeSprite(apiClient: SpritesAPIClient) async -> Bool {
        // Kill any stale Claude process from a previous interrupted session
        logger.info("Killing stale Claude processes")
        await runExecWithTimeout(apiClient: apiClient, command: "pkill claude", timeout: 5)
        logger.info("Waking sprite")
        let woke = await runExecWithTimeout(apiClient: apiClient, command: "echo ready", timeout: 15)
        if woke {
            logger.info("Sprite awake")
        } else {
            logger.warning("Sprite failed to wake within timeout")
        }
        return woke
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
        return !timedOut
    }
}
