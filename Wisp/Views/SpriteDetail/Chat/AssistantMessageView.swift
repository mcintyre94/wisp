import MarkdownUI
import SwiftUI

struct AssistantMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.content) { content in
                    switch content {
                    case .text(let text):
                        Markdown(text)
                            .markdownTheme(.basic)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
                    case .toolUse(let card):
                        ToolUseCardView(card: card)
                    case .toolResult(let card):
                        ToolResultCardView(card: card)
                    case .error(let errorMessage):
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(10)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                if message.isStreaming {
                    StreamingIndicator()
                }
            }
            Spacer(minLength: 60)
        }
    }
}
