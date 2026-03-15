import Foundation

@Observable
@MainActor
final class QuickActionsViewModel: Identifiable {
    let id = UUID()
    let spriteName: String
    let sessionId: String?
    let workingDirectory: String

    let quickChatViewModel: QuickChatViewModel
    let bashViewModel: BashQuickViewModel

    init(spriteName: String, sessionId: String?, workingDirectory: String) {
        self.spriteName = spriteName
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
        self.quickChatViewModel = QuickChatViewModel(
            spriteName: spriteName,
            sessionId: sessionId,
            workingDirectory: workingDirectory
        )
        self.bashViewModel = BashQuickViewModel(
            spriteName: spriteName,
            workingDirectory: workingDirectory
        )
    }
}
