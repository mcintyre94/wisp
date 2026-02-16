import SwiftUI

struct SettingsView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @AppStorage("claudeModel") private var claudeModel: String = ClaudeModel.sonnet.rawValue
    @AppStorage("maxTurns") private var maxTurns: Int = 0
    @AppStorage("customInstructions") private var customInstructions: String = ""
    @AppStorage("theme") private var theme: String = "system"
    @State private var showSignOutConfirmation = false
    @State private var showGitHubConnect = false
    @State private var showGitHubDisconnectConfirmation = false
    @State private var copiedTokenFlash = false

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
            claudeSection
            instructionsSection
            appearanceSection
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
                if apiClient.hasGitHubToken {
                    Text("Connected")
                        .foregroundStyle(.green)
                } else {
                    Text("Not Connected")
                        .foregroundStyle(.secondary)
                }
            }
            #if DEBUG
            .onTapGesture {
                if let token = apiClient.githubToken {
                    UIPasteboard.general.string = token
                    copiedTokenFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedTokenFlash = false
                    }
                }
            }
            .overlay(alignment: .trailing) {
                if copiedTokenFlash {
                    Text("Copied!")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: copiedTokenFlash)
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

    // MARK: - Actions

    private func signOut() {
        KeychainService.shared.delete(key: .spritesToken)
        KeychainService.shared.delete(key: .claudeToken)
        KeychainService.shared.delete(key: .githubToken)
        apiClient.refreshAuthState()
    }
}
