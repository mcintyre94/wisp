import SwiftUI

struct DirectoryPickerView: View {
    @Binding var workingDirectory: String
    let spriteName: String
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    @State private var directories: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var manualPath = ""

    var body: some View {
        List {
            Section {
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
            } header: {
                Text("Manual Entry")
            }

            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Listing directories...")
                        Spacer()
                    }
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.secondary)
                } else if directories.isEmpty {
                    Text("No directories found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(directories, id: \.self) { (dir: String) in
                        Button {
                            workingDirectory = dir
                            dismiss()
                        } label: {
                            HStack {
                                Text(displayPath(dir))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if dir == workingDirectory {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Directories")
            }
        }
        .navigationTitle("Working Directory")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDirectories()
        }
    }

    private func displayPath(_ path: String) -> String {
        if path == "/home/sprite" {
            return "~"
        }
        if path.hasPrefix("/home/sprite/") {
            return "~/" + path.dropFirst("/home/sprite/".count)
        }
        return path
    }

    private func loadDirectories() async {
        isLoading = true
        errorMessage = nil

        let (output, success) = await apiClient.runExec(
            spriteName: spriteName,
            command: "find /home/sprite -maxdepth 1 -type d -not -name '.*' 2>/dev/null | sort",
            timeout: 15
        )

        if !success && output.isEmpty {
            errorMessage = "Could not list directories — sprite may be unavailable"
            isLoading = false
            return
        }

        let paths = output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        directories = paths
        isLoading = false
    }
}
