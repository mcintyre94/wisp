import SwiftUI

struct ToolInputDetailView: View {
    let toolName: String
    let input: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch toolName {
            case "Bash":
                bashInput
            case "Read":
                filePathInput("Reading")
            case "Write":
                writeInput
            case "Edit":
                editInput
            case "Glob":
                patternInput("Pattern")
            case "Grep":
                patternInput("Search")
            default:
                genericInput
            }
        }
    }

    private var bashInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Command")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(input["command"]?.stringValue ?? "")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func filePathInput(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(input["file_path"]?.stringValue ?? "")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var writeInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(input["file_path"]?.stringValue ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if let content = input["content"]?.stringValue {
                Text(content)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(10)
                    .textSelection(.enabled)
            }
        }
    }

    private var editInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(input["file_path"]?.stringValue ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if let oldStr = input["old_string"]?.stringValue {
                Text("- \(oldStr)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.red)
                    .lineLimit(5)
            }
            if let newStr = input["new_string"]?.stringValue {
                Text("+ \(newStr)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green)
                    .lineLimit(5)
            }
        }
    }

    private func patternInput(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(input["pattern"]?.stringValue ?? "")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var genericInput: some View {
        Text(input.prettyString)
            .font(.system(.caption2, design: .monospaced))
            .lineLimit(15)
            .textSelection(.enabled)
    }
}
