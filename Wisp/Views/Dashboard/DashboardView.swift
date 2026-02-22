import SwiftUI

enum SpriteSortOrder: String, CaseIterable {
    case name = "Name"
    case newest = "Newest"
}

struct DashboardView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var viewModel = DashboardViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var sortOrder: SpriteSortOrder = .newest

    private var sortedSprites: [Sprite] {
        switch sortOrder {
        case .name:
            viewModel.sprites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest:
            viewModel.sprites.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

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
                        ForEach(sortedSprites) { sprite in
                            NavigationLink(value: sprite) {
                                SpriteRowView(sprite: sprite)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete") {
                                    viewModel.spriteToDelete = sprite
                                }
                                .tint(.red)
                            }
                            .confirmationDialog("Delete Sprite?", isPresented: .init(
                                get: { viewModel.spriteToDelete?.id == sprite.id },
                                set: { if !$0 { viewModel.spriteToDelete = nil } }
                            )) {
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.deleteSprite(sprite, apiClient: apiClient) }
                                }
                            } message: {
                                Text("This will permanently delete \"\(sprite.name)\". This action cannot be undone.")
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.loadSprites(apiClient: apiClient)
                    }
                }
            }
            .navigationTitle("Sprites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        Menu {
                            Picker("Sort", selection: $sortOrder) {
                                ForEach(SpriteSortOrder.allCases, id: \.self) { order in
                                    Text(order.rawValue)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
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
