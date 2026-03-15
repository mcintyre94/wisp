import Foundation

struct ShareIntent: Equatable {
    let spriteName: String
    let fileURLs: [URL]
}

@Observable
@MainActor
final class ShareIntentCoordinator {
    static let appGroupID = "group.com.wisp.app"

    var pendingIntent: ShareIntent?

    func handleURL(_ url: URL) {
        guard url.scheme == "wisp",
              url.host == "share",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let spriteName = components.queryItems?.first(where: { $0.name == "sprite" })?.value,
              let sessionID = components.queryItems?.first(where: { $0.name == "session" })?.value
        else { return }

        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("pending_share/\(sessionID)")

        let fileURLs: [URL]
        if let containerURL,
           let files = try? FileManager.default.contentsOfDirectory(
               at: containerURL,
               includingPropertiesForKeys: [.nameKey],
               options: .skipsHiddenFiles
           ) {
            fileURLs = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            fileURLs = []
        }

        pendingIntent = ShareIntent(spriteName: spriteName, fileURLs: fileURLs)
    }

    /// Returns and clears the intent if it matches the given sprite name.
    func consume(forSprite name: String) -> ShareIntent? {
        guard pendingIntent?.spriteName == name else { return nil }
        let intent = pendingIntent
        pendingIntent = nil
        return intent
    }
}
