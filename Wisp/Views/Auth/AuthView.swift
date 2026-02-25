import SwiftUI

struct AuthView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var viewModel = AuthViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StepIndicator(currentStep: viewModel.step)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

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

// MARK: - Step Indicator

private struct StepIndicator: View {
    let currentStep: AuthViewModel.AuthStep

    private let steps: [(label: String, step: AuthViewModel.AuthStep)] = [
        ("Sprites", .spritesToken),
        ("Claude", .claudeToken),
        ("GitHub", .githubToken),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(isCompleted(item.step) ? Color.accentColor : Color(.systemGray4))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(circleColor(for: item.step))
                            .frame(width: 28, height: 28)

                        if isCompleted(item.step) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isCurrent(item.step) ? .white : .secondary)
                        }
                    }

                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(isCurrent(item.step) ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func circleColor(for step: AuthViewModel.AuthStep) -> Color {
        if isCompleted(step) || isCurrent(step) {
            return .accentColor
        }
        return Color(.systemGray5)
    }

    private func isCurrent(_ step: AuthViewModel.AuthStep) -> Bool {
        step == currentStep
    }

    private func isCompleted(_ step: AuthViewModel.AuthStep) -> Bool {
        let order: [AuthViewModel.AuthStep] = [.spritesToken, .claudeToken, .githubToken]
        guard let currentIndex = order.firstIndex(of: currentStep),
              let stepIndex = order.firstIndex(of: step) else { return false }
        return stepIndex < currentIndex
    }
}
