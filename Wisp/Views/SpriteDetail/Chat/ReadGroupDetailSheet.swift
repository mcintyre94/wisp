import SwiftUI

struct ReadGroupDetailSheet: View {
    let group: ReadGroupCard
    var workingDirectory: String = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(group.cards) { card in
                    ReadGroupFileRow(card: card, workingDirectory: workingDirectory)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Read \(group.cards.count) Files")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReadGroupFileRow: View {
    let card: ToolUseCard
    var workingDirectory: String
    @State private var isExpanded = false

    private var filePath: String {
        (card.input["file_path"]?.stringValue ?? "unknown").relativeToCwd(workingDirectory)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let result = card.result {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(result.displayContent)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            } else {
                Text("No output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(filePath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let elapsed = card.elapsedString {
                    Text(elapsed)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    let group = ReadGroupCard(cards: [
        {
            let c = ToolUseCard(toolUseId: "r1", toolName: "Read", input: .object(["file_path": .string("/home/sprite/project/Wisp/Models/Claude/ChatMessage.swift")]))
            c.result = ToolResultCard(toolUseId: "r1", toolName: "Read", content: .string("import Foundation\n\nenum ChatRole: String {...}"))
            return c
        }(),
        {
            let c = ToolUseCard(toolUseId: "r2", toolName: "Read", input: .object(["file_path": .string("/home/sprite/project/Wisp/ViewModels/ChatViewModel.swift")]))
            c.result = ToolResultCard(toolUseId: "r2", toolName: "Read", content: .string("import Foundation\nimport SwiftData\n\n@Observable\nfinal class ChatViewModel {...}"))
            return c
        }(),
    ])
    return ReadGroupDetailSheet(group: group, workingDirectory: "/home/sprite/project")
}
