import SwiftUI

struct CheckpointMarkerView: View {
    let comment: String?
    let onFork: () -> Void

    var body: some View {
        Button(action: onFork) {
            HStack(spacing: 8) {
                line
                Image(systemName: "diamond.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)
                Text(comment ?? "Checkpoint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.branch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                line
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(height: 0.5)
    }
}
