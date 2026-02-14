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
            Text("Step 1 of 2")
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

            Button("Save & Start") {
                viewModel.saveClaudeToken(apiClient: apiClient)
            }
            .disabled(viewModel.claudeToken.isEmpty)
        } header: {
            Text("Step 2 of 2")
        } footer: {
            Text("Enter your Claude Code OAuth token (sk-ant-oat01-...)")
        }
    }
}
