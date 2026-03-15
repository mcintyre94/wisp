import SwiftUI

private enum QuickActionsTab {
    case chat, bash
}

struct QuickActionsView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss
    let viewModel: QuickActionsViewModel
    var insertCallback: ((String) -> Void)? = nil
    var startChatCallback: ((String) -> Void)? = nil

    @State private var selectedTab: QuickActionsTab = .chat

    var body: some View {
        NavigationStack {
            Group {
                switch selectedTab {
                case .chat:
                    QuickChatView(viewModel: viewModel.quickChatViewModel)
                case .bash:
                    bashTab
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Tab", selection: $selectedTab) {
                        Text("Quick Chat").tag(QuickActionsTab.chat)
                        Text("Bash").tag(QuickActionsTab.bash)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: handleDone) {
                        Image(systemName: "xmark")
                    }
                }
            }
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
