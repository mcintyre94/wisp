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
    var modelOverride: ClaudeModel?
    var remoteSessions: [ClaudeSessionEntry] = []
    var hasAnyRemoteSessions = false
    var isLoadingRemoteSessions = false
    var isLoadingHistory = false

    private(set) var execSessionId: String?
    private(set) var sessionId: String?
    var workingDirectory: String
    private(set) var worktreePath: String?
    /// True when any chat for this sprite has had a worktree created, indicating the
    /// sprite has a git repo. Used to suppress session-resume UI on new chats.
    private(set) var spriteUsesWorktrees = false
    var streamTask: Task<Void, Never>?
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
    /// Set by SpriteDetailView to indicate this chat is currently being viewed.
    /// When true, result events do not trigger the unread indicator.
    var isActive: Bool = false

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

    init(spriteName: String, chatId: UUID, workingDirectory: String, worktreePath: String? = nil) {
        self.spriteName = spriteName
        self.chatId = chatId
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
        execSessionId = chat.execSessionId
        workingDirectory = chat.workingDirectory
        worktreePath = chat.worktreePath

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
            linkToolResults(in: messages)
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
            let encodedPath = Self.claudeProjectPathEncoding(workingDirectory)
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
            await importJSONLSession(sessionId: entry.sessionId, apiClient: apiClient, modelContext: modelContext)
        }
    }

    /// Import a Claude JSONL session: read the JSONL, convert to wisp format, write the
    /// wisp file to the sprite, then load via the normal wisp log path.
    private func importJSONLSession(sessionId: String, apiClient: SpritesAPIClient, modelContext: ModelContext) async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let encodedPath = Self.claudeProjectPathEncoding(workingDirectory)
        let projectDir = "/home/sprite/.claude/projects/\(encodedPath)"
        let command = "cat '\(projectDir)/\(sessionId).jsonl' 2>/dev/null"

        let (output, _) = await apiClient.runExec(
            spriteName: spriteName,
            command: command,
            timeout: 15
        )

        guard !output.isEmpty else { return }

        // Parse JSONL for immediate display
        let parsed = Self.parseSessionJSONL(output)
        guard !parsed.isEmpty else { return }

        messages = parsed
        rebuildToolUseIndex()
        persistMessages(modelContext: modelContext)

        // Convert JSONL to wisp format and write to sprite so future loads use one code path
        let wispContent = Self.convertJSONLToWisp(output)
        if !wispContent.isEmpty {
            let logPath = Self.wispLogPath(for: chatId)
            _ = await apiClient.runExec(
                spriteName: spriteName,
                command: "mkdir -p /home/sprite/.wisp/chats && cat > \(shellEscape(logPath)) <<'WISP_EOF'\n\(wispContent)\nWISP_EOF",
                timeout: 15
            )
        }
    }



    /// Parse a Claude session JSONL string into ChatMessages.
    /// Resilient — skips any lines that fail to decode.
    static func parseSessionJSONL(_ jsonl: String) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var currentAssistant: ChatMessage?
        var toolUseNames: [String: String] = [:]  // toolUseId -> toolName
        var toolUseCards: [String: ToolUseCard] = [:]  // toolUseId -> card (for result linkage)

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
                    let textBlocks = blocks.filter { $0.type == "text" }
                    let toolResultBlocks = blocks.filter { $0.type == "tool_result" }

                    if !textBlocks.isEmpty && toolResultBlocks.isEmpty {
                        // Pure text blocks: either a real user message (non-meta) or an
                        // internal injection like a skill invocation (isMeta:true).
                        // Skip meta entries — they're not user-authored content.
                        if entry.isMeta == true { break }

                        // Non-meta user message stored as text blocks (some Claude Code
                        // versions write user turns as [{type:text,text:...}] instead of
                        // a plain string). Treat it the same as the string case.
                        if let assistant = currentAssistant {
                            messages.append(assistant)
                            currentAssistant = nil
                        }
                        let text = textBlocks.compactMap { $0.text }.joined(separator: "\n")
                        let msg = ChatMessage(role: .user, content: [.text(text)])
                        messages.append(msg)
                    } else {
                        // Tool results — append to current assistant message
                        let assistant = currentAssistant ?? ChatMessage(role: .assistant)
                        if currentAssistant == nil {
                            currentAssistant = assistant
                        }
                        for block in toolResultBlocks {
                            guard let toolUseId = block.toolUseId else { continue }
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
                            toolUseCards[toolUseId]?.result = card
                            assistant.content.append(.toolResult(card))
                        }
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
                        toolUseCards[id] = card
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

    /// Parse a wisp NDJSON log file into ChatMessages.
    /// The file contains `wisp_user_prompt` events (user messages) interleaved with
    /// raw Claude stream-json events (system, assistant, user/tool_result, result).
    /// Resilient — skips any lines that fail to decode.
    static func parseWispLog(_ ndjson: String) -> (messages: [ChatMessage], sessionId: String?) {
        var messages: [ChatMessage] = []
        var currentAssistant: ChatMessage?
        var toolUseCards: [String: ToolUseCard] = [:]
        var sessionId: String?
        let decoder = JSONDecoder.apiDecoder()

        for line in ndjson.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8) else { continue }

            // Try wisp user prompt event first
            if let wispEvent = try? decoder.decode(WispUserPromptEvent.self, from: Data(data)),
               wispEvent.type == "wisp_user_prompt" {
                if let assistant = currentAssistant {
                    messages.append(assistant)
                    currentAssistant = nil
                }
                messages.append(ChatMessage(role: .user, content: [.text(wispEvent.text)]))
                continue
            }

            // Try Claude stream event
            guard let event = try? decoder.decode(ClaudeStreamEvent.self, from: Data(data)) else {
                continue
            }

            switch event {
            case .system(let se):
                sessionId = se.sessionId

            case .assistant(let ae):
                let assistant = currentAssistant ?? ChatMessage(role: .assistant)
                if currentAssistant == nil { currentAssistant = assistant }

                for block in ae.message.content {
                    switch block {
                    case .text(let text):
                        guard !text.isEmpty else { continue }
                        if case .text(let existing) = assistant.content.last {
                            assistant.content[assistant.content.count - 1] = .text(existing + text)
                        } else {
                            assistant.content.append(.text(text))
                        }
                    case .toolUse(let toolUse):
                        let card = ToolUseCard(
                            toolUseId: toolUse.id,
                            toolName: toolUse.name,
                            input: toolUse.input
                        )
                        toolUseCards[toolUse.id] = card
                        assistant.content.append(.toolUse(card))
                    case .unknown:
                        break
                    }
                }

            case .user(let toolResultEvent):
                let assistant = currentAssistant ?? ChatMessage(role: .assistant)
                if currentAssistant == nil { currentAssistant = assistant }

                for result in toolResultEvent.message.content {
                    let toolName = toolUseCards[result.toolUseId]?.toolName ?? "Tool"
                    let resultCard = ToolResultCard(
                        toolUseId: result.toolUseId,
                        toolName: toolName,
                        content: result.content ?? .null
                    )
                    toolUseCards[result.toolUseId]?.result = resultCard
                    assistant.content.append(.toolResult(resultCard))
                }

            case .result(let re):
                sessionId = re.sessionId
                if let assistant = currentAssistant {
                    messages.append(assistant)
                    currentAssistant = nil
                }

            case .unknown:
                break
            }
        }

        // Finalize any trailing assistant message
        if let assistant = currentAssistant {
            messages.append(assistant)
        }

        return (messages, sessionId)
    }

    /// Convert a Claude JSONL session string to wisp NDJSON format.
    /// User prompts become `wisp_user_prompt` events; assistant, tool result,
    /// system, and result lines are passed through verbatim (the JSONL and stream
    /// formats share the same structure — extra JSONL fields are ignored by the decoder).
    static func convertJSONLToWisp(_ jsonl: String) -> String {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let encoder = JSONEncoder()

        var lines: [String] = []

        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(SessionJSONLLine.self, from: Data(data)),
                  let type = entry.type
            else { continue }

            if type == "user" {
                guard entry.isMeta != true else { continue }

                if let content = entry.message?.content {
                    switch content {
                    case .string(let text):
                        // User prompt — convert to wisp_user_prompt
                        let event = WispUserPromptEvent(text: text, timestamp: "")
                        if let eventData = try? encoder.encode(event),
                           let eventStr = String(data: eventData, encoding: .utf8) {
                            lines.append(eventStr)
                        }
                    case .blocks(let blocks):
                        let hasToolResults = blocks.contains { $0.type == "tool_result" }
                        if hasToolResults {
                            // Tool results — pass through verbatim
                            lines.append(String(line))
                        } else {
                            // Text-only blocks — convert to wisp_user_prompt
                            let text = blocks.compactMap { $0.text }.joined(separator: "\n")
                            guard !text.isEmpty else { continue }
                            let event = WispUserPromptEvent(text: text, timestamp: "")
                            if let eventData = try? encoder.encode(event),
                               let eventStr = String(data: eventData, encoding: .utf8) {
                                lines.append(eventStr)
                            }
                        }
                    }
                }
            } else {
                // system, assistant, result — pass through verbatim
                lines.append(String(line))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Load chat history from the wisp NDJSON log file on the sprite.
    private func loadFromWispLog(apiClient: SpritesAPIClient, modelContext: ModelContext) async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let logPath = Self.wispLogPath(for: chatId)
        let (output, success) = await apiClient.runExec(
            spriteName: spriteName,
            command: "cat \(shellEscape(logPath)) 2>/dev/null",
            timeout: 30
        )

        guard success, !output.isEmpty else { return }

        let (parsed, parsedSessionId) = Self.parseWispLog(output)
        guard !parsed.isEmpty else { return }

        messages = parsed
        if let parsedSessionId { sessionId = parsedSessionId }
        rebuildToolUseIndex()
        persistMessages(modelContext: modelContext)
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
        // Cancel any orphaned reconnect task (e.g., reconnectIfNeeded fired in the same
        // run-loop turn before the task body had a chance to set .reconnecting).
        streamTask?.cancel()
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
        // Only interrupt genuine exec streams (.streaming / .connecting).
        // If the VM is already reconnecting, leave it alone.
        guard status == .streaming || status == .connecting else { return }
        // Cancel the stale stream — exec session stays alive on server for max_run_after_disconnect
        streamTask?.cancel()
        streamTask = nil
        status = .idle
        reconnectIfNeeded(apiClient: apiClient, modelContext: modelContext)
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
        let savedPrompt = queuedPrompt
        let savedAttachments = queuedAttachments

        detach(modelContext: modelContext)

        // Note: we keep sessionId intact so the next message can resume the session.
        // If the session turns out to be stale, the stale-session retry logic handles it.

        // Kill the exec session to stop it; clear execSessionId to prevent reconnect.
        let execId = execSessionId
        execSessionId = nil

        if let apiClient, let savedPrompt, let modelContext {
            // A message was queued behind the interrupted stream — drain it after the kill
            // so the user's pending input isn't silently discarded.
            let sName = spriteName
            let prompt = buildPrompt(text: savedPrompt, attachments: savedAttachments)
            let userMessage = ChatMessage(role: .user, content: [.text(prompt)])
            messages.append(userMessage)
            persistMessages(modelContext: modelContext)
            status = .connecting
            streamTask = Task {
                if let execId {
                    try? await apiClient.killExecSession(spriteName: sName, execSessionId: execId)
                }
                await executeClaudeCommand(prompt: prompt, apiClient: apiClient, modelContext: modelContext)
            }
        } else if let apiClient, let execId {
            let sName = spriteName
            Task {
                try? await apiClient.killExecSession(spriteName: sName, execSessionId: execId)
            }
        }
    }

    /// Attempt to reconnect to a running exec session when switching back to this chat.
    /// Called after loadSession — reattaches to the exec WebSocket if one exists.
    func reconnectIfNeeded(apiClient: SpritesAPIClient, modelContext: ModelContext) {
        guard !isStreaming else { return }

        if messages.isEmpty {
            // No local messages — the wisp log file (or legacy JSONL) on the sprite
            // contains the full conversation. Load it so the chat isn't blank.
            // This handles the case where SwiftData was cleared or the app was reinstalled.
            if !isLoadingHistory {
                Task { await loadFromWispLog(apiClient: apiClient, modelContext: modelContext) }
            }
            return
        }

        // If the last session completed cleanly, content is already loaded from
        // persistence — no need to hit the network at all.
        if let chat = fetchChat(modelContext: modelContext), chat.lastSessionComplete {
            // Edge case: app killed between persistMessages and saveSession(isComplete:false).
            // The session was previously complete but a new user message was appended and
            // persisted before the exec session was created. Restore it as a draft.
            restoreUndeliveredDraft(modelContext: modelContext)
            return
        }

        guard let execId = execSessionId else {
            // No exec session ID: message was never sent, or legacy service-based chat.
            // Restore any trailing user message as a draft rather than leaving a
            // stale bubble with no response.
            restoreUndeliveredDraft(modelContext: modelContext)
            return
        }

        // Optimistically show reconnecting immediately — local state already tells us
        // the session wasn't complete, so no need to wait for the task to start before
        // the UI reflects that we're reconnecting. reattachToExec also sets this, but
        // setting synchronously here avoids a brief idle flash while the Task warms up.
        status = .reconnecting

        // Cancel any orphaned task that may still be running (e.g., from a concurrent
        // call to reconnectIfNeeded triggered by both DashboardView startup and
        // resumeAllAfterBackground before the first task had a chance to set .reconnecting).
        streamTask?.cancel()
        streamTask = Task {
            // If this task was pre-cancelled (e.g. superseded by a second reconnectIfNeeded
            // call in the same run-loop turn), bail out before touching any state.
            guard !Task.isCancelled else { return }
            await reattachToExec(execSessionId: execId, apiClient: apiClient, modelContext: modelContext)
        }
    }

    /// If the last message is a user message with no response, remove it from history
    /// and restore its text to the input box as a draft.
    func restoreUndeliveredDraft(modelContext: ModelContext) {
        guard let last = messages.last, last.role == .user else { return }
        let text = last.textContent
        messages.removeLast()
        persistMessages(modelContext: modelContext)
        guard !text.isEmpty, inputText.isEmpty else { return }
        inputText = text
        saveDraft(modelContext: modelContext)
    }

    // MARK: - Private

    private func executeClaudeCommand(
        prompt: String,
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .connecting

        // Install question tool before connecting (sprite is awake at this point)
        if UserDefaults.standard.bool(forKey: "claudeQuestionTool") {
            let toolReady = await installClaudeQuestionToolIfNeeded(apiClient: apiClient)
            if !toolReady {
                status = .error("Claude question tool failed to install — disable it in Settings or try again")
                return
            }
        }

        // Persist the new session immediately; clear any prior completion flag
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

        // Build the full bash -c command with env vars inlined
        let logPath = Self.wispLogPath(for: chatId)
        var commandParts: [String] = [
            "export CLAUDE_CODE_OAUTH_TOKEN=\(shellEscape(claudeToken))",
            "export NO_DNA=1", // Signal to CLIs that they're running under an agent operator (no-dna.org)
            "mkdir -p \(shellEscape(workingDirectory))",
            "mkdir -p /home/sprite/.wisp/chats",
            "cd \(shellEscape(workingDirectory))",
        ]

        // Write the user prompt to the wisp log file before launching Claude.
        // Stream output doesn't include user prompts (they're CLI arguments),
        // so we write them ourselves to make the log file self-contained.
        let promptEvent = WispUserPromptEvent(
            text: prompt,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        if let jsonData = try? JSONEncoder().encode(promptEvent),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            commandParts.append("printf '%s\\n' \(shellEscape(jsonStr)) >> \(shellEscape(logPath))")
        }

        let gitName = UserDefaults.standard.string(forKey: "gitName") ?? ""
        let gitEmail = UserDefaults.standard.string(forKey: "gitEmail") ?? ""
        if !gitName.isEmpty {
            commandParts.append("git config --global user.name \(shellEscape(gitName))")
        }
        if !gitEmail.isEmpty {
            commandParts.append("git config --global user.email \(shellEscape(gitEmail))")
        }

        var claudeCmd = "claude -p --verbose --output-format stream-json --dangerously-skip-permissions"
        if UserDefaults.standard.bool(forKey: "claudeQuestionTool") {
            let sessionId = chatId.uuidString.lowercased()
            let configPath = ClaudeQuestionTool.mcpConfigFilePath(for: sessionId)
            // Write per-session MCP config (inlined in the command chain so no extra round-trip)
            commandParts.append("echo \(shellEscape(ClaudeQuestionTool.mcpConfigJSON(for: sessionId))) > \(shellEscape(configPath))")
            claudeCmd += " --disallowedTools AskUserQuestion"
            claudeCmd += " --mcp-config \(shellEscape(configPath))"
        }

        let modelId = modelOverride?.rawValue ?? UserDefaults.standard.string(forKey: "claudeModel") ?? ClaudeModel.sonnet.rawValue
        claudeCmd += " --model \(modelId)"

        let maxTurns = UserDefaults.standard.integer(forKey: "maxTurns")
        if maxTurns > 0 {
            claudeCmd += " --max-turns \(maxTurns)"
        }

        let customInstructions = UserDefaults.standard.string(forKey: "customInstructions") ?? ""
        if !customInstructions.isEmpty {
            claudeCmd += " --append-system-prompt \(shellEscape(customInstructions))"
        }

        usedResume = sessionId != nil
        if let sessionId {
            claudeCmd += " --resume \(shellEscape(sessionId))"
        }
        claudeCmd += " \(shellEscape(fullPrompt))"

        // Wrap claude with a heartbeat so the sprite stays alive while Claude
        // is waiting for an API response and Wisp is detached. The heartbeat
        // writes a byte to stderr every 20s — enough to count as output without
        // interfering with the NDJSON stdout stream. The trap ensures cleanup.
        let wrappedClaudeCmd = "{ (while true; do sleep 20; printf . >&2; done) & HBEAT=$!; trap \"kill $HBEAT 2>/dev/null\" EXIT; \(claudeCmd) | tee -a \(shellEscape(logPath)); kill $HBEAT 2>/dev/null; }"
        commandParts.append(wrappedClaudeCmd)
        let fullCommand = commandParts.joined(separator: " && ")

        receivedSystemEvent = false
        receivedResultEvent = false
        turnHasMutations = false
        processedEventUUIDs = []
        hasPlayedFirstTextHaptic = false

        logger.info("Exec command: \(Self.sanitize(fullCommand))")

        let session = apiClient.createExecSession(
            spriteName: spriteName,
            command: fullCommand,
            maxRunAfterDisconnect: 3600
        )
        session.connect()

        let assistantMessage = ChatMessage(role: .assistant)
        messages.append(assistantMessage)
        currentAssistantMessage = assistantMessage

        let streamResult = await processExecStream(events: session.events(), modelContext: modelContext)
        session.disconnect()

        let uuidCount = processedEventUUIDs.count
        logger.info("[Chat] Exec stream ended: result=\(streamResult), cancelled=\(Task.isCancelled), uuids=\(uuidCount)")

        // If cancelled (e.g. by resumeAfterBackground), bail out immediately.
        guard !Task.isCancelled else { return }

        if currentAssistantMessage?.id == assistantMessage.id {
            currentAssistantMessage = nil
        }

        // On disconnect, exec session is still alive on the server (max_run_after_disconnect).
        // Proactively reattach after a short delay so the user gets the response even if
        // they stay on this screen rather than triggering a manual tab-switch reconnect.
        if case .disconnected = streamResult {
            logger.info("[Chat] Disconnected mid-stream, will reattach after delay")
            status = .idle
            persistMessages(modelContext: modelContext)
            let capturedApiClient = apiClient
            let capturedModelContext = modelContext
            streamTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                reconnectIfNeeded(apiClient: capturedApiClient, modelContext: capturedModelContext)
            }
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
    enum StreamResult: Equatable, CustomStringConvertible {
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

    /// Process events from an exec WebSocket stream.
    /// Events whose UUID is in `processedEventUUIDs` are skipped (but system/result
    /// flags are still tracked). New event UUIDs are added to `processedEventUUIDs`
    /// as they are handled, so reattach replays never duplicate content.
    func processExecStream(
        events: AsyncThrowingStream<ExecEvent, Error>,
        modelContext: ModelContext
    ) async -> StreamResult {
        var receivedData = false
        var lastPersistTime = Date.distantPast

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if !receivedData {
                logger.warning("No exec data received in 30s")
            }
        }

        func handleOrSkip(_ parsedEvent: ClaudeStreamEvent) {
            if let uuid = parsedEvent.uuid, processedEventUUIDs.contains(uuid) {
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
            if isReplayingLiveService {
                applyReplayBuffer()
                isReplaying = false
                isReplayingLiveService = false
                if case .reconnecting = status { status = .streaming }
            }
            handleEvent(parsedEvent, modelContext: modelContext)
        }

        do {
            streamLoop: for try await event in events {
                guard !Task.isCancelled else { break streamLoop }

                switch event {
                case .sessionInfo(let id):
                    execSessionId = id
                    saveSession(modelContext: modelContext, isComplete: false)
                    if case .connecting = status { status = .streaming }
                    else if case .reconnecting = status { status = .streaming }

                case .stdout(let data):
                    receivedData = true
                    timeoutTask.cancel()
                    if case .connecting = status { status = .streaming }
                    else if case .reconnecting = status { status = .streaming }

                    let parsedEvents = await parser.parse(data: data)
                    for parsedEvent in parsedEvents {
                        handleOrSkip(parsedEvent)
                    }

                    if receivedResultEvent { break streamLoop }

                    let now = Date()
                    if now.timeIntervalSince(lastPersistTime) > 1 {
                        lastPersistTime = now
                        persistMessages(modelContext: modelContext)
                    }

                case .stderr:
                    // Heartbeat noise — count as activity to avoid timeout but discard
                    receivedData = true
                    timeoutTask.cancel()
                    if case .connecting = status { status = .streaming }
                    else if case .reconnecting = status { status = .streaming }

                case .exit(let code):
                    timeoutTask.cancel()
                    logger.info("Exec exit: code=\(code)")
                    let remaining = await parser.flush()
                    for e in remaining {
                        handleOrSkip(e)
                    }
                    break streamLoop
                }
            }

            let remaining = await parser.flush()
            for e in remaining {
                handleOrSkip(e)
            }
            timeoutTask.cancel()

            let uuidCount = processedEventUUIDs.count
            logger.info("Exec stream ended: receivedData=\(receivedData) uuids=\(uuidCount) gotResult=\(self.receivedResultEvent)")
            if Task.isCancelled { return .cancelled }
            if !receivedData { return .timedOut }
            return receivedResultEvent ? .completed : .disconnected
        } catch {
            timeoutTask.cancel()
            logger.error("Exec stream error: \(Self.sanitize(error.localizedDescription), privacy: .public)")
            if Task.isCancelled { return .cancelled }
            if receivedData { return .disconnected }
            status = .error("No response from Claude — try again")
            return .timedOut
        }
    }

    /// Reattach to a running exec session after disconnect (e.g. app backgrounded).
    /// Replays scrollback from the exec session, then streams live events.
    /// If the exec session is gone (sprite slept), falls back to restoreFromSessionFile.
    private func reattachToExec(
        execSessionId: String,
        apiClient: SpritesAPIClient,
        modelContext: ModelContext
    ) async {
        status = .reconnecting
        isReplaying = true
        isReplayingLiveService = true
        defer {
            applyReplayBuffer()
            isReplaying = false
            isReplayingLiveService = false
        }

        hasPlayedFirstTextHaptic = false

        // Snapshot the current tail assistant message content before any clearing.
        // Used below to restore if the replay produces less content (e.g. truncated logs).
        let savedContent: [ChatContent]
        if let existing = currentAssistantMessage {
            savedContent = existing.content
        } else if let last = messages.last, last.role == .assistant {
            savedContent = last.content
        } else {
            savedContent = []
        }

        // Ensure we have an assistant message to append into.
        let assistantMessage: ChatMessage
        let hasPriorEvents = !processedEventUUIDs.isEmpty
        if let existing = currentAssistantMessage {
            assistantMessage = existing
            if !hasPriorEvents { assistantMessage.content = [] }
        } else if let last = messages.last, last.role == .assistant {
            assistantMessage = last
            if !hasPriorEvents { assistantMessage.content = [] }
            currentAssistantMessage = last
        } else {
            assistantMessage = ChatMessage(role: .assistant)
            messages.append(assistantMessage)
            currentAssistantMessage = assistantMessage
        }

        await parser.reset()
        if !hasPriorEvents {
            toolUseIndex = [:]
            rebuildToolUseIndex()
        }
        receivedSystemEvent = false
        receivedResultEvent = false

        let session = apiClient.attachExecSession(spriteName: spriteName, execSessionId: execSessionId)
        session.connect()

        let streamResult = await processExecStream(events: session.events(), modelContext: modelContext)
        session.disconnect()

        if currentAssistantMessage?.id == assistantMessage.id {
            currentAssistantMessage = nil
        }

        // .timedOut means no data was received at all — exec session is gone (sprite slept,
        // session expired). Restore from Claude's session file so the user sees the result.
        // .disconnected means data was received but no result event — the connection dropped
        // while Claude was still running. Schedule a proactive reconnect (same as the initial
        // stream) so we re-attach and pick up the rest rather than showing partial content.
        if case .timedOut = streamResult, sessionId != nil {
            if case .error = status { status = .reconnecting }
            logger.info("[Chat] Exec session gone on reattach — restoring from session file")
            await restoreFromSessionFile(apiClient: apiClient, modelContext: modelContext)
        } else if case .disconnected = streamResult {
            logger.info("[Chat] Dropped mid-reattach — will reconnect after delay")
            saveSession(modelContext: modelContext)
            if !Task.isCancelled { status = .idle }
            persistMessages(modelContext: modelContext)
            let capturedApiClient = apiClient
            let capturedModelContext = modelContext
            streamTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                reconnectIfNeeded(apiClient: capturedApiClient, modelContext: capturedModelContext)
            }
            return
        }

        saveSession(modelContext: modelContext)
        if !Task.isCancelled {
            status = .idle
        }
        persistMessages(modelContext: modelContext)

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

    /// Restore chat history from Claude's .jsonl session file on the sprite.
    /// Used when the exec session is gone (sprite slept, exec expired).
    private func restoreFromSessionFile(apiClient: SpritesAPIClient, modelContext: ModelContext) async {
        // Try wisp log file first — it captures the full stream including sub-agent calls.
        let logPath = Self.wispLogPath(for: chatId)
        let (wispOutput, wispSuccess) = await apiClient.runExec(
            spriteName: spriteName,
            command: "cat \(shellEscape(logPath)) 2>/dev/null",
            timeout: 30
        )

        if wispSuccess, !wispOutput.isEmpty {
            let (parsed, parsedSessionId) = Self.parseWispLog(wispOutput)
            if !parsed.isEmpty {
                messages = parsed
                if let parsedSessionId { sessionId = parsedSessionId }
                rebuildToolUseIndex()

                if let last = messages.last, last.role == .user {
                    restoreUndeliveredDraft(modelContext: modelContext)
                } else {
                    self.execSessionId = nil
                    saveSession(modelContext: modelContext, isComplete: true)
                }
                return
            }
        }

        // Fallback: read Claude's internal JSONL for chats that predate wisp log files.
        guard let sessionId = sessionId else { return }

        let encodedPath = Self.claudeProjectPathEncoding(workingDirectory)
        let path = "~/.claude/projects/\(encodedPath)/\(sessionId).jsonl"

        var (output, success) = await apiClient.runExec(
            spriteName: spriteName,
            command: "cat \(path)",
            timeout: 30
        )

        if !success || output.isEmpty {
            let (findOutput, _) = await apiClient.runExec(
                spriteName: spriteName,
                command: "find ~/.claude -name '\(sessionId).jsonl' -print -quit 2>/dev/null",
                timeout: 15
            )
            let foundPath = findOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !foundPath.isEmpty {
                (output, success) = await apiClient.runExec(
                    spriteName: spriteName,
                    command: "cat '\(foundPath)'",
                    timeout: 30
                )
            }
        }

        guard !output.isEmpty else { return }

        let parsed = Self.parseSessionJSONL(output)
        guard !parsed.isEmpty else { return }

        messages = parsed
        rebuildToolUseIndex()

        if let last = messages.last, last.role == .user {
            restoreUndeliveredDraft(modelContext: modelContext)
        } else {
            self.execSessionId = nil
            saveSession(modelContext: modelContext, isComplete: true)
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
                    if toolUse.name == "mcp__askUser__WispAsk" && !isReplaying {
                        markChatUnread(modelContext: modelContext)
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
            let alreadyComplete = fetchChat(modelContext: modelContext)?.lastSessionComplete ?? false
            saveSession(modelContext: modelContext, isComplete: true)
            if !alreadyComplete { markChatUnread(modelContext: modelContext) }

            let autoCheckpointEnabled = UserDefaults.standard.bool(forKey: "autoCheckpoint")
            if !isReplaying, turnHasMutations, autoCheckpointEnabled, let apiClient {
                let assistantMsg = currentAssistantMessage
                let sprite = spriteName
                Task { [weak self, weak assistantMsg] in
                    guard let self else { return }
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
        Task { [weak self] in
            let jsonObject = ["answer": answer]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject) else { return }
            let path = ClaudeQuestionTool.responseFilePath(for: sessionId)
            do {
                _ = try await apiClient.uploadFile(spriteName: sprite, remotePath: path, data: jsonData)
            } catch {
                self?.status = .error("Failed to send answer — try again")
            }
        }
    }

    var isCheckpointing = false

    func createCheckpoint(for message: ChatMessage, modelContext: ModelContext) {
        guard let apiClient, message.checkpointId == nil else { return }
        isCheckpointing = true
        let sprite = spriteName
        Task { [weak self, weak message] in
            defer { self?.isCheckpointing = false }
            guard let self else { return }
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

    /// Builds the shell command that creates a git worktree for a new chat branch.
    ///
    /// - Fetches origin so the new branch starts from the latest remote state (non-fatal on failure).
    /// - Resolves the remote's default branch via `origin/HEAD` (handles master, develop, etc.);
    ///   `remote set-head --auto` populates it if not already set. Falls back to local `HEAD` if
    ///   everything fails (no remote, offline and never fetched).
    /// - Marks all directories as safe to avoid "dubious ownership" errors when the repo is owned
    ///   by a different uid than the running process (common on Sprites).
    /// - Prunes stale worktree registrations (handles dirs deleted without `git worktree remove`).
    /// - Echoes the worktree path on success, or `WORKTREE_ERR:<stderr>` on failure.
    ///
    /// Extracted as a pure function so it can be unit-tested without going through the async exec path.
    static func buildWorktreeSetupCommand(
        currentWorkDir: String,
        worktreeParent: String,
        worktreeDir: String,
        uniqueBranchName: String
    ) -> String {
        let qWorkDir = shellEscape(currentWorkDir)
        let qWorktreeParent = shellEscape(worktreeParent)
        let qWorktreeDir = shellEscape(worktreeDir)
        let qBranch = shellEscape(uniqueBranchName)

        return """
        git config --global --add safe.directory '*' 2>/dev/null; \
        git -C \(qWorkDir) fetch origin 2>/dev/null || true; \
        git -C \(qWorkDir) remote set-head origin --auto 2>/dev/null || true; \
        BASE_REF=$(git -C \(qWorkDir) symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo HEAD); \
        git -C \(qWorkDir) worktree prune 2>/dev/null; \
        mkdir -p \(qWorktreeParent) && GTWT_OUT=$(git -C \(qWorkDir) worktree add \(qWorktreeDir) -b \(qBranch) "$BASE_REF" 2>&1); \
        if [ $? -eq 0 ]; then echo \(qWorktreeDir); else echo "WORKTREE_ERR:$(echo $GTWT_OUT)"; fi
        """
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

        let command = Self.buildWorktreeSetupCommand(
            currentWorkDir: currentWorkDir,
            worktreeParent: worktreeParent,
            worktreeDir: worktreeDir,
            uniqueBranchName: uniqueBranchName
        )

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
            copyCommands.append("cp \(shellEscape(attachment.path)) \(shellEscape(newPath)) 2>/dev/null && echo ok || echo skip")
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

    private func markChatUnread(modelContext: ModelContext) {
        guard !isActive else { return }
        guard let chat = fetchChat(modelContext: modelContext) else { return }
        chat.isUnread = true
        try? modelContext.save()
    }

    private func saveSession(modelContext: ModelContext, isComplete: Bool? = nil) {
        guard let chat = fetchChat(modelContext: modelContext) else { return }
        chat.claudeSessionId = sessionId
        chat.execSessionId = execSessionId
        chat.lastUsed = Date()
        if let isComplete { chat.lastSessionComplete = isComplete }
        try? modelContext.save()
    }

    /// Encode a filesystem path the same way Claude Code does when creating its
    /// per-project JSONL directories: replace every `/` and `.` with `-`.
    ///
    /// Example: `/home/sprite/.wisp/worktrees/wisp/my-branch`
    ///       →  `-home-sprite--wisp-worktrees-wisp-my-branch`
    ///
    /// Wisp previously only replaced `/`, producing `-home-sprite-.wisp-...`
    /// which didn't match the on-disk directory name.
    /// Re-link ToolResultCards to their ToolUseCards after a SwiftData round-trip.
    /// Persistence serialises tool use and tool result as separate flat items and does
    /// not store the ToolUseCard.result reference, so it must be rebuilt on load.
    private func linkToolResults(in messages: [ChatMessage]) {
        var toolUseCards: [String: ToolUseCard] = [:]
        for message in messages {
            for item in message.content {
                switch item {
                case .toolUse(let card):
                    toolUseCards[card.toolUseId] = card
                case .toolResult(let result):
                    toolUseCards[result.toolUseId]?.result = result
                default:
                    break
                }
            }
        }
    }

    /// Encode a filesystem path the same way Claude Code does when creating its
    /// per-project JSONL directories: replace every `/` and `.` with `-`.
    ///
    /// Example: `/home/sprite/.wisp/worktrees/wisp/my-branch`
    ///       →  `-home-sprite--wisp-worktrees-wisp-my-branch`
    ///
    /// Wisp previously only replaced `/`, producing `-home-sprite-.wisp-...`
    /// which didn't match the on-disk directory name.
    /// Path to the wisp stream log file for a given chat on the sprite.
    nonisolated static func wispLogPath(for chatId: UUID) -> String {
        "/home/sprite/.wisp/chats/\(chatId.uuidString.lowercased()).wisplog"
    }

    nonisolated static func claudeProjectPathEncoding(_ path: String) -> String {
        path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
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

    func setExecSessionId(_ id: String?) {
        execSessionId = id
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
