import SwiftUI

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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.messages.isEmpty && !isReadOnly {
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
                    if viewModel.isStreaming && viewModel.pendingWispAskCard == nil {
                        ThinkingShimmerView(label: viewModel.activeToolLabel ?? "Thinking...")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id("shimmer")
                    }
                    if let pendingText = viewModel.queuedPrompt {
                        PendingUserBubbleView(text: pendingText) {
                            viewModel.inputText = pendingText
                            viewModel.queuedPrompt = nil
                            isInputFocused = true
                        } onCancel: {
                            viewModel.cancelQueuedPrompt()
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
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
                if viewModel.isStreaming {
                    proxy.scrollTo("bottom")
                }
            }
            .onChange(of: viewModel.activeToolLabel) {
                if viewModel.isStreaming {
                    proxy.scrollTo("bottom")
                }
            }
            .onChange(of: viewModel.queuedPrompt) {
                proxy.scrollTo("bottom")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let topAccessory { topAccessory }
                ChatStatusBar(
                    status: viewModel.status,
                    modelName: viewModel.modelName,
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
                    isFocused: $isInputFocused
                )
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
