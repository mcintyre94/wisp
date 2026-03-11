import SwiftUI

struct QuickActionsView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss
    let viewModel: QuickActionsViewModel
    var insertCallback: ((String) -> Void)? = nil

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            tabs
        }
    }

    private var headerBar: some View {
        ZStack(alignment: .center) {
            Text(selectedTab == 0 ? "Quick Chat" : "Bash")
                .font(.headline)
            HStack {
                Button("Done", action: handleDone)
                    .padding(.leading)
                Spacer()
            }
        }
        .frame(height: 44)
        .background(.bar)
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
            BashQuickView(viewModel: viewModel.bashViewModel) { text in
                cb(text)
                dismiss()
            }
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

#Preview {
    QuickActionsView(
        viewModel: QuickActionsViewModel(
            spriteName: "my-sprite",
            sessionId: nil,
            workingDirectory: "/home/sprite/project"
        )
    )
    .environment(SpritesAPIClient())
}
