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
    @State private var streamingChatIds: Set<UUID> = []
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
                ChatView(viewModel: chatViewModel, isReadOnly: isReadOnly, topAccessory: AnyView(pickerView))
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
        .navigationTitle(sprite.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    }

    private func switchToChat(_ chat: SpriteChat) {
        // Detach old VM (cancel stream but keep service running)
        if let oldVM = chatViewModel {
            let wasStreaming = oldVM.detach(modelContext: modelContext)
            if wasStreaming {
                streamingChatIds.insert(oldVM.chatId)
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

        // Reconnect if this chat was streaming when we switched away
        if streamingChatIds.remove(chat.id) != nil {
            vm.reconnectIfNeeded(apiClient: apiClient, modelContext: modelContext)
        }
    }
}
