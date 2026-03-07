import Foundation

@Observable @MainActor
final class ServicesViewModel {
    let spriteName: String
    var services: [ServiceInfo] = []
    var isLoading = false
    var errorMessage: String?

    // Map service name → friendly display name (e.g., chat display name)
    var displayNames: [String: String] = [:]

    init(spriteName: String) {
        self.spriteName = spriteName
    }

    func load(apiClient: SpritesAPIClient, chatNames: [String: String] = [:]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            services = try await apiClient.listServices(spriteName: spriteName)
            displayNames = chatNames
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(apiClient: SpritesAPIClient, chatNames: [String: String] = [:]) async {
        await load(apiClient: apiClient, chatNames: chatNames)
    }

    func stop(service: ServiceInfo, apiClient: SpritesAPIClient) async {
        do {
            try await apiClient.deleteService(spriteName: spriteName, serviceName: service.name)
            services.removeAll { $0.name == service.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func displayName(for service: ServiceInfo) -> String {
        displayNames[service.name] ?? service.name
    }
}
