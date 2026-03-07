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
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            sprites = try await apiClient.listSprites()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshSprites(apiClient: SpritesAPIClient) async {
        guard !isLoading else { return }
        isLoading = true

        if let updated = try? await apiClient.listSprites() {
            sprites = updated
        }

        isLoading = false
    }

    var wakingSprites: Set<String> = []

    func wakeSprite(_ sprite: Sprite, apiClient: SpritesAPIClient) async {
        guard !wakingSprites.contains(sprite.name) else { return }
        wakingSprites.insert(sprite.name)
        defer { wakingSprites.remove(sprite.name) }

        // Fire a no-op exec to trigger the wake
        Task {
            _ = await apiClient.runExec(spriteName: sprite.name, command: "true", timeout: 60)
        }

        // Poll until running or timeout
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(2))
            if let updated = try? await apiClient.listSprites() {
                sprites = updated
                if updated.first(where: { $0.name == sprite.name })?.status == .running {
                    return
                }
            }
        }
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
