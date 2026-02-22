import SwiftUI

struct RepoPickerView: View {
    @Binding var selection: GitHubRepo?
    let token: String?

    @Environment(\.dismiss) private var dismiss
    @State private var repos: [GitHubRepo] = []
    @State private var searchText = ""
    @State private var cloneURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var client: GitHubAPIClient { GitHubAPIClient(token: token) }
    private var hasToken: Bool { token != nil }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Paste a clone URL", text: $cloneURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Clone") {
                        selectFromURL()
                    }
                    .disabled(parsedCloneURL == nil)
                }
            } header: {
                Text("Clone URL")
            }

            if isLoading && repos.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Failed to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else if repos.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if repos.isEmpty && !hasToken {
                ContentUnavailableView(
                    "Search GitHub",
                    systemImage: "magnifyingglass",
                    description: Text("Type to search for repositories")
                )
            } else {
                ForEach(repos) { repo in
                    Button {
                        selection = repo
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(repo.fullName)
                                    .fontWeight(.medium)
                                if repo.isPrivate {
                                    Image(systemName: "lock")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let description = repo.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationTitle("Select Repository")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search repositories")
        .textInputAutocapitalization(.never)
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            if newValue.isEmpty {
                if hasToken {
                    searchTask = Task { await loadUserRepos() }
                } else {
                    repos = []
                }
            } else {
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await search(query: newValue)
                }
            }
        }
        .task {
            if hasToken {
                await loadUserRepos()
            }
        }
    }

    private func loadUserRepos() async {
        isLoading = true
        errorMessage = nil
        do {
            repos = try await client.fetchUserRepos()
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func search(query: String) async {
        isLoading = true
        errorMessage = nil
        do {
            repos = try await client.searchRepos(query: query)
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private var parsedCloneURL: URL? {
        let trimmed = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    private func selectFromURL() {
        guard let url = parsedCloneURL else { return }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let stripped = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
        let components = stripped.components(separatedBy: "/")
        let fullName = components.suffix(2).joined(separator: "/")
        selection = GitHubRepo(
            id: url.absoluteString.hashValue,
            fullName: fullName.isEmpty ? url.absoluteString : fullName,
            description: nil,
            cloneURL: url.absoluteString,
            isPrivate: false
        )
        dismiss()
    }
}
