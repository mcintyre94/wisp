import SwiftUI
import UIKit

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    var hasQueuedMessage: Bool = false
    let onSend: () -> Void
    let onInterrupt: () -> Void
    var onBrowseSpriteFiles: (() -> Void)? = nil
    var onPickPhoto: (() -> Void)? = nil
    var onPickFile: (() -> Void)? = nil
    var onPasteFromClipboard: (() -> Void)? = nil
    var isUploading: Bool = false
    var attachedFiles: [AttachedFile] = []
    var onRemoveAttachment: ((AttachedFile) -> Void)? = nil
    var lastUploadedFileName: String? = nil
    var onStash: (() -> Void)? = nil
    var isFocused: FocusState<Bool>.Binding

    @State private var showStopConfirmation = false
    @State private var textInputHeight: CGFloat = 36

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

                PasteInterceptingTextInput(
                    text: $text,
                    isFocused: isFocused,
                    isDisabled: hasQueuedMessage,
                    placeholder: "Message...",
                    onPasteNonText: onPasteFromClipboard,
                    dynamicHeight: $textInputHeight
                )
                .frame(height: max(textInputHeight, 36))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(in: .rect(cornerRadius: 20))

                if isStreaming {
                    Button {
                        showStopConfirmation = true
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .tint(.red)
                    .buttonStyle(.glass)
                    .confirmationDialog("Stop Claude?", isPresented: $showStopConfirmation) {
                        Button("Stop", role: .destructive, action: onInterrupt)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will interrupt the current response.")
                    }
                }

                Menu {
                    if let onStash, !isEmpty {
                        Button("Stash Draft", systemImage: "tray.and.arrow.down") {
                            onStash()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                } primaryAction: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    isFocused.wrappedValue = false
                    onSend()
                }
                .tint(isEmpty || hasQueuedMessage ? .gray : Color("AccentColor"))
                .disabled(isEmpty || hasQueuedMessage)
                .buttonStyle(.glass)
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

#Preview("Idle") {
    @Previewable @State var text = ""
    @Previewable @FocusState var isFocused: Bool
    ChatInputBar(
        text: $text,
        isStreaming: false,
        onSend: {},
        onInterrupt: {},
        isFocused: $isFocused
    )
}

#Preview("Streaming") {
    @Previewable @State var text = ""
    @Previewable @FocusState var isFocused: Bool
    ChatInputBar(
        text: $text,
        isStreaming: true,
        onSend: {},
        onInterrupt: {},
        isFocused: $isFocused
    )
}
