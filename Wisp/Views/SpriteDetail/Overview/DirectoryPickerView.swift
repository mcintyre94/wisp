import SwiftUI

struct DirectoryPickerView: View {
    @Binding var workingDirectory: String
    let spriteName: String
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    @State private var currentPath: String
    @State private var entries: [DirectoryEntry] = []
    @State private var worktreeEntries: [DirectoryEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var manualPath = ""

    init(workingDirectory: Binding<String>, spriteName: String) {
        self._workingDirectory = workingDirectory
        self.spriteName = spriteName
        let parent = (workingDirectory.wrappedValue as NSString).deletingLastPathComponent
        self._currentPath = State(initialValue: parent)
    }

    private struct DirectoryEntry: Identifiable {
        let path: String
        let sessionCount: Int
        var id: String { path }
    }

    var body: some View {
        List {
            if !worktreeEntries.isEmpty {
                Section("Worktrees") {
                    ForEach(worktreeEntries) { entry in
                        Button {
                            workingDirectory = entry.path
                            dismiss()
                        } label: {
                            entryRow(entry, icon: "arrow.triangle.branch", isWorktree: true)
                        }
                    }
                }
            }

            Section("Directories") {
                if currentPath != "/" {
                    Button {
                        currentPath = (currentPath as NSString).deletingLastPathComponent
                    } label: {
                        Label("Parent directory", systemImage: "arrow.up")
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Listing directories...")
                        Spacer()
                    }
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.secondary)
                } else if entries.isEmpty {
                    Text("No subdirectories")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        Button {
                            currentPath = entry.path
                        } label: {
                            entryRow(entry, icon: "folder", isWorktree: false)
                        }
                    }
                }
            }

            Section("Manual Entry") {
                HStack {
                    TextField("Custom path", text: $manualPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Go") {
                        let path = manualPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !path.isEmpty else { return }
                        workingDirectory = path
                        dismiss()
                    }
                    .disabled(manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle(currentPath.displayPath)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use") {
                    workingDirectory = currentPath
                    dismiss()
                }
            }
        }
        .task {
            await loadWorktrees()
        }
        .task(id: currentPath) {
            await loadDirectories()
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: DirectoryEntry, icon: String, isWorktree: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(isWorktree ? worktreeDisplayName(entry.path) : entry.path.displayPath)
                    .foregroundStyle(.primary)
                if isWorktree {
                    Text(entry.path.displayPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if entry.sessionCount > 0 {
                Text("\(entry.sessionCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if entry.path == workingDirectory {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
            if !isWorktree {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Returns `{repo}/{branch-fragment}` for a worktree path under ~/.wisp/worktrees/
    private func worktreeDisplayName(_ path: String) -> String {
        let prefix = "/home/sprite/.wisp/worktrees/"
        guard path.hasPrefix(prefix) else { return path.displayPath }
        let relative = String(path.dropFirst(prefix.count))
        let parts = relative.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return relative }
        return "\(parts[0]) / \(parts[1])"
    }

    private func loadDirectories() async {
        isLoading = true
        errorMessage = nil

        // Single-quote-escape the path to prevent shell injection
        let escapedPath = currentPath.replacingOccurrences(of: "'", with: "'\\''")
        let command = """
        find '\(escapedPath)' -maxdepth 1 -mindepth 1 -type d -not -name '.*' 2>/dev/null | sort | while read d; do
          enc=$(echo "$d" | sed 's|/|-|g')
          c=$(find "/home/sprite/.claude/projects/${enc}" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
          printf "DIR:%s:%s\\n" "$d" "$c"
        done
        """

        let (output, success) = await apiClient.runExec(
            spriteName: spriteName,
            command: command,
            timeout: 15
        )

        if !success && output.isEmpty {
            errorMessage = "Could not list directories — sprite may be unavailable"
            isLoading = false
            return
        }

        entries = parseEntries(from: output, prefix: "DIR:")
        isLoading = false
    }

    private func loadWorktrees() async {
        let command = """
        find /home/sprite/.wisp/worktrees -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort | while read d; do
          enc=$(echo "$d" | sed 's|/|-|g')
          c=$(find "/home/sprite/.claude/projects/${enc}" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
          printf "TREE:%s:%s\\n" "$d" "$c"
        done
        """

        let (output, _) = await apiClient.runExec(
            spriteName: spriteName,
            command: command,
            timeout: 15
        )

        worktreeEntries = parseEntries(from: output, prefix: "TREE:")
    }

    private func parseEntries(from output: String, prefix: String) -> [DirectoryEntry] {
        output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(prefix) else { return nil }
            return parseEntry(String(trimmed.dropFirst(prefix.count)))
        }
    }

    /// Parses `{path}:{count}` — path may itself contain colons (unlikely on Linux but handled)
    private func parseEntry(_ raw: String) -> DirectoryEntry? {
        guard let lastColon = raw.lastIndex(of: ":") else { return nil }
        let path = String(raw[raw.startIndex..<lastColon])
        let countStr = String(raw[raw.index(after: lastColon)...])
        guard !path.isEmpty else { return nil }
        let count = Int(countStr.trimmingCharacters(in: .whitespaces)) ?? 0
        return DirectoryEntry(path: path, sessionCount: count)
    }
}

#Preview {
    NavigationStack {
        DirectoryPickerView(
            workingDirectory: .constant("/home/sprite/project"),
            spriteName: "my-sprite"
        )
        .environment(SpritesAPIClient())
    }
}
