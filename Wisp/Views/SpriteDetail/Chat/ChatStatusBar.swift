import SwiftUI

struct ChatStatusBar: View {
    let status: ChatStatus
    let modelName: String?
    @Binding var modelOverride: ClaudeModel?
    var hasPendingWispAsk: Bool = false

    @AppStorage("claudeModel") private var globalModel: String = ClaudeModel.sonnet.rawValue

    private var effectiveModel: ClaudeModel {
        modelOverride ?? ClaudeModel(rawValue: globalModel) ?? .sonnet
    }

    private var statusKey: String {
        switch status {
        case .idle: return "idle-\(modelName ?? "")-\(effectiveModel.rawValue)"
        case .connecting: return "connecting"
        case .streaming: return hasPendingWispAsk ? "waiting" : "streaming"
        case .reconnecting: return "reconnecting"
        case .error(let message): return "error-\(message)"
        }
    }

    var body: some View {
        HStack {
            statusPill
            Spacer()
        }
        .padding(.horizontal)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            switch status {
            case .idle:
                modelPicker
            case .connecting:
                ProgressView()
                    .controlSize(.mini)
                Text("Connecting...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .streaming:
                ProgressView()
                    .controlSize(.mini)
                Text(hasPendingWispAsk ? "Waiting for answer..." : "Streaming...")
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
        .glassEffect()
        .animation(.easeInOut(duration: 0.2), value: statusKey)
    }

    private var modelPicker: some View {
        Menu {
            ForEach(ClaudeModel.allCases) { model in
                Button {
                    if model.rawValue == globalModel {
                        modelOverride = nil
                    } else {
                        modelOverride = model
                    }
                } label: {
                    HStack {
                        Text(model.displayName)
                        if model == effectiveModel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 9))
                Text(effectiveModel.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 8))
            }
        }
    }
}

private let previewBackground = LinearGradient(
    colors: [.blue.opacity(0.9), .purple.opacity(0.9)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

#Preview("Idle - Model Picker") {
    @Previewable @State var modelOverride: ClaudeModel? = nil
    ChatStatusBar(status: .idle, modelName: "claude-sonnet-4-5-20250929", modelOverride: $modelOverride)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(previewBackground)
}

#Preview("Streaming") {
    @Previewable @State var modelOverride: ClaudeModel? = nil
    ChatStatusBar(status: .streaming, modelName: nil, modelOverride: $modelOverride)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(previewBackground)
}

#Preview("Connecting") {
    @Previewable @State var modelOverride: ClaudeModel? = nil
    ChatStatusBar(status: .connecting, modelName: nil, modelOverride: $modelOverride)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(previewBackground)
}

#Preview("Reconnecting") {
    @Previewable @State var modelOverride: ClaudeModel? = nil
    ChatStatusBar(status: .reconnecting, modelName: nil, modelOverride: $modelOverride)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(previewBackground)
}

#Preview("Error") {
    @Previewable @State var modelOverride: ClaudeModel? = nil
    ChatStatusBar(status: .error("Connection lost"), modelName: nil, modelOverride: $modelOverride)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(previewBackground)
}

#Preview("All States") {
    @Previewable @State var stateIndex = 0
    @Previewable @State var modelOverride: ClaudeModel? = nil

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
            modelName: states[stateIndex].1,
            modelOverride: $modelOverride
        )

        Button("Next State") {
            stateIndex = (stateIndex + 1) % states.count
        }.buttonStyle(.bordered).background(.regularMaterial, in: .capsule)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(previewBackground)
}
