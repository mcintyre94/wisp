import Foundation
import UIKit

@Observable
@MainActor
final class AuthViewModel {
    var spritesToken = ""
    var claudeToken = ""
    var isValidating = false
    var errorMessage: String?
    var step: AuthStep = .spritesToken
    var isComplete = false

    // GitHub device flow state
    var githubUserCode = ""
    var githubVerificationURL = ""
    var isPollingGitHub = false
    var githubError: String?
    var githubPollingTask: Task<Void, Never>?

    private let keychain = KeychainService.shared
    private let githubClient = GitHubDeviceFlowClient()

    enum AuthStep {
        case spritesToken
        case claudeToken
        case githubToken
    }

    func validateSpritesToken(apiClient: SpritesAPIClient) async {
        let trimmed = spritesToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a Sprites API token."
            return
        }

        isValidating = true
        errorMessage = nil

        do {
            try keychain.save(trimmed, for: .spritesToken)
            apiClient.refreshAuthState()
            try await apiClient.validateToken()
            step = .claudeToken
        } catch {
            keychain.delete(key: .spritesToken)
            apiClient.refreshAuthState()
            errorMessage = "Invalid Sprites token. Please check and try again."
        }

        isValidating = false
    }

    func saveClaudeToken(apiClient: SpritesAPIClient) {
        let trimmed = claudeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a Claude Code OAuth token."
            return
        }

        do {
            try keychain.save(trimmed, for: .claudeToken)
            // Don't call refreshAuthState() here — defer until GitHub step resolves
            // so RootView doesn't flip to Dashboard before user sees step 3
            step = .githubToken
        } catch {
            errorMessage = "Failed to save Claude token."
        }
    }

    func startGitHubDeviceFlow(apiClient: SpritesAPIClient) {
        githubPollingTask?.cancel()
        githubError = nil
        githubUserCode = ""

        githubPollingTask = Task {
            do {
                let response = try await githubClient.requestDeviceCode()
                githubUserCode = response.userCode
                githubVerificationURL = response.verificationUri
                isPollingGitHub = true

                let token = try await githubClient.pollForToken(
                    deviceCode: response.deviceCode,
                    expiresIn: response.expiresIn,
                    interval: response.interval
                )

                try keychain.save(token, for: .githubToken)
                isPollingGitHub = false
                apiClient.refreshAuthState()
            } catch is CancellationError {
                isPollingGitHub = false
            } catch {
                githubError = error.localizedDescription
                isPollingGitHub = false
            }
        }
    }

    func copyCodeAndOpenGitHub() {
        UIPasteboard.general.string = githubUserCode
        if let url = URL(string: githubVerificationURL) {
            UIApplication.shared.open(url)
        }
    }

    func skipGitHub(apiClient: SpritesAPIClient) {
        githubPollingTask?.cancel()
        githubPollingTask = nil
        isPollingGitHub = false
        apiClient.refreshAuthState()
    }
}
