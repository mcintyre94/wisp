import Foundation
import SwiftUI

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

    func deleteSprite(_ sprite: Sprite, apiClient: SpritesAPIClient) async {
        // Optimistic removal
        let previousSprites = sprites
        withAnimation {
            sprites.removeAll { $0.id == sprite.id }
        }

        do {
            try await apiClient.deleteSprite(name: sprite.name)
        } catch {
            // Revert and refresh on failure
            withAnimation {
                sprites = previousSprites
            }
            errorMessage = error.localizedDescription
            await loadSprites(apiClient: apiClient)
        }
    }
}
