import SwiftUI
import SwiftData

struct SpriteDetailView: View {
    let sprite: Sprite
    @Binding var selectedTab: SpriteTab
    @State private var chatListViewModel: SpriteChatListViewModel
    @State private var chatViewModel: ChatViewModel?
    @State private var checkpointsViewModel: CheckpointsViewModel
    @State private var showingChat = false
    @State private var showingCheckpoints = false
    @State private var showStaleChatsAlert = false
    @State private var showCopiedFeedback = false
    @State private var pendingFork: (checkpointId: String, messageId: UUID)? = nil
    @State private var isForking = false
    @State private var spriteQuickActionsViewModel: QuickActionsViewModel?
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(ChatSessionManager.self) private var chatSessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(sprite: Sprite, selectedTab: Binding<SpriteTab>) {
        self.sprite = sprite
        _selectedTab = selectedTab
        _chatListViewModel = State(initialValue: SpriteChatListViewModel(spriteName: sprite.name))
        _checkpointsViewModel = State(initialValue: CheckpointsViewModel(spriteName: sprite.name))
    }

    private var showTabPicker: Bool { sizeClass != .regular }

    private var navSelectionBinding: Binding<SpriteNavSelection?> {
        Binding(
            get: {
                switch selectedTab {
                case .overview: return .overview
                case .checkpoints: return .checkpoints
                case .chat: return chatListViewModel.activeChatId.map { .chat($0) }
                }
            },
            set: { newValue in
                guard let newValue else { return }
                switch newValue {
                case .overview:
                    selectedTab = .overview
                case .checkpoints:
                    selectedTab = .checkpoints
                case .chat(let id):
                    selectedTab = .chat
                    if let chat = chatListViewModel.chats.first(where: { $0.id == id }) {
                        markChatRead(chat)
                        switchToChat(chat)
                    }
                }
            }
        )
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            SpriteNavigationPanel(
                sprite: sprite,
                selection: navSelectionBinding,
                chatListViewModel: chatListViewModel,
                onCreateChat: {
                    let chat = chatListViewModel.createChat(modelContext: modelContext)
                    selectedTab = .chat
                    switchToChat(chat)
                }
            )
            .frame(width: 260)

            Divider()

            if selectedTab != .chat { Spacer(minLength: 0) }
            tabContent
                .frame(maxWidth: selectedTab == .chat ? .infinity : 680, maxHeight: .infinity)
            if selectedTab != .chat { Spacer(minLength: 0) }
        }
    }

    private var pickerView: some View {
        SpriteTabPicker(selectedTab: $selectedTab)
    }

    private var compactLayout: some View {
        SpriteOverviewView(
            sprite: sprite,
            chatListViewModel: chatListViewModel,
            onChatSelected: { chat in
                markChatRead(chat)
                switchToChat(chat)
                showingChat = true
            },
            onNewChat: {
                let chat = chatListViewModel.createChat(modelContext: modelContext)
                switchToChat(chat)
                showingChat = true
            },
            onCheckpoints: {
                showingCheckpoints = true
            }
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            SpriteOverviewView(sprite: sprite)
                .safeAreaInset(edge: .top, spacing: 0) { if showTabPicker { pickerView } }
        case .chat:
            if let chatViewModel {
                let isReadOnly = chatListViewModel.activeChat?.isClosed == true
                ChatView(
                    viewModel: chatViewModel,
                    isReadOnly: isReadOnly,
                    topAccessory: showTabPicker ? AnyView(pickerView) : nil,
                    existingSessionIds: Set(chatListViewModel.chats.filter { !$0.isClosed }.compactMap(\.claudeSessionId)),
                    onFork: { checkpointId, messageId in
                        pendingFork = (checkpointId, messageId)
                    }
                )
                .id(chatViewModel.chatId)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) { if showTabPicker { pickerView } }
            }
        case .checkpoints:
            CheckpointsView(viewModel: checkpointsViewModel)
                .safeAreaInset(edge: .top, spacing: 0) { if showTabPicker { pickerView } }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .navigationDestination(isPresented: $showingChat) {
            if let vm = chatViewModel {
                let isReadOnly = chatListViewModel.activeChat?.isClosed == true
                ChatView(
                    viewModel: vm,
                    isReadOnly: isReadOnly,
                    chatListViewModel: chatListViewModel,
                    onNewChat: {
                        let chat = chatListViewModel.createChat(modelContext: modelContext)
                        switchToChat(chat)
                    },
                    onSelectChat: { chat in
                        markChatRead(chat)
                        switchToChat(chat)
                    },
                    existingSessionIds: Set(chatListViewModel.chats.filter { !$0.isClosed }.compactMap(\.claudeSessionId)),
                    onFork: { checkpointId, messageId in
                        pendingFork = (checkpointId, messageId)
                    }
                )
                .id(vm.chatId)
                .onAppear { vm.isActive = true }
                .onDisappear { vm.isActive = false }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationDestination(isPresented: $showingCheckpoints) {
            CheckpointsView(viewModel: checkpointsViewModel)
        }
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
                    .contextMenu {
                        if selectedTab != .checkpoints {
                            Button {
                                openSpriteQuickActions()
                            } label: {
                                Label("Quick Actions", systemImage: "bolt")
                            }
                        }
                        Button {
                            UIPasteboard.general.string = sprite.name
                        } label: {
                            Label("Copy Name", systemImage: "doc.on.doc")
                        }
                    }
            }
            if sizeClass == .regular {
                // iPad/Mac: tab-conditional toolbar
                if selectedTab == .chat {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            let chat = chatListViewModel.createChat(modelContext: modelContext)
                            switchToChat(chat)
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                } else if selectedTab == .overview {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openSpriteQuickActions()
                        } label: {
                            Image(systemName: "bolt")
                        }
                    }
                }
            } else {
                // iPhone: bolt on overview (ChatView has its own bolt when pushed)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openSpriteQuickActions()
                    } label: {
                        Image(systemName: "bolt")
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
        .onAppear {
            // On iPad/Mac, chat is visible alongside the sidebar so activate immediately.
            // On iPhone, the pushed ChatView manages isActive via its own onAppear/onDisappear.
            if sizeClass == .regular {
                chatViewModel?.isActive = true
            }
        }
        .onDisappear {
            chatViewModel?.isActive = false
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                chatSessionManager.resumeAllAfterBackground(apiClient: apiClient, modelContext: modelContext)
            }
        }
        .sheet(item: $spriteQuickActionsViewModel) { vm in
            QuickActionsView(
                viewModel: vm,
                startChatCallback: { text in
                    let chat = chatListViewModel.createChat(modelContext: modelContext)
                    switchToChat(chat)
                    chatViewModel?.inputText = text
                    if sizeClass != .regular {
                        showingChat = true
                    } else {
                        selectedTab = .chat
                    }
                    spriteQuickActionsViewModel = nil
                }
            )
            .environment(apiClient)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Sprite Recreated", isPresented: $showStaleChatsAlert) {
            Button("Start Fresh", role: .destructive) {
                chatSessionManager.detachAll(modelContext: modelContext)
                chatViewModel = nil
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

    private func openSpriteQuickActions() {
        spriteQuickActionsViewModel = QuickActionsViewModel(
            spriteName: sprite.name,
            sessionId: nil,
            workingDirectory: "/home/sprite/project"
        )
    }

    /// Called by user-tap sites (overview row, iPad nav panel, switcher sheet via
    /// `selectChat`) to clear the unread indicator. Kept separate from `switchToChat`
    /// because that method is also called programmatically (e.g. from the initial
    /// `.task` that positions on the last-active chat), where clearing unread would
    /// be wrong — the user never explicitly selected anything.
    private func markChatRead(_ chat: SpriteChat) {
        guard chat.isUnread else { return }
        chat.isUnread = false
        try? modelContext.save()
    }

    private func switchToChat(_ chat: SpriteChat) {
        guard chatViewModel?.chatId != chat.id else { return }

        // Deactivate outgoing VM
        chatViewModel?.isActive = false

        // Look up or create a VM from the app-wide cache — old VM keeps streaming in background
        let vm = chatSessionManager.viewModel(
            for: chat,
            spriteName: sprite.name,
            apiClient: apiClient,
            modelContext: modelContext
        )
        vm.isActive = true
        chatViewModel = vm
        chatListViewModel.activeChatId = chat.id

        // Reconnect if idle with a service that may have new events.
        // Guards on !isStreaming internally, so safe to call on an already-streaming VM.
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
            if sizeClass != .regular {
                showingChat = true
            }
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

private func mockSprite(name: String = "my-sprite", status: String = "running") -> Sprite {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try! decoder.decode(Sprite.self, from: Data("""
        {"id":"s1","name":"\(name)","status":"\(status)","created_at":"2025-01-15T10:30:00Z"}
        """.utf8))
}

#Preview {
    @Previewable @State var selectedTab: SpriteTab = .chat
    SpriteDetailView(sprite: mockSprite(), selectedTab: $selectedTab)
        .environment(SpritesAPIClient())
        .environment(ChatSessionManager())
        .modelContainer(for: [SpriteChat.self, SpriteSession.self], inMemory: true)
}
