import Foundation

@Observable
@MainActor
final class SpriteOverviewViewModel {
    var sprite: Sprite
    var isRefreshing = false
    var errorMessage: String?
    var copiedURL = false

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

        isRefreshing = false
    }
}
