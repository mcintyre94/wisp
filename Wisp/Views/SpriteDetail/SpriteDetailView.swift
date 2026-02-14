import SwiftUI
import SwiftData

enum SpriteTab: String, CaseIterable {
    case overview = "Overview"
    case chat = "Chat"
    case checkpoints = "Checkpoints"
}

struct SpriteDetailView: View {
    let sprite: Sprite
    @State private var selectedTab: SpriteTab = .chat
    @State private var chatViewModel: ChatViewModel
    @State private var checkpointsViewModel: CheckpointsViewModel
    @Environment(\.modelContext) private var modelContext

    init(sprite: Sprite) {
        self.sprite = sprite
        _chatViewModel = State(initialValue: ChatViewModel(spriteName: sprite.name))
        _checkpointsViewModel = State(initialValue: CheckpointsViewModel(spriteName: sprite.name))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(SpriteTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .overview:
                SpriteOverviewView(sprite: sprite)
            case .chat:
                ChatView(viewModel: chatViewModel)
            case .checkpoints:
                CheckpointsView(viewModel: checkpointsViewModel)
            }
        }
        .navigationTitle(sprite.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedTab == .chat {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        chatViewModel.startNewChat(modelContext: modelContext)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(chatViewModel.isStreaming)
                }
            }
        }
        .task {
            chatViewModel.loadSession(modelContext: modelContext)
        }
    }
}
