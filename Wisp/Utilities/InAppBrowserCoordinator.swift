import SwiftUI

@Observable
@MainActor
final class InAppBrowserCoordinator {
    var presentedURL: URL?
    var authToken: String?

    func open(_ url: URL) {
        presentedURL = url
    }
}
