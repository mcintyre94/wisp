import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var workingDirectory: String = ""
    var onCreateCheckpoint: (() -> Void)? = nil
    var isCheckpointDisabled: Bool = false
    var onAnswerWispAsk: ((String) -> Void)? = nil

    var body: some View {
        switch message.role {
        case .user:
            UserBubbleView(message: message)
        case .assistant:
            AssistantMessageView(
                message: message,
                isStreaming: isStreaming,
                workingDirectory: workingDirectory,
                onCreateCheckpoint: onCreateCheckpoint,
                isCheckpointDisabled: isCheckpointDisabled,
                onAnswerWispAsk: onAnswerWispAsk
            )
        case .system:
            systemMessage
        }
    }

    private var systemMessage: some View {
        HStack {
            Spacer()
            if let text = message.content.first, case .text(let str) = text {
                Text(str)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
        }
    }
}
