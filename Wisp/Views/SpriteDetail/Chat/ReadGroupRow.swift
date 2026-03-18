import SwiftUI

struct ReadGroupRow: View {
    let group: ReadGroupCard
    var workingDirectory: String = ""
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text("Read \(group.cards.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if let elapsed = group.elapsedString {
                    Text(elapsed)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let group = ReadGroupCard(cards: [
        {
            let c = ToolUseCard(toolUseId: "r1", toolName: "Read", input: .object(["file_path": .string("/home/sprite/project/Wisp/Models/Claude/ChatMessage.swift")]))
            c.result = ToolResultCard(toolUseId: "r1", toolName: "Read", content: .string("import Foundation\n..."))
            return c
        }(),
        {
            let c = ToolUseCard(toolUseId: "r2", toolName: "Read", input: .object(["file_path": .string("/home/sprite/project/Wisp/ViewModels/ChatViewModel.swift")]))
            c.result = ToolResultCard(toolUseId: "r2", toolName: "Read", content: .string("import Foundation\n..."))
            return c
        }(),
        {
            let c = ToolUseCard(toolUseId: "r3", toolName: "Read", input: .object(["file_path": .string("/home/sprite/project/Wisp/Views/SpriteDetail/Chat/AssistantMessageView.swift")]))
            c.result = ToolResultCard(toolUseId: "r3", toolName: "Read", content: .string("import SwiftUI\n..."))
            return c
        }(),
    ])
    return ReadGroupRow(group: group, workingDirectory: "/home/sprite/project") {}
        .padding()
}
