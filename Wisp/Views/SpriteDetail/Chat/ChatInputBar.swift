import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    var hasQueuedMessage: Bool = false
    let onSend: () -> Void
    let onInterrupt: () -> Void
    var onBrowseSpriteFiles: (() -> Void)? = nil
    var onPickPhoto: (() -> Void)? = nil
    var onPickFile: (() -> Void)? = nil
    var onLongPressSend: (() -> Void)? = nil
    var isUploading: Bool = false
    var attachedFiles: [AttachedFile] = []
    var onRemoveAttachment: ((AttachedFile) -> Void)? = nil
    var lastUploadedFileName: String? = nil
    var isFocused: FocusState<Bool>.Binding

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedFiles.isEmpty
    }

    var body: some View {
        VStack(spacing: 6) {
            if !attachedFiles.isEmpty {
                AttachmentChipsView(
                    files: attachedFiles,
                    onRemove: { file in onRemoveAttachment?(file) }
                )
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let fileName = lastUploadedFileName {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Uploaded \(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                if let onBrowseSpriteFiles, let onPickPhoto, let onPickFile {
                    ChatAttachmentButton(
                        isUploading: isUploading,
                        isDisabled: hasQueuedMessage,
                        onBrowseSpriteFiles: onBrowseSpriteFiles,
                        onPickPhoto: onPickPhoto,
                        onPickFile: onPickFile
                    )
                }

                TextField("Message...", text: $text, axis: .vertical)
                    .focused(isFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .glassEffect(in: .rect(cornerRadius: 20))
                    .disabled(hasQueuedMessage)

                if isStreaming {
                    Button(action: onInterrupt) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .tint(.red)
                    .buttonStyle(.glass)
                }

                Button {
                    isFocused.wrappedValue = false
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .tint(isEmpty || hasQueuedMessage ? .gray : Color("AccentColor"))
                .disabled(isEmpty || hasQueuedMessage)
                .buttonStyle(.glass)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if !isEmpty && !hasQueuedMessage {
                                onLongPressSend?()
                            }
                        }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: attachedFiles.count)
        .animation(.easeInOut(duration: 0.2), value: lastUploadedFileName)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .padding(.bottom, isRunningOnMac ? 12 : 0)
    }

    private var isRunningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }
}
