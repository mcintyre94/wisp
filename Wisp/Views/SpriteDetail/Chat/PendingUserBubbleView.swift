import SwiftUI

struct PendingUserBubbleView: View {
    let text: String
    var onCancel: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    private let dismissThreshold: CGFloat = 80

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.blue.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                Label("Queued", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .offset(x: dragOffset)
        .opacity(1 - Double(min(abs(dragOffset) / dismissThreshold, 1)) * 0.5)
        .gesture(
            DragGesture(minimumDistance: 20)
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    // Only allow dragging right (positive)
                    if value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width > dismissThreshold {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = 400
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onCancel?()
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
