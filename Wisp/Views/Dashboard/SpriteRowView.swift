import SwiftUI

struct SpriteRowView: View {
    let sprite: Sprite

    @State private var isPulsing = false

    var body: some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
                .opacity(sprite.status == .running && isPulsing ? 0.4 : 1.0)
                .animation(
                    sprite.status == .running
                        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sprite.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let createdAt = sprite.createdAt {
                    Text(createdAt.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(sprite.status.displayName)
                .font(.caption)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15), in: Capsule())
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .glassEffect(in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .onAppear {
            if sprite.status == .running {
                DispatchQueue.main.async {
                    isPulsing = true
                }
            }
        }
        .onChange(of: sprite.status) { _, newValue in
            isPulsing = newValue == .running
        }
    }

    private var statusColor: Color {
        switch sprite.status {
        case .running: return .green
        case .warm: return .orange
        case .cold: return .blue
        case .unknown: return .gray
        }
    }
}
