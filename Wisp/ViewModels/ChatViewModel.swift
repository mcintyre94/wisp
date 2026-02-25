import Foundation
import FoundationModels
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
    private var turnHasMutations = false
    private var pendingForkContext: String?
    private var apiClient: SpritesAPIClient?
    /// UUIDs of Claude NDJSON events already processed.
    /// Used by reconnect to skip already-handled events instead of clearing content.
    private var processedEventUUIDs: Set<String> = []

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
        self.apiClient = apiClient
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

        if let context = chat.forkContext, !context.isEmpty {
            let notice = ChatMessage(role: .system, content: [.text("Forked from a previous chat")])
            messages.insert(notice, at: 0)
            pendingForkContext = context
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
            // Only reconnect if the service exists (running or stopped with logs)
            guard let _ = try? await apiClient.getServiceStatus(spriteName: spriteName, serviceName: serviceName)
            else { return }

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

        var fullPrompt = prompt
        if let forkCtx = pendingForkContext {
            fullPrompt = forkCtx + "\n\n---\n\n" + prompt
            pendingForkContext = nil
            if let chat = fetchChat(modelContext: modelContext) {
                chat.forkContext = nil
                try? modelContext.save()
            }
        }

        let escapedPrompt = fullPrompt
            .replacingOccurrences(of: "'", with: "'\\''")

        // Build the full bash -c command with env vars inlined
        var commandParts: [String] = [
            "export CLAUDE_CODE_OAUTH_TOKEN='\(claudeToken)'",
            "mkdir -p \(workingDirectory)",
            "cd \(workingDirectory)",
        ]

        let gitName = UserDefaults.standard.string(forKey: "gitName") ?? ""
        let gitEmail = UserDefaults.standard.string(forKey: "gitEmail") ?? ""
        if !gitName.isEmpty {
            let escapedName = gitName.replacingOccurrences(of: "'", with: "'\\''")
            commandParts.append("git config --global user.name '\(escapedName)'")
        }
        if !gitEmail.isEmpty {
            let escapedEmail = gitEmail.replacingOccurrences(of: "'", with: "'\\''")
            commandParts.append("git config --global user.email '\(escapedEmail)'")
        }

        commandParts.append(Self.mcpSetupCommand)

        var claudeCmd = "claude -p --verbose --output-format stream-json --dangerously-skip-permissions"
        claudeCmd += " --mcp-config ~/.wisp/mcp_config.json"

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
        turnHasMutations = false
        processedEventUUIDs = []

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
        let uuidCount = processedEventUUIDs.count
        logger.info("[Chat] Main stream ended: result=\(streamResult), cancelled=\(Task.isCancelled), uuids=\(uuidCount)")

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
    /// Events whose UUID is in `processedEventUUIDs` are skipped (but system/result
    /// flags are still tracked). New event UUIDs are added to `processedEventUUIDs`
    /// as they are handled, so reconnect replays never duplicate content.
    private func processServiceStream(
        stream: AsyncThrowingStream<ServiceLogEvent, Error>,
        modelContext: ModelContext,
        breakOnComplete: Bool = false
    ) async -> StreamResult {
        var receivedData = false
        var lastPersistTime = Date.distantPast
        var eventCount = 0
        var skippedCount = 0

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if !receivedData {
                logger.warning("No service data received in 30s")
            }
        }

        func handleOrSkip(_ parsedEvent: ClaudeStreamEvent) {
            // Deduplicate by UUID — skip events we've already processed
            if let uuid = parsedEvent.uuid, processedEventUUIDs.contains(uuid) {
                skippedCount += 1
                // Still track critical flags on skipped events
                switch parsedEvent {
                case .system(let se):
                    receivedSystemEvent = true
                    sessionId = se.sessionId
                    modelName = se.model
                case .result(let re):
                    receivedResultEvent = true
                    sessionId = re.sessionId
                default: break
                }
                return
            }
            if let uuid = parsedEvent.uuid {
                processedEventUUIDs.insert(uuid)
            }
            handleEvent(parsedEvent, modelContext: modelContext)
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
                        handleOrSkip(parsedEvent)
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
                        handleOrSkip(e)
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
                            handleOrSkip(e)
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
                handleOrSkip(e)
            }
            timeoutTask.cancel()

            let uuidCount = processedEventUUIDs.count
            logger.info("Stream ended: events=\(eventCount) receivedData=\(receivedData) skipped=\(skippedCount) uuids=\(uuidCount)")
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
    /// Skips already-processed Claude events (tracked by `totalClaudeEventsProcessed`)
    /// so existing content stays on screen with no flash. Only genuinely new events
    /// are appended. If the service is still running after a replay, polls and
    /// re-replays until the service stops or a result event arrives.
    private func reconnectToServiceLogs(
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .reconnecting
        let priorUUIDs = processedEventUUIDs.count
        logger.info("[Chat] Reconnecting to service logs (\(priorUUIDs) prior UUIDs)")

        // Ensure we have an assistant message to append into.
        // Only clear content if we have no prior events to skip (cold reconnect).
        let assistantMessage: ChatMessage
        let hasPriorEvents = !processedEventUUIDs.isEmpty
        if let existing = currentAssistantMessage {
            assistantMessage = existing
            if !hasPriorEvents { assistantMessage.content = [] }
            assistantMessage.isStreaming = true
        } else if let last = messages.last(where: { $0.role == .assistant }) {
            assistantMessage = last
            if !hasPriorEvents { assistantMessage.content = [] }
            assistantMessage.isStreaming = true
            currentAssistantMessage = last
        } else {
            assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
            messages.append(assistantMessage)
            currentAssistantMessage = assistantMessage
        }

        // Replay loop — each iteration fetches full log history.
        // processServiceStream skips events whose UUID is already in
        // processedEventUUIDs, so content is never cleared mid-stream.
        while !Task.isCancelled {
            receivedSystemEvent = false
            receivedResultEvent = false

            // Reset parser for new HTTP stream (buffer may have stale partial data)
            await parser.reset()

            if !hasPriorEvents {
                // Cold start — clear tool index for fresh replay
                toolUseIndex = [:]
                rebuildToolUseIndex()
            }

            let stream = apiClient.streamServiceLogs(
                spriteName: spriteName,
                serviceName: serviceName
            )

            status = .streaming
            let streamResult = await processServiceStream(
                stream: stream,
                modelContext: modelContext
            )

            let currentUUIDs = processedEventUUIDs.count
            logger.info("[Chat] Reconnect stream ended: result=\(streamResult), content=\(assistantMessage.content.count), uuids=\(currentUUIDs)")

            guard !Task.isCancelled else { return }

            // If we got a result event, Claude is done
            if receivedResultEvent { break }

            // Check if service is still running before retrying
            if let serviceInfo = try? await apiClient.getServiceStatus(spriteName: spriteName, serviceName: serviceName),
               serviceInfo.state.status == "running" {
                logger.info("[Chat] Service still running, will re-poll after delay")
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            // Service not running or status check failed — we're done
            break
        }

        // Finalize
        assistantMessage.isStreaming = false
        if currentAssistantMessage?.id == assistantMessage.id {
            currentAssistantMessage = nil
        }

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
                    if ["Write", "Edit"].contains(toolUse.name) {
                        turnHasMutations = true
                    }
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

            if turnHasMutations, let apiClient {
                let assistantMsg = currentAssistantMessage
                let sprite = spriteName
                Task { [weak assistantMsg] in
                    let comment = await Self.generateCheckpointComment(from: assistantMsg)
                    await self.createAutoCheckpoint(
                        apiClient: apiClient,
                        sprite: sprite,
                        comment: comment,
                        assistantMessage: assistantMsg,
                        modelContext: modelContext
                    )
                }
            }

        case .unknown:
            break
        }
    }

    // MARK: - Auto-Checkpoints

    private func createAutoCheckpoint(
        apiClient: SpritesAPIClient,
        sprite: String,
        comment: String?,
        assistantMessage: ChatMessage?,
        modelContext: ModelContext
    ) async {
        do {
            try await apiClient.createCheckpoint(spriteName: sprite, comment: comment)
            let checkpoints = try await apiClient.listCheckpoints(spriteName: sprite)
            let newest = checkpoints
                .filter { $0.id != "Current" }
                .sorted { ($0.createTime ?? .distantPast) > ($1.createTime ?? .distantPast) }
                .first
            if let cp = newest {
                assistantMessage?.checkpointId = cp.id
                assistantMessage?.checkpointComment = comment
                persistMessages(modelContext: modelContext)
            }
        } catch {
            logger.error("Auto-checkpoint failed: \(error.localizedDescription)")
        }
    }

    var isCheckpointing = false

    func createCheckpoint(for message: ChatMessage, modelContext: ModelContext) {
        guard let apiClient, message.checkpointId == nil else { return }
        isCheckpointing = true
        let sprite = spriteName
        Task { [weak message] in
            defer { self.isCheckpointing = false }
            let comment = await Self.generateCheckpointComment(from: message)
            await self.createAutoCheckpoint(
                apiClient: apiClient,
                sprite: sprite,
                comment: comment,
                assistantMessage: message,
                modelContext: modelContext
            )
        }
    }

    /// Generates a changelog-style checkpoint comment using the on-device language model.
    /// Falls back to the first-line truncation approach if the model is unavailable or fails.
    static func generateCheckpointComment(from message: ChatMessage?) async -> String? {
        guard let message else { return nil }

        let (text, toolActions) = await MainActor.run {
            let tools = message.content.compactMap { item -> String? in
                if case .toolUse(let card) = item {
                    return "\(card.toolName): \(card.summary)"
                }
                return nil
            }
            return (message.textContent, tools)
        }

        guard !text.isEmpty || !toolActions.isEmpty else { return nil }

        let fallback: String = {
            if !text.isEmpty {
                let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
                return String(firstLine.prefix(80))
            }
            return toolActions.first.map { String($0.prefix(80)) } ?? "Checkpoint"
        }()

        guard SystemLanguageModel.default.isAvailable else { return fallback }

        do {
            let session = LanguageModelSession(
                instructions: """
                You write ultra-short git-commit-style summaries (2-6 words). Past tense. \
                No filler words. No mentions of AI, assistant, or user. \
                Focus on what actions were taken, NOT on file contents or explanations. \
                Omit full paths — just use the filename or directory name. \
                Examples: "Cloned kit-plugins", "Fixed login redirect bug", \
                "Added dark mode to SettingsView", "Wrote PLUGIN_IDEAS.md".
                """
            )
            var input = ""
            if !toolActions.isEmpty {
                input += "Tool actions:\n\(toolActions.joined(separator: "\n"))\n\n"
            }
            if !text.isEmpty {
                input += "Assistant message:\n\(String(text.prefix(1000)))"
            }
            let response = try await session.respond(
                to: "Summarize the action in as few words as possible:\n\n\(input)"
            )
            let generated = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`."))
            return generated.isEmpty ? fallback : String(generated.prefix(120))
        } catch {
            return fallback
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

    // MARK: - MCP Setup

    /// Base64-encoded content of ~/.wisp/ask_user_mcp.py.
    /// Provides the AskUserQuestion MCP tool for Claude Code headless sessions.
    private static let mcpServerScriptBase64 =
        "IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwoiIiJXaXNwIE1DUCBzZXJ2ZXIgcHJvdmlkaW5nIEFza1VzZXJRdWVzdGlvbiBmb3IgQ2xhdWRlIENvZGUgaGVhZGxlc3Mgc2Vzc2lvbnMuIiIiCgppbXBvcnQganNvbgppbXBvcnQgb3MKaW1wb3J0IHN5cwppbXBvcnQgdGltZQoKUVVFU1RJT05fRklMRSA9ICIvdG1wLy53aXNwX2Fza19wZW5kaW5nLmpzb24iClJFU1BPTlNFX0ZJTEUgPSAiL3RtcC8ud2lzcF9hc2tfcmVzcG9uc2UuanNvbiIKClRJTUVPVVQgPSAzMDAgICMgNSBtaW51dGVzCgoKZGVmIHJlYWRfbWVzc2FnZSgpOgogICAgaGVhZGVycyA9IHt9CiAgICB3aGlsZSBUcnVlOgogICAgICAgIGxpbmUgPSBzeXMuc3RkaW4ucmVhZGxpbmUoKQogICAgICAgIGlmIG5vdCBsaW5lOgogICAgICAgICAgICByZXR1cm4gTm9uZQogICAgICAgIGxpbmUgPSBsaW5lLnJzdHJpcCgiXHJcbiIpCiAgICAgICAgaWYgbm90IGxpbmU6CiAgICAgICAgICAgIGJyZWFrCiAgICAgICAgaWYgIjoiIGluIGxpbmU6CiAgICAgICAgICAgIGtleSwgXywgdmFsdWUgPSBsaW5lLnBhcnRpdGlvbigiOiIpCiAgICAgICAgICAgIGhlYWRlcnNba2V5LnN0cmlwKCkubG93ZXIoKV0gPSB2YWx1ZS5zdHJpcCgpCiAgICBsZW5ndGggPSBpbnQoaGVhZGVycy5nZXQoImNvbnRlbnQtbGVuZ3RoIiwgMCkpCiAgICBpZiBsZW5ndGggPT0gMDoKICAgICAgICByZXR1cm4gTm9uZQogICAgZGF0YSA9IHN5cy5zdGRpbi5yZWFkKGxlbmd0aCkKICAgIHJldHVybiBqc29uLmxvYWRzKGRhdGEpCgoKZGVmIHNlbmRfbWVzc2FnZShvYmopOgogICAgZGF0YSA9IGpzb24uZHVtcHMob2JqKQogICAgc3lzLnN0ZG91dC53cml0ZShmIkNvbnRlbnQtTGVuZ3RoOiB7bGVuKGRhdGEpfVxyXG5cclxue2RhdGF9IikKICAgIHN5cy5zdGRvdXQuZmx1c2goKQoKClRPT0xfREVGID0gewogICAgIm5hbWUiOiAiQXNrVXNlclF1ZXN0aW9uIiwKICAgICJkZXNjcmlwdGlvbiI6ICgKICAgICAgICAiQXNrIHRoZSB1c2VyIGEgY2xhcmlmeWluZyBxdWVzdGlvbiBhbmQgd2FpdCBmb3IgdGhlaXIgcmVzcG9uc2UgYmVmb3JlICIKICAgICAgICAicHJvY2VlZGluZy4gVXNlIHdoZW4geW91IG5lZWQgYSBkZWNpc2lvbiBvciBwcmVmZXJlbmNlIGZyb20gdGhlIHVzZXIuIgogICAgKSwKICAgICJpbnB1dFNjaGVtYSI6IHsKICAgICAgICAidHlwZSI6ICJvYmplY3QiLAogICAgICAgICJwcm9wZXJ0aWVzIjogewogICAgICAgICAgICAicXVlc3Rpb24iOiB7CiAgICAgICAgICAgICAgICAidHlwZSI6ICJzdHJpbmciLAogICAgICAgICAgICAgICAgImRlc2NyaXB0aW9uIjogIlRoZSBxdWVzdGlvbiB0byBhc2sgdGhlIHVzZXIiLAogICAgICAgICAgICB9LAogICAgICAgICAgICAib3B0aW9ucyI6IHsKICAgICAgICAgICAgICAgICJ0eXBlIjogImFycmF5IiwKICAgICAgICAgICAgICAgICJkZXNjcmlwdGlvbiI6ICJPcHRpb25hbCBsaXN0IG9mIGNob2ljZXMgZm9yIHRoZSB1c2VyIHRvIHNlbGVjdCBmcm9tIiwKICAgICAgICAgICAgICAgICJpdGVtcyI6IHsKICAgICAgICAgICAgICAgICAgICAidHlwZSI6ICJvYmplY3QiLAogICAgICAgICAgICAgICAgICAgICJwcm9wZXJ0aWVzIjogewogICAgICAgICAgICAgICAgICAgICAgICAibGFiZWwiOiB7InR5cGUiOiAic3RyaW5nIn0sCiAgICAgICAgICAgICAgICAgICAgICAgICJkZXNjcmlwdGlvbiI6IHsidHlwZSI6ICJzdHJpbmcifSwKICAgICAgICAgICAgICAgICAgICB9LAogICAgICAgICAgICAgICAgICAgICJyZXF1aXJlZCI6IFsibGFiZWwiXSwKICAgICAgICAgICAgICAgIH0sCiAgICAgICAgICAgIH0sCiAgICAgICAgfSwKICAgICAgICAicmVxdWlyZWQiOiBbInF1ZXN0aW9uIl0sCiAgICB9LAp9CgoKZGVmIGhhbmRsZV9hc2tfdXNlcl9xdWVzdGlvbihhcmdzLCBtc2dfaWQpOgogICAgIyBDbGVhbiB1cCBzdGFsZSByZXNwb25zZSBmaWxlCiAgICB0cnk6CiAgICAgICAgb3MucmVtb3ZlKFJFU1BPTlNFX0ZJTEUpCiAgICBleGNlcHQgT1NFcnJvcjoKICAgICAgICBwYXNzCgogICAgIyBXcml0ZSBxdWVzdGlvbiBmb3IgdGhlIGFwcCB0byBwaWNrIHVwCiAgICB3aXRoIG9wZW4oUVVFU1RJT05fRklMRSwgInciKSBhcyBmOgogICAgICAgIGpzb24uZHVtcChhcmdzLCBmKQoKICAgICMgUG9sbCBmb3IgcmVzcG9uc2UKICAgIGRlYWRsaW5lID0gdGltZS50aW1lKCkgKyBUSU1FT1VUCiAgICBhbnN3ZXIgPSAiVXNlciBkaWQgbm90IHJlc3BvbmQuIFVzZSB5b3VyIGJlc3QganVkZ21lbnQgYW5kIHByb2NlZWQuIgogICAgd2hpbGUgdGltZS50aW1lKCkgPCBkZWFkbGluZToKICAgICAgICBpZiBvcy5wYXRoLmV4aXN0cyhSRVNQT05TRV9GSUxFKToKICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgd2l0aCBvcGVuKFJFU1BPTlNFX0ZJTEUpIGFzIGY6CiAgICAgICAgICAgICAgICAgICAgcmVzcCA9IGpzb24ubG9hZChmKQogICAgICAgICAgICAgICAgYW5zd2VyID0gcmVzcC5nZXQoImFuc3dlciIsIGFuc3dlcikKICAgICAgICAgICAgICAgIG9zLnJlbW92ZShSRVNQT05TRV9GSUxFKQogICAgICAgICAgICBleGNlcHQgKE9TRXJyb3IsIGpzb24uSlNPTkRlY29kZUVycm9yKToKICAgICAgICAgICAgICAgIHBhc3MKICAgICAgICAgICAgYnJlYWsKICAgICAgICB0aW1lLnNsZWVwKDAuMikKCiAgICAjIENsZWFuIHVwIHF1ZXN0aW9uIGZpbGUKICAgIHRyeToKICAgICAgICBvcy5yZW1vdmUoUVVFU1RJT05fRklMRSkKICAgIGV4Y2VwdCBPU0Vycm9yOgogICAgICAgIHBhc3MKCiAgICBzZW5kX21lc3NhZ2UoewogICAgICAgICJqc29ucnBjIjogIjIuMCIsCiAgICAgICAgImlkIjogbXNnX2lkLAogICAgICAgICJyZXN1bHQiOiB7ImNvbnRlbnQiOiBbeyJ0eXBlIjogInRleHQiLCAidGV4dCI6IGFuc3dlcn1dfSwKICAgIH0pCgoKZGVmIG1haW4oKToKICAgIHdoaWxlIFRydWU6CiAgICAgICAgbXNnID0gcmVhZF9tZXNzYWdlKCkKICAgICAgICBpZiBtc2cgaXMgTm9uZToKICAgICAgICAgICAgYnJlYWsKCiAgICAgICAgbWV0aG9kID0gbXNnLmdldCgibWV0aG9kIiwgIiIpCiAgICAgICAgbXNnX2lkID0gbXNnLmdldCgiaWQiKQoKICAgICAgICBpZiBtZXRob2QgPT0gImluaXRpYWxpemUiOgogICAgICAgICAgICBzZW5kX21lc3NhZ2UoewogICAgICAgICAgICAgICAgImpzb25ycGMiOiAiMi4wIiwKICAgICAgICAgICAgICAgICJpZCI6IG1zZ19pZCwKICAgICAgICAgICAgICAgICJyZXN1bHQiOiB7CiAgICAgICAgICAgICAgICAgICAgInByb3RvY29sVmVyc2lvbiI6ICIyMDI0LTExLTA1IiwKICAgICAgICAgICAgICAgICAgICAiY2FwYWJpbGl0aWVzIjogeyJ0b29scyI6IHt9fSwKICAgICAgICAgICAgICAgICAgICAic2VydmVySW5mbyI6IHsibmFtZSI6ICJ3aXNwLWFzay11c2VyIiwgInZlcnNpb24iOiAiMS4wLjAifSwKICAgICAgICAgICAgICAgIH0sCiAgICAgICAgICAgIH0pCiAgICAgICAgZWxpZiBtZXRob2QgPT0gInRvb2xzL2xpc3QiOgogICAgICAgICAgICBzZW5kX21lc3NhZ2UoewogICAgICAgICAgICAgICAgImpzb25ycGMiOiAiMi4wIiwKICAgICAgICAgICAgICAgICJpZCI6IG1zZ19pZCwKICAgICAgICAgICAgICAgICJyZXN1bHQiOiB7InRvb2xzIjogW1RPT0xfREVGXX0sCiAgICAgICAgICAgIH0pCiAgICAgICAgZWxpZiBtZXRob2QgPT0gInRvb2xzL2NhbGwiOgogICAgICAgICAgICBwYXJhbXMgPSBtc2cuZ2V0KCJwYXJhbXMiLCB7fSkKICAgICAgICAgICAgaWYgcGFyYW1zLmdldCgibmFtZSIpID09ICJBc2tVc2VyUXVlc3Rpb24iOgogICAgICAgICAgICAgICAgaGFuZGxlX2Fza191c2VyX3F1ZXN0aW9uKHBhcmFtcy5nZXQoImFyZ3VtZW50cyIsIHt9KSwgbXNnX2lkKQogICAgICAgICMgSWdub3JlIG5vdGlmaWNhdGlvbnMgKG5vIGlkKSBhbmQgdW5rbm93biBtZXRob2RzCgoKaWYgX19uYW1lX18gPT0gIl9fbWFpbl9fIjoKICAgIG1haW4oKQo="

    /// Shell command that installs the Wisp MCP server on the Sprite if not already present.
    private static var mcpSetupCommand: String {
        let configJSON = #"{"mcpServers":{"askUser":{"command":"python3","args":["/home/sprite/.wisp/ask_user_mcp.py"]}}}"#
        return "[ -f ~/.wisp/ask_user_mcp.py ] || { mkdir -p ~/.wisp && printf '\(mcpServerScriptBase64)' | base64 -d > ~/.wisp/ask_user_mcp.py && chmod +x ~/.wisp/ask_user_mcp.py && printf '\(configJSON)' > ~/.wisp/mcp_config.json; }"
    }
}

