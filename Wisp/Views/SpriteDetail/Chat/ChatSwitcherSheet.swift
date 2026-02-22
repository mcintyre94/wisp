import SwiftUI
import SwiftData

struct ChatSwitcherSheet: View {
    @Bindable var viewModel: SpriteChatListViewModel
    @Environment(SpritesAPIClient.self) private var apiClient
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
                        viewModel.selectChat(chat)
                        dismiss()
                    }
                    .contextMenu {
                        Button {
                            renameText = chat.customName ?? ""
                            chatToRename = chat
                        } label: {
                            Label("Rename", systemImage: "pencil")
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
                                viewModel.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
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
                            viewModel.deleteChat(chat, apiClient: apiClient, modelContext: modelContext)
                            chatToDelete = nil
                        }
                    } message: {
                        Text("This will permanently delete the chat and its history.")
                    }
                }
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chat.displayName)
                        .font(.body)
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
