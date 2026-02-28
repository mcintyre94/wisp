import MarkdownUI
import SwiftUI

struct AssistantMessageView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
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
                        Markdown(text)
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
                    case .toolUse(let card):
                        if card.toolName == "TodoWrite" {
                            PlanCardView(card: card)
                        } else if card.result != nil {
                            // Completed tool -- compact step row
                            ToolStepRow(card: card) {
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
                                Text(card.activityLabel)
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
            ToolDetailSheet(card: card)
        }
    }
}
