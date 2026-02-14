import Foundation

@Observable
@MainActor
final class SpriteOverviewViewModel {
    var sprite: Sprite
    var isRefreshing = false
    var hasLoaded = false
    var isUpdatingAuth = false
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
}
