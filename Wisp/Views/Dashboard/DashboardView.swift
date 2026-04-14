import SwiftData
import SwiftUI

enum SpriteSortOrder: String, CaseIterable {
    case name = "Name"
    case newest = "Newest"
    case recentlyUpdated = "Recently Updated"
}

struct DashboardView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(ChatSessionManager.self) private var chatSessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel = DashboardViewModel()
    @Query(filter: #Predicate<SpriteChat> { $0.isUnread }) private var unreadChats: [SpriteChat]
    @State private var selectedSpriteID: String?
    @State private var selectedTab: SpriteTab = .chat
    @State private var sortOrder: SpriteSortOrder = .recentlyUpdated
    @State private var showSettings = false

    private var sortedSprites: [Sprite] {
        switch sortOrder {
        case .name:
            viewModel.sprites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest:
            viewModel.sprites.sortedByDate(\.createdAt)
        case .recentlyUpdated:
            viewModel.sprites.sortedByDate(\.updatedAt)
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 12) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SpriteSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Sprite")
        }
    }

    // iPad/Mac sidebar rows — use List(selection:) + .tag for split view column navigation
    @ViewBuilder
    private var iPadSpriteListRows: some View {
        ForEach(sortedSprites) { sprite in
            SpriteRowView(
                sprite: sprite,
                isPlain: true,
                isSelected: false,
                hasUnreadChats: unreadChats.contains { $0.spriteName == sprite.name }
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
            .id(sprite.id)
        }
    }

    // iPhone rows — NavigationLink(value:) drives push navigation in NavigationStack
    @ViewBuilder
    private var iPhoneSpriteListRows: some View {
        ForEach(sortedSprites) { sprite in
            NavigationLink(value: sprite.id) {
                SpriteRowView(
                    sprite: sprite,
                    isPlain: false,
                    isSelected: false,
                    hasUnreadChats: unreadChats.contains { $0.spriteName == sprite.name }
                )
            }
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
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .id(sprite.id)
        }
    }

    // iPhone: explicit NavigationStack so SpriteDetailView can push further views
    private var iPhoneContent: some View {
        NavigationStack {
            Group {
                if viewModel.sprites.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Sprites",
                        systemImage: "sparkles",
                        description: Text("Create a Sprite to get started")
                    )
                } else {
                    List {
                        iPhoneSpriteListRows
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await viewModel.loadSprites(apiClient: apiClient)
                    }
                }
            }
            .navigationTitle("Sprites")
            .toolbar { dashboardToolbar }
            .navigationDestination(for: String.self) { id in
                if let sprite = sortedSprites.first(where: { $0.id == id }) {
                    SpriteDetailView(sprite: sprite, selectedTab: $selectedTab)
                        .id(id)
                }
            }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    Group {
                        if viewModel.sprites.isEmpty && !viewModel.isLoading {
                            ContentUnavailableView(
                                "No Sprites",
                                systemImage: "sparkles",
                                description: Text("Create a Sprite to get started")
                            )
                        } else {
                            List(selection: $selectedSpriteID) {
                                iPadSpriteListRows
                            }
                            .listStyle(.sidebar)
                            .refreshable {
                                await viewModel.loadSprites(apiClient: apiClient)
                            }
                        }
                    }
                    .navigationTitle("Sprites")
                    .toolbar { dashboardToolbar }
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
            } else {
                iPhoneContent
            }
        }
        .onChange(of: sortedSprites) { _, newSprites in
            if let id = selectedSpriteID, !newSprites.contains(where: { $0.id == id }) {
                selectedSpriteID = nil
            }
        }
        .onChange(of: selectedSpriteID) { _, _ in
            selectedTab = .overview
        }
        .task {
            await viewModel.loadSprites(apiClient: apiClient)
            apiClient.cleanupLegacyServices(spriteNames: viewModel.sprites.map(\.name), modelContext: modelContext)
        }
        .task {
            // Reconnect any chats that were in-progress when the app was last closed.
            // isActive stays false on these VMs so result events mark them unread.
            let descriptor = FetchDescriptor<SpriteChat>(
                predicate: #Predicate { !$0.lastSessionComplete }
            )
            let incomplete = (try? modelContext.fetch(descriptor)) ?? []
            for chat in incomplete where chat.claudeSessionId != nil {
                let vm = chatSessionManager.viewModel(
                    for: chat,
                    spriteName: chat.spriteName,
                    apiClient: apiClient,
                    modelContext: modelContext
                )
                vm.reconnectIfNeeded(apiClient: apiClient, modelContext: modelContext)
            }
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
        .environment(ChatSessionManager())
        .modelContainer(for: [SpriteChat.self, SpriteSession.self], inMemory: true)
}
