import SwiftUI
import SwiftData

struct ChatSwitcherSheet: View {
    @Bindable var viewModel: SpriteChatListViewModel
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var chatToDelete: SpriteChat?

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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            chatToDelete = chat
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        if !chat.isClosed {
                            Button {
                                viewModel.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
                            } label: {
                                Label("Close", systemImage: "xmark.circle")
                            }
                            .tint(.orange)
                        }
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
                        viewModel.deleteChat(chat, apiClient: apiClient, modelContext: modelContext)
                        chatToDelete = nil
                    }
                }
            } message: {
                Text("This will permanently delete the chat and its history.")
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
