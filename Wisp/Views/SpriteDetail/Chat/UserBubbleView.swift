import SwiftUI

struct UserBubbleView: View {
    let message: ChatMessage
    @State private var showTimestamp = false

    private func linkedText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].link = url
            attributed[attrRange].underlineStyle = .single
        }
        return attributed
    }

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(message.content) { content in
                    if case .text(let text) = content {
                        Text(linkedText(text))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showTimestamp.toggle()
                                }
                            }
                    }
                }
                if showTimestamp {
                    Text(message.timestamp.chatTimestamp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
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

#Preview {
    let message = ChatMessage(role: .user, content: [.text("Can you add a README to this project?")])
    UserBubbleView(message: message)
        .padding()
}
