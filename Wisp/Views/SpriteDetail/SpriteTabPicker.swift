import SwiftUI

enum SpriteTab: String, CaseIterable {
    case overview = "Overview"
    case chat = "Chat"
    case checkpoints = "Checkpoints"
    case services = "Services"
}

struct SpriteTabPicker: View {
    @Binding var selectedTab: SpriteTab

    // Services are accessible via the Overview section on compact — exclude from picker
    private static let compactTabs: [SpriteTab] = [.overview, .chat, .checkpoints]

    var body: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(Self.compactTabs, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .glassEffect()
        .padding()
    }
}

#Preview {
    SpriteTabPicker(selectedTab: .constant(.chat))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.9), .purple.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
}
