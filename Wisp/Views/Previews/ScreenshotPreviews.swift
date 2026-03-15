import SwiftUI

#if DEBUG

// MARK: - Chat Screenshot Preview

@MainActor
private struct ChatScreenshot: View {
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage

    init() {
        let now = Date()

        userMessage = ChatMessage(
            role: .user,
            content: [.text("Set up a new Express.js project with TypeScript and add a health check endpoint")]
        )

        // Tool 1: mkdir + npm init (2s)
        let tool1 = ToolUseCard(
            toolUseId: "tool_1",
            toolName: "Bash",
            input: .object(["command": .string("mkdir -p src && npm init -y")]),
            startedAt: now.addingTimeInterval(-12)
        )
        let result1 = ToolResultCard(
            toolUseId: "tool_1",
            toolName: "Bash",
            content: .string("Wrote to /home/sprite/project/package.json"),
            completedAt: now.addingTimeInterval(-10)
        )
        tool1.result = result1

        // Tool 2: Write tsconfig.json (<1s)
        let tool2 = ToolUseCard(
            toolUseId: "tool_2",
            toolName: "Write",
            input: .object(["file_path": .string("/home/sprite/project/tsconfig.json")]),
            startedAt: now.addingTimeInterval(-9)
        )
        let result2 = ToolResultCard(
            toolUseId: "tool_2",
            toolName: "Write",
            content: .string("File written successfully"),
            completedAt: now.addingTimeInterval(-8.5)
        )
        tool2.result = result2

        // Tool 3: Write src/index.ts (<1s)
        let tool3 = ToolUseCard(
            toolUseId: "tool_3",
            toolName: "Write",
            input: .object(["file_path": .string("/home/sprite/project/src/index.ts")]),
            startedAt: now.addingTimeInterval(-8)
        )
        let result3 = ToolResultCard(
            toolUseId: "tool_3",
            toolName: "Write",
            content: .string("File written successfully"),
            completedAt: now.addingTimeInterval(-7.5)
        )
        tool3.result = result3

        // Tool 4: npm install (5s)
        let tool4 = ToolUseCard(
            toolUseId: "tool_4",
            toolName: "Bash",
            input: .object(["command": .string("npm install express @types/express typescript")]),
            startedAt: now.addingTimeInterval(-7)
        )
        let result4 = ToolResultCard(
            toolUseId: "tool_4",
            toolName: "Bash",
            content: .string("added 67 packages in 4.2s"),
            completedAt: now.addingTimeInterval(-2)
        )
        tool4.result = result4

        // Tool 5: Active (no result -- shimmer handles display)
        let tool5 = ToolUseCard(
            toolUseId: "tool_5",
            toolName: "Bash",
            input: .object(["command": .string("npx tsc && node dist/index.js")]),
            startedAt: now.addingTimeInterval(-1)
        )

        assistantMessage = ChatMessage(
            role: .assistant,
            content: [
                .text("I'll set up an Express.js project with TypeScript for you."),
                .toolUse(tool1), .toolResult(result1),
                .toolUse(tool2), .toolResult(result2),
                .toolUse(tool3), .toolResult(result3),
                .toolUse(tool4), .toolResult(result4),
                .toolUse(tool5),
            ],
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatStatusBar(status: .streaming, modelName: "claude-4-sonnet")

                ScrollView {
                    VStack(spacing: 12) {
                        ChatMessageView(message: userMessage)
                        ChatMessageView(message: assistantMessage)
                        ThinkingShimmerView(label: "Running npx tsc && node dist/index.js...")
                    }
                    .padding()
                }

                // Static input bar mockup
                HStack(spacing: 12) {
                    Text("Message...")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .navigationTitle("my-project")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Chat") {
    ChatScreenshot()
}

// MARK: - Overview Screenshot Preview

#Preview("Overview") {
    NavigationStack {
        List {
            SpriteRowView(sprite: Sprite(
                name: "my-project",
                status: .running,
                createdAt: Date().addingTimeInterval(-2 * 3600)
            ))
            SpriteRowView(sprite: Sprite(
                name: "api-server",
                status: .warm,
                createdAt: Date().addingTimeInterval(-24 * 3600)
            ))
            SpriteRowView(sprite: Sprite(
                name: "data-pipeline",
                status: .cold,
                createdAt: Date().addingTimeInterval(-3 * 24 * 3600)
            ))
            SpriteRowView(sprite: Sprite(
                name: "playground",
                status: .cold,
                createdAt: Date().addingTimeInterval(-7 * 24 * 3600)
            ))
        }
        .navigationTitle("Sprites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image(systemName: "gearshape")
            }
            ToolbarItem(placement: .primaryAction) {
                Image(systemName: "plus")
            }
        }
    }
}

#endif
