import SwiftData
import SwiftUI

struct QuickMessagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \QuickMessage.createdAt) private var quickMessages: [QuickMessage]
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            if quickMessages.isEmpty {
                ContentUnavailableView(
                    "No Quick Messages",
                    systemImage: "text.bubble",
                    description: Text("Add quick messages in Settings.")
                )
                .navigationTitle("Quick Messages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            } else {
                List(quickMessages) { message in
                    Button {
                        onSelect(message.text)
                        dismiss()
                    } label: {
                        Text(message.text)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                }
                .navigationTitle("Quick Messages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    QuickMessagePickerSheet { _ in }
        .modelContainer(for: QuickMessage.self, inMemory: true)
}
