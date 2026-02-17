import SwiftUI
import SwiftData

struct SpriteOverviewView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SpriteOverviewViewModel
    @State private var workingDirectory = "/home/sprite/project"

    init(sprite: Sprite) {
        _viewModel = State(initialValue: SpriteOverviewViewModel(sprite: sprite))
    }

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    Text("Status")
                    Spacer()
                    if viewModel.hasLoaded {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(statusColor)
                            Text(viewModel.sprite.status.displayName)
                        }
                    } else {
                        ProgressView()
                    }
                }
            }

            Section("Details") {
                if let url = viewModel.sprite.url, let linkURL = URL(string: url) {
                    Button {
                        openURL(linkURL)
                    } label: {
                        HStack {
                            Text("URL")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    .contextMenu {
                        Button {
                            UIApplication.shared.open(linkURL)
                        } label: {
                            Label("Open in Safari", systemImage: "safari")
                        }
                        Button {
                            UIPasteboard.general.string = url
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                    }
                }

                Toggle("Public URL", isOn: Binding(
                    get: { viewModel.sprite.urlSettings?.auth == "public" },
                    set: { _ in
                        Task { await viewModel.togglePublicAccess(apiClient: apiClient) }
                    }
                ))
                .disabled(viewModel.isUpdatingAuth || !viewModel.hasLoaded)

                if let createdAt = viewModel.sprite.createdAt {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(createdAt.relativeFormatted)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    DirectoryPickerView(
                        workingDirectory: $workingDirectory,
                        spriteName: viewModel.sprite.name
                    )
                } label: {
                    HStack {
                        Text("Working Directory")
                        Spacer()
                        Text(displayWorkingDirectory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Sprites CLI") {
                switch viewModel.spritesCLIAuthStatus {
                case .unknown, .checking:
                    HStack(spacing: 8) {
                        Text("Sprites CLI")
                        Spacer()
                        ProgressView()
                        Text("Checking...")
                            .foregroundStyle(.secondary)
                    }
                case .authenticated:
                    HStack {
                        Text("Sprites CLI")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Authenticated")
                            .foregroundStyle(.secondary)
                    }
                case .notAuthenticated:
                    Button {
                        Task { await viewModel.authenticateSprites(apiClient: apiClient) }
                    } label: {
                        HStack {
                            Text("Sprites CLI")
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.isAuthenticatingSprites {
                                ProgressView()
                            } else {
                                Text("Authenticate")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(viewModel.isAuthenticatingSprites)
                }
            }

            Section("GitHub") {
                switch viewModel.gitHubAuthStatus {
                case .unknown, .checking:
                    HStack(spacing: 8) {
                        Text("GitHub CLI")
                        Spacer()
                        ProgressView()
                        Text("Checking...")
                            .foregroundStyle(.secondary)
                    }
                case .authenticated:
                    HStack {
                        Text("GitHub CLI")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Authenticated")
                            .foregroundStyle(.secondary)
                    }
                case .notAuthenticated:
                    if apiClient.hasGitHubToken {
                        Button {
                            Task { await viewModel.authenticateGitHub(apiClient: apiClient) }
                        } label: {
                            HStack {
                                Text("GitHub CLI")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.isAuthenticatingGitHub {
                                    ProgressView()
                                } else {
                                    Text("Authenticate")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .disabled(viewModel.isAuthenticatingGitHub)
                    } else {
                        HStack {
                            Text("GitHub CLI")
                            Spacer()
                            Text("Not authenticated")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh(apiClient: apiClient)
        }
        .task {
            loadWorkingDirectory()
            await viewModel.refresh(apiClient: apiClient)
            await viewModel.checkSpritesAuth(apiClient: apiClient)
            await viewModel.checkGitHubAuth(apiClient: apiClient)
        }
        .onChange(of: workingDirectory) {
            saveWorkingDirectory()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    private var displayWorkingDirectory: String {
        if workingDirectory == "/home/sprite" {
            return "~"
        }
        if workingDirectory.hasPrefix("/home/sprite/") {
            return "~/" + workingDirectory.dropFirst("/home/sprite/".count)
        }
        return workingDirectory
    }

    private func loadWorkingDirectory() {
        let name = viewModel.sprite.name
        let descriptor = FetchDescriptor<SpriteSession>(
            predicate: #Predicate { $0.spriteName == name }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            workingDirectory = session.workingDirectory
        }
    }

    private func saveWorkingDirectory() {
        let name = viewModel.sprite.name
        let descriptor = FetchDescriptor<SpriteSession>(
            predicate: #Predicate { $0.spriteName == name }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            session.workingDirectory = workingDirectory
            try? modelContext.save()
        } else {
            let session = SpriteSession(spriteName: name, workingDirectory: workingDirectory)
            modelContext.insert(session)
            try? modelContext.save()
        }
    }

    private var statusColor: Color {
        switch viewModel.sprite.status {
        case .running: return .green
        case .warm: return .orange
        case .cold: return .blue
        case .unknown: return .gray
        }
    }
}
