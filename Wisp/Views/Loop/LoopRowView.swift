import SwiftUI

struct LoopRowView: View {
    let loop: SpriteLoop

    var body: some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(loop.prompt)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(loop.spriteName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Every \(loop.interval.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(loop.timeRemainingDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        switch loop.state {
        case .active: .green
        case .paused: .orange
        case .stopped: .gray
        }
    }
}

#Preview {
    List {
        LoopRowView(loop: SpriteLoop(
            spriteName: "my-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check PR #42 for new review comments",
            interval: .tenMinutes
        ))
    }
}
