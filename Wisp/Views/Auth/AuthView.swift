import SwiftUI

struct AuthView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var viewModel = AuthViewModel()

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.step {
                case .spritesToken:
                    spritesTokenSection
                case .claudeToken:
                    claudeTokenSection
                case .githubToken:
                    githubTokenSection
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sign In")
            .disabled(viewModel.isValidating)
        }
    }

    private var spritesTokenSection: some View {
        Section {
            SecureField("Sprites API Token", text: $viewModel.spritesToken)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                Task {
                    await viewModel.validateSpritesToken(apiClient: apiClient)
                }
            } label: {
                HStack {
                    Text("Validate & Continue")
                    Spacer()
                    if viewModel.isValidating {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.spritesToken.isEmpty || viewModel.isValidating)
        } header: {
            Text("Step 1 of 3")
        } footer: {
            Text("Enter your Sprites API token from sprites.dev")
        }
    }

    private var claudeTokenSection: some View {
        Section {
            SecureField("Claude Code OAuth Token", text: $viewModel.claudeToken)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button("Save & Continue") {
                viewModel.saveClaudeToken(apiClient: apiClient)
            }
            .disabled(viewModel.claudeToken.isEmpty)
        } header: {
            Text("Step 2 of 3")
        } footer: {
            Text("Enter your Claude Code OAuth token (sk-ant-oat01-...)")
        }
    }

    private var githubTokenSection: some View {
        Section {
            if !viewModel.githubUserCode.isEmpty {
                GitHubDeviceFlowView(
                    userCode: viewModel.githubUserCode,
                    verificationURL: viewModel.githubVerificationURL,
                    isPolling: viewModel.isPollingGitHub,
                    error: viewModel.githubError,
                    onCopyAndOpen: { viewModel.copyCodeAndOpenGitHub() },
                    onCancel: { viewModel.skipGitHub(apiClient: apiClient) }
                )
            } else if viewModel.githubError != nil {
                // Error state — show retry
            } else {
                Button {
                    viewModel.startGitHubDeviceFlow(apiClient: apiClient)
                } label: {
                    Label("Connect GitHub Account", systemImage: "lock.shield")
                }
            }

            Button("Skip for Now") {
                viewModel.skipGitHub(apiClient: apiClient)
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("Step 3 of 3 — Optional")
        } footer: {
            Text("Connect GitHub to clone repos directly onto your Sprites. You can always connect later from Settings.")
        }
    }
}
