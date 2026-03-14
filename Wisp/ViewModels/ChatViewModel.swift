import Foundation
import FoundationModels
import os
import SwiftData
import UIKit

private let logger = Logger(subsystem: "com.wisp.app", category: "Chat")

enum ChatStatus: Sendable, Equatable {
    case idle
    case connecting
    case streaming
    case reconnecting
    case error(String)

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }
}

struct AttachedFile: Identifiable {
    let id = UUID()
    let name: String   // "main.py" or "photo_20260228.jpg"
    let path: String   // "/home/sprite/project/main.py"

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp", "svg",
    ]

    var isImage: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
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
    var hasAnyRemoteSessions = false
    var isLoadingRemoteSessions = false
    var isLoadingHistory = false

    private var serviceName: String
    private var sessionId: String?
    var workingDirectory: String
    private(set) var worktreePath: String?
    /// True when any chat for this sprite has had a worktree created, indicating the
    /// sprite has a git repo. Used to suppress session-resume UI on new chats.
    private(set) var spriteUsesWorktrees = false
    private var streamTask: Task<Void, Never>?
    var namingTask: Task<String, Never>?
    private let parser = ClaudeStreamParser()
    private var currentAssistantMessage: ChatMessage?
    private var toolUseIndex: [String: (messageIndex: Int, toolName: String)] = [:]
    private var receivedSystemEvent = false
    private var receivedResultEvent = false
    private var usedResume = false
    var queuedPrompt: String?
    var queuedAttachments: [AttachedFile] = []
    var stashedDraft: String?
    private var retriedAfterTimeout = false
    private var turnHasMutations = false
    private var pendingForkContext: String?
    private var apiClient: SpritesAPIClient?

    /// UUIDs of Claude NDJSON events already processed.
    /// Used by reconnect to skip already-handled events instead of clearing content.
    var processedEventUUIDs: Set<String> = []
    private var hasPlayedFirstTextHaptic = false

    /// When true, handleEvent buffers content changes instead of mutating the
    /// @Observable ChatMessage directly. Flushed in one shot after replay ends,
    /// reducing the N per-event SwiftUI re-renders to a single update.
    private var isReplaying = false
    private var replayContentBuffer: [ChatContent] = []
    private var replayToolUseBuffer: [String: (messageIndex: Int, toolName: String)] = [:]
    /// When true (reconnecting to a still-running service), isReplaying is cleared
    /// on the first new event so live events stream in incrementally rather than
    /// being batched until the connection drops.
    private var isReplayingLiveService = false

    init(spriteName: String, chatId: UUID, currentServiceName: String?, workingDirectory: String, worktreePath: String? = nil) {
        self.spriteName = spriteName
        self.chatId = chatId
        self.serviceName = currentServiceName ?? "wisp-claude-\(UUID().uuidString.prefix(8).lowercased())"
        self.workingDirectory = workingDirectory
        self.worktreePath = worktreePath
    }

    // MARK: - Attachment State

    var attachedFiles: [AttachedFile] = []
    var isUploadingAttachment = false
    var uploadAttachmentError: String?
    var lastUploadedFileName: String?
    private var uploadFeedbackTask: Task<Void, Never>?

    private static let maxUploadBytes: Int = 10 * 1024 * 1024 // 10 MB

    func addAttachedFile(remotePath: String) {
        let name = (remotePath as NSString).lastPathComponent
        attachedFiles.append(AttachedFile(name: name, path: remotePath))
    }

    func uploadFileFromDevice(apiClient: SpritesAPIClient, fileURL: URL) async -> String? {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > Self.maxUploadBytes {
            uploadAttachmentError = "File is too large to upload (max 10 MB)"
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            uploadAttachmentError = "Failed to read file: \(error.localizedDescription)"
            return nil
        }

        return await uploadAttachmentData(apiClient: apiClient, data: data, filename: fileURL.lastPathComponent)
    }

    func uploadPhotoData(apiClient: SpritesAPIClient, data: Data, fileExtension: String) async -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "photo_\(formatter.string(from: Date())).\(fileExtension)"
        return await uploadAttachmentData(apiClient: apiClient, data: data, filename: filename)
    }

    private func uploadAttachmentData(apiClient: SpritesAPIClient, data: Data, filename: String) async -> String? {
        let remotePath = workingDirectory.hasSuffix("/")
            ? workingDirectory + filename
            : workingDirectory + "/" + filename

        isUploadingAttachment = true
        uploadAttachmentError = nil
        defer { isUploadingAttachment = false }

        do {
            try await apiClient.uploadFile(
                spriteName: spriteName,
                remotePath: remotePath,
                data: data
            )
            lastUploadedFileName = filename
            uploadFeedbackTask?.cancel()
            uploadFeedbackTask = Task {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled {
                    lastUploadedFileName = nil
                }
            }
            return remotePath
        } catch {
            uploadAttachmentError = "Upload failed: \(error.localizedDescription)"
            return nil
        }
    }

    var isStreaming: Bool {
        if case .streaming = status { return true }
        if case .connecting = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    var activeToolLabel: String? {
        guard let message = currentAssistantMessage else { return nil }
        for item in message.content.reversed() {
            if case .toolUse(let card) = item, card.result == nil {
                return card.activityLabel.relativeToCwd(workingDirectory)
            }
        }
        return nil
    }

    /// The ID of the message currently being built by a streaming response.
    /// Views use this alongside `isStreaming` to show typing indicators on the right bubble.
    var currentAssistantMessageId: UUID? {
        currentAssistantMessage?.id
    }

    func loadSession(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        self.apiClient = apiClient
        guard let chat = fetchChat(modelContext: modelContext) else { return }

        sessionId = chat.claudeSessionId
        workingDirectory = chat.workingDirectory
        worktreePath = chat.worktreePath
        if let svcName = chat.currentServiceName {
            serviceName = svcName
        }

        // Check if any chat on this sprite has ever had a worktree — if so the sprite
        // has git and new chats should suppress the session-resume UI.
        let name = spriteName
        let worktreeDescriptor = FetchDescriptor<SpriteChat>(
            predicate: #Predicate { $0.spriteName == name && $0.worktreePath != nil }
        )
        spriteUsesWorktrees = (try? modelContext.fetch(worktreeDescriptor))?.isEmpty == false

        if messages.isEmpty {
            let persisted = chat.loadMessages()
            messages = persisted.map { ChatMessage(from: $0) }
            rebuildToolUseIndex()
            processedEventUUIDs = chat.loadStreamEventUUIDs()
        }

        if inputText.isEmpty, let draft = chat.draftInputText, !draft.isEmpty {
            inputText = draft
        }

        if attachedFiles.isEmpty, let paths = chat.draftAttachmentPaths, !paths.isEmpty {
            attachedFiles = paths.map { path in
                AttachedFile(name: (path as NSString).lastPathComponent, path: path)
            }
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
        let paths = attachedFiles.map(\.path)
        chat.draftAttachmentPaths = paths.isEmpty ? nil : paths
        try? modelContext.save()
    }

    func stashDraft() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stashedDraft = text
        inputText = ""
    }

    private func restoreStash() {
        guard let stash = stashedDraft else { return }
        stashedDraft = nil
        inputText = stash
    }

    /// True when this chat uses (or will use) a git worktree.
    /// Covers both established worktrees and fresh chats on sprites that have
    /// previously created worktrees (i.e. the sprite has a git repo).
    var usesWorktree: Bool {
        worktreePath != nil || spriteUsesWorktrees
    }

    func fetchRemoteSessions(apiClient: SpritesAPIClient, existingSessionIds: Set<String>) {
        // Worktrees are always fresh — no sessions to resume
        guard !usesWorktree else { return }
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
            hasAnyRemoteSessions = !entries.isEmpty
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
        if !processedEventUUIDs.isEmpty {
            chat.saveStreamEventUUIDs(processedEventUUIDs)
        }
        try? modelContext.save()
    }

    private func rebuildToolUseIndex() {
        toolUseIndex = [:]
        var toolCards: [String: ToolUseCard] = [:]
        for (messageIndex, message) in messages.enumerated() {
            for item in message.content {
                if case .toolUse(let card) = item {
                    toolUseIndex[card.toolUseId] = (
                        messageIndex: messageIndex,
                        toolName: card.toolName
                    )
                    toolCards[card.toolUseId] = card
                }
            }
        }
        // Second pass: link tool results to their tool use cards
        for message in messages {
            for item in message.content {
                if case .toolResult(let resultCard) = item {
                    toolCards[resultCard.toolUseId]?.result = resultCard
                }
            }
        }
    }

    func cancelQueuedPrompt() {
        queuedPrompt = nil
        queuedAttachments = []
    }

    private func buildPrompt(text: String, attachments: [AttachedFile]) -> String {
        guard !attachments.isEmpty else { return text }
        let images = attachments.filter { $0.isImage }
        let files = attachments.filter { !$0.isImage }

        var parts: [String] = []

        if !files.isEmpty {
            parts.append(files.map(\.path).joined(separator: "\n"))
        }

        if !images.isEmpty {
            let hint = images.map { "Use the Read tool to view this image: \($0.path)" }
                .joined(separator: "\n")
            parts.append(hint)
        }

        if !text.isEmpty {
            parts.append(text)
        }

        return parts.joined(separator: "\n\n")
    }

    func sendMessage(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedFiles.isEmpty else { return }

        inputText = ""

        saveDraft(modelContext: modelContext)
        retriedAfterTimeout = false

        if isStreaming {
            // Queue for later — store text and attachments separately so the
            // pending bubble can show nice attachment chips instead of raw paths
            queuedPrompt = text
            queuedAttachments = attachedFiles
            attachedFiles = []
            restoreStash()
            return
        }

        // Capture attachments before clearing so the stream task can copy them to the
        // worktree if one gets created on the first message.
        let capturedText = text
        let capturedAttachments = attachedFiles

        // Build prompt with attached file paths prepended (used for the display message)
        let prompt = buildPrompt(text: text, attachments: attachedFiles)
        attachedFiles = []
        restoreStash()

        let isFirstMessage = messages.isEmpty
        let userMessage = ChatMessage(role: .user, content: [.text(prompt)])
        messages.append(userMessage)
        persistMessages(modelContext: modelContext)

        if isFirstMessage {
            namingTask = Task { await autoNameChat(firstMessage: prompt, modelContext: modelContext) }
        }

        let worktreeEnabled = UserDefaults.standard.bool(forKey: "worktreePerChat")
        let needsWorktreeSetup = isFirstMessage && worktreePath == nil && worktreeEnabled
        status = .connecting
        streamTask = Task {
            var claudePrompt = prompt
            if needsWorktreeSetup {
                // Wait for chat naming and use the result directly as the branch base
                let chatName = await self.namingTask?.value ?? capturedText
                let branch = Self.branchName(from: chatName)
                await self.setupWorktree(branchName: branch, apiClient: apiClient, modelContext: modelContext)
                // If a worktree was created and there were uploaded files, copy them into
                // the worktree so Claude can work with them in the git context, then
                // rebuild the prompt so the paths it receives point inside the worktree.
                if self.worktreePath != nil && !capturedAttachments.isEmpty {
                    let worktreeAttachments = await self.copyAttachmentsToWorktree(capturedAttachments, apiClient: apiClient)
                    let rebuiltPrompt = self.buildPrompt(text: capturedText, attachments: worktreeAttachments)
                    claudePrompt = rebuiltPrompt
                    // Sync the displayed user bubble to show the same paths Claude receives
                    userMessage.content = [.text(rebuiltPrompt)]
                }
            }
            await executeClaudeCommand(prompt: claudePrompt, apiClient: apiClient, modelContext: modelContext)
        }
    }

    func resumeAfterBackground(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        guard isStreaming else { return }
        // Cancel the stale stream and reconnect via service logs
        streamTask?.cancel()
        streamTask = Task {
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext, serviceIsRunning: true)
        }
    }

    /// Stop streaming without deleting the service (used when switching away from a chat).
    /// Returns true if the VM was actively streaming when detached.
    @discardableResult
    func detach(modelContext: ModelContext? = nil) -> Bool {
        let wasStreaming = isStreaming

        streamTask?.cancel()
        streamTask = nil

        currentAssistantMessage = nil
        queuedPrompt = nil
        queuedAttachments = []
        status = .idle

        if let modelContext {
            persistMessages(modelContext: modelContext)
        }
        return wasStreaming
    }

    func interrupt(apiClient: SpritesAPIClient? = nil, modelContext: ModelContext? = nil) {
        detach(modelContext: modelContext)

        // Note: we keep sessionId intact so the next message can resume the session.
        // If the session turns out to be stale, the stale-session retry logic handles it.

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

        // If the last session completed cleanly, content is already loaded from
        // persistence — no need to hit the network at all.
        if let chat = fetchChat(modelContext: modelContext), chat.lastSessionComplete {
            return
        }

        streamTask = Task {
            // Only reconnect if the service exists (running or stopped with logs)
            guard let serviceInfo = try? await apiClient.getServiceStatus(spriteName: spriteName, serviceName: serviceName)
            else { return }

            let isRunning = serviceInfo.state.status == "running"
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext, serviceIsRunning: isRunning)
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

        // Install question tool after service cleanup (sprite is awake at this point)
        if UserDefaults.standard.bool(forKey: "claudeQuestionTool") {
            let toolReady = await installClaudeQuestionToolIfNeeded(apiClient: apiClient)
            if !toolReady {
                status = .error("Claude question tool failed to install — disable it in Settings or try again")
                return
            }
        }

        // Persist the new service name immediately for reconnect; clear any prior completion flag
        saveSession(modelContext: modelContext, isComplete: false)

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
            "export NO_DNA=1", // Signal to CLIs that they're running under an agent operator (no-dna.org)
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

        var claudeCmd = "claude -p --verbose --output-format stream-json --dangerously-skip-permissions"
        if UserDefaults.standard.bool(forKey: "claudeQuestionTool") {
            let sessionId = chatId.uuidString.lowercased()
            let configPath = ClaudeQuestionTool.mcpConfigFilePath(for: sessionId)
            // Write per-session MCP config (inlined in the command chain so no extra round-trip)
            commandParts.append("echo '\(ClaudeQuestionTool.mcpConfigJSON(for: sessionId))' > \(configPath)")
            claudeCmd += " --disallowedTools AskUserQuestion"
            claudeCmd += " --mcp-config \(configPath)"
        }

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

        // Wrap claude with a heartbeat so the sprite stays alive while Claude
        // is waiting for an API response and Wisp is detached. The heartbeat
        // writes a byte to stderr every 20s — enough to count as output without
        // interfering with the NDJSON stdout stream. The trap ensures cleanup.
        let wrappedClaudeCmd = "{ (while true; do sleep 20; printf . >&2; done) & HBEAT=$!; trap \"kill $HBEAT 2>/dev/null\" EXIT; \(claudeCmd); kill $HBEAT 2>/dev/null; }"
        commandParts.append(wrappedClaudeCmd)
        let fullCommand = commandParts.joined(separator: " && ")

        receivedSystemEvent = false
        receivedResultEvent = false
        turnHasMutations = false
        processedEventUUIDs = []
        hasPlayedFirstTextHaptic = false

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

        let assistantMessage = ChatMessage(role: .assistant)
        messages.append(assistantMessage)
        currentAssistantMessage = assistantMessage

        let streamResult = await processServiceStream(stream: stream, modelContext: modelContext, breakOnComplete: true)
        let uuidCount = processedEventUUIDs.count
        logger.info("[Chat] Main stream ended: result=\(streamResult), cancelled=\(Task.isCancelled), uuids=\(uuidCount)")

        // If cancelled (e.g. by resumeAfterBackground), bail out immediately.
        // The reconnect task now owns the assistant message and shared state.
        guard !Task.isCancelled else { return }

        if currentAssistantMessage?.id == assistantMessage.id {
            currentAssistantMessage = nil
        }

        // Attempt reconnection on disconnect
        if case .disconnected = streamResult {
            logger.info("[Chat] Disconnected mid-stream, attempting reconnect via service logs")
            await reconnectToServiceLogs(apiClient: apiClient, modelContext: modelContext, serviceIsRunning: true)
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
            let prompt = buildPrompt(text: queued, attachments: queuedAttachments)
            queuedPrompt = nil
            queuedAttachments = []
            let userMessage = ChatMessage(role: .user, content: [.text(prompt)])
            messages.append(userMessage)
            persistMessages(modelContext: modelContext)
            await executeClaudeCommand(prompt: prompt, apiClient: apiClient, modelContext: modelContext)
        }
    }

    /// Result of processing a service stream
    enum StreamResult: CustomStringConvertible {
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
    func processServiceStream(
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
            // First new event after skipping historical ones on a live-service reconnect:
            // flush the replay buffer (empty, since skipped events don't buffer anything)
            // and switch to incremental rendering so live events stream in as they arrive.
            if isReplayingLiveService {
                applyReplayBuffer()
                isReplaying = false
                isReplayingLiveService = false
                if case .reconnecting = status { status = .streaming }
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
            logger.info("Stream ended: events=\(eventCount) receivedData=\(receivedData) skipped=\(skippedCount) uuids=\(uuidCount) gotResult=\(self.receivedResultEvent)")
            if Task.isCancelled { return .cancelled }
            if !receivedData { return .timedOut }
            // A clean stream close without the result event means Claude is still running —
            // treat it as a disconnect so the caller reconnects rather than going idle.
            return receivedResultEvent ? .completed : .disconnected
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
    /// Core reconnect loop — fetches full log history on repeat until a result event
    /// arrives or the service is confirmed stopped. Separated from
    /// `reconnectToServiceLogs` so it can be tested against a mock API client.
    func runReconnectLoop(
        apiClient: some ServiceLogsProvider,
        modelContext: ModelContext,
        serviceIsRunning: Bool = false
    ) async {
        isReplaying = true
        isReplayingLiveService = serviceIsRunning
        defer {
            applyReplayBuffer()
            isReplaying = false
            isReplayingLiveService = false
        }
        status = .reconnecting
        let priorUUIDs = processedEventUUIDs.count
        logger.info("[Chat] Reconnecting to service logs (\(priorUUIDs) prior UUIDs)")

        hasPlayedFirstTextHaptic = false

        // Ensure we have an assistant message to append into.
        // Only clear content if we have no prior events to skip (cold reconnect).
        let assistantMessage: ChatMessage
        let hasPriorEvents = !processedEventUUIDs.isEmpty
        if let existing = currentAssistantMessage {
            assistantMessage = existing
            if !hasPriorEvents { assistantMessage.content = [] }
        } else if let last = messages.last(where: { $0.role == .assistant }) {
            assistantMessage = last
            if !hasPriorEvents { assistantMessage.content = [] }
            currentAssistantMessage = last
        } else {
            assistantMessage = ChatMessage(role: .assistant)
            messages.append(assistantMessage)
            currentAssistantMessage = assistantMessage
        }

        // Replay loop — each iteration fetches full log history.
        // processServiceStream skips events whose UUID is already in
        // processedEventUUIDs, so content is never cleared mid-stream.
        var retriedAfterServiceStopped = false
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

            let streamResult = await processServiceStream(
                stream: stream,
                modelContext: modelContext
            )

            // Flush buffered content to the observable message in one shot
            applyReplayBuffer()

            let currentUUIDs = processedEventUUIDs.count
            logger.info("[Chat] Reconnect stream ended: result=\(streamResult), content=\(assistantMessage.content.count), uuids=\(currentUUIDs)")

            guard !Task.isCancelled else { return }

            // If we got a result event, Claude is done
            if receivedResultEvent { break }

            // Check if service is still running
            let isRunning = (try? await apiClient.getServiceStatus(spriteName: spriteName, serviceName: serviceName))?.state.status == "running"

            if isRunning {
                logger.info("[Chat] Service still running, will re-poll after delay")
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            // Service has stopped (or status check failed / service gone). The GET stream
            // may have been killed by iOS just as Claude finished writing its final events —
            // a race between the connection dying and the result arriving. Allow one extra
            // retry so we catch any events that landed in the log after the stream closed.
            if !retriedAfterServiceStopped {
                retriedAfterServiceStopped = true
                logger.info("[Chat] Service stopped without result event — retrying once for final events")
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            // Already retried after stop — give up
            break
        }

        // Finalize
        if currentAssistantMessage?.id == assistantMessage.id {
            currentAssistantMessage = nil
        }

        saveSession(modelContext: modelContext)
        if !Task.isCancelled {
            status = .idle
        }
        persistMessages(modelContext: modelContext)
    }

    private func reconnectToServiceLogs(
        apiClient: SpritesAPIClient,
        modelContext: ModelContext,
        serviceIsRunning: Bool = false
    ) async {
        await runReconnectLoop(apiClient: apiClient, modelContext: modelContext, serviceIsRunning: serviceIsRunning)

        if let queued = queuedPrompt, !Task.isCancelled {
            let prompt = buildPrompt(text: queued, attachments: queuedAttachments)
            queuedPrompt = nil
            queuedAttachments = []
            let userMessage = ChatMessage(role: .user, content: [.text(prompt)])
            messages.append(userMessage)
            persistMessages(modelContext: modelContext)
            await executeClaudeCommand(prompt: prompt, apiClient: apiClient, modelContext: modelContext)
        }
    }

    func handleEvent(_ event: ClaudeStreamEvent, modelContext: ModelContext) {
        switch event {
        case .system(let systemEvent):
            receivedSystemEvent = true
            sessionId = systemEvent.sessionId
            modelName = systemEvent.model
            if let cwd = systemEvent.cwd { workingDirectory = cwd }
            logger.info("System event tools: \(systemEvent.tools ?? [], privacy: .public)")
            saveSession(modelContext: modelContext)

        case .assistant(let assistantEvent):
            guard let message = currentAssistantMessage else { return }

            for block in assistantEvent.message.content {
                switch block {
                case .text(let text):
                    if !isReplaying && !hasPlayedFirstTextHaptic {
                        hasPlayedFirstTextHaptic = true
                        fireHaptic(.medium)
                    }
                    // Merge consecutive text blocks
                    if isReplaying {
                        if case .text(let existing) = replayContentBuffer.last {
                            replayContentBuffer[replayContentBuffer.count - 1] = .text(existing + text)
                        } else {
                            replayContentBuffer.append(.text(text))
                        }
                    } else {
                        if case .text(let existing) = message.content.last {
                            message.content[message.content.count - 1] = .text(existing + text)
                        } else {
                            message.content.append(.text(text))
                        }
                    }
                case .toolUse(let toolUse):
                    let card = ToolUseCard(
                        toolUseId: toolUse.id,
                        toolName: toolUse.name,
                        input: toolUse.input
                    )
                    logger.info("Tool use: \(toolUse.name, privacy: .public) id=\(toolUse.id, privacy: .public)")
                    if isReplaying {
                        replayContentBuffer.append(.toolUse(card))
                        replayToolUseBuffer[toolUse.id] = (
                            messageIndex: messages.count - 1,
                            toolName: toolUse.name
                        )
                    } else {
                        message.content.append(.toolUse(card))
                        toolUseIndex[toolUse.id] = (
                            messageIndex: messages.count - 1,
                            toolName: toolUse.name
                        )
                    }
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
                let toolName = replayToolUseBuffer[result.toolUseId]?.toolName
                    ?? toolUseIndex[result.toolUseId]?.toolName
                    ?? "Unknown"
                let resultCard = ToolResultCard(
                    toolUseId: result.toolUseId,
                    toolName: toolName,
                    content: result.content ?? .null
                )
                if isReplaying {
                    replayContentBuffer.append(.toolResult(resultCard))
                    // Link result to matching tool use card in the buffer
                    for item in replayContentBuffer {
                        if case .toolUse(let toolCard) = item, toolCard.toolUseId == result.toolUseId {
                            toolCard.result = resultCard
                            break
                        }
                    }
                } else {
                    message.content.append(.toolResult(resultCard))
                    // Link result back to matching tool use card
                    for item in message.content {
                        if case .toolUse(let toolCard) = item, toolCard.toolUseId == result.toolUseId {
                            toolCard.result = resultCard
                            break
                        }
                    }
                    fireHaptic(.light)
                }
            }

        case .result(let resultEvent):
            if resultEvent.isError == true {
                logger.error("Claude result error: \(resultEvent.result ?? "unknown", privacy: .public)")
            }
            receivedResultEvent = true
            sessionId = resultEvent.sessionId
            saveSession(modelContext: modelContext, isComplete: true)

            let autoCheckpointEnabled = UserDefaults.standard.bool(forKey: "autoCheckpoint")
            if !isReplaying, turnHasMutations, autoCheckpointEnabled, let apiClient {
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

    var pendingWispAskCard: ToolUseCard? {
        for message in messages.reversed() {
            for item in message.content {
                if case .toolUse(let card) = item,
                   card.toolName == "mcp__askUser__WispAsk",
                   card.result == nil {
                    return card
                }
            }
        }
        return nil
    }

    func submitWispAskAnswer(_ answer: String) {
        guard let apiClient else { return }
        let sprite = spriteName
        let sessionId = chatId.uuidString.lowercased()
        Task {
            let jsonObject = ["answer": answer]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject) else { return }
            let path = ClaudeQuestionTool.responseFilePath(for: sessionId)
            do {
                _ = try await apiClient.uploadFile(spriteName: sprite, remotePath: path, data: jsonData)
            } catch {
                status = .error("Failed to send answer — try again")
            }
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

    @discardableResult
    private func autoNameChat(firstMessage: String, modelContext: ModelContext) async -> String {
        guard let chat = fetchChat(modelContext: modelContext) else { return firstMessage }
        if let existing = chat.customName { return existing }
        let name = await Self.generateChatName(from: firstMessage)
        chat.customName = name
        try? modelContext.save()
        return name
    }

    static func generateChatName(from prompt: String) async -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }

        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        let fallback = String(firstLine.prefix(50))

        guard SystemLanguageModel.default.isAvailable else { return fallback }

        do {
            let session = LanguageModelSession(
                instructions: """
                You write ultra-short chat titles (2-5 words). Imperative or noun phrase. \
                No filler words. Capture what the user wants to accomplish. \
                No punctuation at the end. Return ONLY the title. \
                Examples: "Debug login redirect", "Add dark mode", "Write unit tests", \
                "Explain Swift closures", "Set up CI pipeline".
                """
            )
            let response = try await session.respond(
                to: "Write a short title for a chat that starts with this message:\n\n\(String(trimmed.prefix(500)))"
            )
            let generated = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`."))
            return generated.isEmpty ? fallback : String(generated.prefix(80))
        } catch {
            return fallback
        }
    }

    // MARK: - Worktrees

    /// Returns a POSIX single-quoted shell argument with any internal single quotes escaped.
    /// Single quotes have no escape sequence in POSIX shell, so the idiom is:
    /// close the quote, insert a backslash-escaped literal quote, then reopen.
    /// e.g. "it's here" → "'it'\\''s here'"
    static func shellEscapePath(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Converts a chat name to a kebab-case git branch name.
    /// e.g. "Add dark mode" → "add-dark-mode"
    static func branchName(from chatName: String) -> String {
        let kebab = chatName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined(separator: "-")
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return kebab.isEmpty ? "chat" : String(kebab.prefix(50))
    }

    /// Runs a preliminary exec to set up a git worktree for this chat.
    /// Updates `workingDirectory` and `worktreePath` if worktree creation succeeds.
    /// Silently skips if the working directory is not inside a git repo.
    private func setupWorktree(
        branchName: String,
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        let chatIdPrefix = String(chatId.uuidString.prefix(8).lowercased())
        let currentWorkDir = workingDirectory
        let repoName = URL(fileURLWithPath: currentWorkDir).lastPathComponent
        let uniqueBranchName = "\(branchName)-\(chatIdPrefix)"
        let worktreeParent = "/home/sprite/.wisp/worktrees/\(repoName)"
        let worktreeDir = "\(worktreeParent)/\(uniqueBranchName)"

        // Mark all directories as safe to avoid "dubious ownership" errors when the repo
        // is owned by a different uid than the running process (common on Sprites).
        // Prune stale worktree registrations (handles dirs deleted without `git worktree remove`).
        // Capture stderr from worktree add collapsed to one line so we can log it on failure.
        let command = "git config --global --add safe.directory '*' 2>/dev/null; git -C '\(currentWorkDir)' pull 2>/dev/null || true; git -C '\(currentWorkDir)' worktree prune 2>/dev/null; mkdir -p '\(worktreeParent)' && GTWT_OUT=$(git -C '\(currentWorkDir)' worktree add '\(worktreeDir)' -b '\(uniqueBranchName)' 2>&1); if [ $? -eq 0 ]; then echo '\(worktreeDir)'; else echo \"WORKTREE_ERR:$(echo $GTWT_OUT)\"; fi"

        let (output, _) = await apiClient.runExec(spriteName: spriteName, command: command, timeout: 60)
        // git worktree add may print "HEAD is now at..." to stdout before our echo,
        // so take only the last non-empty line which is always the echo'd path.
        let lastLine = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

        if lastLine.hasPrefix("WORKTREE_ERR:") {
            logger.warning("[Worktree] git worktree add failed: \(lastLine)")
            return
        }

        // Guard against any unexpected non-path output being treated as a working directory
        let path = lastLine
        guard !path.isEmpty && path.hasPrefix("/") else {
            logger.info("[Worktree] Setup skipped — not a git repo or worktree add failed")
            return
        }

        workingDirectory = path
        worktreePath = path
        spriteUsesWorktrees = true
        if let chat = fetchChat(modelContext: modelContext) {
            chat.worktreePath = path
            chat.worktreeBranch = uniqueBranchName
            chat.workingDirectory = path
            try? modelContext.save()
        }
        logger.info("[Worktree] Created at \(path) on branch \(uniqueBranchName)")
    }

    /// Copies uploaded files into the worktree directory and returns updated AttachedFile
    /// values whose paths point to the new locations. Files that fail to copy are left
    /// with their original paths so Claude can still access them via the absolute path.
    func copyAttachmentsToWorktree(_ attachments: [AttachedFile], apiClient: SpritesAPIClient) async -> [AttachedFile] {
        guard let worktree = worktreePath else { return attachments }

        // Build copy commands and track (original array index → new path) for files that need moving.
        // Paths are single-quote escaped to prevent shell injection from filenames with apostrophes.
        var copyJobs: [(index: Int, newPath: String)] = []
        var copyCommands: [String] = []

        for (i, attachment) in attachments.enumerated() {
            let filename = URL(fileURLWithPath: attachment.path).lastPathComponent
            let newPath = worktree.hasSuffix("/") ? worktree + filename : worktree + "/" + filename
            guard attachment.path != newPath else { continue }
            copyJobs.append((index: i, newPath: newPath))
            copyCommands.append("cp \(Self.shellEscapePath(attachment.path)) \(Self.shellEscapePath(newPath)) 2>/dev/null && echo ok || echo skip")
        }

        guard !copyJobs.isEmpty else { return attachments }

        let command = copyCommands.joined(separator: "; ")
        let (output, _) = await apiClient.runExec(spriteName: spriteName, command: command, timeout: 30)
        let results = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Apply results: only use the new path where cp succeeded; fall back to original otherwise.
        var updated = attachments
        for (jobIndex, job) in copyJobs.enumerated() {
            if jobIndex < results.count && results[jobIndex] == "ok" {
                updated[job.index] = AttachedFile(name: attachments[job.index].name, path: job.newPath)
            }
        }
        return updated
    }

    private func fetchChat(modelContext: ModelContext) -> SpriteChat? {
        let id = chatId
        let descriptor = FetchDescriptor<SpriteChat>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func saveSession(modelContext: ModelContext, isComplete: Bool? = nil) {
        guard let chat = fetchChat(modelContext: modelContext) else { return }
        chat.claudeSessionId = sessionId
        chat.currentServiceName = serviceName
        chat.lastUsed = Date()
        if let isComplete { chat.lastSessionComplete = isComplete }
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

    /// Flush the replay content buffer into the current assistant message in one shot,
    /// replacing N per-event observable mutations with a single array assignment.
    private func applyReplayBuffer() {
        guard !replayContentBuffer.isEmpty, let message = currentAssistantMessage else {
            replayContentBuffer = []
            replayToolUseBuffer = [:]
            return
        }
        for item in replayContentBuffer {
            if case .text(let newText) = item,
               case .text(let existing) = message.content.last {
                message.content[message.content.count - 1] = .text(existing + newText)
            } else {
                message.content.append(item)
            }
        }
        toolUseIndex.merge(replayToolUseBuffer) { _, new in new }
        replayContentBuffer = []
        replayToolUseBuffer = [:]
    }

    private func fireHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    #if DEBUG
    func setCurrentAssistantMessage(_ message: ChatMessage?) {
        currentAssistantMessage = message
    }
    #endif

    private func installClaudeQuestionToolIfNeeded(apiClient: SpritesAPIClient) async -> Bool {
        let (output, _) = await apiClient.runExec(
            spriteName: spriteName,
            command: ClaudeQuestionTool.checkVersionCommand,
            timeout: 10
        )
        guard output.trimmingCharacters(in: .whitespacesAndNewlines) != ClaudeQuestionTool.version else {
            return true  // already up to date
        }
        logger.info("Installing Claude question tool (version \(ClaudeQuestionTool.version))...")
        do {
            // Write files directly via the REST filesystem API to avoid shell command length limits
            try await apiClient.uploadFile(
                spriteName: spriteName,
                remotePath: ClaudeQuestionTool.serverPyPath,
                data: Data(ClaudeQuestionTool.serverScript.utf8)
            )
        } catch {
            logger.error("Claude question tool installation failed: \(error)")
            return false
        }
        // Make server.py executable and write version file via exec
        // (the fs/write API corrupts very small payloads to null bytes)
        let installCommand = "\(ClaudeQuestionTool.chmodCommand) && mkdir -p ~/.wisp/claude-question && echo -n '\(ClaudeQuestionTool.version)' > \(ClaudeQuestionTool.versionPath)"
        let (installOutput, installSuccess) = await apiClient.runExec(
            spriteName: spriteName,
            command: installCommand,
            timeout: 10
        )
        guard installSuccess else {
            let trimmedOutput = installOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("Claude question tool install command failed: \(trimmedOutput)")
            return false
        }

        let verificationCommand =
            "if test -x \(ClaudeQuestionTool.serverPyPath) && [ \"$(cat \(ClaudeQuestionTool.versionPath) 2>/dev/null)\" = '\(ClaudeQuestionTool.version)' ]; then printf '\(ClaudeQuestionTool.version)'; else exit 1; fi"
        let (verificationOutput, verificationSuccess) = await apiClient.runExec(
            spriteName: spriteName,
            command: verificationCommand,
            timeout: 10
        )
        guard verificationSuccess,
            verificationOutput.trimmingCharacters(in: .whitespacesAndNewlines) == ClaudeQuestionTool.version
        else {
            logger.error("Claude question tool verification failed: \(verificationOutput)")
            return false
        }

        return true
    }
}
