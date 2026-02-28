import SwiftUI

struct PendingUserBubbleView: View {
    let text: String
    let onEdit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.blue.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                HStack(spacing: 10) {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .tint(.secondary)
                    Label("Queued", systemImage: "clock")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
            }
        }
    }
}

#Preview {
    VStack {
        PendingUserBubbleView(text: "Can you make the tests pass?", onEdit: {}, onCancel: {})
        PendingUserBubbleView(text: "This is a longer queued message that wraps onto multiple lines to test layout", onEdit: {}, onCancel: {})
    }
    .padding()
}
