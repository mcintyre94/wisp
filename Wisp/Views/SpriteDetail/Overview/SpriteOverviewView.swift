import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct SpriteOverviewView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SpriteOverviewViewModel
    @State private var workingDirectory = "/home/sprite/project"
    @State private var showUploadOptions = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showOverwriteConfirmation = false

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

            Section("Files") {
                Button {
                    showUploadOptions = true
                } label: {
                    HStack {
                        Label("Upload File", systemImage: "square.and.arrow.up")
                        Spacer()
                        if viewModel.isUploading {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isUploading)
                .confirmationDialog("Upload", isPresented: $showUploadOptions) {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo")
                    }
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Choose File", systemImage: "doc")
                    }
                }

                if let result = viewModel.uploadResult {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(URL(filePath: result.path).lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(result.size), countStyle: .file)))")
                            .foregroundStyle(.green)
                    }
                }

                if let error = viewModel.uploadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
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
        .alert(
            "File Already Exists",
            isPresented: $showOverwriteConfirmation
        ) {
            Button("Replace", role: .destructive) {
                Task { await viewModel.confirmOverwrite() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelOverwrite()
            }
        } message: {
            if let pending = viewModel.pendingUpload {
                Text("\"\(pending.filename)\" already exists in the working directory. Do you want to replace it?")
            }
        }
        .onChange(of: viewModel.pendingUpload != nil) { _, hasPending in
            showOverwriteConfirmation = hasPending
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 1, matching: .images)
        .onChange(of: selectedPhotos) { _, items in
            guard let item = items.first else { return }
            selectedPhotos = []
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    viewModel.uploadError = "Failed to load photo"
                    return
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let filename = "photo_\(Int(Date().timeIntervalSince1970)).\(ext)"
                await viewModel.uploadData(
                    apiClient: apiClient,
                    data: data,
                    filename: filename,
                    workingDirectory: workingDirectory
                )
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await viewModel.uploadFile(
                        apiClient: apiClient,
                        fileURL: url,
                        workingDirectory: workingDirectory
                    )
                }
            case .failure(let error):
                viewModel.uploadError = error.localizedDescription
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
