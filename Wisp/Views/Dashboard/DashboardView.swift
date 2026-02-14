import SwiftUI

struct DashboardView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var viewModel = DashboardViewModel()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.sprites.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Sprites",
                        systemImage: "sparkles",
                        description: Text("Create a Sprite to get started")
                    )
                } else {
                    List {
                        ForEach(viewModel.sprites) { sprite in
                            NavigationLink(value: sprite) {
                                SpriteRowView(sprite: sprite)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    viewModel.spriteToDelete = sprite
                                }
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.loadSprites(apiClient: apiClient)
                    }
                }
            }
            .navigationTitle("Sprites")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Sprite.self) { sprite in
                SpriteDetailView(sprite: sprite)
            }
            .task {
                await viewModel.loadSprites(apiClient: apiClient)
            }
            .sheet(isPresented: $viewModel.showCreateSheet) {
                CreateSpriteSheet()
                    .onDisappear {
                        Task { await viewModel.loadSprites(apiClient: apiClient) }
                    }
            }
            .alert("Delete Sprite?", isPresented: .init(
                get: { viewModel.spriteToDelete != nil },
                set: { if !$0 { viewModel.spriteToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteSprite(apiClient: apiClient) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let sprite = viewModel.spriteToDelete {
                    Text("This will permanently delete \"\(sprite.name)\". This action cannot be undone.")
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
}
