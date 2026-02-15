import SwiftUI

struct SettingsView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @AppStorage("claudeModel") private var claudeModel: String = ClaudeModel.sonnet.rawValue
    @AppStorage("maxTurns") private var maxTurns: Int = 0
    @AppStorage("customInstructions") private var customInstructions: String = ""
    @AppStorage("theme") private var theme: String = "system"
    @State private var showSignOutConfirmation = false

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
        apiClient.refreshAuthState()
    }
}
