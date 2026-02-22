import SwiftUI
import SwiftData

struct CreateSpriteSheet: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isCreating = false
    @State private var creationStatus: String?
    @State private var hasMetMinLength = false
    @State private var errorMessage: String?
    @State private var selectedRepo: GitHubRepo?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sprite name", text: $name)
                        .focused($isNameFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: name) { _, newValue in
                            let filtered = String(newValue.lowercased().filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" })
                            let truncated = String(filtered.prefix(63))
                            if truncated != newValue {
                                name = truncated
                            }
                            if name.count >= 3 {
                                hasMetMinLength = true
                            }
                        }
                } footer: {
                    if !name.isEmpty, name.hasPrefix("-") || name.hasSuffix("-") {
                        Text("Name must start and end with a letter or number")
                            .foregroundStyle(.red)
                    } else if hasMetMinLength, name.count < 3 {
                        Text("Name must be at least 3 characters")
                            .foregroundStyle(.red)
                    } else {
                        Text("Lowercase letters, numbers, and hyphens only")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Repository") {
                    NavigationLink {
                        RepoPickerView(selection: $selectedRepo, token: apiClient.githubToken)
                    } label: {
                        HStack {
                            Text("Repository")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(selectedRepo?.fullName ?? "None")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if selectedRepo != nil {
                        Button("Clear Selection", role: .destructive) {
                            selectedRepo = nil
                        }
                        .font(.subheadline)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if let creationStatus {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(creationStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Sprite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createSprite() }
                    }
                    .disabled(name.isEmpty || nameValidationError != nil || isCreating)
                }
            }
            .disabled(isCreating)
            .onAppear { isNameFocused = true }
        }
    }

    private var nameValidationError: String? {
        if name.count < 3 {
            return "Name must be at least 3 characters"
        }
        if name.hasPrefix("-") || name.hasSuffix("-") {
            return "Name must start and end with a letter or number"
        }
        return nil
    }

    private var repoInfo: (cloneURL: String, repoName: String)? {
        guard let repo = selectedRepo else { return nil }
        return (repo.cloneURL, repo.repoName)
    }

    private func createSprite() async {
        isCreating = true
        errorMessage = nil
        creationStatus = "Creating sprite..."

        do {
            _ = try await apiClient.createSprite(name: name)
            // Clear any stale chats from a previous sprite with the same name
            let spriteName = name
            let descriptor = FetchDescriptor<SpriteChat>(
                predicate: #Predicate { $0.spriteName == spriteName }
            )
            if let staleChats = try? modelContext.fetch(descriptor), !staleChats.isEmpty {
                for chat in staleChats {
                    modelContext.delete(chat)
                }
                try? modelContext.save()
            }

            // Push GitHub token onto sprite if available
            if let ghToken = apiClient.githubToken {
                creationStatus = "Setting up GitHub..."
                _ = await apiClient.runExec(
                    spriteName: spriteName,
                    command: "printf '%s' '\(ghToken)' | gh auth login --with-token && gh auth setup-git"
                )
            }

            // Authenticate Sprites CLI on the new sprite
            if let spritesToken = apiClient.spritesToken {
                creationStatus = "Setting up Sprites CLI..."
                _ = await apiClient.runExec(
                    spriteName: spriteName,
                    command: "sprite auth setup --token '\(spritesToken)'"
                )
            }

            // Clone repo if specified
            if let info = repoInfo {
                creationStatus = "Cloning repository..."
                let clonePath = "/home/sprite/\(info.repoName)"
                _ = await apiClient.runExec(
                    spriteName: spriteName,
                    command: "git clone --depth 1 '\(info.cloneURL)' '\(clonePath)'",
                    timeout: 60
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            creationStatus = nil
        }

        isCreating = false
    }
}
