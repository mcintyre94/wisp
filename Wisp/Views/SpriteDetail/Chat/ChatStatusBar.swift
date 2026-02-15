import SwiftUI

struct ChatStatusBar: View {
    let status: ChatStatus
    let modelName: String?

    private var isVisible: Bool {
        switch status {
        case .idle: return modelName != nil
        case .connecting, .streaming, .reconnecting, .error: return true
        }
    }

    var body: some View {
        if isVisible {
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
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
