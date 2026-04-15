import SwiftUI
import SwiftData

struct ChatSwitcherSheet: View {
    @Bindable var viewModel: SpriteChatListViewModel
    var onSelectChat: ((SpriteChat) -> Void)? = nil
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(ChatSessionManager.self) private var chatSessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var chatToDelete: SpriteChat?
    @State private var chatToRename: SpriteChat?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.chats, id: \.id) { chat in
                    ChatRowView(
                        chat: chat,
                        isActive: chat.id == viewModel.activeChatId
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if chat.isUnread {
                            chat.isUnread = false
                            try? modelContext.save()
                        }
                        // Route selection via an explicit callback rather than mutating
                        // activeChatId here. The sheet runs inside a pushed ChatView subtree,
                        // and SpriteDetailView's onChange(of: activeChatId) doesn't fire in
                        // that context unless the property is already observed in its body —
                        // so relying on observation would silently drop the selection.
                        if let onSelectChat {
                            onSelectChat(chat)
                        } else {
                            viewModel.selectChat(chat)
                        }
                        dismiss()
                    }
                    .contextMenu {
                        Button {
                            chat.isUnread.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(chat.isUnread ? "Mark as Read" : "Mark as Unread", systemImage: chat.isUnread ? "envelope.open" : "envelope.badge")
                        }
                        if let sessionId = chat.claudeSessionId, !chat.isClosed {
                            Button {
                                UIPasteboard.general.string = "cd \(chat.workingDirectory) && claude --resume \(sessionId)"
                            } label: {
                                Label("Copy Resume Command", systemImage: "terminal")
                            }
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
                                viewModel.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
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
                        if let sessionId = chat.claudeSessionId, !chat.isClosed {
                            Button {
                                UIPasteboard.general.string = "cd \(chat.workingDirectory) && claude --resume \(sessionId)"
                            } label: {
                                Label("Copy Resume", systemImage: "terminal")
                            }
                            .tint(.gray)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            chatToDelete = chat
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)

                        if !chat.isClosed {
                            Button {
                                chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                                viewModel.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
                            } label: {
                                Label("Close", systemImage: "xmark.circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete Chat",
                isPresented: Binding(
                    get: { chatToDelete != nil },
                    set: { if !$0 { chatToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let chat = chatToDelete {
                        chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                        viewModel.deleteChat(chat, apiClient: apiClient, modelContext: modelContext)
                        chatToDelete = nil
                    }
                }
            } message: {
                Text("This will permanently delete the chat and its history.")
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.createChat(modelContext: modelContext)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Rename Chat", isPresented: Binding(
                get: { chatToRename != nil },
                set: { if !$0 { chatToRename = nil } }
            )) {
                TextField("Chat name", text: $renameText)
                Button("Save") {
                    if let chat = chatToRename {
                        viewModel.renameChat(chat, name: renameText, modelContext: modelContext)
                        chatToRename = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    chatToRename = nil
                }
            }
        }
    }
}

private struct ChatRowView: View {
    let chat: SpriteChat
    let isActive: Bool

    var body: some View {
        HStack {
            if chat.isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chat.displayName)
                        .font(.body)
                        .fontWeight(chat.isUnread ? .semibold : .regular)
                    if chat.isClosed {
                        Text("Closed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
                if let preview = chat.firstMessagePreview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 0) {
                    Text("Updated ")
                    Text(chat.lastUsed, style: .relative)
                    Text(" ago")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel = SpriteChatListViewModel(spriteName: "my-sprite")
    NavigationStack {
        ChatSwitcherSheet(viewModel: viewModel)
            .environment(SpritesAPIClient())
            .modelContainer(for: [SpriteChat.self, SpriteSession.self], inMemory: true)
    }
}
