import SwiftUI

enum SpriteSortOrder: String, CaseIterable {
    case name = "Name"
    case newest = "Newest"
}

struct DashboardView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var viewModel = DashboardViewModel()
    @State private var selectedSprite: Sprite?
    @State private var sortOrder: SpriteSortOrder = .newest
    @State private var showSettings = false

    private var sortedSprites: [Sprite] {
        switch sortOrder {
        case .name:
            viewModel.sprites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest:
            viewModel.sprites.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if viewModel.sprites.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Sprites",
                        systemImage: "sparkles",
                        description: Text("Create a Sprite to get started")
                    )
                } else {
                    List(selection: $selectedSprite) {
                        ForEach(sortedSprites) { sprite in
                            SpriteRowView(sprite: sprite)
                                .tag(sprite)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            showSettings = true
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
        } detail: {
            if let selectedSprite {
                SpriteDetailView(sprite: selectedSprite)
            } else {
                ContentUnavailableView(
                    "Select a Sprite",
                    systemImage: "sparkles",
                    description: Text("Choose a Sprite from the list to get started")
                )
            }
        }
        .onChange(of: sortedSprites) { _, newSprites in
            if let selected = selectedSprite, !newSprites.contains(selected) {
                selectedSprite = nil
            }
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
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
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
