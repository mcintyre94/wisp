import SwiftUI

struct EditTokenSheet: View {
    enum TokenType {
        case sprites
        case claude

        var title: String {
            switch self {
            case .sprites: "Update Sprites Token"
            case .claude: "Update Claude Token"
            }
        }

        var placeholder: String {
            switch self {
            case .sprites: "Sprites API Token"
            case .claude: "Claude Code OAuth Token (sk-ant-oat01-...)"
            }
        }

        var keychainKey: KeychainKey {
            switch self {
            case .sprites: .spritesToken
            case .claude: .claudeToken
            }
        }

        var needsValidation: Bool {
            switch self {
            case .sprites: true
            case .claude: false
            }
        }
    }

    let tokenType: TokenType
    @Binding var isPresented: Bool
    @Environment(SpritesAPIClient.self) private var apiClient

    @State private var token = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var saveButtonLabel: String {
        tokenType.needsValidation ? "Validate & Save" : "Save"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(tokenType.placeholder, text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(tokenType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonLabel) {
                        Task { await save() }
                    }
                    .disabled(token.isEmpty || isSaving)
                    .overlay {
                        if isSaving {
                            ProgressView()
                        }
                    }
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil

        if tokenType.needsValidation {
            isSaving = true
            defer { isSaving = false }
            do {
                try KeychainService.shared.save(trimmed, for: tokenType.keychainKey)
                apiClient.refreshAuthState()
                try await apiClient.validateToken()
                isPresented = false
            } catch {
                KeychainService.shared.delete(key: tokenType.keychainKey)
                apiClient.refreshAuthState()
                errorMessage = "Invalid token. Please check and try again."
            }
        } else {
            do {
                try KeychainService.shared.save(trimmed, for: tokenType.keychainKey)
                apiClient.refreshAuthState()
                isPresented = false
            } catch {
                errorMessage = "Failed to save token."
            }
        }
    }
}

#Preview {
    EditTokenSheet(tokenType: .claude, isPresented: .constant(true))
        .environment(SpritesAPIClient())
}
