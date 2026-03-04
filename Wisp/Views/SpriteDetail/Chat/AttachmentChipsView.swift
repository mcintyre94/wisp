import SwiftUI

struct AttachmentChipsView: View {
    let files: [AttachedFile]
    var onRemove: ((AttachedFile) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(files) { file in
                    chipView(file)
                }
            }
        }
    }

    private func chipView(_ file: AttachedFile) -> some View {
        HStack(spacing: 4) {
            Image(systemName: iconName(for: file))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(file.name)
                .font(.caption)
                .lineLimit(1)
            if let onRemove {
                Button {
                    onRemove(file)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func iconName(for file: AttachedFile) -> String {
        file.isImage ? "photo" : "doc.fill"
    }
}

#Preview {
    AttachmentChipsView(
        files: [
            .init(name: "main.py", path: "/home/sprite/project/main.py"),
            .init(name: "photo_20260228.jpg", path: "/home/sprite/project/photo_20260228.jpg"),
            .init(name: "README.md", path: "/home/sprite/project/README.md"),
        ],
        onRemove: { _ in }
    )
    .padding()
}
