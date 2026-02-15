import SwiftData
import SwiftUI

@main
struct WispApp: App {
    @State private var apiClient = SpritesAPIClient()
    @AppStorage("theme") private var theme: String = "system"

    private var preferredColorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(apiClient)
                .preferredColorScheme(preferredColorScheme)
        }
        .modelContainer(for: SpriteSession.self)
    }
}
