import MarkdownUI
import SwiftUI

struct AssistantMessageView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var workingDirectory: String = ""
    var onCreateCheckpoint: (() -> Void)? = nil
    var isCheckpointDisabled: Bool = false
    var onAnswerWispAsk: ((String) -> Void)? = nil
    @State private var selectedToolCard: ToolUseCard?

    private var canCheckpoint: Bool {
        onCreateCheckpoint != nil
            && message.checkpointId == nil
            && !isStreaming
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.content.indices, id: \.self) { index in
                    switch message.content[index] {
                    case .text(let text):
                        AssistantTextBubble(
                            text: text,
                            timestamp: message.timestamp,
                            canCheckpoint: canCheckpoint,
                            isCheckpointDisabled: isCheckpointDisabled,
                            onCreateCheckpoint: onCreateCheckpoint
                        )
                    case .toolUse(let card):
                        if card.toolName == "TodoWrite" {
                            PlanCardView(card: card)
                        } else if card.result != nil {
                            // Completed tool -- compact step row
                            ToolStepRow(card: card, workingDirectory: workingDirectory) {
                                selectedToolCard = card
                            }
                        } else if card.toolName == "mcp__askUser__WispAsk" {
                            // Pending question -- interactive card
                            WispAskCard(card: card) { answer in
                                onAnswerWispAsk?(answer)
                            }
                        } else if !isStreaming {
                            // Cancelled/incomplete tool (not streaming) -- muted row
                            HStack(spacing: 6) {
                                Image(systemName: card.iconName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.quaternary)
                                    .frame(width: 16)
                                Text(card.activityLabel.relativeToCwd(workingDirectory))
                                    .font(.caption)
                                    .foregroundStyle(.quaternary)
                                    .strikethrough()
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                        // Active tool while streaming -- shimmer handles it, render nothing
                    case .toolResult:
                        EmptyView()
                    case .error(let errorMessage):
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(10)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Spacer(minLength: 60)
        }
        .sheet(item: $selectedToolCard) { card in
            ToolDetailSheet(card: card, workingDirectory: workingDirectory)
        }
    }
}

private struct AssistantTextBubble: View {
    let text: String
    let timestamp: Date
    var canCheckpoint: Bool = false
    var isCheckpointDisabled: Bool = false
    var onCreateCheckpoint: (() -> Void)? = nil

    @State private var showTimestamp = false

    // Convert backtick-wrapped URLs (code spans) to markdown links so they're tappable.
    // e.g. `https://example.com` → [https://example.com](https://example.com)
    private var processedText: String {
        let pattern = #"`(https?://[^`\s]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[$1]($1)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Markdown(processedText)
                .markdownTheme(.wisp)
                .markdownCodeSyntaxHighlighter(WispCodeHighlighter())
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 16))
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
            if showTimestamp {
                Text(timestamp.chatTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTimestamp.toggle()
            }
        }
    }
}

#Preview("Bash tool with relative paths") {
    let cwd = "/home/sprite/project"
    let card = ToolUseCard(
        toolUseId: "bash-1",
        toolName: "Bash",
        input: .object(["command": .string("ls -la /home/sprite/project/Wisp/Models/")])
    )
    card.result = ToolResultCard(
        toolUseId: "bash-1",
        toolName: "Bash",
        content: .string("ChatMessage.swift\nClaudeEventTypes.swift\nSprite.swift")
    )
    let message = ChatMessage(role: .assistant, content: [
        .text("Here are the model files:"),
        .toolUse(card),
    ])
    return AssistantMessageView(message: message, workingDirectory: cwd)
        .padding()
}

#Preview("Text only") {
    let message = ChatMessage(role: .assistant, content: [
        .text("I've reviewed the codebase and here's what I found:\n\n- The models look good\n- Tests are passing"),
    ])
    return AssistantMessageView(message: message)
        .padding()
}
