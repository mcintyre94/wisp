import Foundation

enum GitHubSpriteAuth {
    case unknown, checking, authenticated, notAuthenticated
}

enum SpritesCLIAuth {
    case unknown, checking, authenticated, notAuthenticated
}

@Observable
@MainActor
final class SpriteOverviewViewModel {
    var sprite: Sprite
    var isRefreshing = false
    var hasLoaded = false
    var isUpdatingAuth = false
    var gitHubAuthStatus: GitHubSpriteAuth = .unknown
    var isAuthenticatingGitHub = false
    var spritesCLIAuthStatus: SpritesCLIAuth = .unknown
    var isAuthenticatingSprites = false
    var errorMessage: String?
    var isUploading = false
    var uploadResult: SpritesAPIClient.FileUploadResponse?
    var uploadError: String?
    var pendingUpload: PendingUpload?

    struct PendingUpload {
        let data: Data
        let filename: String
        let remotePath: String
        let apiClient: SpritesAPIClient
    }

    init(sprite: Sprite) {
        self.sprite = sprite
    }

    func refresh(apiClient: SpritesAPIClient) async {
        isRefreshing = true
        errorMessage = nil

        do {
            sprite = try await apiClient.getSprite(name: sprite.name)
        } catch {
            errorMessage = error.localizedDescription
        }

        hasLoaded = true
        isRefreshing = false
    }

    func togglePublicAccess(apiClient: SpritesAPIClient) async {
        let currentAuth = sprite.urlSettings?.auth ?? "sprite"
        let newAuth = currentAuth == "public" ? "sprite" : "public"

        isUpdatingAuth = true
        do {
            sprite = try await apiClient.updateSprite(
                name: sprite.name,
                urlSettings: Sprite.UrlSettings(auth: newAuth)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdatingAuth = false
    }

    func checkGitHubAuth(apiClient: SpritesAPIClient) async {
        gitHubAuthStatus = .checking
        let (output, _) = await apiClient.runExec(
            spriteName: sprite.name,
            command: "gh auth status >/dev/null 2>&1 && echo GHAUTH_OK || echo GHAUTH_FAIL"
        )
        if output.contains("GHAUTH_OK") {
            gitHubAuthStatus = .authenticated
        } else {
            gitHubAuthStatus = .notAuthenticated
        }
    }

    func authenticateGitHub(apiClient: SpritesAPIClient) async {
        guard let ghToken = apiClient.githubToken else { return }
        isAuthenticatingGitHub = true
        _ = await apiClient.runExec(
            spriteName: sprite.name,
            command: "printf '%s' '\(ghToken)' | gh auth login --with-token && gh auth setup-git"
        )
        isAuthenticatingGitHub = false
        await checkGitHubAuth(apiClient: apiClient)
    }

    func checkSpritesAuth(apiClient: SpritesAPIClient) async {
        spritesCLIAuthStatus = .checking
        let (output, _) = await apiClient.runExec(
            spriteName: sprite.name,
            command: "sprite org list 2>&1 | grep -q 'Currently selected org' && echo SPRITEAUTH_OK || echo SPRITEAUTH_FAIL"
        )
        if output.contains("SPRITEAUTH_OK") {
            spritesCLIAuthStatus = .authenticated
        } else {
            spritesCLIAuthStatus = .notAuthenticated
        }
    }

    func uploadFile(apiClient: SpritesAPIClient, fileURL: URL, workingDirectory: String) async {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
            uploadError = "Failed to read file: \(error.localizedDescription)"
            return
        }
        if accessing { fileURL.stopAccessingSecurityScopedResource() }

        await uploadData(apiClient: apiClient, data: data, filename: fileURL.lastPathComponent, workingDirectory: workingDirectory)
    }

    func uploadData(apiClient: SpritesAPIClient, data: Data, filename: String, workingDirectory: String) async {
        let remotePath = workingDirectory.hasSuffix("/")
            ? workingDirectory + filename
            : workingDirectory + "/" + filename

        isUploading = true
        uploadError = nil
        uploadResult = nil

        do {
            let exists = try await apiClient.fileExists(spriteName: sprite.name, remotePath: remotePath)
            if exists {
                pendingUpload = PendingUpload(data: data, filename: filename, remotePath: remotePath, apiClient: apiClient)
                isUploading = false
                return
            }
            try await performUpload(apiClient: apiClient, remotePath: remotePath, data: data)
        } catch {
            uploadError = error.localizedDescription
        }

        isUploading = false
    }

    func confirmOverwrite() async {
        guard let pending = pendingUpload else { return }
        pendingUpload = nil
        isUploading = true
        uploadError = nil

        do {
            try await performUpload(apiClient: pending.apiClient, remotePath: pending.remotePath, data: pending.data)
        } catch {
            uploadError = error.localizedDescription
        }

        isUploading = false
    }

    func cancelOverwrite() {
        pendingUpload = nil
    }

    private func performUpload(apiClient: SpritesAPIClient, remotePath: String, data: Data) async throws {
        let result = try await apiClient.uploadFile(
            spriteName: sprite.name,
            remotePath: remotePath,
            data: data
        )
        uploadResult = result
        Task {
            try? await Task.sleep(for: .seconds(3))
            if uploadResult?.path == result.path {
                uploadResult = nil
            }
        }
    }

    func authenticateSprites(apiClient: SpritesAPIClient) async {
        guard let token = apiClient.spritesToken else { return }
        isAuthenticatingSprites = true
        _ = await apiClient.runExec(
            spriteName: sprite.name,
            command: "sprite auth setup --token '\(token)'"
        )
        isAuthenticatingSprites = false
        await checkSpritesAuth(apiClient: apiClient)
    }
}
