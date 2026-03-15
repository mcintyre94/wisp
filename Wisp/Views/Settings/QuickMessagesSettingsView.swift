import SwiftData
import SwiftUI

struct QuickMessagesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QuickMessage.createdAt) private var quickMessages: [QuickMessage]
    @State private var editingMessage: QuickMessage?
    @State private var showingAddSheet = false

    var body: some View {
        List {
            if quickMessages.isEmpty {
                ContentUnavailableView(
                    "No Quick Messages",
                    systemImage: "text.bubble",
                    description: Text("Tap + to add messages you send often.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(quickMessages) { message in
                    Button {
                        editingMessage = message
                    } label: {
                        Text(message.text)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(message)
                        }
                    }
                    .contextMenu {
                        Button("Edit") {
                            editingMessage = message
                        }
                        Button("Delete", role: .destructive) {
                            modelContext.delete(message)
                        }
                    }
                }
            }
        }
        .navigationTitle("Quick Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            QuickMessageEditSheet(message: nil)
        }
        .sheet(item: $editingMessage) { message in
            QuickMessageEditSheet(message: message)
        }
    }
}

struct QuickMessageEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let message: QuickMessage?

    @State private var text: String = ""
    @FocusState private var isTextFocused: Bool

    private var isNew: Bool { message == nil }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isTextFocused)
                .padding()
                .navigationTitle(isNew ? "New Quick Message" : "Edit Quick Message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            text = message?.text ?? ""
            isTextFocused = true
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let message {
            message.text = trimmed
        } else {
            modelContext.insert(QuickMessage(text: trimmed))
        }
        dismiss()
    }
}

#Preview("List") {
    NavigationStack {
        QuickMessagesSettingsView()
            .modelContainer(for: QuickMessage.self, inMemory: true)
    }
}

#Preview("Edit Sheet") {
    QuickMessageEditSheet(message: nil)
        .modelContainer(for: QuickMessage.self, inMemory: true)
}
