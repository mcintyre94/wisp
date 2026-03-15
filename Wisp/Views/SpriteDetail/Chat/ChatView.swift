import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: ChatViewModel
    var isReadOnly: Bool = false
    var topAccessory: AnyView? = nil
    var existingSessionIds: Set<String> = []
    var onFork: ((String, UUID) -> Void)? = nil
    @FocusState private var isInputFocused: Bool
    @State private var contentOpacity: Double = 0
    @State private var isAtBottom: Bool = true

    // Attachment state
    @State private var showFileBrowser = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    // Quick Actions
    @State private var quickActionsViewModel: QuickActionsViewModel?

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
                if let topAccessory { topAccessory }
                ChatStatusBar(
                    status: viewModel.status,
                    modelName: viewModel.modelName,
                    modelOverride: Bindable(viewModel).modelOverride,
                    hasPendingWispAsk: viewModel.pendingWispAskCard != nil
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    contentOpacity = 1
                }
            }
        }
        .task {
            // Small delay to let loadSession populate messages first
            try? await Task.sleep(for: .milliseconds(100))
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
        .onChange(of: viewModel.attachedFiles.count) {
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
                    onPasteFromClipboard: handlePasteFromClipboard,
                    isUploading: viewModel.isUploadingAttachment,
                    attachedFiles: viewModel.attachedFiles,
                    onRemoveAttachment: { file in
                        viewModel.attachedFiles.removeAll { $0.id == file.id }
                    },
                    lastUploadedFileName: viewModel.lastUploadedFileName,
                    onStash: { viewModel.stashDraft() },
                    isFocused: $isInputFocused
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    quickActionsViewModel = QuickActionsViewModel(
                        spriteName: viewModel.spriteName,
                        sessionId: viewModel.sessionId,
                        workingDirectory: viewModel.workingDirectory
                    )
                } label: {
                    Image(systemName: "bolt")
                }
            }
        }
        .sheet(item: $quickActionsViewModel) { vm in
            QuickActionsView(
                viewModel: vm,
                insertCallback: { text in
                    viewModel.inputText += (viewModel.inputText.isEmpty ? "" : "\n") + text
                    quickActionsViewModel = nil
                }
            )
            .environment(apiClient)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

        // Try a file URL via item providers (handles security-scoped URLs from Files app)
        for provider in pasteboard.itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let url = item as? URL else { return }
                    Task { @MainActor in
                        if let remotePath = await viewModel.uploadFileFromDevice(apiClient: apiClient, fileURL: url) {
                            viewModel.addAttachedFile(remotePath: remotePath)
                        }
                    }
                }
                return
            }
        }

        // Fallback: direct URL from pasteboard
        if let url = pasteboard.url, url.isFileURL {
            Task {
                if let remotePath = await viewModel.uploadFileFromDevice(apiClient: apiClient, fileURL: url) {
                    viewModel.addAttachedFile(remotePath: remotePath)
                }
            }
            return
        }

        // Fallback: load raw data from item providers (files from Files app use their
        // content UTI directly — e.g. com.adobe.pdf — rather than public.file-url)
        for provider in pasteboard.itemProviders {
            guard let typeId = provider.registeredTypeIdentifiers.first(where: { id in
                guard let type = UTType(id) else { return false }
                return type.conforms(to: .data) && !type.conforms(to: .text)
            }) else { continue }

            let suggestedName = provider.suggestedName
            let fileExt = UTType(typeId)?.preferredFilenameExtension
            provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, _ in
                guard let data else { return }
                let baseName = suggestedName ?? "pasted_file"
                let filename: String
                if let ext = fileExt, !baseName.hasSuffix(".\(ext)") {
                    filename = "\(baseName).\(ext)"
                } else {
                    filename = baseName
                }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent(filename)
                try? FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard (try? data.write(to: tempURL)) != nil else { return }
                Task { @MainActor in
                    if let remotePath = await viewModel.uploadFileFromDevice(apiClient: apiClient, fileURL: tempURL) {
                        viewModel.addAttachedFile(remotePath: remotePath)
                    }
                    try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
                }
            }
            return
        }

        viewModel.uploadAttachmentError = "No image or file found in clipboard"
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
