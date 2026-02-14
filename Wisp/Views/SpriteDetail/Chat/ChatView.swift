import SwiftUI

struct ChatView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ChatViewModel

    init(spriteName: String) {
        _viewModel = State(initialValue: ChatViewModel(spriteName: spriteName))
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatStatusBar(status: viewModel.status, modelName: viewModel.modelName)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            ChatInputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: {
                    viewModel.sendMessage(apiClient: apiClient, modelContext: modelContext)
                },
                onInterrupt: {
                    viewModel.interrupt()
                }
            )
        }
        .task {
            viewModel.loadSession(modelContext: modelContext)
        }
    }
}
