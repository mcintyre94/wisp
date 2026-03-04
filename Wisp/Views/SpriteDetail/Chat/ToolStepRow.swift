import SwiftUI

struct ToolStepRow: View {
    let card: ToolUseCard
    var workingDirectory: String = ""
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: card.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(strippedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if let elapsed = card.elapsedString {
                        Text(elapsed)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }

                if let preview = card.result?.previewContent {
                    Text(preview)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.leading, 22)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var strippedLabel: String {
        let label = card.activityLabel.relativeToCwd(workingDirectory)
        if label.hasSuffix("...") {
            return String(label.dropLast(3))
        }
        return label
    }
}
