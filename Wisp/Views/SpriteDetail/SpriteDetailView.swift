import SwiftUI
import SwiftData

struct SpriteDetailView: View {
    let sprite: Sprite
    @State private var selectedTab: SpriteTab = .chat
    @State private var chatListViewModel: SpriteChatListViewModel
    @State private var chatViewModel: ChatViewModel?
    @State private var checkpointsViewModel: CheckpointsViewModel
    @State private var showChatSwitcher = false
    @State private var showStaleChatsAlert = false
    @State private var knownStreamingChatIds: Set<UUID> = []
    @State private var showCopiedFeedback = false
    @State private var pendingFork: (checkpointId: String, messageId: UUID)? = nil
    @State private var isForking = false
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    init(sprite: Sprite) {
        self.sprite = sprite
        _chatListViewModel = State(initialValue: SpriteChatListViewModel(spriteName: sprite.name))
        _checkpointsViewModel = State(initialValue: CheckpointsViewModel(spriteName: sprite.name))
    }

    private var pickerView: some View {
        SpriteTabPicker(selectedTab: $selectedTab)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            SpriteOverviewView(sprite: sprite)
                .safeAreaInset(edge: .top, spacing: 0) { pickerView }
        case .chat:
            if let chatViewModel {
                let isReadOnly = chatListViewModel.activeChat?.isClosed == true
                ChatView(
                    viewModel: chatViewModel,
                    isReadOnly: isReadOnly,
                    topAccessory: AnyView(pickerView),
                    existingSessionIds: Set(chatListViewModel.chats.filter { !$0.isClosed }.compactMap(\.claudeSessionId)),
                    onFork: { checkpointId, messageId in
                        pendingFork = (checkpointId, messageId)
                    }
                )
                    .id(chatViewModel.chatId)
            } else {
                ProgressView()
                    .safeAreaInset(edge: .top, spacing: 0) { pickerView }
            }
        case .checkpoints:
            CheckpointsView(viewModel: checkpointsViewModel)
                .safeAreaInset(edge: .top, spacing: 0) { pickerView }
        }
    }

    var body: some View {
        tabContent
        .overlay {
            if isForking {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Restoring checkpoint...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .allowsHitTesting(!isForking)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(showCopiedFeedback ? "Copied!" : sprite.name)
                    .font(.headline)
                    .contentTransition(.numericText())
                    .onTapGesture {
                        UIPasteboard.general.string = sprite.name
                        withAnimation {
                            showCopiedFeedback = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            withAnimation {
                                showCopiedFeedback = false
                            }
                        }
                    }
            }
            if selectedTab == .chat {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showChatSwitcher = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }

                        Button {
                            let chat = chatListViewModel.createChat(modelContext: modelContext)
                            switchToChat(chat)
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .disabled(chatViewModel?.status.isConnecting == true)
                    }
                }
            }
        }
        .task {
            chatListViewModel.spriteCreatedAt = sprite.createdAt
            chatListViewModel.loadChats(modelContext: modelContext)

            // Detect stale chats from a recreated sprite
            if let spriteCreated = sprite.createdAt,
               let storedCreated = chatListViewModel.chats.first?.spriteCreatedAt,
               spriteCreated > storedCreated {
                showStaleChatsAlert = true
            }

            // Create first chat if none exist
            if chatListViewModel.chats.isEmpty {
                chatListViewModel.createChat(modelContext: modelContext)
            }

            // Initialize chat VM for active chat
            if let active = chatListViewModel.activeChat {
                switchToChat(active)
            }
        }
        .onChange(of: chatListViewModel.activeChatId) { oldId, newId in
            guard newId != oldId, let newId,
                  let chat = chatListViewModel.chats.first(where: { $0.id == newId }) else { return }
            switchToChat(chat)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                chatViewModel?.resumeAfterBackground(apiClient: apiClient, modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showChatSwitcher) {
            ChatSwitcherSheet(viewModel: chatListViewModel)
        }
        .alert("Sprite Recreated", isPresented: $showStaleChatsAlert) {
            Button("Start Fresh", role: .destructive) {
                chatListViewModel.clearAllChats(apiClient: apiClient, modelContext: modelContext)
                let chat = chatListViewModel.createChat(modelContext: modelContext)
                switchToChat(chat)
            }
            Button("Keep History", role: .cancel) {
                chatListViewModel.updateSpriteCreatedAt(sprite.createdAt, modelContext: modelContext)
            }
        } message: {
            Text("This sprite was created after your existing chats. Would you like to start fresh?")
        }
        .alert("Fork from Checkpoint?", isPresented: .init(
            get: { pendingFork != nil },
            set: { if !$0 { pendingFork = nil } }
        )) {
            Button("Fork", role: .destructive) {
                if let fork = pendingFork {
                    forkFromCheckpoint(checkpointId: fork.checkpointId, messageId: fork.messageId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore the Sprite to this checkpoint and create a new chat. Any changes since will be lost.")
        }
    }

    private func switchToChat(_ chat: SpriteChat) {
        guard chatViewModel?.chatId != chat.id else { return }

        // Detach old VM (cancel stream but keep service running)
        if let oldVM = chatViewModel {
            let wasStreaming = oldVM.detach(modelContext: modelContext)
            if wasStreaming {
                knownStreamingChatIds.insert(oldVM.chatId)
            }
        }

        let vm = ChatViewModel(
            spriteName: sprite.name,
            chatId: chat.id,
            currentServiceName: chat.currentServiceName,
            workingDirectory: chat.workingDirectory
        )
        vm.loadSession(apiClient: apiClient, modelContext: modelContext)
        chatViewModel = vm
        chatListViewModel.activeChatId = chat.id

        // Always try reconnect — checks service status first, so it's
        // cheap for old chats where the service has already stopped.
        // This handles both switching between chats and navigating
        // back to the sprite after the view was destroyed.
        knownStreamingChatIds.remove(chat.id)
        vm.reconnectIfNeeded(apiClient: apiClient, modelContext: modelContext)
    }

    private func forkFromCheckpoint(checkpointId: String, messageId: UUID) {
        pendingFork = nil
        isForking = true

        Task {
            defer { isForking = false }

            do {
                try await apiClient.restoreCheckpoint(
                    spriteName: sprite.name,
                    checkpointId: checkpointId
                )
            } catch {
                return
            }

            let context = buildForkContext(upTo: messageId)
            let priorMessages = buildPriorMessages(upTo: messageId)

            let chat = chatListViewModel.createChat(modelContext: modelContext)
            chat.forkContext = context
            if !priorMessages.isEmpty {
                chat.saveMessages(priorMessages)
            }
            try? modelContext.save()

            switchToChat(chat)
        }
    }

    private func buildPriorMessages(upTo messageId: UUID) -> [PersistedChatMessage] {
        guard let vm = chatViewModel else { return [] }
        guard let idx = vm.messages.firstIndex(where: { $0.id == messageId }) else { return [] }

        var persisted = vm.messages.prefix(through: idx).map { $0.toPersisted() }

        // Add a system notice marking the fork point
        let notice = PersistedChatMessage(
            id: UUID(),
            timestamp: Date(),
            role: .system,
            content: [.text("Forked from checkpoint — filesystem restored to this point")]
        )
        persisted.append(notice)
        return persisted
    }

    private func buildForkContext(upTo messageId: UUID) -> String? {
        guard let vm = chatViewModel else { return nil }
        guard let idx = vm.messages.firstIndex(where: { $0.id == messageId }) else { return nil }

        let relevant = vm.messages.prefix(through: idx)
        var lines: [String] = []
        for msg in relevant.suffix(6) {
            let role = msg.role == .user ? "User" : "Assistant"
            let text = msg.textContent
            guard !text.isEmpty, msg.role != .system else { continue }
            let truncated = String(text.prefix(300))
            lines.append("\(role): \(truncated)")
        }

        guard !lines.isEmpty else { return nil }
        return "Context from a previous conversation (filesystem was restored to an earlier checkpoint):\n\n"
            + lines.joined(separator: "\n\n")
    }
}
