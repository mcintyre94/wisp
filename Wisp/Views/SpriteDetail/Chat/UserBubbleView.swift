import SwiftUI

struct UserBubbleView: View {
    let message: ChatMessage
    @State private var showTimestamp = false

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(message.content) { content in
                    if case .text(let text) = content {
                        Text(text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                }
                if showTimestamp {
                    Text(message.timestamp.chatTimestamp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTimestamp.toggle()
                }
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.textContent
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}
