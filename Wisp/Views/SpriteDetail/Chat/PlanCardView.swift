import SwiftUI

struct PlanCardView: View {
    let card: ToolUseCard
    @State private var isExpanded = true

    private var todos: [(id: String, content: String, status: String)] {
        guard case .array(let items) = card.input["todos"] else { return [] }
        return items.enumerated().compactMap { (index, item) -> (id: String, content: String, status: String)? in
            guard let content = item["content"]?.stringValue,
                  let status = item["status"]?.stringValue else { return nil }
            let id = item["id"]?.stringValue ?? "\(index)"
            return (id, content, status)
        }
    }

    private var completedCount: Int {
        todos.filter { $0.status == "completed" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Text("Plan")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Text("\(completedCount)/\(todos.count) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Items
            if isExpanded && !todos.isEmpty {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(todos, id: \.id) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: statusIcon(for: todo.status))
                                .font(.system(size: 14))
                                .foregroundStyle(statusColor(for: todo.status))
                                .frame(width: 16)

                            Text(todo.content)
                                .font(.caption)
                                .foregroundStyle(todo.status == "completed" ? .secondary : .primary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: card.result != nil) {
            // Collapse when result arrives (plan applied)
            if card.result != nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
    }

    private func statusIcon(for status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "arrow.right.circle.fill"
        default: return "circle"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "completed": return .green
        case "in_progress": return .blue
        default: return .secondary
        }
    }
}

#Preview("Mixed Status") {
    let card = ToolUseCard(
        toolUseId: "plan-1",
        toolName: "TodoWrite",
        input: .object([
            "todos": .array([
                .object(["id": .string("1"), "content": .string("Research codebase structure"), "status": .string("completed"), "priority": .string("high")]),
                .object(["id": .string("2"), "content": .string("Write data models"), "status": .string("completed"), "priority": .string("high")]),
                .object(["id": .string("3"), "content": .string("Implement API client"), "status": .string("in_progress"), "priority": .string("high")]),
                .object(["id": .string("4"), "content": .string("Add unit tests"), "status": .string("pending"), "priority": .string("medium")]),
                .object(["id": .string("5"), "content": .string("Update documentation"), "status": .string("pending"), "priority": .string("low")]),
            ])
        ])
    )
    PlanCardView(card: card)
        .padding()
}

#Preview("All Pending") {
    let card = ToolUseCard(
        toolUseId: "plan-2",
        toolName: "TodoWrite",
        input: .object([
            "todos": .array([
                .object(["id": .string("1"), "content": .string("Set up project structure"), "status": .string("pending")]),
                .object(["id": .string("2"), "content": .string("Configure dependencies"), "status": .string("pending")]),
                .object(["id": .string("3"), "content": .string("Build initial prototype"), "status": .string("pending")]),
            ])
        ])
    )
    PlanCardView(card: card)
        .padding()
}

#Preview("All Complete") {
    let card = ToolUseCard(
        toolUseId: "plan-3",
        toolName: "TodoWrite",
        input: .object([
            "todos": .array([
                .object(["id": .string("1"), "content": .string("Fix login bug"), "status": .string("completed")]),
                .object(["id": .string("2"), "content": .string("Add error handling"), "status": .string("completed")]),
            ])
        ])
    )
    PlanCardView(card: card)
        .padding()
}
