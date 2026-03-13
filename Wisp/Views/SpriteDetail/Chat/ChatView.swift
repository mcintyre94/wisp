import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(LoopManager.self) private var loopManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: ChatViewModel
    var isReadOnly: Bool = false
    var selectedTab: Binding<SpriteTab>? = nil
    var existingSessionIds: Set<String> = []
    var onFork: ((String, UUID) -> Void)? = nil
    @FocusState private var isInputFocused: Bool
    @State private var contentOpacity: Double = 0
    @State private var showCreateLoopSheet = false
    @State private var isAtBottom: Bool = true

    // Attachment state
    @State private var showFileBrowser = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    // Side chat
    @State private var showSideChat = false
    @State private var sideChatViewModel: SideChatViewModel?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.messages.isEmpty && !isReadOnly && !viewModel.usesWorktree {
                        SessionSuggestionsView(
                            sessions: viewModel.remoteSessions,
                            hasAnySessions: viewModel.hasAnyRemoteSessions,
                            isLoading: viewModel.isLoadingRemoteSessions || viewModel.isLoadingHistory
                        ) { entry in
                            contentOpacity = 0
                            viewModel.selectRemoteSession(entry, apiClient: apiClient, modelContext: modelContext)
                        }
                    }
                    ForEach(viewModel.messages) { message in
                        messageView(message)
                    }
                    if viewModel.isStreaming && !viewModel.status.isReconnecting && viewModel.pendingWispAskCard == nil {
                        ThinkingShimmerView(label: viewModel.status.isConnecting ? "Connecting…" : (viewModel.activeToolLabel ?? "Thinking…"))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id("shimmer")
                    }
                    if let pendingText = viewModel.queuedPrompt {
                        PendingUserBubbleView(
                            text: pendingText,
                            files: viewModel.queuedAttachments
                        ) {
                            viewModel.inputText = pendingText
                            viewModel.attachedFiles = viewModel.queuedAttachments
                            viewModel.queuedPrompt = nil
                            viewModel.queuedAttachments = []
                            isInputFocused = true
                        } onCancel: {
                            viewModel.cancelQueuedPrompt()
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onScrollVisibilityChange(threshold: 0.5) { visible in
                            isAtBottom = visible
                        }
                }
                .opacity(contentOpacity)
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                proxy.scrollTo("bottom")
            }
            .onChange(of: viewModel.messages.last?.content.count) {
                if viewModel.isStreaming && isAtBottom {
                    proxy.scrollTo("bottom")
                }
            }
            .onChange(of: viewModel.activeToolLabel) {
                if viewModel.isStreaming && isAtBottom {
                    proxy.scrollTo("bottom")
                }
            }
            .onChange(of: viewModel.queuedPrompt) {
                proxy.scrollTo("bottom")
            }
            .onChange(of: viewModel.isStreaming) { _, streaming in
                if streaming {
                    isAtBottom = true
                    proxy.scrollTo("bottom")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let selectedTab { SpriteTabPicker(selectedTab: selectedTab) }
                ChatStatusBar(
                    status: viewModel.status,
                    modelName: viewModel.modelName,
                    hasPendingWispAsk: viewModel.pendingWispAskCard != nil
                )
            }
        }
        .task {
            // Small delay to let loadSession populate messages first
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.3)) {
                contentOpacity = 1
            }
            if viewModel.messages.isEmpty && !isReadOnly {
                viewModel.fetchRemoteSessions(
                    apiClient: apiClient,
                    existingSessionIds: existingSessionIds
                )
            }
        }
        .onChange(of: viewModel.isLoadingHistory) {
            if !viewModel.isLoadingHistory {
                withAnimation(.easeOut(duration: 0.3)) {
                    contentOpacity = 1
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                viewModel.saveDraft(modelContext: modelContext)
            }
        }
        .onChange(of: viewModel.inputText) {
            viewModel.saveDraft(modelContext: modelContext)
        }
        .onDisappear {
            viewModel.saveDraft(modelContext: modelContext)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isReadOnly {
                closedChatBar
            } else {
                ChatInputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    hasQueuedMessage: viewModel.queuedPrompt != nil,
                    onSend: {
                        isInputFocused = false
                        viewModel.sendMessage(apiClient: apiClient, modelContext: modelContext)
                    },
                    onInterrupt: {
                        viewModel.interrupt(apiClient: apiClient, modelContext: modelContext)
                    },
                    onBrowseSpriteFiles: { showFileBrowser = true },
                    onPickPhoto: { showPhotoPicker = true },
                    onPickFile: { showFilePicker = true },
                    onLongPressSend: { showCreateLoopSheet = true },
                    onPasteFromClipboard: handlePasteFromClipboard,
                    onPasteItems: handlePastedItems,
                    isUploading: viewModel.isUploadingAttachment,
                    attachedFiles: viewModel.attachedFiles,
                    onRemoveAttachment: { file in
                        viewModel.attachedFiles.removeAll { $0.id == file.id }
                    },
                    lastUploadedFileName: viewModel.lastUploadedFileName,
                    onStash: { viewModel.stashDraft() },
                    onSideChat: viewModel.sessionId != nil ? {
                        sideChatViewModel = SideChatViewModel(
                            spriteName: viewModel.spriteName,
                            sessionId: viewModel.sessionId!,
                            workingDirectory: viewModel.workingDirectory
                        )
                        showSideChat = true
                    } : nil,
                    isFocused: $isInputFocused
                )
            }
        }
        .sheet(isPresented: $showSideChat) {
            if let vm = sideChatViewModel {
                SideChatView(viewModel: vm)
                    .environment(apiClient)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showFileBrowser) {
            SpriteFileBrowserView(
                spriteName: viewModel.spriteName,
                startingDirectory: viewModel.workingDirectory,
                apiClient: apiClient,
                onFileSelected: { path in
                    let name = (path as NSString).lastPathComponent
                    viewModel.attachedFiles.append(AttachedFile(name: name, path: path))
                }
            )
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 1, matching: .images)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                Task {
                    if let remotePath = await viewModel.uploadFileFromDevice(apiClient: apiClient, fileURL: url) {
                        let name = (remotePath as NSString).lastPathComponent
                        viewModel.attachedFiles.append(AttachedFile(name: name, path: remotePath))
                    }
                }
            case .failure(let error):
                viewModel.uploadAttachmentError = "Failed to pick file: \(error.localizedDescription)"
            }
        }
        .alert("Upload Error", isPresented: .init(
            get: { viewModel.uploadAttachmentError != nil },
            set: { if !$0 { viewModel.uploadAttachmentError = nil } }
        )) {
            Button("OK") { viewModel.uploadAttachmentError = nil }
        } message: {
            if let error = viewModel.uploadAttachmentError {
                Text(error)
            }
        }
        .sheet(isPresented: $showCreateLoopSheet) {
            CreateLoopSheet(
                spriteName: viewModel.spriteName,
                workingDirectory: viewModel.workingDirectory,
                promptText: $viewModel.inputText,
                onCreateLoop: { prompt, interval, duration in
                    let loop = SpriteLoop(
                        spriteName: viewModel.spriteName,
                        workingDirectory: viewModel.workingDirectory,
                        prompt: prompt,
                        interval: interval,
                        duration: duration
                    )
                    modelContext.insert(loop)
                    try? modelContext.save()
                    loopManager.register(loop: loop, modelContext: modelContext)
                    viewModel.inputText = ""
                }
            )
        }
        .onChange(of: selectedPhotos) {
            guard let item = selectedPhotos.first else { return }
            selectedPhotos = []
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    viewModel.uploadAttachmentError = "Failed to load photo data"
                    return
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                if let remotePath = await viewModel.uploadPhotoData(apiClient: apiClient, data: data, fileExtension: ext) {
                    let name = (remotePath as NSString).lastPathComponent
                    viewModel.attachedFiles.append(AttachedFile(name: name, path: remotePath))
                }
            }
        }
    }

    private static let pasteImageFormats: [(UTType, String)] = [
        (.png, "png"),
        (.jpeg, "jpg"),
        (.gif, "gif"),
        (.webP, "webp"),
        (UTType("public.heic") ?? .image, "heic"),
    ]

    private func handlePasteFromClipboard() {
        let pasteboard = UIPasteboard.general

        for (type, ext) in Self.pasteImageFormats {
            if let data = pasteboard.data(forPasteboardType: type.identifier) {
                Task {
                    if let remotePath = await viewModel.uploadPhotoData(apiClient: apiClient, data: data, fileExtension: ext) {
                        viewModel.addAttachedFile(remotePath: remotePath)
                    }
                }
                return
            }
        }

        // Fallback: any image via UIImage
        if pasteboard.hasImages, let image = pasteboard.image, let data = image.pngData() {
            Task {
                if let remotePath = await viewModel.uploadPhotoData(apiClient: apiClient, data: data, fileExtension: "png") {
                    viewModel.addAttachedFile(remotePath: remotePath)
                }
            }
            return
        }

        // Try a file URL (e.g. copied from Files app)
        if let url = pasteboard.url, url.isFileURL {
            Task {
                if let remotePath = await viewModel.uploadFileFromDevice(apiClient: apiClient, fileURL: url) {
                    viewModel.addAttachedFile(remotePath: remotePath)
                }
            }
            return
        }

        viewModel.uploadAttachmentError = "No image or file found in clipboard"
    }

    private func handlePastedItems(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        for (type, ext) in Self.pasteImageFormats where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    if let remotePath = await viewModel.uploadPhotoData(apiClient: apiClient, data: data, fileExtension: ext) {
                        viewModel.addAttachedFile(remotePath: remotePath)
                    }
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    if let remotePath = await viewModel.uploadPhotoData(apiClient: apiClient, data: data, fileExtension: "png") {
                        viewModel.addAttachedFile(remotePath: remotePath)
                    }
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let url = item as? URL, url.isFileURL else { return }
                Task { @MainActor in
                    if let remotePath = await viewModel.uploadFileFromDevice(apiClient: apiClient, fileURL: url) {
                        viewModel.addAttachedFile(remotePath: remotePath)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        let isLastAssistant = message.role == .assistant
            && message.id == viewModel.messages.last(where: { $0.role == .assistant })?.id
        ChatMessageView(
            message: message,
            isStreaming: viewModel.isStreaming && message.id == viewModel.currentAssistantMessageId,
            workingDirectory: viewModel.workingDirectory,
            onCreateCheckpoint: isLastAssistant ? {
                viewModel.createCheckpoint(for: message, modelContext: modelContext)
            } : nil,
            isCheckpointDisabled: viewModel.isCheckpointing,
            onAnswerWispAsk: { answer in
                viewModel.submitWispAskAnswer(answer)
            }
        )
        .id(message.id)

        if let checkpointId = message.checkpointId {
            CheckpointMarkerView(
                comment: message.checkpointComment
            ) {
                onFork?(checkpointId, message.id)
            }
        }
    }

    private var closedChatBar: some View {
        HStack {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
            Text("This chat is closed")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

#Preview {
    let viewModel = ChatViewModel(
        spriteName: "my-sprite",
        chatId: UUID(),
        currentServiceName: nil,
        workingDirectory: "/home/sprite/project"
    )
    NavigationStack {
        ChatView(viewModel: viewModel)
            .environment(SpritesAPIClient())
            .modelContainer(for: [SpriteChat.self, SpriteSession.self], inMemory: true)
    }
}
