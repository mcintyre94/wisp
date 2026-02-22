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

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

@Observable
@MainActor
final class ChatViewModel {
    let spriteName: String
    let chatId: UUID
    var messages: [ChatMessage] = []
    var inputText = ""
    var status: ChatStatus = .idle
    var modelName: String?
    var remoteSessions: [ClaudeSessionEntry] = []
    var isLoadingRemoteSessions = false
    var isLoadingHistory = false

    private var serviceName: String
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

    init(spriteName: String, chatId: UUID, currentServiceName: String?, workingDirectory: String) {
        self.spriteName = spriteName
        self.chatId = chatId
        self.serviceName = currentServiceName ?? "wisp-claude-\(UUID().uuidString.prefix(8).lowercased())"
        self.workingDirectory = workingDirectory
    }

    var isStreaming: Bool {
        if case .streaming = status { return true }
        if case .connecting = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    func loadSession(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        guard let chat = fetchChat(modelContext: modelContext) else { return }

        sessionId = chat.claudeSessionId
        workingDirectory = chat.workingDirectory
        if let svcName = chat.currentServiceName {
            serviceName = svcName
        }

        if messages.isEmpty {
            let persisted = chat.loadMessages()
            messages = persisted.map { ChatMessage(from: $0) }
            rebuildToolUseIndex()
        }

        if inputText.isEmpty, let draft = chat.draftInputText, !draft.isEmpty {
            inputText = draft
        }
    }

    func saveDraft(modelContext: ModelContext) {
        guard let chat = fetchChat(modelContext: modelContext) else { return }
        chat.draftInputText = inputText.isEmpty ? nil : inputText
        try? modelContext.save()
    }

    func fetchRemoteSessions(apiClient: SpritesAPIClient, existingSessionIds: Set<String>) {
        guard !isLoadingRemoteSessions else { return }
        isLoadingRemoteSessions = true

        Task {
            defer { isLoadingRemoteSessions = false }

            // Claude Code stores sessions as {uuid}.jsonl files under the project dir.
            let encodedPath = workingDirectory
                .replacingOccurrences(of: "/", with: "-")
            let projectDir = "/home/sprite/.claude/projects/\(encodedPath)"

            // For each session .jsonl, extract the first user message and the file's last-modified time.
            let command = """
            for f in \(projectDir)/*.jsonl; do [ -f "$f" ] && \
            mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) && \
            grep -m1 '"type":"user"' "$f" | \
            jq -c --arg mt "$mtime" '{sessionId,timestamp,prompt:.message.content,mtime:($mt|tonumber)}'; \
            done 2>/dev/null
            """

            let (output, _) = await apiClient.runExec(
                spriteName: spriteName,
                command: command,
                timeout: 15
            )

            guard !output.isEmpty else { return }

            // Each line from jq is: {"sessionId":"...","timestamp":"...","prompt":"..."}
            var entries: [ClaudeSessionEntry] = []
            for line in output.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode(SessionSummary.self, from: data),
                      let sessionId = parsed.sessionId, !sessionId.isEmpty
                else { continue }
                let modifiedDate = parsed.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                entries.append(ClaudeSessionEntry(
                    sessionId: sessionId,
                    firstPrompt: parsed.prompt,
                    messageCount: nil,
                    modifiedDate: modifiedDate,
                    gitBranch: nil
                ))
            }

            let filtered = entries
                .filter { !existingSessionIds.contains($0.sessionId) }
                .sorted { a, b in
                    (a.modifiedDate ?? .distantPast) > (b.modifiedDate ?? .distantPast)
                }
            remoteSessions = Array(filtered.prefix(5))
            logger.info("Found \(entries.count) remote sessions, \(self.remoteSessions.count) available to resume")
        }
    }

    func selectRemoteSession(_ entry: ClaudeSessionEntry, apiClient: SpritesAPIClient, modelContext: ModelContext) {
        sessionId = entry.sessionId
        remoteSessions = []
        saveSession(modelContext: modelContext)

        Task {
            await loadRemoteHistory(apiClient: apiClient, modelContext: modelContext)
        }
    }

    private func loadRemoteHistory(apiClient: SpritesAPIClient, modelContext: ModelContext) async {
        guard let sessionId else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let encodedPath = workingDirectory
            .replacingOccurrences(of: "/", with: "-")
        let projectDir = "/home/sprite/.claude/projects/\(encodedPath)"
        let command = "cat '\(projectDir)/\(sessionId).jsonl' 2>/dev/null"

        let (output, _) = await apiClient.runExec(
            spriteName: spriteName,
            command: command,
            timeout: 15
        )

        guard !output.isEmpty else { return }

        let parsed = Self.parseSessionJSONL(output)
        guard !parsed.isEmpty else { return }

        messages = parsed
        rebuildToolUseIndex()
        persistMessages(modelContext: modelContext)
    }

