import SwiftUI

struct BashQuickView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Bindable var viewModel: BashQuickViewModel
    var onInsert: ((String) -> Void)? = nil
    @FocusState private var isInputFocused: Bool

    private let shellChars = ["/", "-", "|", ">", "~", "`", "$", "&", "*", "."]

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !viewModel.lastCommand.isEmpty {
                            Text("> \(viewModel.lastCommand)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding([.horizontal, .top])
                                .padding(.bottom, viewModel.output.isEmpty ? 12 : 4)
                        }
                        if !viewModel.output.isEmpty {
                            Text(viewModel.output)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.bottom)
                                .id("output")
                        } else if viewModel.isRunning {
                            ThinkingShimmerView(label: "Running…")
                                .padding()
                        } else {
                            Text("Enter a command to run on the Sprite")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }

                        if let error = viewModel.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: viewModel.output) {
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }

            Divider()

            // Shell character accessory bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shellChars, id: \.self) { char in
                        Button(char) {
                            viewModel.command += char
                        }
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(.rect(cornerRadius: 4))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Enter command…", text: $viewModel.command, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .glassEffect(in: .rect(cornerRadius: 20))
                    .disabled(viewModel.isRunning)

                Button {
                    isInputFocused = false
                    viewModel.send(apiClient: apiClient)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .tint(viewModel.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Color("AccentColor"))
                .disabled(viewModel.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isRunning)
                .buttonStyle(.glass)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .padding(.bottom, isRunningOnMac ? 12 : 0)

            if let onInsert, !viewModel.output.isEmpty, !viewModel.isRunning {
                Button("Insert into chat") {
                    onInsert(viewModel.insertFormatted())
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            isInputFocused = true
        }
    }
}

#Preview {
    BashQuickView(
        viewModel: BashQuickViewModel(
            spriteName: "my-sprite",
            workingDirectory: "/home/sprite/project"
        )
    )
    .environment(SpritesAPIClient())
}
