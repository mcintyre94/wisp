import SwiftUI
import SwiftData

struct SpriteDetailView: View {
    let sprite: Sprite
    @State private var selectedTab: SpriteTab = .chat
    @State private var chatViewModel: ChatViewModel
    @State private var checkpointsViewModel: CheckpointsViewModel
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    init(sprite: Sprite) {
        self.sprite = sprite
        _chatViewModel = State(initialValue: ChatViewModel(spriteName: sprite.name))
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
            ChatView(viewModel: chatViewModel, topAccessory: AnyView(pickerView))
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
                    Button {
                        chatViewModel.startNewChat(apiClient: apiClient, modelContext: modelContext)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(chatViewModel.isStreaming)
                }
            }
        }
        .task {
            chatViewModel.loadSession(apiClient: apiClient, modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                chatViewModel.resumeAfterBackground(apiClient: apiClient, modelContext: modelContext)
            }
        }
    }
}
