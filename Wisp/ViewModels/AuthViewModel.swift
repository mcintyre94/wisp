import Foundation

@Observable
@MainActor
final class AuthViewModel {
    var spritesToken = ""
    var claudeToken = ""
    var isValidating = false
    var errorMessage: String?
    var step: AuthStep = .spritesToken
    var isComplete = false

    private let keychain = KeychainService.shared

    enum AuthStep {
        case spritesToken
        case claudeToken
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
            apiClient.refreshAuthState()
        } catch {
            errorMessage = "Failed to save Claude token."
        }
    }
}
