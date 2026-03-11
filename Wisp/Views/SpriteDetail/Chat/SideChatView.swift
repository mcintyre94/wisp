import MarkdownUI
import SwiftUI

struct SideChatView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: SideChatViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !viewModel.response.isEmpty {
                                Markdown(viewModel.response)
                                    .markdownTheme(.wisp)
                                    .markdownCodeSyntaxHighlighter(WispCodeHighlighter())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .id("response")
                            }

                            if viewModel.isStreaming && viewModel.response.isEmpty {
                                ThinkingShimmerView(label: "Thinking…")
                                    .padding()
                            }

                            if let error = viewModel.error {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                    .font(.subheadline)
                                    .padding()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: viewModel.response) {
                        proxy.scrollTo("response", anchor: .bottom)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    TextField("Ask a quick question…", text: $viewModel.question, axis: .vertical)
                        .focused($isInputFocused)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 36)
                        .glassEffect(in: .rect(cornerRadius: 20))
                        .disabled(viewModel.isStreaming)

                    Button {
                        isInputFocused = false
                        viewModel.send(apiClient: apiClient)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .tint(viewModel.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Color("AccentColor"))
                    .disabled(viewModel.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
                    .buttonStyle(.glass)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .padding(.bottom, isRunningOnMac ? 12 : 0)
            }
            .navigationTitle("Side Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.cancel(apiClient: apiClient)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private var isRunningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }
}

#Preview {
    let viewModel = SideChatViewModel(
        spriteName: "my-sprite",
        sessionId: "abc-123",
        workingDirectory: "/home/sprite/project"
    )
    SideChatView(viewModel: viewModel)
        .environment(SpritesAPIClient())
}
