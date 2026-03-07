import SwiftUI

struct ServiceLogLine: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    let timestamp: Date?
}

struct ServiceDetailView: View {
    let spriteName: String
    let service: ServiceInfo
    let displayName: String

    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var logLines: [ServiceLogLine] = []
    @State private var isStreaming = false
    @State private var streamError: String?
    @State private var showStopConfirmation = false
    @State private var isStopping = false
    @State private var hasStopped = false
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        Group {
            if logLines.isEmpty && isStreaming {
                ProgressView("Loading logs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if logLines.isEmpty && !isStreaming && streamError == nil && hasStopped {
                ContentUnavailableView("Service Stopped", systemImage: "stop.circle", description: Text("No logs captured."))
            } else if logLines.isEmpty && !isStreaming && streamError == nil {
                ContentUnavailableView("No Logs", systemImage: "doc.text", description: Text("No log output yet."))
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(logLines) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.isError ? Color.orange : Color.primary)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .id(line.id)
                        }

                        if let error = streamError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: logLines.count) {
                        if let last = logLines.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .task { scrollToBottom(proxy: proxy) }
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isStopping {
                    ProgressView()
                } else if !hasStopped {
                    Button(role: .destructive) {
                        showStopConfirmation = true
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .tint(.red)
                }
            }
        }
        .confirmationDialog("Stop \"\(displayName)\"?", isPresented: $showStopConfirmation, titleVisibility: .visible) {
            Button("Stop Service", role: .destructive) {
                Task { await stopService() }
            }
        } message: {
            Text("This will terminate the service process.")
        }
        .task {
            await startStreaming()
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = logLines.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func startStreaming() async {
        isStreaming = true
        streamError = nil

        let task = Task {
            do {
                let stream = apiClient.streamServiceLogs(spriteName: spriteName, serviceName: service.name)
                for try await event in stream {
                    switch event.type {
                    case .stdout:
                        if let text = event.data, !text.isEmpty {
                            let line = ServiceLogLine(
                                text: text,
                                isError: false,
                                timestamp: event.timestamp.map { Date(timeIntervalSince1970: $0) }
                            )
                            logLines.append(line)
                        }
                    case .stderr:
                        if let text = event.data, !text.isEmpty {
                            let line = ServiceLogLine(
                                text: text,
                                isError: true,
                                timestamp: event.timestamp.map { Date(timeIntervalSince1970: $0) }
                            )
                            logLines.append(line)
                        }
                    case .stopped, .stopping:
                        hasStopped = true
                    case .exit:
                        hasStopped = true
                    case .complete:
                        break
                    case .error:
                        streamError = event.data ?? "Stream error"
                    default:
                        break
                    }
                }
            } catch is CancellationError {
                // Normal cancellation on view dismiss
            } catch {
                streamError = error.localizedDescription
            }
            isStreaming = false
        }

        streamTask = task
        await task.value
    }

    private func stopService() async {
        isStopping = true
        defer { isStopping = false }
        do {
            try await apiClient.deleteService(spriteName: spriteName, serviceName: service.name)
            hasStopped = true
        } catch {
            streamError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ServiceDetailView(
            spriteName: "my-sprite",
            service: ServiceInfo(
                name: "webapp",
                cmd: "python",
                args: ["-m", "http.server", "8000"],
                httpPort: 8000,
                needs: [],
                state: ServiceInfo.ServiceState(name: "webapp", pid: 1567, startedAt: Date(), status: "running")
            ),
            displayName: "webapp"
        )
        .environment(SpritesAPIClient())
    }
}
