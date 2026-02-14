import Foundation

@Observable
@MainActor
final class CheckpointsViewModel {
    let spriteName: String
    var checkpoints: [Checkpoint] = []
    var isLoading = false
    var isCreating = false
    var errorMessage: String?
    var showCreateSheet = false
    var checkpointToRestore: Checkpoint?
    var isRestoring = false
    var showRestoreSuccess = false

    init(spriteName: String) {
        self.spriteName = spriteName
    }

    func loadCheckpoints(apiClient: SpritesAPIClient) async {
        isLoading = true
        errorMessage = nil

        do {
            checkpoints = try await apiClient.listCheckpoints(spriteName: spriteName)
                .filter { $0.id != "Current" }
            checkpoints.sort { ($0.createTime ?? .distantPast) > ($1.createTime ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func createCheckpoint(apiClient: SpritesAPIClient, comment: String?) async {
        isCreating = true
        errorMessage = nil

        do {
            try await apiClient.createCheckpoint(spriteName: spriteName, comment: comment)
            // Reload list to pick up the new checkpoint
            await loadCheckpoints(apiClient: apiClient)
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }

    func restoreCheckpoint(checkpoint: Checkpoint, apiClient: SpritesAPIClient) async {
        checkpointToRestore = nil
        errorMessage = nil
        isRestoring = true

        do {
            try await apiClient.restoreCheckpoint(spriteName: spriteName, checkpointId: checkpoint.id)
            showRestoreSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isRestoring = false
    }
}
