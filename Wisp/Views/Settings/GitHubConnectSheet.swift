import SwiftUI

struct GitHubConnectSheet: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    @State private var userCode = ""
    @State private var verificationURL = ""
    @State private var isPolling = false
    @State private var error: String?
    @State private var pollingTask: Task<Void, Never>?

    private let client = GitHubDeviceFlowClient()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if userCode.isEmpty && error == nil {
                    ProgressView("Starting device flow...")
                } else if !userCode.isEmpty {
                    Text("Connect GitHub Account")
                        .font(.headline)

                    GitHubDeviceFlowView(
                        userCode: userCode,
                        verificationURL: verificationURL,
                        isPolling: isPolling,
                        error: error,
                        onCopyAndOpen: copyCodeAndOpen,
                        onCancel: cancel
                    )
                } else if let error {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            startDeviceFlow()
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                    }
                }
            }
            .task {
                startDeviceFlow()
            }
        }
    }

    private func startDeviceFlow() {
        pollingTask?.cancel()
        error = nil
        userCode = ""

        pollingTask = Task {
            do {
                let response = try await client.requestDeviceCode()
                userCode = response.userCode
                verificationURL = response.verificationUri
                isPolling = true

                let token = try await client.pollForToken(
                    deviceCode: response.deviceCode,
                    expiresIn: response.expiresIn,
                    interval: response.interval
                )

                try KeychainService.shared.save(token, for: .githubToken)
                apiClient.refreshAuthState()
                dismiss()
            } catch is CancellationError {
                // User cancelled
            } catch {
                self.error = error.localizedDescription
                isPolling = false
            }
        }
    }

    private func copyCodeAndOpen() {
        UIPasteboard.general.string = userCode
        if let url = URL(string: verificationURL) {
            UIApplication.shared.open(url)
        }
    }

    private func cancel() {
        pollingTask?.cancel()
        dismiss()
    }
}