    /// Parse a Claude session JSONL string into ChatMessages.
    /// Resilient — skips any lines that fail to decode.
    static func parseSessionJSONL(_ jsonl: String) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var currentAssistant: ChatMessage?
        var toolUseNames: [String: String] = [:]  // toolUseId -> toolName

        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(SessionJSONLLine.self, from: data),
                  let type = entry.type
            else { continue }

            switch type {
            case "user":
                guard let content = entry.message?.content else { continue }
                switch content {
                case .string(let text):
                    // User prompt — finalize any current assistant message
                    if let assistant = currentAssistant {
                        messages.append(assistant)
                        currentAssistant = nil
                    }
                    let msg = ChatMessage(role: .user, content: [.text(text)])
                    messages.append(msg)

                case .blocks(let blocks):
                    // Tool results — append to current assistant message
                    let assistant = currentAssistant ?? ChatMessage(role: .assistant)
                    if currentAssistant == nil {
                        currentAssistant = assistant
                    }
                    for block in blocks {
                        guard block.type == "tool_result",
                              let toolUseId = block.toolUseId
                        else { continue }
                        let toolName = toolUseNames[toolUseId] ?? "Tool"
                        let resultContent: JSONValue
                        if let c = block.content {
                            resultContent = .string(c.textValue)
                        } else {
                            resultContent = .null
                        }
                        let card = ToolResultCard(
                            toolUseId: toolUseId,
                            toolName: toolName,
                            content: resultContent
                        )
                        assistant.content.append(.toolResult(card))
                    }
                }

            case "assistant":
                guard let blocks = entry.message?.content,
                      case .blocks(let contentBlocks) = blocks
                else { continue }

                let assistant = currentAssistant ?? ChatMessage(role: .assistant)
                if currentAssistant == nil {
                    currentAssistant = assistant
                }

                for block in contentBlocks {
                    switch block.type {
                    case "text":
                        guard let text = block.text, !text.isEmpty else { continue }
                        // Merge consecutive text blocks
                        if case .text(let existing) = assistant.content.last {
                            assistant.content[assistant.content.count - 1] = .text(existing + text)
                        } else {
                            assistant.content.append(.text(text))
                        }
                    case "tool_use":
                        guard let id = block.id, let name = block.name else { continue }
                        toolUseNames[id] = name
                        let card = ToolUseCard(
                            toolUseId: id,
                            toolName: name,
                            input: block.input ?? .null
                        )
                        assistant.content.append(.toolUse(card))
                    default:
                        // Skip thinking, server_tool_use, etc.
                        break
                    }
                }

            default:
                // Skip system, result, progress, etc.
                continue
            }
        }

        // Finalize any trailing assistant message
        if let assistant = currentAssistant {
            messages.append(assistant)
        }

        return messages
    }

    func persistMessages(modelContext: ModelContext) {
        let persisted = messages.map { $0.toPersisted() }
        guard let chat = fetchChat(modelContext: modelContext) else { return }
        chat.saveMessages(persisted)
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
        saveDraft(modelContext: modelContext)
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

    /// Stop streaming without deleting the service (used when switching away from a chat).
    /// Returns true if the VM was actively streaming when detached.
    @discardableResult
    func detach(modelContext: ModelContext? = nil) -> Bool {
        let wasStreaming = isStreaming

        streamTask?.cancel()
        streamTask = nil

        if let msg = currentAssistantMessage {
            msg.isStreaming = false
        }
        currentAssistantMessage = nil
        status = .idle

        if let modelContext {
            persistMessages(modelContext: modelContext)
        }
        return wasStreaming
    }

    func interrupt(apiClient: SpritesAPIClient? = nil, modelContext: ModelContext? = nil) {
        detach(modelContext: modelContext)

        // Delete the service to stop it
        if let apiClient {
            let sName = spriteName
            let svcName = serviceName
            Task {
                try? await apiClient.deleteService(spriteName: sName, serviceName: svcName)
            }
        }
    }

    /// Attempt to reconnect to an existing service when switching back to this chat.
    /// Called after loadSession — checks if service logs might have new content.
    func reconnectIfNeeded(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        guard !isStreaming, !messages.isEmpty else { return }

        streamTask = Task {
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext)
        }
    }

    // MARK: - Private

    private func executeClaudeCommand(
        prompt: String,
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .connecting

        // Delete old service, then use a fresh name so logs start clean
        let oldServiceName = serviceName
        serviceName = "wisp-claude-\(UUID().uuidString.prefix(8).lowercased())"
        try? await apiClient.deleteService(spriteName: spriteName, serviceName: oldServiceName)

        // Persist the new service name immediately for reconnect
        saveSession(modelContext: modelContext)

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

        let streamResult = await processServiceStream(stream: stream, modelContext: modelContext, breakOnComplete: true)
        logger.info("[Chat] Main stream ended: result=\(streamResult), cancelled=\(Task.isCancelled)")

        // If cancelled (e.g. by resumeAfterBackground), bail out immediately.
        // The reconnect task now owns the assistant message and shared state.
        guard !Task.isCancelled else { return }

        assistantMessage.isStreaming = false
        if currentAssistantMessage?.id == assistantMessage.id {
            currentAssistantMessage = nil
        }

        // Attempt reconnection on disconnect
        if case .disconnected = streamResult {
            logger.info("[Chat] Disconnected mid-stream, attempting reconnect via service logs")
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext)
            return
        }

        // If timed out with no data, clear Claude lock files and retry once
        if case .timedOut = streamResult, !retriedAfterTimeout {
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
        if usedResume && !receivedSystemEvent {
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

        if let queued = queuedPrompt {
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

    /// Process events from a service log stream (two-level NDJSON parsing).
    /// `breakOnComplete`: when true, exit the loop on a `.complete` event. Used for the
    /// initial PUT stream where `.complete` means the service process ended. For GET logs
    /// reconnection, `.complete` just means the log replay finished and the stream ends
    /// naturally, so we leave it as false.
    private func processServiceStream(
        stream: AsyncThrowingStream<ServiceLogEvent, Error>,
        modelContext: ModelContext,
        breakOnComplete: Bool = false
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
            streamLoop: for try await event in stream {
                guard !Task.isCancelled else { break streamLoop }
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

                    // Result event means Claude is done — stop waiting for more
                    if receivedResultEvent { break streamLoop }

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
                    if breakOnComplete {
                        let flushed = await parser.flush()
                        for e in flushed {
                            handleEvent(e, modelContext: modelContext)
                        }
                        break streamLoop
                    }

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

    /// Reconnect to a running service via GET logs (provides full history).
    /// Reuses the existing assistant message — clears its content and replays
    /// the full service log into it, avoiding duplicate messages entirely.
    private func reconnectToServiceLogs(
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .reconnecting
        logger.info("[Chat] Reconnecting to service logs")

        receivedSystemEvent = false
        receivedResultEvent = false

        // Reuse the existing assistant message — clear and replay into it
        let assistantMessage: ChatMessage
        if let existing = currentAssistantMessage {
            assistantMessage = existing
            assistantMessage.content = []
            assistantMessage.isStreaming = true
        } else if let last = messages.last(where: { $0.role == .assistant }) {
            assistantMessage = last
            assistantMessage.content = []
            assistantMessage.isStreaming = true
            currentAssistantMessage = last
        } else {
            // No assistant message exists (shouldn't happen, but be safe)
            assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
            messages.append(assistantMessage)
            currentAssistantMessage = assistantMessage
        }

        // Reset parser and tool index for fresh replay
        await parser.reset()
        toolUseIndex = [:]
        rebuildToolUseIndex()

        let stream = apiClient.streamServiceLogs(
            spriteName: spriteName,
            serviceName: serviceName
        )

        status = .streaming
        let streamResult = await processServiceStream(stream: stream, modelContext: modelContext)

        assistantMessage.isStreaming = false
        if currentAssistantMessage?.id == assistantMessage.id {
            currentAssistantMessage = nil
        }

        logger.info("[Chat] Reconnect stream ended: result=\(streamResult), content=\(assistantMessage.content.count)")

        // Retry on disconnect if Claude hasn't finished
        if case .disconnected = streamResult, !receivedResultEvent, !Task.isCancelled {
            logger.info("Disconnected again during reconnect, retrying")
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext)
            return
        }

        // Finalize
        saveSession(modelContext: modelContext)
        if !Task.isCancelled {
            status = .idle
        }
        persistMessages(modelContext: modelContext)

        if let queued = queuedPrompt, !Task.isCancelled {
            queuedPrompt = nil
            await executeClaudeCommand(prompt: queued, apiClient: apiClient, modelContext: modelContext)
        }
    }

    func handleEvent(_ event: ClaudeStreamEvent, modelContext: ModelContext) {
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
            currentAssistantMessage?.isStreaming = false
            sessionId = resultEvent.sessionId
            saveSession(modelContext: modelContext)

        case .unknown:
            break
        }
    }

    private func fetchChat(modelContext: ModelContext) -> SpriteChat? {
        let id = chatId
        let descriptor = FetchDescriptor<SpriteChat>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func saveSession(modelContext: ModelContext) {
        guard let chat = fetchChat(modelContext: modelContext) else { return }
        chat.claudeSessionId = sessionId
        chat.currentServiceName = serviceName
        chat.lastUsed = Date()
        try? modelContext.save()
    }

    /// Strip timestamp prefixes from service log lines.
    /// The logs endpoint returns lines like "2026-02-19T09:13:24.665Z [stdout] {...}"
    /// but the PUT stream returns just "{...}". This normalizes both formats.
    nonisolated static func stripLogTimestamps(_ text: String) -> String {
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

    nonisolated static func sanitize(_ string: String) -> String {
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

    #if DEBUG
    func setCurrentAssistantMessage(_ message: ChatMessage?) {
        currentAssistantMessage = message
    }
    #endif
}
