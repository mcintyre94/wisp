import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct SpriteOverviewView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(ChatSessionManager.self) private var chatSessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var viewModel: SpriteOverviewViewModel
    @State private var workingDirectory = "/home/sprite/project"
    @State private var showUploadOptions = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showOverwriteConfirmation = false
    @State private var chatToDelete: SpriteChat?
    @State private var chatToRename: SpriteChat?
    @State private var renameText = ""

    // Optional chat/checkpoint navigation (compact layout only)
    private let chatListViewModel: SpriteChatListViewModel?
    private let onChatSelected: ((SpriteChat) -> Void)?
    private let onNewChat: (() -> Void)?
    private let onCheckpoints: (() -> Void)?

    init(
        sprite: Sprite,
        chatListViewModel: SpriteChatListViewModel? = nil,
        onChatSelected: ((SpriteChat) -> Void)? = nil,
        onNewChat: (() -> Void)? = nil,
        onCheckpoints: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: SpriteOverviewViewModel(sprite: sprite))
        self.chatListViewModel = chatListViewModel
        self.onChatSelected = onChatSelected
        self.onNewChat = onNewChat
        self.onCheckpoints = onCheckpoints
    }

    var body: some View {
        List {
            if let chatListVM = chatListViewModel {
                Section("Chats") {
                    ForEach(chatListVM.chats, id: \.id) { chat in
                        chatRow(for: chat, in: chatListVM)
                    }
                    Button {
                        onNewChat?()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }

                Section {
                    Button {
                        onCheckpoints?()
                    } label: {
                        HStack {
                            Label("Checkpoints", systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

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

            Section("Claude Code") {
                switch viewModel.claudeCodeVersionStatus {
                case .unknown, .checking:
                    HStack(spacing: 8) {
                        Text("Version")
                        Spacer()
                        ProgressView()
                        Text("Checking...")
                            .foregroundStyle(.secondary)
                    }
                case .upToDate(let version):
                    HStack {
                        Text("Version")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(version)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = version
                        } label: {
                            Label("Copy Version", systemImage: "doc.on.doc")
                        }
                    }
                case .updateAvailable(let current, _):
                    HStack {
                        Text("Version")
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                        Text(current)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = current
                        } label: {
                            Label("Copy Version", systemImage: "doc.on.doc")
                        }
                    }
                case .updating:
                    HStack(spacing: 8) {
                        Text("Version")
                        Spacer()
                        ProgressView()
                        Text("Updating...")
                            .foregroundStyle(.secondary)
                    }
                case .updateFailed(let error):
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                case .failed:
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("Not installed")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await viewModel.updateClaudeCode(apiClient: apiClient) }
                } label: {
                    HStack {
                        if case .updateAvailable(_, let latest) = viewModel.claudeCodeVersionStatus {
                            Text("Update to \(latest)")
                                .foregroundStyle(.primary)
                        } else {
                            Text("Update Claude Code")
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        if case .updating = viewModel.claudeCodeVersionStatus {
                            ProgressView()
                        } else if case .checking = viewModel.claudeCodeVersionStatus {
                            EmptyView()
                        } else if case .upToDate = viewModel.claudeCodeVersionStatus {
                            Text("Latest version")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .disabled({
                    if case .updating = viewModel.claudeCodeVersionStatus { return true }
                    if case .checking = viewModel.claudeCodeVersionStatus { return true }
                    if case .upToDate = viewModel.claudeCodeVersionStatus { return true }
                    return false
                }())
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
            async let claude: Void = viewModel.checkClaudeCodeVersion(apiClient: apiClient)
            async let sprites: Void = viewModel.checkSpritesAuth(apiClient: apiClient)
            async let github: Void = viewModel.checkGitHubAuth(apiClient: apiClient)
            _ = await (claude, sprites, github)
        }
        .task {
            await viewModel.pollStatus(apiClient: apiClient)
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
        .alert("Rename Chat", isPresented: Binding(
            get: { chatToRename != nil },
            set: { if !$0 { chatToRename = nil } }
        )) {
            TextField("Chat name", text: $renameText)
            Button("Save") {
                if let chat = chatToRename, let chatListVM = chatListViewModel {
                    chatListVM.renameChat(chat, name: renameText, modelContext: modelContext)
                    chatToRename = nil
                }
            }
            Button("Cancel", role: .cancel) {
                chatToRename = nil
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

    @ViewBuilder
    private func chatRow(for chat: SpriteChat, in chatListVM: SpriteChatListViewModel) -> some View {
        Button {
            onChatSelected?(chat)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if chat.isUnread {
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(chat.displayName)
                            .fontWeight(chat.isUnread ? .semibold : .regular)
                        if chat.isClosed {
                            Text("Closed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.fill.tertiary, in: Capsule())
                        }
                    }
                    if let preview = chat.firstMessagePreview {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                chat.isUnread.toggle()
                try? modelContext.save()
            } label: {
                Label(chat.isUnread ? "Read" : "Unread",
                      systemImage: chat.isUnread ? "envelope.open" : "envelope.badge")
            }
            .tint(.blue)
            if let sessionId = chat.claudeSessionId, !chat.isClosed {
                Button {
                    UIPasteboard.general.string = "cd \(chat.workingDirectory) && claude --resume \(sessionId)"
                } label: {
                    Label("Copy Resume", systemImage: "terminal")
                }
                .tint(.gray)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                chatToDelete = chat
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if !chat.isClosed {
                Button {
                    chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                    chatListVM.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            Button {
                chat.isUnread.toggle()
                try? modelContext.save()
            } label: {
                Label(chat.isUnread ? "Mark as Read" : "Mark as Unread",
                      systemImage: chat.isUnread ? "envelope.open" : "envelope.badge")
            }
            if let sessionId = chat.claudeSessionId, !chat.isClosed {
                Button {
                    UIPasteboard.general.string = "cd \(chat.workingDirectory) && claude --resume \(sessionId)"
                } label: {
                    Label("Copy Resume Command", systemImage: "terminal")
                }
            }
            Button {
                renameText = chat.customName ?? ""
                chatToRename = chat
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if !chat.isClosed {
                Button {
                    chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                    chatListVM.closeChat(chat, apiClient: apiClient, modelContext: modelContext)
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                chatToDelete = chat
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete Chat",
            isPresented: Binding(
                get: { chatToDelete?.id == chat.id },
                set: { if !$0 { chatToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                chatSessionManager.remove(chatId: chat.id, modelContext: modelContext)
                chatListVM.deleteChat(chat, apiClient: apiClient, modelContext: modelContext)
                chatToDelete = nil
            }
        } message: {
            Text("This will permanently delete the chat and its history.")
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
        let key = "workingDirectory_\(viewModel.sprite.name)"
        if let saved = UserDefaults.standard.string(forKey: key) {
            workingDirectory = saved
        }
    }

    private func saveWorkingDirectory() {
        let key = "workingDirectory_\(viewModel.sprite.name)"
        UserDefaults.standard.set(workingDirectory, forKey: key)
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

private func mockSprite(name: String = "my-sprite", status: String = "running") -> Sprite {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try! decoder.decode(Sprite.self, from: Data("""
        {"id":"s1","name":"\(name)","status":"\(status)","created_at":"2025-01-15T10:30:00Z"}
        """.utf8))
}

#Preview {
    NavigationStack {
        SpriteOverviewView(sprite: mockSprite())
            .environment(SpritesAPIClient())
            .environment(ChatSessionManager())
            .modelContainer(for: [SpriteChat.self, SpriteSession.self], inMemory: true)
            .navigationTitle("my-sprite")
            .navigationBarTitleDisplayMode(.inline)
    }
}
