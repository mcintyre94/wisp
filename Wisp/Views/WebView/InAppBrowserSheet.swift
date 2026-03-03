import SwiftUI

struct InAppBrowserSheet: View {
    let initialURL: URL
    var authToken: String?
    @Environment(\.dismiss) private var dismiss
    @State private var state = WebViewState()
    @State private var showConsoleLogs = false

    private var displayTitle: String {
        let host = (state.currentURL ?? initialURL).host() ?? ""
        if host.hasSuffix(".sprites.app"), let name = host.split(separator: ".").first {
            return String(name)
        }
        return host.isEmpty ? initialURL.absoluteString : host
    }

    private var consoleIndicatorColor: Color? {
        if state.consoleLogs.contains(where: { $0.level == .error }) { return .red }
        if state.consoleLogs.contains(where: { $0.level == .warn }) { return .orange }
        if !state.consoleLogs.isEmpty { return .accentColor }
        return nil
    }

    var body: some View {
        NavigationStack {
            WebViewPage(initialURL: initialURL, authToken: authToken, state: state)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showConsoleLogs) {
                    ConsoleLogDrawer(logs: state.consoleLogs) {
                        state.consoleLogs.removeAll()
                    }
                    .presentationDetents([.fraction(0.4), .large])
                    .presentationDragIndicator(.visible)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }

                    ToolbarItem(placement: .status) {
                        if state.isLoading {
                            ProgressView()
                        }
                    }

                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            state.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!state.canGoBack)

                        Button {
                            state.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!state.canGoForward)

                        Spacer()

                        ShareLink(item: state.currentURL ?? initialURL)

                        Button {
                            UIApplication.shared.open(state.currentURL ?? initialURL)
                        } label: {
                            Image(systemName: "safari")
                        }

                        Button {
                            showConsoleLogs = true
                        } label: {
                            Image(systemName: "terminal")
                                .overlay(alignment: .topTrailing) {
                                    if let color = consoleIndicatorColor {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 7, height: 7)
                                            .offset(x: 5, y: -5)
                                    }
                                }
                        }
                    }
                }
        }
    }
}

private struct ConsoleLogDrawer: View {
    let logs: [ConsoleLogEntry]
    let onClear: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    ContentUnavailableView(
                        "No Console Output",
                        systemImage: "terminal",
                        description: Text("Console messages will appear here.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List(logs) { entry in
                            ConsoleLogRow(entry: entry)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }
                        .listStyle(.plain)
                        .onChange(of: logs.count) { _, _ in
                            if let last = logs.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { onClear() }
                        .disabled(logs.isEmpty)
                }
            }
        }
    }
}

#Preview("Console Drawer - Empty") {
    ConsoleLogDrawer(logs: []) {}
}

#Preview("Console Drawer - With Logs") {
    ConsoleLogDrawer(logs: [
        ConsoleLogEntry(level: .log, message: "Page loaded"),
        ConsoleLogEntry(level: .info, message: "User signed in"),
        ConsoleLogEntry(level: .debug, message: "Cache hit: true"),
        ConsoleLogEntry(level: .warn, message: "Deprecated API used"),
        ConsoleLogEntry(level: .error, message: "Failed to fetch: 404 Not Found"),
    ]) {}
}

private struct ConsoleLogRow: View {
    let entry: ConsoleLogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.level.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(entry.level.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                .padding(.top, 1)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.top, 1)
        }
    }
}
