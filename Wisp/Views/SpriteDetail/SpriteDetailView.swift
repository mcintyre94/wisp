import SwiftUI

enum SpriteTab: String, CaseIterable {
    case overview = "Overview"
    case chat = "Chat"
    case checkpoints = "Checkpoints"
}

struct SpriteDetailView: View {
    let sprite: Sprite
    @State private var selectedTab: SpriteTab = .chat

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(SpriteTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .overview:
                SpriteOverviewView(sprite: sprite)
            case .chat:
                ChatView(spriteName: sprite.name)
            case .checkpoints:
                CheckpointsView(spriteName: sprite.name)
            }
        }
        .navigationTitle(sprite.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
