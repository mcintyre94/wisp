import SwiftUI
import SwiftData

enum SpriteNavSelection: Hashable {
    case overview
    case checkpoints
    case chat(UUID)
}

struct SpriteNavigationPanel: View {
    let sprite: Sprite
    @Binding var selection: SpriteNavSelection?
    let chatListViewModel: SpriteChatListViewModel
    let onCreateChat: () -> Void

    private var openChats: [SpriteChat] {
        chatListViewModel.chats.filter { !$0.isClosed }
    }

    private var closedChats: [SpriteChat] {
        chatListViewModel.chats.filter { $0.isClosed }
    }

    var body: some View {
        List(selection: $selection) {
            Label("Overview", systemImage: "info.circle")
                .tag(SpriteNavSelection.overview)

            Label("Checkpoints", systemImage: "clock.arrow.circlepath")
                .tag(SpriteNavSelection.checkpoints)

            Section("Chats") {
                ForEach(openChats) { chat in
                    chatRow(chat)
                        .tag(SpriteNavSelection.chat(chat.id))
                }
                if !closedChats.isEmpty {
                    ForEach(closedChats) { chat in
                        chatRow(chat)
                            .tag(SpriteNavSelection.chat(chat.id))
                    }
                }
                Button(action: onCreateChat) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func chatRow(_ chat: SpriteChat) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.displayName)
                    .font(.subheadline)
                if let preview = chat.firstMessagePreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if chat.isClosed {
                Image(systemName: "archivebox")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

