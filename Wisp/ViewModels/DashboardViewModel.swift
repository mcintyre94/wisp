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

        if let updated = try? await apiClient.listSprites(), updated != sprites {
            // Only replace the array when data actually changed. An unconditional
            // assignment re-triggers SwiftUI observation even when content is identical,
            // which re-renders the List and can interrupt an in-flight
            // NavigationSplitView push on iPhone, leaving selectedSpriteID set but
            // no detail shown (stuck selection).
            sprites = updated
        }

        isLoading = false
    }

    private(set) var wakingSprites: Set<String> = []

    func wakeSprite(_ sprite: Sprite, apiClient: SpritesAPIClient) async {
        guard !wakingSprites.contains(sprite.name) else { return }
        wakingSprites.insert(sprite.name)
        defer { wakingSprites.remove(sprite.name) }

        do {
            _ = try await apiClient.wakeSpriteIfNeeded(name: sprite.name, timeout: 60)
        } catch {
            errorMessage = error.localizedDescription
        }

        if let updated = try? await apiClient.listSprites() {
            sprites = updated
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
