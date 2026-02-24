import MarkdownUI
import SwiftUI

struct AssistantMessageView: View {
    let message: ChatMessage
    var onCreateCheckpoint: (() -> Void)? = nil
    var isCheckpointDisabled: Bool = false

    private var canCheckpoint: Bool {
        onCreateCheckpoint != nil
            && message.checkpointId == nil
            && !message.isStreaming
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.content.indices, id: \.self) { index in
                    switch message.content[index] {
                    case .text(let text):
                        Markdown(text)
                            .markdownTheme(.basic)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = text
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                if canCheckpoint {
                                    Button {
                                        onCreateCheckpoint?()
                                    } label: {
                                        Label("Create Checkpoint", systemImage: "diamond")
                                    }
                                    .disabled(isCheckpointDisabled)
                                }
                            }
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
