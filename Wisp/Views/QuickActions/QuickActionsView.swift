import SwiftUI

struct QuickActionsView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss
    let viewModel: QuickActionsViewModel
    var insertCallback: ((String) -> Void)? = nil
    var startChatCallback: ((String) -> Void)? = nil

    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            tabs
                .navigationTitle(selectedTab == 0 ? "Quick Chat" : "Bash")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: handleDone) {
                            Image(systemName: "xmark")
                        }
                    }
                }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            QuickChatView(viewModel: viewModel.quickChatViewModel)
                .tabItem { Label("Quick Chat", systemImage: "bubble.left") }
                .tag(0)
            bashTab
                .tabItem { Label("Bash", systemImage: "terminal") }
                .tag(1)
        }
    }

    @ViewBuilder private var bashTab: some View {
        if let cb = insertCallback {
            BashQuickView(viewModel: viewModel.bashViewModel, onInsert: { text in
                cb(text)
                dismiss()
            })
        } else if let cb = startChatCallback {
            BashQuickView(viewModel: viewModel.bashViewModel, onStartChat: { text in
                cb(text)
                dismiss()
            })
        } else {
            BashQuickView(viewModel: viewModel.bashViewModel)
        }
    }

    private func handleDone() {
        viewModel.quickChatViewModel.cancel(apiClient: apiClient)
        viewModel.bashViewModel.cancel(apiClient: apiClient)
        dismiss()
    }
}

#Preview("No callback") {
    QuickActionsView(
        viewModel: QuickActionsViewModel(
            spriteName: "my-sprite",
            sessionId: nil,
            workingDirectory: "/home/sprite/project"
        )
    )
    .environment(SpritesAPIClient())
}

#Preview("Insert into chat") {
    QuickActionsView(
        viewModel: QuickActionsViewModel(
            spriteName: "my-sprite",
            sessionId: nil,
            workingDirectory: "/home/sprite/project"
        ),
        insertCallback: { _ in }
    )
    .environment(SpritesAPIClient())
}

#Preview("Start Chat") {
    QuickActionsView(
        viewModel: QuickActionsViewModel(
            spriteName: "my-sprite",
            sessionId: nil,
            workingDirectory: "/home/sprite/project"
        ),
        startChatCallback: { _ in }
    )
    .environment(SpritesAPIClient())
}
