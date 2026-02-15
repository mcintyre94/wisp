import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onInterrupt: () -> Void
    var isFocused: FocusState<Bool>.Binding

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $text, axis: .vertical)
                .focused(isFocused)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)

            if isStreaming {
                Button(action: onInterrupt) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                }
                .tint(.red)
                .buttonStyle(.glass)
            }

            Button {
                isFocused.wrappedValue = false
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .tint(isEmpty ? .gray : .blue)
            .disabled(isEmpty)
            .buttonStyle(.glass)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
