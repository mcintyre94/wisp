import SwiftUI

struct ToolDetailSheet: View {
    let card: ToolUseCard
    var workingDirectory: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    inputSection
                    resultSection
                }
                .padding()
            }
            .navigationTitle(card.toolName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: card.iconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Text(card.toolName)
                .font(.headline)

            Spacer()

            if let elapsed = card.elapsedString {
                Text(elapsed)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5), in: Capsule())
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ToolInputDetailView(toolName: card.toolName, input: card.input, workingDirectory: workingDirectory)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let resultCard = card.result {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(resultCard.displayContent.relativeToCwd(workingDirectory))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(maxHeight: 400)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

#Preview("Grep result with relative paths") {
    let cwd = "/home/sprite/project"
    let card = ToolUseCard(
        toolUseId: "grep-1",
        toolName: "Grep",
        input: .object(["pattern": .string("relativeToCwd"), "path": .string("/home/sprite/project")])
    )
    card.result = ToolResultCard(
        toolUseId: "grep-1",
        toolName: "Grep",
        content: .string("""
            /home/sprite/project/Wisp/Utilities/Extensions.swift:42:func relativeToCwd(_ cwd: String) -> String {
            /home/sprite/project/Wisp/Views/SpriteDetail/Chat/ToolStepRow.swift:51:card.activityLabel.relativeToCwd(workingDirectory)
            /home/sprite/project/WispTests/ExtensionsTests.swift:58:path.relativeToCwd(cwd)
            """)
    )
    return ToolDetailSheet(card: card, workingDirectory: cwd)
}
