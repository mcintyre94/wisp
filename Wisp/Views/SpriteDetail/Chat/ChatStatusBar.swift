import SwiftUI

struct ChatStatusBar: View {
    let status: ChatStatus
    let modelName: String?

    private var statusKey: String {
        switch status {
        case .idle: return "idle-\(modelName ?? "")"
        case .connecting: return "connecting"
        case .streaming: return "streaming"
        case .reconnecting: return "reconnecting"
        case .error(let message): return "error-\(message)"
        }
    }

    private var isVisible: Bool {
        switch status {
        case .idle: return modelName != nil
        case .connecting, .streaming, .reconnecting, .error: return true
        }
    }

    var body: some View {
        if isVisible {
            HStack {
                statusPill
                Spacer()
            }
            .padding(.horizontal)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
                switch status {
                case .idle:
                    if let modelName {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 10))
                        Text(modelName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case .connecting:
                    ProgressView()
                        .controlSize(.mini)
                    Text("Connecting...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .streaming:
                    ProgressView()
                        .controlSize(.mini)
                    Text("Streaming...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .reconnecting:
                    ProgressView()
                        .controlSize(.mini)
                    Text("Reconnecting...")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 10))
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .animation(.easeInOut(duration: 0.2), value: statusKey)
    }
}

#Preview("Idle") {
    ChatStatusBar(status: .idle, modelName: "claude-sonnet-4-5-20250929")
}

#Preview("Streaming") {
    ChatStatusBar(status: .streaming, modelName: nil)
}

#Preview("Connecting") {
    ChatStatusBar(status: .connecting, modelName: nil)
}

#Preview("Reconnecting") {
    ChatStatusBar(status: .reconnecting, modelName: nil)
}

#Preview("Error") {
    ChatStatusBar(status: .error("Connection lost"), modelName: nil)
}

#Preview("All States") {
    @Previewable @State var stateIndex = 0

    let states: [(ChatStatus, String?)] = [
        (.connecting, nil),
        (.streaming, nil),
        (.idle, "claude-sonnet-4-5-20250929"),
        (.reconnecting, nil),
        (.error("Connection lost"), nil),
    ]

    VStack(spacing: 20) {
        ChatStatusBar(
            status: states[stateIndex].0,
            modelName: states[stateIndex].1
        )

        Button("Next State") {
            stateIndex = (stateIndex + 1) % states.count
        }
    }
}
