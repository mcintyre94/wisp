import SwiftUI

struct SettingsView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @AppStorage("claudeModel") private var claudeModel: String = ClaudeModel.sonnet.rawValue
    @AppStorage("maxTurns") private var maxTurns: Int = 0
    @AppStorage("claudeQuestionTool") private var claudeQuestionTool: Bool = true
    @AppStorage("gitName") private var gitName: String = ""
    @AppStorage("gitEmail") private var gitEmail: String = ""
    @AppStorage("customInstructions") private var customInstructions: String = ""
    @AppStorage("theme") private var theme: String = "system"
    @AppStorage("autoCheckpoint") private var autoCheckpoint: Bool = false
    @AppStorage("worktreePerChat") private var worktreePerChat: Bool = true
    @State private var showSignOutConfirmation = false
    @State private var showGitHubConnect = false
    @State private var showGitHubDisconnectConfirmation = false
    @State private var copiedTokenFlash = false
    #if DEBUG
    @State private var copiedDeviceIDFlash = false
    @State private var copiedCommitFlash = false
    private var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "Unavailable"
    }
    private var buildCommit: String {
        Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "unknown"
    }
    #endif

    private var selectedModel: ClaudeModel {
        ClaudeModel(rawValue: claudeModel) ?? .sonnet
    }

    private var themeColorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some View {
        Form {
            accountSection
            gitIdentitySection
            claudeSection
            instructionsSection
            appearanceSection
            #if DEBUG
            developerSection
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGitHubConnect) {
            GitHubConnectSheet()
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            HStack {
                Label("Sprites API", systemImage: "server.rack")
                Spacer()
                Text(apiClient.isAuthenticated ? "Connected" : "Disconnected")
                    .foregroundStyle(apiClient.isAuthenticated ? .green : .secondary)
            }

            HStack {
                Label("Claude Code", systemImage: "brain")
                Spacer()
                Text(apiClient.hasClaudeToken ? "Connected" : "Disconnected")
                    .foregroundStyle(apiClient.hasClaudeToken ? .green : .secondary)
            }

            HStack {
                Label("GitHub", systemImage: "lock.shield")
                Spacer()
                #if DEBUG
                Text(copiedTokenFlash ? "Copied!" : (apiClient.hasGitHubToken ? "Connected" : "Not Connected"))
                    .foregroundStyle(copiedTokenFlash ? .green : (apiClient.hasGitHubToken ? .green : .secondary))
                    .contentTransition(.numericText())
                #else
                Text(apiClient.hasGitHubToken ? "Connected" : "Not Connected")
                    .foregroundStyle(apiClient.hasGitHubToken ? .green : .secondary)
                #endif
            }
            #if DEBUG
            .onTapGesture {
                if let token = apiClient.githubToken {
                    UIPasteboard.general.string = token
                    withAnimation {
                        copiedTokenFlash = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            copiedTokenFlash = false
                        }
                    }
                }
            }
            #endif

            if apiClient.hasGitHubToken {
                Button("Disconnect GitHub", role: .destructive) {
                    showGitHubDisconnectConfirmation = true
                }
                .confirmationDialog("Disconnect GitHub?", isPresented: $showGitHubDisconnectConfirmation) {
                    Button("Disconnect", role: .destructive) {
                        KeychainService.shared.delete(key: .githubToken)
                        apiClient.refreshAuthState()
                    }
                } message: {
                    Text("This will remove your GitHub token. You can reconnect later.")
                }
            } else {
                Button("Connect GitHub") {
                    showGitHubConnect = true
                }
            }

            Button("Sign Out", role: .destructive) {
                showSignOutConfirmation = true
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("This will remove all saved tokens. You'll need to sign in again.")
            }
        }
    }

    private var claudeSection: some View {
        Section("Claude") {
            Picker("Model", selection: $claudeModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }

            Picker("Max Turns", selection: $maxTurns) {
                Text("Unlimited").tag(0)
                ForEach(1...50, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Git Worktree Per Chat", isOn: $worktreePerChat)
                Text("Each chat gets its own git branch and worktree, so changes are isolated.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-Checkpoint", isOn: $autoCheckpoint)
                Text("Automatically take a checkpoint after Claude has written files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Claude Question Tool", isOn: $claudeQuestionTool)
                Text("Allows Claude to ask you clarifying questions. Installs a small helper on your Sprite the first time you chat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gitIdentitySection: some View {
        Section {
            TextField("Name", text: $gitName)
                .textContentType(.name)
                .autocorrectionDisabled()
            TextField("Email", text: $gitEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Git Identity")
        } footer: {
            if apiClient.hasGitHubToken {
                Text("Auto-populated from your GitHub profile. Used for git commits on Sprites.")
            } else {
                Text("Used for git commits on Sprites.")
            }
        }
    }

    private var instructionsSection: some View {
        Section {
            TextField("e.g. Always use TypeScript", text: $customInstructions, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Custom Instructions")
        } footer: {
            Text("Appended to Claude's system prompt for every message.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section {
            HStack {
                Label("Device ID", systemImage: "iphone")
                Spacer()
                Text(copiedDeviceIDFlash ? "Copied!" : deviceID)
                    .font(.caption)
                    .foregroundStyle(copiedDeviceIDFlash ? .green : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.numericText())
            }
            .onTapGesture {
                UIPasteboard.general.string = deviceID
                withAnimation {
                    copiedDeviceIDFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        copiedDeviceIDFlash = false
                    }
                }
            }
            HStack {
                Label("Build Commit", systemImage: "hammer")
                Spacer()
                Text(copiedCommitFlash ? "Copied!" : buildCommit)
                    .font(.caption)
                    .foregroundStyle(copiedCommitFlash ? .green : .secondary)
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText())
            }
            .onTapGesture {
                UIPasteboard.general.string = buildCommit
                withAnimation {
                    copiedCommitFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        copiedCommitFlash = false
                    }
                }
            }
        } header: {
            Text("Developer")
        }
    }
    #endif

    // MARK: - Actions

    private func signOut() {
        KeychainService.shared.delete(key: .spritesToken)
        KeychainService.shared.delete(key: .claudeToken)
        KeychainService.shared.delete(key: .githubToken)
        apiClient.refreshAuthState()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SpritesAPIClient())
    }
}
