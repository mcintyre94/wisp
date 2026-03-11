import SwiftUI

enum SpriteSortOrder: String, CaseIterable {
    case name = "Name"
    case newest = "Newest"
}

struct DashboardView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel = DashboardViewModel()
    @State private var selectedSpriteID: String?
    @State private var selectedTab: SpriteTab = .chat
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

    @ViewBuilder
    private var spriteListRows: some View {
        ForEach(sortedSprites) { sprite in
            SpriteRowView(
                sprite: sprite,
                isPlain: sizeClass == .regular,
                isSelected: sizeClass != .regular && selectedSpriteID == sprite.id
            )
            .tag(sprite.id)
            .swipeActions(edge: .trailing) {
                Button("Delete") {
                    viewModel.spriteToDelete = sprite
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                if (sprite.status == .warm || sprite.status == .cold) && !viewModel.wakingSprites.contains(sprite.name) {
                    Button {
                        Task { await viewModel.wakeSprite(sprite, apiClient: apiClient) }
                    } label: {
                        Label("Wake", systemImage: "bolt.fill")
                    }
                    .tint(.orange)
                }
            }
            .contextMenu {
                if (sprite.status == .warm || sprite.status == .cold) && !viewModel.wakingSprites.contains(sprite.name) {
                    Button {
                        Task { await viewModel.wakeSprite(sprite, apiClient: apiClient) }
                    } label: {
                        Label("Wake Sprite", systemImage: "bolt.fill")
                    }
                }
                Button(role: .destructive) {
                    viewModel.spriteToDelete = sprite
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
            .listRowSeparator(sizeClass == .regular ? .automatic : .hidden)
            .listRowBackground(sizeClass == .regular ? nil : Color.clear)
            .listRowInsets(sizeClass == .regular ? nil : EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .id(sprite.id)
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
                } else if sizeClass == .regular {
                    // iPad/Mac: use .sidebar list style so the split view properly
                    // auto-dismisses the sidebar overlay on selection (portrait iPad,
                    // multitasking). .plain doesn't trigger this behaviour.
                    List(selection: $selectedSpriteID) {
                        spriteListRows
                    }
                    .listStyle(.sidebar)
                    .refreshable {
                        await viewModel.loadSprites(apiClient: apiClient)
                    }
                } else {
                    List(selection: $selectedSpriteID) {
                        spriteListRows
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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
            if let id = selectedSpriteID, let selectedSprite = sortedSprites.first(where: { $0.id == id }) {
                SpriteDetailView(sprite: selectedSprite, selectedTab: $selectedTab)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "Select a Sprite",
                    systemImage: "sparkles",
                    description: Text("Choose a Sprite from the list to get started")
                )
            }
        }
        .onChange(of: sortedSprites) { _, newSprites in
            if let id = selectedSpriteID, !newSprites.contains(where: { $0.id == id }) {
                selectedSpriteID = nil
            }
        }
        .onChange(of: selectedSpriteID) { _, _ in
            if sizeClass != .regular {
                selectedTab = .chat
            }
        }
        .task {
            await viewModel.loadSprites(apiClient: apiClient)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await viewModel.refreshSprites(apiClient: apiClient)
            }
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

#Preview {
    DashboardView()
        .environment(SpritesAPIClient())
}
