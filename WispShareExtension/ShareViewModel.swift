import Foundation
import UIKit
import UniformTypeIdentifiers

// MARK: - Minimal API types (extension cannot import the main app target)

struct ShareSprite: Identifiable, Sendable {
    let id: String
    let name: String
    let status: String
}

private struct SpritesListResponse: Decodable {
    let sprites: [SpritePayload]

    struct SpritePayload: Decodable {
        let id: String
        let name: String
        let status: String
    }
}

// MARK: - ShareViewModel

@Observable
@MainActor
final class ShareViewModel {
    private static let appGroupID = "group.com.wisp.app"
    private static let apiBase   = "https://api.sprites.dev/v1"

    var sprites: [ShareSprite] = []
    var isLoading = false
    var sendingToSpriteID: String?
    var errorMessage: String?

    private let extensionContext: NSExtensionContext

    init(extensionContext: NSExtensionContext) {
        self.extensionContext = extensionContext
    }

    // MARK: - Lifecycle

    func load() async {
        guard let token = storedToken else {
            errorMessage = "Open Wisp first to sign in, then try again."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            sprites = try await fetchSprites(token: token)
        } catch {
            errorMessage = "Couldn't load sprites: \(error.localizedDescription)"
        }
    }

    func share(to sprite: ShareSprite) async {
        sendingToSpriteID = sprite.id
        defer { sendingToSpriteID = nil }

        let sessionID = UUID().uuidString
        guard let container = appGroupContainer?.appendingPathComponent("pending_share/\(sessionID)") else {
            errorMessage = "Couldn't access app group storage."
            return
        }

        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Couldn't create staging directory."
            return
        }

        let providers = itemProviders
        var savedAny = false
        for provider in providers {
            if await saveItem(provider, to: container) != nil {
                savedAny = true
            }
        }

        guard savedAny else {
            errorMessage = "No supported files found in the shared content."
            return
        }

        var components = URLComponents()
        components.scheme = "wisp"
        components.host = "share"
        components.queryItems = [
            URLQueryItem(name: "sprite",  value: sprite.name),
            URLQueryItem(name: "session", value: sessionID),
        ]

        guard let url = components.url else { return }
        extensionContext.open(url) { _ in }
        extensionContext.completeRequest(returningItems: [], completionHandler: nil)
    }

    func cancel() {
        extensionContext.completeRequest(returningItems: [], completionHandler: nil)
    }

    // MARK: - Private helpers

    private var storedToken: String? {
        UserDefaults(suiteName: Self.appGroupID)?.string(forKey: "spritesToken")
    }

    private var appGroupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
    }

    private var itemProviders: [NSItemProvider] {
        (extensionContext.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []
    }

    private func fetchSprites(token: String) async throws -> [ShareSprite] {
        guard let url = URL(string: "\(Self.apiBase)/sprites") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(SpritesListResponse.self, from: data)
        return decoded.sprites.map { ShareSprite(id: $0.id, name: $0.name, status: $0.status) }
    }

    /// Saves a single item provider's content into `directory`. Returns the saved URL or nil.
    private func saveItem(_ provider: NSItemProvider, to directory: URL) async -> URL? {
        // 1. Prefer a concrete file URL (Files app, document picker, etc.)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let sourceURL = item as? URL else { cont.resume(returning: nil); return }
                    let accessing = sourceURL.startAccessingSecurityScopedResource()
                    defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
                    let dest = directory.appendingPathComponent(sourceURL.lastPathComponent)
                    try? FileManager.default.copyItem(at: sourceURL, to: dest)
                    let saved = FileManager.default.fileExists(atPath: dest.path) ? dest : nil
                    cont.resume(returning: saved)
                }
            }
        }

        // 2. Image types — load as raw data and write with the right extension
        let imageTypes: [(String, String)] = [
            (UTType.png.identifier,  "png"),
            (UTType.jpeg.identifier, "jpg"),
            (UTType.gif.identifier,  "gif"),
            (UTType.webP.identifier, "webp"),
        ]
        for (typeID, ext) in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(typeID) {
                return await loadData(from: provider, typeID: typeID, ext: ext, to: directory)
            }
        }

        // 3. Any other conforming data type (PDFs, archives, etc.)
        if let typeID = provider.registeredTypeIdentifiers.first(where: { id in
            guard let t = UTType(id) else { return false }
            return t.conforms(to: .data) && !t.conforms(to: .text)
        }) {
            let ext = UTType(typeID)?.preferredFilenameExtension ?? "bin"
            return await loadData(from: provider, typeID: typeID, ext: ext, to: directory)
        }

        return nil
    }

    private func loadData(
        from provider: NSItemProvider,
        typeID: String,
        ext: String,
        to directory: URL
    ) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                guard let data else { cont.resume(returning: nil); return }
                let base = provider.suggestedName ?? "shared_file"
                let name = base.hasSuffix(".\(ext)") ? base : "\(base).\(ext)"
                let dest = directory.appendingPathComponent(name)
                try? data.write(to: dest)
                let saved = FileManager.default.fileExists(atPath: dest.path) ? dest : nil
                cont.resume(returning: saved)
            }
        }
    }
}
