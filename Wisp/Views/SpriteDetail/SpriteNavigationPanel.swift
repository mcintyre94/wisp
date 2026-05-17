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
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(ChatSessionManager.self) private var chatSessionManager
    @Environment(\.modelContext) private var modelContext
    @State private var chatToRename: SpriteChat?
    @State private var renameText = ""
    @State private var chatToDelete: SpriteChat?

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
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.sidebar)
        .alert("Rename Chat", isPresented: Binding(
            get: { chatToRename != nil },
            set: { if !$0 { chatToRename = nil } }
        )) {
            TextField("Chat name", text: $renameText)
            Button("Save") {
                if let chat = chatToRename {
                    chatListViewModel.renameChat(chat, name: renameText, modelContext: modelContext)
                    chatToRename = nil
                }
            }
            Button("Cancel", role: .cancel) { chatToRename = nil }
        }
    }

    @ViewBuilder
    private func chatRow(_ chat: SpriteChat) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.displayName)
                    .font(.subheadline)
                    .fontWeight(chat.isUnread ? .semibold : .regular)
                if let preview = chat.firstMessagePreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if chatSessionManager.isStreaming(chatId: chat.id) {
                StreamingDot()
            } else if chat.isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            } else if chat.isClosed {
                Image(systemName: "archivebox")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button {
                chat.isUnread.toggle()
                try? modelContext.save()
            } label: {
                Label(chat.isUnread ? "Mark as Read" : "Mark as Unread", systemImage: chat.isUnread ? "envelope.open" : "envelope.badge")
            }
            Button {
                renameText = chat.customName ?? ""
                chatToRename = chat
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if !chat.isClosed {
                Button {
                    chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                    chatListViewModel.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                chatToDelete = chat
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                chat.isUnread.toggle()
                try? modelContext.save()
            } label: {
                Label(chat.isUnread ? "Read" : "Unread", systemImage: chat.isUnread ? "envelope.open" : "envelope.badge")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                chatToDelete = chat
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if !chat.isClosed {
                Button {
                    chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                    chatListViewModel.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
                .tint(.orange)
            }
        }
        .confirmationDialog(
            "Delete Chat",
            isPresented: Binding(
                get: { chatToDelete?.id == chat.id },
                set: { if !$0 { chatToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                chatListViewModel.deleteChat(chat, apiClient: apiClient, modelContext: modelContext)
                chatToDelete = nil
            }
        } message: {
            Text("This will permanently delete the chat and its history.")
        }
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
    @Previewable @State var selection: SpriteNavSelection? = .chat(UUID())
    NavigationStack {
        List {
            SpriteNavigationPanel(
                sprite: mockSprite(),
                selection: $selection,
                chatListViewModel: SpriteChatListViewModel(spriteName: "my-sprite"),
                onCreateChat: {}
            )
        }
    }
    .environment(SpritesAPIClient())
    .environment(ChatSessionManager())
    .modelContainer(for: [SpriteChat.self, SpriteSession.self], inMemory: true)
}

