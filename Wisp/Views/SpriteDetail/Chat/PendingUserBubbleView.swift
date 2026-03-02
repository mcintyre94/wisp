import SwiftUI

struct PendingUserBubbleView: View {
    let text: String
    var files: [AttachedFile] = []
    let onEdit: () -> Void
    let onCancel: () -> Void

    @State private var dragOffset: CGFloat = 0

    private let dismissThreshold: CGFloat = 80
    private let dismissOffset: CGFloat = 400
    private let dismissDuration: TimeInterval = 0.2

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                VStack(alignment: .leading, spacing: 6) {
                    if !files.isEmpty {
                        AttachmentChipsView(files: files)
                    }
                    if !text.isEmpty {
                        Text(text)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.blue.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onCancel) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                HStack(spacing: 10) {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .tint(.secondary)
                    Label("Queued", systemImage: "clock")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
            }
        }
        .offset(x: dragOffset)
        .opacity(1 - Double(min(abs(dragOffset) / dismissThreshold, 1)) * 0.5)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width > dismissThreshold {
                        withAnimation(.easeOut(duration: dismissDuration)) {
                            dragOffset = dismissOffset
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(dismissDuration))
                            onCancel()
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

#Preview {
    VStack {
        PendingUserBubbleView(text: "Can you make the tests pass?", onEdit: {}, onCancel: {})
        PendingUserBubbleView(text: "This is a longer queued message that wraps onto multiple lines to test layout", onEdit: {}, onCancel: {})
        PendingUserBubbleView(
            text: "Fix this",
            files: [
                .init(name: "photo.jpg", path: "/home/sprite/project/photo.jpg"),
                .init(name: "main.py", path: "/home/sprite/project/main.py"),
            ],
            onEdit: {},
            onCancel: {}
        )
        PendingUserBubbleView(
            text: "",
            files: [.init(name: "screenshot.png", path: "/home/sprite/project/screenshot.png")],
            onEdit: {},
            onCancel: {}
        )
    }
    .padding()
}
