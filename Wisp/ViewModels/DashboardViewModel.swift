import Foundation

@Observable
@MainActor
final class DashboardViewModel {
    var sprites: [Sprite] = []
    var isLoading = false
    var errorMessage: String?
    var showCreateSheet = false
    var spriteToDelete: Sprite?

    func loadSprites(apiClient: SpritesAPIClient) async {
        isLoading = true
        errorMessage = nil

        do {
            sprites = try await apiClient.listSprites()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteSprite(apiClient: SpritesAPIClient) async {
        guard let sprite = spriteToDelete else { return }
        spriteToDelete = nil

        do {
            try await apiClient.deleteSprite(name: sprite.name)
            sprites.removeAll { $0.id == sprite.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
