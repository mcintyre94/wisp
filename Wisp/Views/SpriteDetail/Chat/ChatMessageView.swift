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

#Preview("User message") {
    let message = ChatMessage(role: .user, content: [.text("List the Swift files in the Models directory")])
    return ChatMessageView(message: message)
        .padding()
}

#Preview("Assistant with Bash tool") {
    let cwd = "/home/sprite/project"
    let card = ToolUseCard(
        toolUseId: "bash-1",
        toolName: "Bash",
        input: .object(["command": .string("ls /home/sprite/project/Wisp/Models/")])
    )
    card.result = ToolResultCard(
        toolUseId: "bash-1",
        toolName: "Bash",
        content: .string("ChatMessage.swift\nSprite.swift")
    )
    let message = ChatMessage(role: .assistant, content: [.toolUse(card)])
    return ChatMessageView(message: message, workingDirectory: cwd)
        .padding()
}
