import SwiftUI

struct ServiceRowView: View {
    let service: ServiceInfo
    let displayName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Text(service.cmd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let port = service.httpPort {
                        Text(":\(port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(service.state.status.capitalized)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch service.state.status {
        case "running": return .green
        case "stopped": return .secondary
        default: return .orange
        }
    }
}

#Preview {
    List {
        ServiceRowView(
            service: ServiceInfo(
                name: "wisp-claude-abc123",
                cmd: "claude",
                args: ["-p"],
                httpPort: nil,
                needs: [],
                state: ServiceInfo.ServiceState(name: "wisp-claude-abc123", pid: 1234, startedAt: Date(), status: "running")
            ),
            displayName: "Chat 1"
        )
        ServiceRowView(
            service: ServiceInfo(
                name: "webapp",
                cmd: "python",
                args: ["-m", "http.server", "8000"],
                httpPort: 8000,
                needs: ["postgres"],
                state: ServiceInfo.ServiceState(name: "webapp", pid: 1567, startedAt: Date(), status: "running")
            ),
            displayName: "webapp"
        )
    }
}
