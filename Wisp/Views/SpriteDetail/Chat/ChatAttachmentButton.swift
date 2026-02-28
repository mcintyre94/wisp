import SwiftUI

struct ChatAttachmentButton: View {
    let isUploading: Bool
    let isDisabled: Bool
    let onBrowseSpriteFiles: () -> Void
    let onPickPhoto: () -> Void
    let onPickFile: () -> Void

    var body: some View {
        if isUploading {
            ProgressView()
                .controlSize(.small)
        } else {
            Menu {
                Button {
                    onBrowseSpriteFiles()
                } label: {
                    Label("Browse Sprite Files", systemImage: "folder")
                }

                Button {
                    onPickPhoto()
                } label: {
                    Label("Photo Library", systemImage: "photo")
                }

                Button {
                    onPickFile()
                } label: {
                    Label("Choose File", systemImage: "doc")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .tint(Color.accentColor)
            .disabled(isDisabled)
        }
    }
}

#Preview {
    ChatAttachmentButton(
        isUploading: false,
        isDisabled: false,
        onBrowseSpriteFiles: {},
        onPickPhoto: {},
        onPickFile: {}
    )
}
