import SwiftData
import SwiftUI

@main
struct WispApp: App {
    @State private var apiClient = SpritesAPIClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(apiClient)
        }
        .modelContainer(for: SpriteSession.self)
    }
}
