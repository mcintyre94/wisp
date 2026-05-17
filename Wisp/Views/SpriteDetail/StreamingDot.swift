import SwiftUI

/// A slowly pulsing orange dot shown on chat rows while Claude is actively streaming.
struct StreamingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 8, height: 8)
            .opacity(pulse ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .onDisappear { pulse = false }
    }
}

#Preview {
    HStack(spacing: 16) {
        StreamingDot()
        Text("Streaming…")
            .foregroundStyle(.secondary)
    }
    .padding()
}
