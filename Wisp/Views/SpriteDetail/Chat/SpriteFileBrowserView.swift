import SwiftUI

struct SpriteFileBrowserView: View {
    let spriteName: String
    let startingDirectory: String
    let apiClient: SpritesAPIClient
    let onFileSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DirectoryListingView(
                spriteName: spriteName,
                directoryPath: startingDirectory,
                apiClient: apiClient,
                onFileSelected: { path in
                    onFileSelected(path)
                    dismiss()
                }
            )
            .navigationTitle("Sprite Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - File Entry Model

struct FileEntry: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?

    static func parse(line: String) -> FileEntry? {
        // Expected format: "d 4096 /home/sprite/project/src" or "f 1234 /home/sprite/project/main.py"
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count == 3 else { return nil }

        let typeChar = String(parts[0])
        guard typeChar == "d" || typeChar == "f" else { return nil }

        let isDirectory = typeChar == "d"
        let size = Int64(parts[1])
        let path = String(parts[2])
        let name = (path as NSString).lastPathComponent

        guard !name.isEmpty else { return nil }

        return FileEntry(
            name: name,
            path: path,
            isDirectory: isDirectory,
            size: isDirectory ? nil : size
        )
    }

    static func parseOutput(_ output: String) -> [FileEntry] {
        output
            .split(separator: "\n")
            .compactMap { parse(line: String($0)) }
    }
}

// MARK: - Directory Listing

private struct DirectoryListingView: View {
    let spriteName: String
    let directoryPath: String
    let apiClient: SpritesAPIClient
    let onFileSelected: (String) -> Void

    @State private var entries: [FileEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tooManyEntries = false

    private let maxEntries = 200

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Connecting to sprite...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if entries.isEmpty {
                ContentUnavailableView {
                    Label("Empty Directory", systemImage: "folder")
                } description: {
                    Text("No files found")
                }
            } else {
                List {
                    if directoryPath != "/" {
                        NavigationLink(value: parentPath) {
                            Label(".. (parent)", systemImage: "arrow.up.doc")
                        }
                    }

                    ForEach(entries) { entry in
                        if entry.isDirectory {
                            NavigationLink(value: entry.path) {
                                directoryRow(entry)
                            }
                        } else {
                            Button {
                                onFileSelected(entry.path)
                            } label: {
                                fileRow(entry)
                            }
                        }
                    }

                    if tooManyEntries {
                        Text("Only showing first \(maxEntries) entries")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(directoryPath == "/" ? "/" : (directoryPath as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { path in
            DirectoryListingView(
                spriteName: spriteName,
                directoryPath: path,
                apiClient: apiClient,
                onFileSelected: onFileSelected
            )
        }
        .task {
            await loadEntries()
        }
    }

    private var parentPath: String {
        let parent = (directoryPath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    @ViewBuilder
    private func directoryRow(_ entry: FileEntry) -> some View {
        Label {
            Text(entry.name)
        } icon: {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func fileRow(_ entry: FileEntry) -> some View {
        HStack {
            Label {
                Text(entry.name)
            } icon: {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let size = entry.size {
                Text(formattedSize(size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func loadEntries() async {
        isLoading = true
        errorMessage = nil

        let command = "find \(directoryPath) -maxdepth 1 -not -name '.*' -printf '%y %s %p\\n' 2>/dev/null | sort -k3"
        let (output, success) = await apiClient.runExec(spriteName: spriteName, command: command)

        if !success && output.isEmpty {
            errorMessage = "Could not reach sprite"
            isLoading = false
            return
        }

        var parsed = FileEntry.parseOutput(output)
        // Remove the directory itself (find includes it)
        parsed.removeAll { $0.path == directoryPath }

        if parsed.count > maxEntries {
            tooManyEntries = true
            parsed = Array(parsed.prefix(maxEntries))
        }

        // Sort: directories first, then alphabetically
        parsed.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        entries = parsed
        isLoading = false
    }
}

#Preview {
    SpriteFileBrowserView(
        spriteName: "test-sprite",
        startingDirectory: "/home/sprite/project",
        apiClient: SpritesAPIClient(),
        onFileSelected: { _ in }
    )
}
