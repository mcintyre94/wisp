import SwiftUI

struct ThinkingShimmerView: View {
    let label: String

    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        HStack(spacing: 8) {
            PulsingDot()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .overlay(shimmerGradient)
                .mask(
                    Text(label)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                )
                .animation(.easeInOut(duration: 0.2), value: label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 2
            }
        }
    }

    private var shimmerGradient: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.4), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.4)
            .offset(x: geo.size.width * shimmerOffset)
        }
    }
}

private struct PulsingDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.purple)
            .frame(width: 6, height: 6)
            .scaleEffect(isAnimating ? 1.3 : 0.8)
            .opacity(isAnimating ? 1 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}
