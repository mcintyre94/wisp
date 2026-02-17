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
